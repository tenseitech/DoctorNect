-- RDS replay parity: book_appointment_atomic expects appointments.sync_origin (sync bridge migration).
BEGIN;

ALTER TABLE public.appointments ADD COLUMN IF NOT EXISTS sync_origin VARCHAR(64) DEFAULT 'patient_supabase';
ALTER TABLE public.patients ADD COLUMN IF NOT EXISTS sync_origin VARCHAR(64) DEFAULT 'patient_supabase';
ALTER TABLE public.prescriptions ADD COLUMN IF NOT EXISTS sync_origin VARCHAR(64) DEFAULT 'doctor_firestore';

COMMIT;