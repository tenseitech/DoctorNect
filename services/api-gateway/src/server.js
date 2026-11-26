'use strict';

require('../../../scripts/lib/bootstrap_root_env').loadRootEnv();
const http = require('node:http');
const path = require('node:path');
const config = require('./config');
const { verifyFirebaseIdToken } = require('./token_verifier');
const { assertFirebaseTokenNotRevoked } = require('./firebase_revocation');
const { resolveCorsOrigin } = require('./cors');
const { mintPostgrestJwt } = require('./jwt_minter');
const { secureCompare, hashUid, RateLimiter, emitAuditLog } = require('./security');
const { createRateLimiter } = require('./rate_limit_factory');
const { buildApiSecurityHeaders } = require('./api_security_headers');
const { assertGatewayProductionConfig } = require('./validate_production_config');
const { proxyToPostgrest } = require('./proxy');
const { defaultJwksClient } = require('./jwks');
const { resolveDataPlane, assertClientRoutingHintIgnored } = require('../../../scripts/lib/demo_routing');
const { resolveClientIpFromRequest } = require('../../../scripts/lib/trusted_client_ip');
const { clientAuthErrorMessage } = require('./client_auth_errors');
const { checkPostgrestHttp, checkRedisPing } = require('./health_dependencies');
const { resolveRequestId, REQUEST_ID_HEADER } = require('./request_context');
const { shouldEmitGatewayAuditLog } = require('./audit_log_policy');

async function limiterAllows(limiter, key) {
  const result = limiter.isAllowed(key);
  return typeof result?.then === 'function' ? result : result;
}

async function limiterBlocked(limiter, key) {
  const result = limiter.isBlocked(key);
  return typeof result?.then === 'function' ? result : result;
}

async function limiterRecordFailure(limiter, key) {
  const result = limiter.recordFailure(key);
  return typeof result?.then === 'function' ? result : result;
}

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
  const rateLimiter = overrides.rateLimiter || createRateLimiter({
    windowMs: cfg.rateLimitWindowMs,
    maxRequests: cfg.rateLimitMaxRequests,
    redisUrl: cfg.rateLimitRedisUrl,
  });
  const failedServiceKeyLimiter = overrides.failedServiceKeyLimiter || new RateLimiter({
    windowMs: cfg.failedServiceKeyWindowMs,
    maxRequests: cfg.failedServiceKeyMaxAttempts,
  });
  const effectiveAnonLimit = overrides.anonRateLimitMaxRequests !== undefined
    ? overrides.anonRateLimitMaxRequests
    : (overrides.rateLimitMaxRequests !== undefined
        ? overrides.rateLimitMaxRequests
        : (cfg.anonRateLimitMaxRequests || 60));

  const anonRateLimiter = overrides.anonRateLimiter || createRateLimiter({
    windowMs: cfg.anonRateLimitWindowMs || cfg.rateLimitWindowMs,
    maxRequests: effectiveAnonLimit,
    redisUrl: cfg.rateLimitRedisUrl,
    keyPrefix: 'gw:anon:',
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
    const requestId = resolveRequestId(req);

    const clientIp = resolveClientIpFromRequest(req);

    // Helper to send response and log
    const corsOrigin = resolveCorsOrigin(req, cfg.corsAllowedOrigins || []);

    const sendJson = (statusCode, data, headers = {}) => {
      const diff = process.hrtime(startTime);
      const latencyMs = diff[0] * 1000 + diff[1] / 1e6;

      const responseHeaders = buildApiSecurityHeaders({
        'Content-Type': 'application/json',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Authorization, Content-Type, apikey, Prefer, Range, x-client-info, x-request-id',
        'Access-Control-Expose-Headers': 'x-request-id',
        [REQUEST_ID_HEADER]: requestId,
        ...headers,
      });
      if (corsOrigin) {
        responseHeaders['Access-Control-Allow-Origin'] = corsOrigin;
        responseHeaders.Vary = 'Origin';
      }

      res.writeHead(statusCode, responseHeaders);
      res.end(JSON.stringify(data));

      if (shouldEmitGatewayAuditLog({
        statusCode,
        method: req.method,
        path: req.url,
      })) {
        emitAuditLog({
          method: req.method,
          path: req.url,
          status: statusCode,
          latencyMs,
          uidHash: clientUidHash,
          role: clientRole,
          ip: clientIp,
          requestId,
        });
      }
    };

    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
      if (!corsOrigin) {
        res.writeHead(204);
        res.end();
        return;
      }
      res.writeHead(204, {
        'Access-Control-Allow-Origin': corsOrigin,
        Vary: 'Origin',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Authorization, Content-Type, apikey, Prefer, Range, x-client-info, x-request-id',
        'Access-Control-Expose-Headers': 'x-request-id',
        [REQUEST_ID_HEADER]: requestId,
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

    // Liveness: process is up (no dependency probes).
    if (cleanPath === '/livez') {
      return sendJson(200, {
        status: 'ok',
        service: 'doctornect-auth-gateway',
        probe: 'liveness',
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
      });
    }

    // Readiness: dependencies required to serve API traffic.
    if (cleanPath === '/readyz') {
      const [postgrest, redis] = await Promise.all([
        checkPostgrestHttp(cfg.postgrestUrl, 3000),
        checkRedisPing(cfg.rateLimitRedisUrl, 2000),
      ]);
      const redisRequired = Boolean(String(cfg.rateLimitRedisUrl || '').trim());
      const ready = postgrest.ok && (!redisRequired || redis.ok);
      return sendJson(ready ? 200 : 503, {
        status: ready ? 'ready' : 'not_ready',
        service: 'doctornect-auth-gateway',
        probe: 'readiness',
        dependencies: {
          postgrest: { ok: postgrest.ok, status: postgrest.status },
          redis: {
            ok: redis.ok,
            status: redis.status,
            required: redisRequired,
          },
        },
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
      });
    }

    // Health check (gateway + PostgREST upstream; backward compatible with load balancers using /healthz)
    if (cleanPath === '/healthz') {
      const postgrest = await checkPostgrestHttp(cfg.postgrestUrl, 3000);
      const healthy = postgrest.ok;
      return sendJson(healthy ? 200 : 503, {
        status: healthy ? 'healthy' : 'degraded',
        service: 'doctornect-auth-gateway',
        probe: 'dependency',
        postgrest: { ok: postgrest.ok, status: postgrest.status },
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

    const hintCheck = assertClientRoutingHintIgnored(req.headers);
    if (!hintCheck.ok) {
      return sendJson(400, {
        error: 'Bad Request',
        message: 'Client routing hints are not permitted.',
      });
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
    if (await limiterBlocked(failedServiceKeyLimiter, `ip:${clientIp}`)) {
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
      const blockedNow = await limiterRecordFailure(failedServiceKeyLimiter, `ip:${clientIp}`);
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
        if (cfg.firebaseRevocationCheck !== false) {
          await assertFirebaseTokenNotRevoked(bearerToken, {
            required: cfg.requireFirebaseRevocationCheck === true,
          });
        }
        clientRole = 'authenticated';
        clientUidHash = hashUid(authenticatedPayload.uid);
        // Per-UID rate limit for authenticated callers
        if (authenticatedPayload.uid && !(await limiterAllows(rateLimiter, `uid:${authenticatedPayload.uid}`))) {
          return sendJson(429, {
            error: 'Too Many Requests',
            message: 'Rate limit exceeded for user. Please try again shortly.',
          });
        }
      } catch (err) {
        // Unauthenticated due to invalid token: apply per-IP rate limit before error
        if (!(await limiterAllows(rateLimiter, `ip:${clientIp}`))) {
          return sendJson(429, {
            error: 'Too Many Requests',
            message: 'Rate limit exceeded. Please try again shortly.',
          });
        }
        return sendJson(401, {
          error: 'Unauthorized',
          message: clientAuthErrorMessage(err),
        });
      }
    } else {
      // 3. Unauthenticated / Anonymous Request
      const lowerCleanPath = cleanPath.toLowerCase();
      const isAllowlisted = cfg.anonPublicAllowlist.some((allowed) =>
        lowerCleanPath.startsWith(allowed.toLowerCase())
      );
      if (isAllowlisted) {
        if (!(await limiterAllows(anonRateLimiter, `anon:${clientIp}`))) {
          return sendJson(429, {
            error: 'Too Many Requests',
            message: 'Rate limit exceeded. Please try again shortly.',
          });
        }
        clientRole = 'anon';
      } else {
        if (!(await limiterAllows(rateLimiter, `ip:${clientIp}`))) {
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
        return sendJson(403, {
          error: 'Forbidden',
          message: `RPC function '${rpcName}' is not allowed.`,
        });
      }
    } else {
      const tableName = subPath.replace(/^\/+/, '').split('/')[0].toLowerCase();
      if (!effectiveDirectAllowedTables.has(tableName)) {
        return sendJson(403, {
          error: 'Forbidden',
          message: `Resource table '${tableName}' is not allowed.`,
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
          return sendJson(403, {
            error: 'Forbidden',
            message: `Embedded resource '${rel}' is not allowed.`,
          });
        }
      }
    }

    const appEnv = String(process.env.APP_ENV || '').toLowerCase();
    let targetBaseUrl = cfg.postgrestUrl;
    let jwtSecret = cfg.postgrestJwtSecret;
    let jwtAud = cfg.postgrestJwtAud;
    if (appEnv === 'production' && cfg.demoRealRoutingEnabled && clientRole !== 'service_role') {
      const plane = resolveDataPlane({
        appEnv,
        firebaseUid: authenticatedPayload?.uid || null,
      });
      if (plane === 'supabase') {
        if (!cfg.demoPostgrestUrl || !cfg.demoPostgrestJwtSecret) {
          return sendJson(503, {
            error: 'Service Unavailable',
            message: 'Demo data plane is not configured.',
          });
        }
        targetBaseUrl = cfg.demoPostgrestUrl;
        jwtSecret = cfg.demoPostgrestJwtSecret;
        jwtAud = cfg.demoPostgrestJwtAud;
      }
    }

    // Mint appropriate PostgREST JWT and proxy
    let postgrestJwt;
    if (clientRole === 'service_role') {
      postgrestJwt = mintPostgrestJwt({
        role: 'service_role',
        jwtSecret,
        jwtAud,
      });
    } else if (clientRole === 'authenticated') {
      postgrestJwt = mintPostgrestJwt({
        role: 'authenticated',
        sub: authenticatedPayload.uid,
        appRole: authenticatedPayload.appRole,
        verified: authenticatedPayload.verified,
        phoneNumber: authenticatedPayload.phoneNumber,
        jwtSecret,
        jwtAud,
      });
    } else {
      postgrestJwt = mintPostgrestJwt({
        role: 'anon',
        jwtSecret,
        jwtAud,
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
      targetBaseUrl,
      postgrestJwt,
      body: bodyBuf,
      requestId,
      onFinished: (statusCode) => {
        if (!shouldEmitGatewayAuditLog({
          statusCode,
          method: req.method,
          path: req.url,
        })) {
          return;
        }
        const diff = process.hrtime(startTime);
        const latencyMs = diff[0] * 1000 + diff[1] / 1e6;
        emitAuditLog({
          method: req.method,
          path: req.url,
          status: statusCode,
          latencyMs,
          uidHash: clientUidHash,
          role: clientRole,
          ip: clientIp,
          requestId,
        });
      },
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
  const { assertGatewayProductionRuntime } = require('./assert_gateway_production_runtime');
  assertGatewayProductionConfig();
  void assertGatewayProductionRuntime()
    .then(() => {
      const { server } = createGatewayServer();
      server.listen(config.port, config.host, () => {
        console.log(`[DoctorNect Auth Gateway] Listening on http://${config.host}:${config.port}`);
        console.log(`[DoctorNect Auth Gateway] Proxying to PostgREST at ${config.postgrestUrl}`);
      });
    })
    .catch((err) => {
      console.error('[DoctorNect Auth Gateway] Production runtime checks failed:', err.message);
      process.exit(1);
    });
}

module.exports = {
  createGatewayServer,
  extractEmbeddedRelations,
};
