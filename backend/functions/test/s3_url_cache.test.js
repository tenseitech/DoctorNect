'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const { S3Client } = require('@aws-sdk/client-s3');
const { _test } = require('../s3_storage');
const { setRedisClientForTesting } = require('../redis');

const {
  getS3UploadUrlHandler,
  getS3DownloadUrlHandler,
  deleteS3ObjectHandler,
  setS3ClientForTesting,
  s3DownloadUrlCacheKey,
  getCachedDownloadUrl,
  setCachedDownloadUrl,
  invalidateS3DownloadUrlCache,
  invalidateS3DownloadUrlCacheBatch,
  getS3UrlCacheConfig,
} = _test;

function hashKey(value) {
  return crypto.createHash('sha256').update(String(value || '')).digest('hex');
}

function createMockS3Client() {
  const client = new S3Client({
    region: 'ap-south-1',
    credentials: {
      accessKeyId: 'mock-access-key',
      secretAccessKey: 'mock-secret-key',
    },
    requestChecksumCalculation: 'WHEN_REQUIRED',
    responseChecksumValidation: 'WHEN_REQUIRED',
  });
  client.send = async () => ({});
  return client;
}

function createMockDb(initialData = {}) {
  const store = new Map();
  for (const [coll, docs] of Object.entries(initialData)) {
    for (const [id, data] of Object.entries(docs)) {
      store.set(`${coll}/${id}`, data);
    }
  }

  return {
    collection(collName) {
      return {
        doc(docId) {
          const key = `${collName}/${docId}`;
          return {
            async get() {
              const data = store.get(key);
              return {
                id: docId,
                exists: data !== undefined,
                data: () => data || null,
              };
            },
          };
        },
      };
    },
  };
}

function createTrackingRedis() {
  const store = new Map(); // key -> { value, ttl }
  const calls = {
    get: [],
    set: [],
    del: [],
    ttl: [],
  };

  return {
    store,
    calls,
    shouldFail: false,
    async get(key) {
      calls.get.push(key);
      if (this.shouldFail) throw new Error('Redis connection ECONNREFUSED');
      const entry = store.get(key);
      return entry ? entry.value : null;
    },
    async set(key, val, mode, ttl) {
      calls.set.push({ key, val, mode, ttl });
      if (this.shouldFail) throw new Error('Redis connection ECONNREFUSED');
      store.set(key, { value: val, ttl: ttl || 2700 });
      return 'OK';
    },
    async del(...keys) {
      calls.del.push(keys);
      if (this.shouldFail) throw new Error('Redis connection ECONNREFUSED');
      let count = 0;
      for (const k of keys) {
        if (store.delete(k)) count++;
      }
      return count;
    },
    async ttl(key) {
      calls.ttl.push(key);
      if (this.shouldFail) throw new Error('Redis connection ECONNREFUSED');
      const entry = store.get(key);
      return entry ? entry.ttl : -2;
    },
  };
}

const originalEnv = process.env.S3_URL_CACHE;

test.beforeEach(() => {
  setS3ClientForTesting(createMockS3Client());
});

test.afterEach(() => {
  if (originalEnv === undefined) {
    delete process.env.S3_URL_CACHE;
  } else {
    process.env.S3_URL_CACHE = originalEnv;
  }
});

test('S3 URL cache flag default is "off"', () => {
  delete process.env.S3_URL_CACHE;
  assert.equal(getS3UrlCacheConfig(), 'off');
});

test('Flag off -> zero Redis calls on download or upload', async () => {
  process.env.S3_URL_CACHE = 'off';
  const mockRedis = createTrackingRedis();
  setRedisClientForTesting(mockRedis);

  const db = createMockDb({
    users: { p_1: { role: 'patient', profileId: 'p_1' } },
  });
  const auth = { uid: 'p_1' };
  const objectKey = 'health_records/p_1/rec_1/rec_1.pdf';

  const res = await getS3DownloadUrlHandler({ objectKey }, auth, db);
  assert.ok(res.url);
  assert.equal(res.cached, undefined);
  assert.equal(res.expiresIn, 600);
  assert.equal(mockRedis.calls.get.length, 0);
  assert.equal(mockRedis.calls.set.length, 0);
});

test('ORDER MATTERS: auth failure never reaches cache', async () => {
  process.env.S3_URL_CACHE = 'on';
  const mockRedis = createTrackingRedis();
  setRedisClientForTesting(mockRedis);

  const db = createMockDb({
    users: {
      p_unauthorized: { role: 'patient', profileId: 'p_unauthorized' },
      p_owner: { role: 'patient', profileId: 'p_owner' },
    },
  });
  const auth = { uid: 'p_unauthorized' };
  const objectKey = 'health_records/p_owner/rec_1/secret_record.pdf';

  // Seed the cache with a fake URL
  const expectedKey = s3DownloadUrlCacheKey(objectKey);
  mockRedis.store.set(expectedKey, { value: 'https://cached.s3/secret_record.pdf', ttl: 2500 });

  // Unauthorized user attempts download
  await assert.rejects(
    async () => getS3DownloadUrlHandler({ objectKey }, auth, db),
    (err) => {
      assert.equal(err.code, 'permission-denied');
      return true;
    },
  );

  // Assert that mockRedis.get was NEVER called for this key
  assert.equal(mockRedis.calls.get.length, 0, 'Authorization must precede any cache lookup');
});

test('Cache hit returns cached URL with enough remaining life (>= 15 mins)', async () => {
  process.env.S3_URL_CACHE = 'on';
  const mockRedis = createTrackingRedis();
  setRedisClientForTesting(mockRedis);

  const db = createMockDb({
    users: { p_1: { role: 'patient', profileId: 'p_1' } },
  });
  const auth = { uid: 'p_1' };
  const objectKey = 'health_records/p_1/rec_1/rec_1.pdf';
  const cacheKey = s3DownloadUrlCacheKey(objectKey);

  // 1. Initial request misses cache, signs fresh URL and sets Redis cache with TTL 2700s
  const res1 = await getS3DownloadUrlHandler({ objectKey }, auth, db);
  assert.ok(res1.url);
  assert.equal(res1.expiresIn, 3600);
  assert.equal(mockRedis.calls.set.length, 1);
  assert.equal(mockRedis.calls.set[0].key, cacheKey);
  assert.equal(mockRedis.calls.set[0].ttl, 2700, 'Cache TTL must be presigned expiry - 15m (3600 - 900 = 2700)');

  // 2. Second request hits cache
  const res2 = await getS3DownloadUrlHandler({ objectKey }, auth, db);
  assert.equal(res2.cached, true);
  assert.equal(res2.url, res1.url);
  assert.ok(res2.expiresIn >= 900, `Cached URL must have >= 15 min remaining life, got ${res2.expiresIn}`);
});

test('Delete invalidates cached download URL', async () => {
  process.env.S3_URL_CACHE = 'on';
  const mockRedis = createTrackingRedis();
  setRedisClientForTesting(mockRedis);

  const db = createMockDb({
    users: { p_1: { role: 'patient', profileId: 'p_1' } },
  });
  const auth = { uid: 'p_1' };
  const objectKey = 'health_records/p_1/rec_1/rec_to_delete.pdf';
  const cacheKey = s3DownloadUrlCacheKey(objectKey);

  // Seed cache
  mockRedis.store.set(cacheKey, { value: 'https://cached.s3/rec_to_delete.pdf', ttl: 2000 });

  // Delete the object
  const deleteRes = await deleteS3ObjectHandler({ objectKey }, auth, db);
  assert.equal(deleteRes.success, true);

  // Assert del was called for cacheKey
  assert.ok(mockRedis.calls.del.some((call) => call.includes(cacheKey)));
  assert.equal(mockRedis.store.has(cacheKey), false);
});

test('Upload URL generation (overwrite protection) invalidates cached download URL', async () => {
  process.env.S3_URL_CACHE = 'on';
  const mockRedis = createTrackingRedis();
  setRedisClientForTesting(mockRedis);

  const db = createMockDb({
    users: { p_1: { role: 'patient', profileId: 'p_1' } },
  });
  const auth = { uid: 'p_1' };

  // Request upload URL for patient_profile
  const uploadRes = await getS3UploadUrlHandler(
    {
      purpose: 'patient_profile',
      parentId: 'p_1',
      fileName: 'avatar.jpg',
      contentType: 'image/jpeg',
      sizeBytes: 1024,
    },
    auth,
    db,
  );

  const generatedKey = uploadRes.objectKey;
  const cacheKey = s3DownloadUrlCacheKey(generatedKey);

  assert.ok(mockRedis.calls.del.some((call) => call.includes(cacheKey)));
});

test('Batch invalidation removes all specified keys', async () => {
  process.env.S3_URL_CACHE = 'on';
  const mockRedis = createTrackingRedis();
  setRedisClientForTesting(mockRedis);

  const keys = ['patients/p_1/rec1.pdf', 'patients/p_1/rec2.pdf'];
  const cacheKey1 = s3DownloadUrlCacheKey(keys[0]);
  const cacheKey2 = s3DownloadUrlCacheKey(keys[1]);

  mockRedis.store.set(cacheKey1, { value: 'url1', ttl: 1000 });
  mockRedis.store.set(cacheKey2, { value: 'url2', ttl: 1000 });

  await invalidateS3DownloadUrlCacheBatch(keys);

  assert.equal(mockRedis.store.has(cacheKey1), false);
  assert.equal(mockRedis.store.has(cacheKey2), false);
});

test('Fail-open policy: Redis error or down generates fresh presigned URL', async () => {
  process.env.S3_URL_CACHE = 'on';
  const mockRedis = createTrackingRedis();
  mockRedis.shouldFail = true; // Simulating Redis failure / ECONNREFUSED
  setRedisClientForTesting(mockRedis);

  const db = createMockDb({
    users: { p_1: { role: 'patient' } },
  });
  const auth = { uid: 'p_1' };
  const objectKey = 'patients/p_1/health_records/rec_1.pdf';

  // Must not throw; must fail open and generate fresh presigned URL
  const res = await getS3DownloadUrlHandler({ objectKey }, auth, db);
  assert.ok(res.url);
  assert.equal(res.cached, undefined);
  assert.equal(res.expiresIn, 3600);
});
