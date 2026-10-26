'use strict';

const http = require('node:http');
const https = require('node:https');
const { URL } = require('node:url');

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
  // Map /rest/v1/* -> /*
  let forwardPath = req.url;
  if (forwardPath.startsWith('/rest/v1')) {
    forwardPath = forwardPath.slice('/rest/v1'.length);
    if (!forwardPath.startsWith('/')) forwardPath = '/' + forwardPath;
  }

  const forwardHeaders = { ...req.headers };
  delete forwardHeaders.host;
  delete forwardHeaders.authorization;
  delete forwardHeaders.apikey;
  delete forwardHeaders.role;
  delete forwardHeaders['x-role'];

  // Inject PostgREST authorization
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
