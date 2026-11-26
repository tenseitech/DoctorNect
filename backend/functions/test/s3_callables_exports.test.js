'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');

test('Firebase index.js exports S3 callable functions (SEC-10)', () => {
  const index = require('../index');
  assert.equal(typeof index.getS3UploadUrl, 'function');
  assert.equal(typeof index.getS3DownloadUrl, 'function');
  assert.equal(typeof index.getS3DownloadUrls, 'function');
  assert.equal(typeof index.deleteS3Object, 'function');
  assert.equal(typeof index.confirmS3Upload, 'function');
});