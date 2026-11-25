'use strict';

/**
 * Test harness: deterministic gateway test env (avoids host .env / shell leaking prod flags).
 */
process.env.DISABLE_FIREBASE_ADMIN_INIT = '1';
process.env.NODE_ENV = 'test';
process.env.APP_ENV = 'staging';
process.env.FIREBASE_REVOCATION_CHECK = 'true';
delete process.env.RATE_LIMIT_REDIS_URL;
delete process.env.REDIS_URL;
delete process.env.SKIP_GATEWAY_PROD_ASSERT;