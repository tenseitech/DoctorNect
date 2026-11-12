-- Migration: 20260928000002_add_lab_reports_s3_storage_fields.sql
-- Description: Add AWS S3 storage reference columns to lab_bookings and lab_orders tables
-- Allows referencing AWS S3 object keys directly without breaking legacy report_storage_url references

ALTER TABLE lab_bookings
ADD COLUMN IF NOT EXISTS report_storage_key TEXT,
ADD COLUMN IF NOT EXISTS report_storage_provider VARCHAR(32) DEFAULT 'legacy';

COMMENT ON COLUMN lab_bookings.report_storage_key IS 'AWS S3 canonical object key (e.g. lab_reports/{patientId}/{bookingId}/{uuid}.ext)';
COMMENT ON COLUMN lab_bookings.report_storage_provider IS 'Storage backend identifier: s3, firebase, or legacy';

ALTER TABLE lab_orders
ADD COLUMN IF NOT EXISTS report_storage_key TEXT,
ADD COLUMN IF NOT EXISTS report_storage_provider VARCHAR(32) DEFAULT 'legacy';

COMMENT ON COLUMN lab_orders.report_storage_key IS 'AWS S3 canonical object key (e.g. lab_reports/{patientId}/{orderId}/{uuid}.ext)';
COMMENT ON COLUMN lab_orders.report_storage_provider IS 'Storage backend identifier: s3, firebase, or legacy';
