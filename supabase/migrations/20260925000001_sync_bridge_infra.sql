-- ============================================================================
-- DOCTORNECT: STAGED SYNC BRIDGE & DEAD-LETTER QUEUE INFRASTRUCTURE
-- ============================================================================
-- Migration: 20260925000001_sync_bridge_infra.sql
-- Description: Supports staged migration where Patient role is on Supabase
--              while Doctor/Pharmacy/Lab/Ambulance remain on Firestore.
--              Includes loop prevention columns, DLQ table, and module status.
-- ============================================================================

-- 1. Sync Dead-Letter Queue (DLQ) Table
CREATE TABLE IF NOT EXISTS public.sync_dead_letter_queue (
    dlq_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    direction VARCHAR(32) NOT NULL CHECK (direction IN ('supabase_to_firestore', 'firestore_to_supabase', 'reconciler')),
    entity_type VARCHAR(64) NOT NULL,
    entity_id VARCHAR(128) NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    error_message TEXT NOT NULL,
    error_stack TEXT,
    retry_count INT NOT NULL DEFAULT 0,
    status VARCHAR(32) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'resolved', 'failed_permanent', 'needs_review')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMPTZ,
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_sync_dlq_status ON public.sync_dead_letter_queue(status, created_at);
CREATE INDEX IF NOT EXISTS idx_sync_dlq_entity ON public.sync_dead_letter_queue(entity_type, entity_id);

-- Enable RLS on DLQ (strict internal table: superuser and service_role only)
ALTER TABLE public.sync_dead_letter_queue ENABLE ROW LEVEL SECURITY;

-- 2. Metadata Columns for Loop Prevention & Monotonicity
ALTER TABLE public.appointments ADD COLUMN IF NOT EXISTS sync_origin VARCHAR(64) DEFAULT 'patient_supabase';
ALTER TABLE public.appointments ADD COLUMN IF NOT EXISTS synced_by VARCHAR(64);

ALTER TABLE public.prescriptions ADD COLUMN IF NOT EXISTS sync_origin VARCHAR(64) DEFAULT 'doctor_firestore';
ALTER TABLE public.prescriptions ADD COLUMN IF NOT EXISTS synced_by VARCHAR(64);

ALTER TABLE public.patients ADD COLUMN IF NOT EXISTS sync_origin VARCHAR(64) DEFAULT 'patient_supabase';
ALTER TABLE public.patients ADD COLUMN IF NOT EXISTS synced_by VARCHAR(64);

ALTER TABLE public.reviews ADD COLUMN IF NOT EXISTS sync_origin VARCHAR(64) DEFAULT 'patient_supabase';
ALTER TABLE public.reviews ADD COLUMN IF NOT EXISTS synced_by VARCHAR(64);

-- 3. Default Remote Configuration for Patient Module Status (Kill-Switch)
INSERT INTO public.system_config (config_key, config_value, updated_at)
VALUES (
    'patient_module_status',
    '{"status": "active", "allow_writes": true, "message": "Normal operational state"}',
    NOW()
)
ON CONFLICT (config_key) DO UPDATE
SET config_value = EXCLUDED.config_value, updated_at = NOW();
