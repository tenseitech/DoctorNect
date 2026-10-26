'use strict';

module.exports = {
  port: parseInt(process.env.PORT || '3000', 10),
  host: process.env.HOST || '0.0.0.0',
  postgrestUrl: process.env.PGRST_URL || 'http://127.0.0.1:3001',
  firebaseProjectId: process.env.FIREBASE_PROJECT_ID || 'medibond-45fad',
  postgrestJwtSecret: process.env.PGRST_JWT_SECRET || 'doctornect-secure-postgrest-jwt-secret-min32chars',
  postgrestJwtAud: process.env.PGRST_JWT_AUD || 'authenticated',
  serviceRoleKey: process.env.SERVICE_ROLE_KEY || '',
  anonKey: process.env.ANON_KEY || 'doctornect-anon-public-key',
  maxBodySizeBytes: parseInt(process.env.MAX_BODY_SIZE_BYTES || '5242880', 10), // 5 MB
  rateLimitWindowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS || '60000', 10), // 1 min
  rateLimitMaxRequests: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS || '120', 10),
  // Public endpoints accessible without an authenticated user token
  anonPublicAllowlist: [
    '/rest/v1/doctor_directory',
    '/rest/v1/medical_specializations',
    '/rest/v1/banner_configs',
    '/rest/v1/lab_catalog_tests',
    '/healthz',
  ],
};
