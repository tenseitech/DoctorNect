-- RDS replay: same as migration 20261115000003_appointments_sync_origin_replay.sql
BEGIN;
ALTER TABLE public.appointments ADD COLUMN IF NOT EXISTS sync_origin VARCHAR(64) DEFAULT 'patient_supabase';
ALTER TABLE public.patients ADD COLUMN IF NOT EXISTS sync_origin VARCHAR(64) DEFAULT 'patient_supabase';
ALTER TABLE public.prescriptions ADD COLUMN IF NOT EXISTS sync_origin VARCHAR(64) DEFAULT 'doctor_firestore';
COMMIT;