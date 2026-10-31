'use strict';

const DEFAULT_S3_BUCKET = 'doctornect-672027759702-ap-south-1-an';

/**
 * Canonical private vault bucket name for Cloud Functions (presign, delete, audit fields).
 * @param {NodeJS.ProcessEnv} [env]
 * @returns {string}
 */
function getS3BucketName(env = process.env) {
  const primary = String(env.S3_BUCKET || '').trim();
  if (primary) return primary;

  // TODO(2026-06-30): Remove legacy env reads after all deployed functions use S3_BUCKET only.
  const legacyName = String(env.S3_BUCKET_NAME || '').trim();
  if (legacyName) return legacyName;
  const legacyVault = String(env.AWS_S3_VAULT_BUCKET || '').trim();
  if (legacyVault) return legacyVault;

  return DEFAULT_S3_BUCKET;
}

module.exports = {
  getS3BucketName,
  DEFAULT_S3_BUCKET,
};
