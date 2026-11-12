'use strict';

const http = require('node:http');
const https = require('node:https');
const { URL } = require('node:url');

const path = require('node:path');

/**
 * Proxies an authenticated request to the backing PostgREST instance.
 *
 * @param {import('node:http').IncomingMessage} req
 * @param {import('node:http').ServerResponse} res
 * @param {Object} options
 * @param {string} options.targetBaseUrl PostgREST base URL (e.g. http://127.0.0.1:3001)
 * @param {string} options.postgrestJwt Freshly minted HS256 JWT
 * @param {Buffer} [options.body] Request body buffer
 */
function proxyToPostgrest(req, res, options) {
  const targetUrl = new URL(options.targetBaseUrl);
  // Normalize and map /rest/v1/* -> /*
  const [urlPath, queryString] = (req.url || '/').split('?');
  let decodedPath = urlPath;
  try {
    decodedPath = decodeURIComponent(urlPath);
  } catch (_) {}
  let normPath = path.posix.normalize(decodedPath).replace(/^\/+/, '/').replace(/\/+$/, '') || '/';
  if (normPath.startsWith('/rest/v1')) {
    normPath = normPath.slice('/rest/v1'.length);
    if (!normPath.startsWith('/')) normPath = '/' + normPath;
  }
  normPath = normPath.replace(/\/+$/, '') || '/';
  // Lowercase table or rpc resource name for PostgREST
  const parts = normPath.split('/');
  if (parts.length > 1) {
    if (parts[1].toLowerCase() === 'rpc' && parts.length > 2) {
      parts[2] = parts[2].toLowerCase();
    } else {
      parts[1] = parts[1].toLowerCase();
    }
    normPath = parts.join('/');
  }
  const forwardPath = queryString ? `${normPath}?${queryString}` : normPath;

  // Forwarded header positive allowlist (replaces header denylist)
  const FORWARDED_HEADER_ALLOWLIST = new Set([
    'accept',
    'content-type',
    'prefer',
    'range',
    'accept-profile',
    'content-profile',
    'x-client-info',
    'content-range',
    'accept-range',
  ]);

  const forwardHeaders = {};
  for (const [key, val] of Object.entries(req.headers || {})) {
    const lowerKey = key.toLowerCase();
    if (FORWARDED_HEADER_ALLOWLIST.has(lowerKey)) {
      forwardHeaders[lowerKey] = val;
    }
  }

  // Schema Profile Handling: PostgREST is locked to 'public'.
  // Forwarded requests strictly declare public profile.
  forwardHeaders['accept-profile'] = 'public';
  forwardHeaders['content-profile'] = 'public';

  // Inject minted PostgREST authorization
  forwardHeaders.authorization = `Bearer ${options.postgrestJwt}`;

  if (options.body && options.body.length > 0) {
    forwardHeaders['content-length'] = options.body.length;
  }

  const isHttps = targetUrl.protocol === 'https:';
  const transport = isHttps ? https : http;

  const proxyReq = transport.request(
    {
      hostname: targetUrl.hostname,
      port: targetUrl.port || (isHttps ? 443 : 80),
      path: forwardPath,
      method: req.method,
      headers: forwardHeaders,
      timeout: 15000,
    },
    (proxyRes) => {
      // Forward status and headers
      res.writeHead(proxyRes.statusCode, proxyRes.headers);
      proxyRes.pipe(res);
    }
  );

  proxyReq.on('error', (err) => {
    if (!res.headersSent) {
      res.writeHead(502, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Bad Gateway', message: 'Unable to reach PostgREST backend.' }));
    }
  });

  proxyReq.on('timeout', () => {
    proxyReq.destroy();
    if (!res.headersSent) {
      res.writeHead(504, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Gateway Timeout', message: 'PostgREST backend timed out.' }));
    }
  });

  if (options.body && options.body.length > 0) {
    proxyReq.write(options.body);
  }
  proxyReq.end();
}

module.exports = {
  proxyToPostgrest,
};
