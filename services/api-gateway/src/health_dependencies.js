'use strict';

let IORedis = null;
try {
  // eslint-disable-next-line global-require, import/no-extraneous-dependencies
  IORedis = require('ioredis');
} catch (_) {
  IORedis = null;
}

async function checkPostgrestHttp(postgrestUrl, timeoutMs = 3000) {
  const pgRoot = String(postgrestUrl || '').replace(/\/+$/, '');
  if (!pgRoot) {
    return { ok: false, status: 'not_configured' };
  }
  try {
    const upstream = await fetch(`${pgRoot}/`, {
      method: 'GET',
      signal: AbortSignal.timeout(timeoutMs),
    });
    const ok = upstream.ok || upstream.status === 404 || upstream.status === 405;
    return { ok, status: upstream.status };
  } catch (err) {
    return { ok: false, status: 'unreachable' };
  }
}

async function checkRedisPing(redisUrl, timeoutMs = 2000) {
  const url = String(redisUrl || '').trim();
  if (!url) {
    return { ok: false, status: 'not_configured' };
  }
  if (!IORedis) {
    return { ok: false, status: 'client_unavailable' };
  }
  const client = new IORedis(url, {
    maxRetriesPerRequest: 0,
    enableReadyCheck: true,
    lazyConnect: true,
    connectTimeout: timeoutMs,
  });
  try {
    await client.connect();
    const pong = await Promise.race([
      client.ping(),
      new Promise((_, reject) => {
        setTimeout(() => reject(new Error('timeout')), timeoutMs);
      }),
    ]);
    const ok = String(pong || '').toUpperCase() === 'PONG';
    return { ok, status: ok ? 'ok' : 'unexpected_response' };
  } catch (_) {
    return { ok: false, status: 'unreachable' };
  } finally {
    try {
      client.disconnect();
    } catch (_) {
      /* ignore */
    }
  }
}

module.exports = {
  checkPostgrestHttp,
  checkRedisPing,
};