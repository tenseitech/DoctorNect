'use strict';

const http = require('node:http');
const config = require('./config');
const { verifyFirebaseIdToken } = require('./token_verifier');
const { mintPostgrestJwt } = require('./jwt_minter');
const { secureCompare, hashUid, RateLimiter, emitAuditLog } = require('./security');
const { proxyToPostgrest } = require('./proxy');
const { defaultJwksClient } = require('./jwks');

function createGatewayServer(overrides = {}) {
  const cfg = { ...config, ...overrides };
  const rateLimiter = new RateLimiter({
    windowMs: cfg.rateLimitWindowMs,
    maxRequests: cfg.rateLimitMaxRequests,
  });
  const jwksClient = cfg.jwksClient || defaultJwksClient;
  const allowedMethodsSet = new Set((cfg.allowedMethods || []).map((m) => m.toUpperCase()));
  const allowedTablesSet = new Set(cfg.allowedTables || []);
  const allowedRpcsSet = new Set(cfg.allowedRpcs || []);

  const server = http.createServer(async (req, res) => {
    const startTime = process.hrtime();
    let clientRole = 'anon';
    let clientUidHash = null;

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
        ip: req.socket.remoteAddress,
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

    // Health check
    const cleanPath = (req.url || '/').split('?')[0];
    if (cleanPath === '/healthz') {
      return sendJson(200, {
        status: 'healthy',
        service: 'doctornect-auth-gateway',
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
      });
    }

    // Rate limiting per IP or UID
    const clientIp = req.socket.remoteAddress || 'unknown';
    if (!rateLimiter.isAllowed(clientIp)) {
      return sendJson(429, {
        error: 'Too Many Requests',
        message: 'Rate limit exceeded. Please try again shortly.',
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

    // Validate path against allowed tables and RPCs
    const subPath = cleanPath.slice('/rest/v1'.length);
    if (!subPath || subPath === '/') {
      return sendJson(404, { error: 'Not Found', message: 'Endpoint not found.' });
    }

    if (subPath.startsWith('/rpc/')) {
      const rpcName = subPath.slice('/rpc/'.length).split('/')[0];
      if (!allowedRpcsSet.has(rpcName)) {
        return sendJson(404, {
          error: 'Not Found',
          message: `RPC function '${rpcName}' is not allowed or not found.`,
        });
      }
    } else {
      const tableName = subPath.replace(/^\/+/, '').split('/')[0];
      if (!allowedTablesSet.has(tableName)) {
        return sendJson(404, {
          error: 'Not Found',
          message: `Resource table '${tableName}' is not allowed or not found.`,
        });
      }
    }

    // Extract authorization credentials
    const authHeader = req.headers.authorization || '';
    const apikeyHeader = req.headers.apikey || '';
    let bearerToken = null;

    if (authHeader.startsWith('Bearer ')) {
      bearerToken = authHeader.slice(7).trim();
    }

    // 1. Service Role Key Check (Constant Time)
    if (
      cfg.serviceRoleKey &&
      (secureCompare(bearerToken || '', cfg.serviceRoleKey) || secureCompare(apikeyHeader, cfg.serviceRoleKey))
    ) {
      clientRole = 'service_role';
      clientUidHash = 'service_role';

      const postgrestJwt = mintPostgrestJwt({
        role: 'service_role',
        jwtSecret: cfg.postgrestJwtSecret,
        jwtAud: cfg.postgrestJwtAud,
      });

      return proxyToPostgrest(req, res, {
        targetBaseUrl: cfg.postgrestUrl,
        postgrestJwt,
        body: bodyBuf,
      });
    }

    // 2. Firebase ID Token Verification
    if (bearerToken && bearerToken !== cfg.anonKey) {
      try {
        const verified = await verifyFirebaseIdToken(bearerToken, {
          jwksClient,
          projectId: cfg.firebaseProjectId,
        });

        clientRole = 'authenticated';
        clientUidHash = hashUid(verified.uid);

        const postgrestJwt = mintPostgrestJwt({
          role: 'authenticated',
          sub: verified.uid,
          appRole: verified.appRole,
          verified: verified.verified,
          jwtSecret: cfg.postgrestJwtSecret,
          jwtAud: cfg.postgrestJwtAud,
        });

        return proxyToPostgrest(req, res, {
          targetBaseUrl: cfg.postgrestUrl,
          postgrestJwt,
          body: bodyBuf,
        });
      } catch (err) {
        return sendJson(401, {
          error: 'Unauthorized',
          message: `Authentication failed: ${err.message}`,
        });
      }
    }

    // 3. Anonymous Request
    const isAllowlisted = cfg.anonPublicAllowlist.some((allowed) => cleanPath.startsWith(allowed));
    if (isAllowlisted) {
      clientRole = 'anon';

      const postgrestJwt = mintPostgrestJwt({
        role: 'anon',
        jwtSecret: cfg.postgrestJwtSecret,
        jwtAud: cfg.postgrestJwtAud,
      });

      return proxyToPostgrest(req, res, {
        targetBaseUrl: cfg.postgrestUrl,
        postgrestJwt,
        body: bodyBuf,
      });
    }

    // Default deny for non-public paths without authentication
    return sendJson(401, {
      error: 'Unauthorized',
      message: 'Authentication token required for this resource.',
    });
  });

  return {
    server,
    rateLimiter,
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
};
