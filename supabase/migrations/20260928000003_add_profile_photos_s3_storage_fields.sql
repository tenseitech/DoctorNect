-- Migration: 20260928000003_add_profile_photos_s3_storage_fields.sql
-- Description: Add AWS S3 storage reference columns to patients, users, and doctors tables
-- Allows referencing AWS S3 object keys directly without breaking legacy photo_url references

ALTER TABLE patients
ADD COLUMN IF NOT EXISTS photo_key TEXT,
ADD COLUMN IF NOT EXISTS photo_storage VARCHAR(32) DEFAULT 'legacy';

COMMENT ON COLUMN patients.photo_key IS 'AWS S3 canonical object key (e.g. patients/{patientId}/profile/{uuid}.ext)';
COMMENT ON COLUMN patients.photo_storage IS 'Storage backend identifier: s3, firebase, base64, or legacy';

ALTER TABLE users
ADD COLUMN IF NOT EXISTS photo_key TEXT,
ADD COLUMN IF NOT EXISTS photo_storage VARCHAR(32) DEFAULT 'legacy';

COMMENT ON COLUMN users.photo_key IS 'AWS S3 canonical object key for avatar';
COMMENT ON COLUMN users.photo_storage IS 'Storage backend identifier: s3, firebase, base64, or legacy';

ALTER TABLE doctors
ADD COLUMN IF NOT EXISTS photo_key TEXT,
ADD COLUMN IF NOT EXISTS photo_storage VARCHAR(32) DEFAULT 'legacy';

COMMENT ON COLUMN doctors.photo_key IS 'AWS S3 canonical object key (e.g. doctor_profiles/{doctorId}/profile/{uuid}.ext)';
COMMENT ON COLUMN doctors.photo_storage IS 'Storage backend identifier: s3, firebase, base64, or legacy';
