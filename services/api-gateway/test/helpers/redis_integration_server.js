'use strict';

const { RedisMemoryServer } = require('redis-memory-server');

let server = null;

/**
 * Start ephemeral local Redis for integration tests (not production).
 * @returns {Promise<string>} redis:// URL
 */
async function startRedisIntegrationServer() {
  if (server) return server.getConnectionString();
  server = new RedisMemoryServer({
    instance: {
      port: 0,
      ip: '127.0.0.1',
    },
    autoStart: true,
  });
  const host = await server.getHost();
  const port = await server.getPort();
  return `redis://${host}:${port}`;
}

async function stopRedisIntegrationServer() {
  if (server) {
    await server.stop();
    server = null;
  }
}

module.exports = {
  startRedisIntegrationServer,
  stopRedisIntegrationServer,
};