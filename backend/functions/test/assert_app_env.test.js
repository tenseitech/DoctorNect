'use strict';

const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const {
  assertAppEnvDatabaseRouting,
  assertProductionRedisTls,
  assertProductionOtpHmacOnly,
  warnProductionOtpHmacFallback,
  assertProductionReviewOtpDisabled,
  assertProductionAppCheckEnforcement,
  assertProductionNoPlaceholderSecrets,
  assertProductionCutoverBoot,
  shouldRunCutoverBootAsserts,
  assertProductionFirestoreForbidden,
} = require('../src/db/assert_app_env');

describe('assertAppEnvDatabaseRouting', () => {
  const original = { ...process.env };

  beforeEach(() => {
    process.env = { ...original };
  });

  afterEach(() => {
    process.env = original;
  });

  it('production rejects missing PROD_GATEWAY_*', () => {
    process.env.APP_ENV = 'production';
    delete process.env.PROD_GATEWAY_URL;
    delete process.env.PROD_GATEWAY_SERVICE_KEY;
    assert.throws(() => assertAppEnvDatabaseRouting(), /PROD_GATEWAY_URL/);
  });

  it('production rejects supabase.co gateway URL', () => {
    process.env.APP_ENV = 'production';
    process.env.PROD_GATEWAY_URL = 'https://abc.supabase.co';
    process.env.PROD_GATEWAY_SERVICE_KEY = 'x'.repeat(40);
    assert.throws(() => assertAppEnvDatabaseRouting(), /supabase\.co/);
  });

  it('staging requires Supabase credentials', () => {
    process.env.APP_ENV = 'staging';
    delete process.env.STAGING_SUPABASE_URL;
    delete process.env.SUPABASE_URL;
    delete process.env.STAGING_SUPABASE_SERVICE_ROLE_KEY;
    assert.throws(() => assertAppEnvDatabaseRouting(), /STAGING_SUPABASE_URL/);
  });

  it('staging passes with STAGING_* set', () => {
    process.env.APP_ENV = 'staging';
    process.env.STAGING_SUPABASE_URL = 'https://staging.example.supabase.co';
    process.env.STAGING_SUPABASE_SERVICE_ROLE_KEY = 'staging-key-' + 'x'.repeat(32);
    assert.doesNotThrow(() => assertAppEnvDatabaseRouting());
  });
});

describe('assertProductionRedisTls', () => {
  const original = { ...process.env };

  beforeEach(() => {
    process.env = { ...original };
  });

  afterEach(() => {
    process.env = original;
  });

  it('production rejects REDIS_TLS=false', () => {
    process.env.APP_ENV = 'production';
    process.env.REDIS_TLS = 'false';
    assert.throws(() => assertProductionRedisTls(), /REDIS_TLS/);
  });

  it('production rejects redis:// host URL', () => {
    process.env.APP_ENV = 'production';
    process.env.REDIS_HOST = 'redis://cache.example:6379';
    delete process.env.REDIS_TLS;
    assert.throws(() => assertProductionRedisTls(), /plaintext|rediss/i);
  });

  it('production rejects plaintext REDIS_URL', () => {
    process.env.APP_ENV = 'production';
    delete process.env.REDIS_HOST;
    process.env.REDIS_URL = 'redis://cache.example:6379';
    process.env.REDIS_TLS = 'true';
    assert.throws(() => assertProductionRedisTls(), /REDIS_URL|plaintext/i);
  });

  it('production allows rediss:// or TLS default with hostname', () => {
    process.env.APP_ENV = 'production';
    process.env.REDIS_PASSWORD = 'unit-test-redis-auth';
    process.env.REDIS_HOST = 'rediss://cache.example:6380';
    assert.doesNotThrow(() => assertProductionRedisTls());

    process.env.REDIS_HOST = 'cache.internal';
    process.env.REDIS_TLS = 'true';
    assert.doesNotThrow(() => assertProductionRedisTls());
    delete process.env.REDIS_PASSWORD;
  });

  it('production rejects Redis without AUTH password', () => {
    process.env.APP_ENV = 'production';
    process.env.REDIS_HOST = 'cache.internal';
    process.env.REDIS_TLS = 'true';
    delete process.env.REDIS_PASSWORD;
    const { buildRedisOptions } = require('../src/config/redis');
    assert.throws(() => buildRedisOptions(), (err) => err.code === 'REDIS_INSECURE_CONFIG');
  });

  it('staging skips Redis TLS enforcement', () => {
    process.env.APP_ENV = 'staging';
    process.env.REDIS_TLS = 'false';
    process.env.REDIS_HOST = 'redis://127.0.0.1:6379';
    assert.doesNotThrow(() => assertProductionRedisTls());
  });
});

describe('assertProductionOtpHmacOnly', () => {
  const original = { ...process.env };

  beforeEach(() => {
    process.env = { ...original };
  });

  afterEach(() => {
    process.env = original;
  });

  it('production rejects ALLOW_LEGACY_UNSALTED_OTP_HASH', () => {
    process.env.APP_ENV = 'production';
    process.env.ALLOW_LEGACY_UNSALTED_OTP_HASH = 'true';
    assert.throws(() => assertProductionOtpHmacOnly(), /ALLOW_LEGACY_UNSALTED_OTP_HASH/);
  });

  it('staging allows legacy OTP flag', () => {
    process.env.APP_ENV = 'staging';
    process.env.ALLOW_LEGACY_UNSALTED_OTP_HASH = 'true';
    assert.doesNotThrow(() => assertProductionOtpHmacOnly());
  });
});

describe('warnProductionOtpHmacFallback', () => {
  const original = { ...process.env };

  beforeEach(() => {
    process.env = { ...original };
  });

  afterEach(() => {
    process.env = original;
  });

  it('warns in production when MSG91 is set without OTP_HMAC_SECRET', () => {
    process.env.APP_ENV = 'production';
    process.env.MSG91_AUTH_KEY = 'placeholder-key';
    delete process.env.OTP_HMAC_SECRET;
    const warnings = [];
    warnProductionOtpHmacFallback(process.env, (msg) => warnings.push(msg));
    assert.equal(warnings.length, 1);
    assert.match(warnings[0], /OTP_HMAC_SECRET/);
  });

  it('does not warn when OTP_HMAC_SECRET is configured', () => {
    process.env.APP_ENV = 'production';
    process.env.MSG91_AUTH_KEY = 'placeholder-key';
    process.env.OTP_HMAC_SECRET = 'a'.repeat(32);
    const warnings = [];
    warnProductionOtpHmacFallback(process.env, (msg) => warnings.push(msg));
    assert.equal(warnings.length, 0);
  });
});

describe('assertProductionAppCheckEnforcement', () => {
  const original = { ...process.env };

  beforeEach(() => {
    process.env = { ...original };
  });

  afterEach(() => {
    process.env = original;
  });

  it('medibond-45fad rejects ENFORCE_OTP_APP_CHECK=false', () => {
    process.env.GCLOUD_PROJECT = 'medibond-45fad';
    process.env.ENFORCE_OTP_APP_CHECK = 'false';
    process.env.ENFORCE_ABUSE_APP_CHECK = 'true';
    assert.throws(() => assertProductionAppCheckEnforcement(), /ENFORCE_OTP_APP_CHECK/);
  });

  it('medibond-45fad rejects ENFORCE_ABUSE_APP_CHECK=0', () => {
    process.env.GCLOUD_PROJECT = 'medibond-45fad';
    process.env.ENFORCE_OTP_APP_CHECK = 'true';
    process.env.ENFORCE_ABUSE_APP_CHECK = '0';
    assert.throws(() => assertProductionAppCheckEnforcement(), /ENFORCE_ABUSE_APP_CHECK/);
  });

  it('medibond-staging allows app check flags off', () => {
    process.env.GCLOUD_PROJECT = 'medibond-staging';
    process.env.APP_ENV = 'staging';
    process.env.ENFORCE_OTP_APP_CHECK = 'false';
    assert.doesNotThrow(() => assertProductionAppCheckEnforcement());
  });
});

describe('assertProductionReviewerOtpPolicy', () => {
  const original = { ...process.env };

  beforeEach(() => {
    process.env = { ...original };
  });

  afterEach(() => {
    process.env = original;
  });

  it('production rejects plain REVIEW_FIXED_OTP when reviewer disabled', () => {
    process.env.APP_ENV = 'production';
    process.env.REVIEWER_OTP_ENABLED = 'false';
    process.env.REVIEW_FIXED_OTP = '123456';
    assert.throws(() => assertProductionReviewOtpDisabled(), /REVIEW_FIXED_OTP/);
  });

  it('production requires demo routing when reviewer enabled', () => {
    process.env.APP_ENV = 'production';
    process.env.REVIEWER_OTP_ENABLED = 'true';
    process.env.REVIEW_ACCESS_UNTIL = '2099-01-01T00:00:00.000Z';
    process.env.REVIEW_PATIENT_PHONES = '9999900001';
    assert.throws(() => assertProductionReviewOtpDisabled(), /DEMO_REAL_ROUTING_ENABLED/);
  });

  it('staging allows reviewer OTP flags', () => {
    process.env.APP_ENV = 'staging';
    process.env.REVIEWER_OTP_ENABLED = 'true';
    process.env.REVIEW_FIXED_OTP = '123456';
    assert.doesNotThrow(() => assertProductionReviewOtpDisabled());
  });
});

describe('legacy Firestore deploy boot', () => {
  const original = { ...process.env };

  beforeEach(() => {
    process.env = { ...original };
  });

  afterEach(() => {
    process.env = original;
  });

  it('legacy Firestore env (flags unset) no longer skips production boot asserts', () => {
    process.env.USE_SUPABASE_DB_DOCTOR_PATIENT = '0';
    delete process.env.FIRESTORE_FORBIDDEN;
    process.env.APP_ENV = 'production';
    delete process.env.NODE_ENV;
    delete process.env.SKIP_APP_ENV_DB_ASSERT;
    assert.equal(shouldRunCutoverBootAsserts(process.env), true);
  });

  it('production requires FIRESTORE_FORBIDDEN=1', () => {
    process.env.APP_ENV = 'production';
    delete process.env.FIRESTORE_FORBIDDEN;
    assert.throws(() => assertProductionFirestoreForbidden(process.env), /FIRESTORE_FORBIDDEN=1/);
    process.env.FIRESTORE_FORBIDDEN = '1';
    assert.doesNotThrow(() => assertProductionFirestoreForbidden(process.env));
    process.env.APP_ENV = 'staging';
    delete process.env.FIRESTORE_FORBIDDEN;
    assert.doesNotThrow(() => assertProductionFirestoreForbidden(process.env));
  });

  it('SKIP_APP_ENV_DB_ASSERT cannot disable asserts on a deployed production runtime', () => {
    process.env.APP_ENV = 'production';
    delete process.env.NODE_ENV;
    process.env.SKIP_APP_ENV_DB_ASSERT = 'true';
    process.env.K_SERVICE = 'unit-test-service';
    assert.equal(shouldRunCutoverBootAsserts(process.env), true);
    delete process.env.K_SERVICE;
    assert.equal(shouldRunCutoverBootAsserts(process.env), false);
  });

  it('FIRESTORE_FORBIDDEN=1 requires cutover boot asserts', () => {
    process.env.USE_SUPABASE_DB_DOCTOR_PATIENT = '0';
    process.env.FIRESTORE_FORBIDDEN = '1';
    delete process.env.APP_ENV;
    delete process.env.NODE_ENV;
    delete process.env.SKIP_APP_ENV_DB_ASSERT;
    assert.equal(shouldRunCutoverBootAsserts(process.env), true);
  });
});

describe('assertProductionCutoverBoot', () => {
  const original = { ...process.env };

  beforeEach(() => {
    process.env = { ...original };
  });

  afterEach(() => {
    process.env = original;
  });

  it('production passes with dummy cutover env', () => {
    process.env.APP_ENV = 'production';
    process.env.FIRESTORE_FORBIDDEN = '1';
    process.env.DATABASE_URL = 'postgresql://user:pass@127.0.0.1:5433/doctornect';
    process.env.PROD_GATEWAY_URL = 'https://gateway.example.doctornect.in';
    process.env.REDIS_HOST = 'tls-redis.example';
    process.env.MSG91_AUTH_KEY = 'dummy-msg91-key-for-unit-test';
    assert.doesNotThrow(() => assertProductionCutoverBoot());
  });

  it('production fails when FIRESTORE_FORBIDDEN missing', () => {
    process.env.APP_ENV = 'production';
    delete process.env.FIRESTORE_FORBIDDEN;
    process.env.DATABASE_URL = 'postgresql://user:pass@127.0.0.1:5433/doctornect';
    process.env.PROD_GATEWAY_URL = 'https://gateway.example.doctornect.in';
    process.env.REDIS_HOST = 'tls-redis.example';
    process.env.MSG91_AUTH_KEY = 'dummy-msg91-key-for-unit-test';
    assert.throws(() => assertProductionCutoverBoot(), /FIRESTORE_FORBIDDEN/);
  });

  it('staging skips production boot guard', () => {
    process.env.APP_ENV = 'staging';
    delete process.env.FIRESTORE_FORBIDDEN;
    delete process.env.DATABASE_URL;
    assert.doesNotThrow(() => assertProductionCutoverBoot());
  });

  it('production passes without DATABASE_URL (gateway-only deploy)', () => {
    process.env.APP_ENV = 'production';
    process.env.FIRESTORE_FORBIDDEN = '1';
    delete process.env.DATABASE_URL;
    process.env.PROD_GATEWAY_URL = 'https://gateway.example.doctornect.in';
    process.env.REDIS_HOST = 'tls-redis.example';
    process.env.MSG91_AUTH_KEY = 'dummy-msg91-key-for-unit-test';
    assert.doesNotThrow(() => assertProductionCutoverBoot());
  });
});

describe('assertProductionNoPlaceholderSecrets', () => {
  const original = { ...process.env };

  beforeEach(() => {
    process.env = { ...original };
  });

  afterEach(() => {
    process.env = original;
  });

  it('production rejects your-secret on MSG91_AUTH_KEY', () => {
    process.env.APP_ENV = 'production';
    process.env.MSG91_AUTH_KEY = 'your-secret';
    assert.throws(() => assertProductionNoPlaceholderSecrets(), /placeholders/);
  });

  it('production rejects your-prefix on OTP_HMAC_SECRET', () => {
    process.env.APP_ENV = 'production';
    process.env.OTP_HMAC_SECRET = 'your-otp-hmac-secret';
    assert.throws(() => assertProductionNoPlaceholderSecrets(), /OTP_HMAC_SECRET/);
  });

  it('production accepts real configured secrets', () => {
    process.env.APP_ENV = 'production';
    process.env.MSG91_AUTH_KEY = 'configured-msg91-key-value';
    process.env.OTP_HMAC_SECRET = 'a'.repeat(32);
    assert.doesNotThrow(() => assertProductionNoPlaceholderSecrets());
  });
});
