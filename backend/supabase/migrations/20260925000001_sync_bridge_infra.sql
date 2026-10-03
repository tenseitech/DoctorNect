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

DROP POLICY IF EXISTS "sync_dead_letter_queue_deny_all" ON public.sync_dead_letter_queue;
CREATE POLICY "sync_dead_letter_queue_deny_all" 
ON public.sync_dead_letter_queue 
FOR ALL 
TO anon, authenticated 
USING (FALSE);

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

-- 4. Double-Booking Prevention Index (DB-level safety net)
-- Prevents a patient from booking multiple active appointments with the same doctor at the same slot
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_active_patient_doctor_slot
ON public.appointments (patient_id, doctor_id, date_time)
WHERE (patient_status != 'cancelled');

-- 5. Completed Appointment Cancellation Defense-in-Depth Safety Net
-- 5A. State Integrity Check Constraint (prevents impossible cancelled+completed state)
ALTER TABLE public.appointments DROP CONSTRAINT IF EXISTS appointments_no_cancel_if_completed_check;
ALTER TABLE public.appointments ADD CONSTRAINT appointments_no_cancel_if_completed_check
CHECK (NOT (patient_status = 'cancelled' AND doctor_status IN ('completed', 'inProgress')));

-- 5B. State Transition Trigger (blocks any update attempting to cancel a completed/in-progress appointment)
CREATE OR REPLACE FUNCTION public.check_appointment_cancellation_integrity()
RETURNS TRIGGER AS $$
BEGIN
    IF (NEW.patient_status = 'cancelled' OR NEW.doctor_status = 'cancelled') THEN
        IF (OLD.doctor_status IN ('completed', 'inProgress', 'noShow') OR OLD.patient_status = 'completed') THEN
            RAISE EXCEPTION 'Cannot cancel an appointment that is already completed or in-progress (current doctor_status: %, patient_status: %)', 
                OLD.doctor_status, OLD.patient_status
                USING ERRCODE = '23514'; -- check_violation
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_completed_appointment_cancellation ON public.appointments;
CREATE TRIGGER trg_prevent_completed_appointment_cancellation
BEFORE UPDATE ON public.appointments
FOR EACH ROW
EXECUTE FUNCTION public.check_appointment_cancellation_integrity();

-- 5C. RLS Policy Hardening (blocks authenticated patients from updating completed appointments)
DROP POLICY IF EXISTS "appointments_update" ON public.appointments;
CREATE POLICY "appointments_update" ON public.appointments
    FOR UPDATE TO authenticated
    USING (
        (
            patient_id = current_profile_id()
            AND doctor_status NOT IN ('completed', 'inProgress', 'noShow')
            AND patient_status != 'completed'
        )
        OR (doctor_id = current_profile_id() AND is_verified_doctor())
        OR is_super_admin()
    )
    WITH CHECK (
        patient_id = (SELECT patient_id FROM public.appointments WHERE appointment_id = appointments.appointment_id)
        AND doctor_id = (SELECT doctor_id FROM public.appointments WHERE appointment_id = appointments.appointment_id)
    );

-- 6. Patient Profile Schema & RLS Hardening
ALTER TABLE public.patients ADD COLUMN IF NOT EXISTS city VARCHAR(128);
ALTER TABLE public.patients ADD COLUMN IF NOT EXISTS state VARCHAR(128);
ALTER TABLE public.patients ADD COLUMN IF NOT EXISTS pincode VARCHAR(16);
ALTER TABLE public.patients ADD COLUMN IF NOT EXISTS country VARCHAR(64) DEFAULT 'India';
ALTER TABLE public.patients ADD COLUMN IF NOT EXISTS conditions TEXT[] DEFAULT ARRAY[]::TEXT[];
ALTER TABLE public.patients ADD COLUMN IF NOT EXISTS allergies TEXT[] DEFAULT ARRAY[]::TEXT[];
ALTER TABLE public.patients ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}'::jsonb;

-- RLS Updates for Patient Self-Management
DROP POLICY IF EXISTS "patients_update" ON public.patients;
CREATE POLICY "patients_update" ON public.patients
    FOR UPDATE TO authenticated
    USING (owner_uid = auth.uid() OR patient_id = current_profile_id() OR is_super_admin())
    WITH CHECK (
        is_super_admin() 
        OR ((owner_uid = auth.uid() OR patient_id = current_profile_id()) AND verified = (SELECT verified FROM public.patients WHERE patient_id = current_profile_id()))
    );

DROP POLICY IF EXISTS "patients_select" ON public.patients;
CREATE POLICY "patients_select" ON public.patients
    FOR SELECT TO authenticated
    USING (owner_uid = auth.uid() OR patient_id = current_profile_id() OR doctor_can_access_patient(patient_id::text) OR is_super_admin());



