'use strict';

const http = require('node:http');
const path = require('node:path');
const config = require('./config');
const { verifyFirebaseIdToken } = require('./token_verifier');
const { mintPostgrestJwt } = require('./jwt_minter');
const { secureCompare, hashUid, RateLimiter, emitAuditLog } = require('./security');
const { proxyToPostgrest } = require('./proxy');
const { defaultJwksClient } = require('./jwks');

function extractEmbeddedRelations(queryString) {
  if (!queryString) return [];
  const relations = new Set();
  const params = new URLSearchParams(queryString);

  const selectAll = params.getAll('select');
  if (selectAll.length > 1) {
    const err = new Error('Duplicate select parameter is not permitted.');
    err.code = 'ERR_DUPLICATE_SELECT';
    throw err;
  }

  for (const selectParam of selectAll) {
    // Supports:
    // - normal: appointments(*), doctors(*)
    // - aliased: my_alias:doctors(*) or "my_alias":"doctors"(*)
    // - quoted: "doctors"(*)
    // - spread: ...doctors(*) or ... "doctors" (*)
    // - hints/inner: doctors!inner(*) or doctors!fk_hint!inner(*) or "doctors"!"hint"!inner(*)
    const selectRegex = /(?:(?:"([^"]+)"|([a-zA-Z0-9_]+))\s*:\s*)?(?:\.\.\.\s*)?(?:"([^"]+)"|([a-zA-Z0-9_]+))(?:!(?:[a-zA-Z0-9_"]+))*\s*\(/g;
    for (const m of selectParam.matchAll(selectRegex)) {
      const rel = (m[3] || m[4]).toLowerCase();
      relations.add(rel);
    }
  }

  for (const [key, val] of params.entries()) {
    if (key.includes('.')) {
      const parts = key.split('.');
      const prefix = parts[0].trim().replace(/^"/, '').replace(/"$/, '').toLowerCase();
      if (prefix && prefix !== 'or' && prefix !== 'and' && prefix !== 'not') {
        relations.add(prefix);
      }
    }
    // PostgREST ordering on embedded resources: order=relation(col) or order=relation.col.desc
    if (key === 'order' || key.endsWith('.order')) {
      const orderMatch = val.match(/(?:(?:"([^"]+)"|([a-zA-Z0-9_]+))\s*\()|(?:(?:"([^"]+)"|([a-zA-Z0-9_]+))\.[a-zA-Z0-9_]+)/);
      if (orderMatch) {
        const rel = (orderMatch[1] || orderMatch[2] || orderMatch[3] || orderMatch[4]).toLowerCase();
        relations.add(rel);
      }
    }
    if (key === 'or' || key === 'and' || key.endsWith('.or') || key.endsWith('.and')) {
      const matches = val.matchAll(/(?:"([^"]+)"|([a-zA-Z0-9_]+))\.[a-zA-Z0-9_]+\.(eq|neq|gt|gte|lt|lte|like|ilike|is|in|cs|cd|ov|sl|sr|nxr|nxl|adj|fts|plfts|phfts|wfts)/g);
      for (const m of matches) {
        relations.add((m[1] || m[2]).toLowerCase());
      }
    }
  }

  return Array.from(relations);
}

function createGatewayServer(overrides = {}) {
  const cfg = { ...config, ...overrides };
  const rateLimiter = new RateLimiter({
    windowMs: cfg.rateLimitWindowMs,
    maxRequests: cfg.rateLimitMaxRequests,
  });
  const failedServiceKeyLimiter = new RateLimiter({
    windowMs: cfg.failedServiceKeyWindowMs,
    maxRequests: cfg.failedServiceKeyMaxAttempts,
  });
  const effectiveAnonLimit = overrides.anonRateLimitMaxRequests !== undefined
    ? overrides.anonRateLimitMaxRequests
    : (overrides.rateLimitMaxRequests !== undefined
        ? overrides.rateLimitMaxRequests
        : (cfg.anonRateLimitMaxRequests || 60));

  const anonRateLimiter = new RateLimiter({
    windowMs: cfg.anonRateLimitWindowMs || cfg.rateLimitWindowMs,
    maxRequests: effectiveAnonLimit,
  });
  const jwksClient = cfg.jwksClient || defaultJwksClient;
  const allowedMethodsSet = new Set((cfg.allowedMethods || []).map((m) => m.toUpperCase()));
  const clientDirectAllowedTablesSet = new Set((cfg.clientDirectAllowedTables || cfg.clientAllowedTables || []).map((t) => t.toLowerCase()));
  const clientAllowedTablesSet = new Set((cfg.clientAllowedTables || cfg.allowedTables || []).map((t) => t.toLowerCase()));
  const serviceRoleAllowedTablesSet = new Set((cfg.serviceRoleAllowedTables || cfg.allowedTables || []).map((t) => t.toLowerCase()));
  const clientAllowedRpcsSet = new Set((cfg.clientAllowedRpcs || cfg.allowedRpcs || []).map((r) => r.toLowerCase()));
  const serviceRoleAllowedRpcsSet = new Set((cfg.serviceRoleAllowedRpcs || cfg.allowedRpcs || []).map((r) => r.toLowerCase()));

  const server = http.createServer(async (req, res) => {
    const startTime = process.hrtime();
    let clientRole = 'anon';
    let clientUidHash = null;

    // Resolve client IP using rightmost trusted hop behind reverse proxy / ALB
    let clientIp = 'unknown';
    const xff = req.headers['x-forwarded-for'];
    if (typeof xff === 'string' && xff.trim()) {
      const hops = xff.split(',').map((h) => h.trim()).filter(Boolean);
      if (hops.length > 0) {
        clientIp = hops[hops.length - 1]; // rightmost trusted hop behind ALB
      }
    } else if (req.socket && req.socket.remoteAddress) {
      clientIp = req.socket.remoteAddress;
    }

    // Helper to send response and log
    const sendJson = (statusCode, data, headers = {}) => {
      const diff = process.hrtime(startTime);
      const latencyMs = diff[0] * 1000 + diff[1] / 1e6;

      const responseHeaders = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Authorization, Content-Type, apikey, Prefer, Range, x-client-info',
        ...headers,
      };

      res.writeHead(statusCode, responseHeaders);
      res.end(JSON.stringify(data));

      emitAuditLog({
        method: req.method,
        path: req.url,
        status: statusCode,
        latencyMs,
        uidHash: clientUidHash,
        role: clientRole,
        ip: clientIp,
      });
    };

    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
      res.writeHead(204, {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Authorization, Content-Type, apikey, Prefer, Range, x-client-info',
        'Access-Control-Max-Age': '86400',
      });
      res.end();
      return;
    }

    // Validate HTTP Method
    if (!allowedMethodsSet.has((req.method || '').toUpperCase())) {
      return sendJson(405, {
        error: 'Method Not Allowed',
        message: `HTTP method ${req.method} is not permitted.`,
      });
    }

    // Extract and normalize request URL path
    const [rawPath, queryString] = (req.url || '/').split('?');
    let decodedPath = rawPath;
    try {
      decodedPath = decodeURIComponent(rawPath);
    } catch (_) {}
    let cleanPath = path.posix.normalize(decodedPath).replace(/^\/+/, '/').replace(/\/+$/, '') || '/';

    // Health check
    if (cleanPath === '/healthz') {
      return sendJson(200, {
        status: 'healthy',
        service: 'doctornect-auth-gateway',
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
      });
    }

    // Read request body with size limit
    let bodyBuf = Buffer.alloc(0);
    try {
      bodyBuf = await new Promise((resolve, reject) => {
        const chunks = [];
        let totalSize = 0;

        req.on('data', (chunk) => {
          totalSize += chunk.length;
          if (totalSize > cfg.maxBodySizeBytes) {
            reject(new Error('Payload Too Large'));
          }
          chunks.push(chunk);
        });

        req.on('end', () => resolve(Buffer.concat(chunks)));
        req.on('error', reject);
      });
    } catch (err) {
      if (err.message === 'Payload Too Large') {
        return sendJson(413, { error: 'Payload Too Large', message: `Request body exceeds ${cfg.maxBodySizeBytes} bytes.` });
      }
      return sendJson(400, { error: 'Bad Request', message: `Error reading request body: ${err.message}` });
    }

    // Validate that route belongs to /rest/v1/*
    if (!cleanPath.startsWith('/rest/v1')) {
      return sendJson(404, { error: 'Not Found', message: 'Endpoint not found.' });
    }

    // Validate Accept-Profile and Content-Profile schema restrictions
    const acceptProfile = req.headers['accept-profile'];
    if (acceptProfile && acceptProfile.trim().toLowerCase() !== 'public') {
      return sendJson(400, {
        error: 'Bad Request',
        message: "Invalid Accept-Profile: only 'public' schema is permitted.",
      });
    }

    const contentProfile = req.headers['content-profile'];
    if (contentProfile && contentProfile.trim().toLowerCase() !== 'public') {
      return sendJson(400, {
        error: 'Bad Request',
        message: "Invalid Content-Profile: only 'public' schema is permitted.",
      });
    }

    // Check if this IP is blocked due to excessive failed service-key attempts
    if (failedServiceKeyLimiter.isBlocked(`ip:${clientIp}`)) {
      return sendJson(429, {
        error: 'Too Many Requests',
        message: 'Too many failed service key attempts. Please try again later.',
      });
    }

    // Extract authorization credentials
    const authHeader = req.headers.authorization || '';
    const apikeyHeader = req.headers.apikey || '';
    let bearerToken = null;

    if (authHeader.startsWith('Bearer ')) {
      bearerToken = authHeader.slice(7).trim();
    }

    let authenticatedPayload = null;

    // 1. Service Role Key Check (Constant Time)
    const isServiceKeyCandidate =
      Boolean(apikeyHeader && apikeyHeader !== cfg.anonKey) ||
      Boolean(bearerToken && !bearerToken.includes('.') && bearerToken !== cfg.anonKey);

    if (
      cfg.serviceRoleKey &&
      (secureCompare(bearerToken || '', cfg.serviceRoleKey) || secureCompare(apikeyHeader, cfg.serviceRoleKey))
    ) {
      clientRole = 'service_role';
      clientUidHash = 'service_role';
      // Service role callers bypass rate limiting
    } else if (isServiceKeyCandidate) {
      // Failed service key attempt: record failure and rate-limit per IP
      const blockedNow = failedServiceKeyLimiter.recordFailure(`ip:${clientIp}`);
      if (blockedNow) {
        return sendJson(429, {
          error: 'Too Many Requests',
          message: 'Too many failed service key attempts. Please try again later.',
        });
      }
      return sendJson(401, {
        error: 'Unauthorized',
        message: 'Invalid service key.',
      });
    } else if (bearerToken && bearerToken !== cfg.anonKey) {
      // 2. Firebase ID Token Verification
      try {
        authenticatedPayload = await verifyFirebaseIdToken(bearerToken, {
          jwksClient,
          projectId: cfg.firebaseProjectId,
        });
        clientRole = 'authenticated';
        clientUidHash = hashUid(authenticatedPayload.uid);
        // Per-UID rate limit for authenticated callers
        if (authenticatedPayload.uid && !rateLimiter.isAllowed(`uid:${authenticatedPayload.uid}`)) {
          return sendJson(429, {
            error: 'Too Many Requests',
            message: 'Rate limit exceeded for user. Please try again shortly.',
          });
        }
      } catch (err) {
        // Unauthenticated due to invalid token: apply per-IP rate limit before error
        if (!rateLimiter.isAllowed(`ip:${clientIp}`)) {
          return sendJson(429, {
            error: 'Too Many Requests',
            message: 'Rate limit exceeded. Please try again shortly.',
          });
        }
        return sendJson(401, {
          error: 'Unauthorized',
          message: `Authentication failed: ${err.message}`,
        });
      }
    } else {
      // 3. Unauthenticated / Anonymous Request
      const lowerCleanPath = cleanPath.toLowerCase();
      const isAllowlisted = cfg.anonPublicAllowlist.some((allowed) =>
        lowerCleanPath.startsWith(allowed.toLowerCase())
      );
      if (isAllowlisted) {
        if (!anonRateLimiter.isAllowed(`anon:${clientIp}`)) {
          return sendJson(429, {
            error: 'Too Many Requests',
            message: 'Rate limit exceeded. Please try again shortly.',
          });
        }
        clientRole = 'anon';
      } else {
        if (!rateLimiter.isAllowed(`ip:${clientIp}`)) {
          return sendJson(429, {
            error: 'Too Many Requests',
            message: 'Rate limit exceeded. Please try again shortly.',
          });
        }
        return sendJson(401, {
          error: 'Unauthorized',
          message: 'Authentication token required for this resource.',
        });
      }
    }

    // Role-dependent allowlist enforcement
    const isServiceRole = clientRole === 'service_role';
    const effectiveDirectAllowedTables = isServiceRole ? serviceRoleAllowedTablesSet : clientDirectAllowedTablesSet;
    const effectiveAllowedTables = isServiceRole ? serviceRoleAllowedTablesSet : clientAllowedTablesSet;
    const effectiveAllowedRpcs = isServiceRole ? serviceRoleAllowedRpcsSet : clientAllowedRpcsSet;

    // Validate path against allowed tables and RPCs
    const subPath = cleanPath.slice('/rest/v1'.length);
    if (!subPath || subPath === '/') {
      return sendJson(404, { error: 'Not Found', message: 'Endpoint not found.' });
    }

    if (subPath.startsWith('/rpc/')) {
      const rpcName = subPath.slice('/rpc/'.length).replace(/^\/+/, '').split('/')[0].toLowerCase();
      if (!effectiveAllowedRpcs.has(rpcName)) {
        return sendJson(404, {
          error: 'Not Found',
          message: `RPC function '${rpcName}' is not allowed or not found.`,
        });
      }
    } else {
      const tableName = subPath.replace(/^\/+/, '').split('/')[0].toLowerCase();
      if (!effectiveDirectAllowedTables.has(tableName)) {
        return sendJson(404, {
          error: 'Not Found',
          message: `Resource table '${tableName}' is not allowed or not found.`,
        });
      }

      // Validate embedded relations in select parameter and filters
      let embeddedRelations;
      try {
        embeddedRelations = extractEmbeddedRelations(queryString);
      } catch (err) {
        if (err.code === 'ERR_DUPLICATE_SELECT') {
          return sendJson(400, {
            error: 'Bad Request',
            message: err.message,
          });
        }
        return sendJson(400, {
          error: 'Bad Request',
          message: `Malformed query parameters: ${err.message}`,
        });
      }

      for (const rel of embeddedRelations) {
        if (!effectiveAllowedTables.has(rel)) {
          return sendJson(404, {
            error: 'Not Found',
            message: `Embedded resource '${rel}' is not allowed or not found.`,
          });
        }
      }
    }

    // Mint appropriate PostgREST JWT and proxy
    let postgrestJwt;
    if (clientRole === 'service_role') {
      postgrestJwt = mintPostgrestJwt({
        role: 'service_role',
        jwtSecret: cfg.postgrestJwtSecret,
        jwtAud: cfg.postgrestJwtAud,
      });
    } else if (clientRole === 'authenticated') {
      postgrestJwt = mintPostgrestJwt({
        role: 'authenticated',
        sub: authenticatedPayload.uid,
        appRole: authenticatedPayload.appRole,
        verified: authenticatedPayload.verified,
        jwtSecret: cfg.postgrestJwtSecret,
        jwtAud: cfg.postgrestJwtAud,
      });
    } else {
      postgrestJwt = mintPostgrestJwt({
        role: 'anon',
        jwtSecret: cfg.postgrestJwtSecret,
        jwtAud: cfg.postgrestJwtAud,
      });
    }

    if (clientRole === 'anon' && !subPath.startsWith('/rpc/')) {
      const params = new URLSearchParams(queryString || '');
      const currentLimit = parseInt(params.get('limit') || '0', 10);
      const maxLimit = cfg.anonMaxRows || 100;
      if (params.has('limit') && currentLimit > maxLimit) {
        params.set('limit', String(maxLimit));
        req.url = `${cleanPath}?${params.toString()}`;
      }
    }

    return proxyToPostgrest(req, res, {
      targetBaseUrl: cfg.postgrestUrl,
      postgrestJwt,
      body: bodyBuf,
    });

    // Default deny for non-public paths without authentication
    return sendJson(401, {
      error: 'Unauthorized',
      message: 'Authentication token required for this resource.',
    });
  });

  return {
    server,
    rateLimiter,
    anonRateLimiter,
  };
}

if (require.main === module) {
  const { server } = createGatewayServer();
  server.listen(config.port, config.host, () => {
    console.log(`[DoctorNect Auth Gateway] Listening on http://${config.host}:${config.port}`);
    console.log(`[DoctorNect Auth Gateway] Proxying to PostgREST at ${config.postgrestUrl}`);
  });
}

module.exports = {
  createGatewayServer,
  extractEmbeddedRelations,
};
