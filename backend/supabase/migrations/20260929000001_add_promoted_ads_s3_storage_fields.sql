-- Migration: 20260929000001_add_promoted_ads_s3_storage_fields.sql
-- Description: Add AWS S3 storage reference columns to promoted_ads table
-- Allows referencing AWS S3 object keys directly without breaking legacy image_url references

ALTER TABLE promoted_ads
ADD COLUMN IF NOT EXISTS image_key TEXT,
ADD COLUMN IF NOT EXISTS image_storage VARCHAR(32) DEFAULT 'legacy';

COMMENT ON COLUMN promoted_ads.image_key IS 'AWS S3 canonical object key (e.g. promoted_ads/{providerId}/{adId}/{uuid}.jpg)';
COMMENT ON COLUMN promoted_ads.image_storage IS 'Storage backend identifier: s3, firebase, or legacy';
