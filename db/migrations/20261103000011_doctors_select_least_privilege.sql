-- Restore least-privilege doctors SELECT (regression in round6 used USING (true)).
-- Idempotent: safe to replay on staging and fresh RDS.

DROP POLICY IF EXISTS doctors_select ON public.doctors;
CREATE POLICY doctors_select ON public.doctors
    FOR SELECT TO authenticated
    USING (
        (owner_uid = (auth.jwt() ->> 'sub'))
        OR (doctor_id = private.current_profile_id())
        OR private.is_super_admin()
        OR (
            EXISTS (
                SELECT 1 FROM public.users u
                WHERE u.id = (auth.jwt() ->> 'sub')
                  AND u.role IN ('doctor', 'superAdmin', 'super_admin', 'admin')
            )
            AND (
                EXISTS (
                    SELECT 1 FROM public.patient_doctor_links pdl
                    WHERE pdl.doctor_id = doctors.doctor_id
                      AND pdl.patient_id = private.current_profile_id()
                )
                OR EXISTS (
                    SELECT 1 FROM public.referrals dr
                    WHERE (dr.from_doctor_id = private.current_profile_id() AND dr.to_doctor_id = doctors.doctor_id)
                       OR (dr.to_doctor_id = private.current_profile_id() AND dr.from_doctor_id = doctors.doctor_id)
                )
            )
        )
    );
