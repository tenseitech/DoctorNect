-- Indexes for FK columns used in RLS EXISTS subqueries (DB-001).

CREATE INDEX IF NOT EXISTS idx_patients_primary_doctor_id
    ON public.patients (primary_doctor_id)
    WHERE primary_doctor_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_patients_invited_doctor_id
    ON public.patients (invited_doctor_id)
    WHERE invited_doctor_id IS NOT NULL;
