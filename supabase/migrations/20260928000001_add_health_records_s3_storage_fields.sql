-- Migration: 20260928000001_add_health_records_s3_storage_fields.sql
-- Description: Add AWS S3 storage reference columns to the health_records table
-- Allows referencing AWS S3 object keys directly without breaking legacy storage_url references

ALTER TABLE health_records
ADD COLUMN IF NOT EXISTS storage_key TEXT,
ADD COLUMN IF NOT EXISTS storage_provider VARCHAR(32) DEFAULT 'legacy';

COMMENT ON COLUMN health_records.storage_key IS 'AWS S3 canonical object key (e.g. health_records/{patientId}/{recordId}/{uuid}.ext)';
COMMENT ON COLUMN health_records.storage_provider IS 'Storage backend identifier: s3, firebase, or legacy';
