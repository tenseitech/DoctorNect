# SQL review packet (proposed migrations + staging probe)

Self-review checklist (proposed SQL only). Line numbers refer to the copies below.

| Item | Result | Notes |
|------|--------|--------|
| **(a)** `update_lab_booking_status` / `update_lab_order_status`: JWT required; lab/patient+lab owner or doctor+doctor owner (per function); state-machine branches match `db/migrations/20261026000001_rpc_null_safe_authz.sql` L620–711 (booking) and L718–809 (order); added `p_report_storage_key` is extra (does not remove or weaken transition rules). | **PASS** | Compare proposed `20261103000015` L50–121 (booking authz + transitions) and L172–244 (order). Deployed baseline: `20261026000001` L639–693 / L762–791. |
| **(b)** Report key prefix matches S3 presign object key; only lab or admin may set. | **PASS** | Prefix `lab_reports/{patientId}/{bookingId\|orderId}/` — JS: `backend/functions/s3_storage.js` L513 (`objectKey = \`lab_reports/${patientId}/${bookingId}/${uuid}.${ext}\``). Proposed validation: `20261103000015` L94–97 (booking), L217–219 (order). Restrictions: L86–93, L208–213. |
| **(c)** `20261103000014`: each `DROP POLICY` name exists in migrations; `appointments_select` / `appointments_update` retain `owner_uid` + `family_members` branches; helpers reference real columns. | **PASS** | Policy origins: `appointments_select` — `20261102000001_round6_guards_and_kyc.sql` L46; `appointments_update` — `20261026000001_rpc_null_safe_authz.sql` L1788; `prescriptions_select` — `20261021000002_phase_d_pharmacy_lab_ambulance.sql` L133; `lab_bookings_update` — `20260930000004_access_gap_fixes.sql` L370; `lab_orders_insert` / `lab_orders_update` — `20261020000001_consolidated_firebase_schema_and_rls.sql` L2285 / L2293; `pharmacy_conn_policy` — `20260923000002_doctornect_rls.sql` L536; `pharmacy_connections_select` / `write` — `20261020000001_consolidated_firebase_schema_and_rls.sql` L2087 / L2096; `lab_conn_policy` — `20260923000002_doctornect_rls.sql` L547; `lab_connections_select` / `write` — `20261020000001_consolidated_firebase_schema_and_rls.sql` L2220 / L2229; `doc_links_select` — `20260923000002_doctornect_rls.sql` L234; `pdl_select` — `20261020000001_consolidated_firebase_schema_and_rls.sql` L1816. Helpers use `labs.deactivated`, `medical_stores.deactivated` (schema `20260923000001_doctornect_schema.sql`). |
| **(d)** No new `SECURITY DEFINER` without `SET search_path = ''` and without revoking from `PUBLIC`/`anon`. | **PASS** | `private.is_verified_lab` / `is_verified_medical_store`: `20261103000014` L8–41; RPCs: `20261103000015` L29–38, L150–159 + `REVOKE` L147–148, L270–271. `20261103000016` adds no `SECURITY DEFINER` functions. |
| **(e)** Staging script `rls_staging_verified_role_matrix.sql`: probes assert expected counts/row counts and raise on mismatch. | **PASS** | `pg_temp.assert_count` L15–28; `DO` blocks L73–84, L95–105, L112–123, L130–141, L146–156. |

**Change vs earlier draft:** `20261103000016` was revised to extend the existing `public.in_app_notifications` table (not a duplicate table) and to use `driver_id` / policy names `amb_requests_*` consistent with `20261020000001_consolidated_firebase_schema_and_rls.sql` L2385–2398.

---

## Full text: `db/proposed/20261103000014_proposed_role_verified_rls_hardening.sql`

```sql
-- PROPOSED (do not apply): verified-role checks on provider policies.
-- Rebuilt from latest migration definitions per policy (not 20261020-only baseline).
-- Drops legacy duplicate policy names (OR-combined) before CREATE.

-- ---------------------------------------------------------------------------
-- Helpers (labs.deactivated / medical_stores.deactivated: 20260923000001_doctornect_schema.sql)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.is_verified_lab()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.labs
        WHERE lab_id = private.current_profile_id()
          AND verified IS TRUE
          AND COALESCE(deactivated, FALSE) IS FALSE
    );
$$;

CREATE OR REPLACE FUNCTION private.is_verified_medical_store()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.medical_stores
        WHERE store_id = private.current_profile_id()
          AND verified IS TRUE
          AND COALESCE(deactivated, FALSE) IS FALSE
    );
$$;

REVOKE ALL ON FUNCTION private.is_verified_lab() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.is_verified_medical_store() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_verified_lab() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.is_verified_medical_store() TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Appointments (base: select 20261102000001, update 20261026000001)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "appointments_select" ON public.appointments;
CREATE POLICY "appointments_select" ON public.appointments
    FOR SELECT TO authenticated
    USING (
        patient_id = private.current_profile_id()
        OR (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR EXISTS (
            SELECT 1 FROM public.patients p
            WHERE p.patient_id = appointments.patient_id
              AND p.owner_uid = (auth.jwt() ->> 'sub')
        )
        OR EXISTS (
            SELECT 1 FROM public.family_members fm
            WHERE fm.member_id = appointments.patient_id
              AND fm.patient_id = private.current_profile_id()
        )
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "appointments_update" ON public.appointments;
CREATE POLICY "appointments_update" ON public.appointments
    FOR UPDATE TO authenticated
    USING (
        patient_id = private.current_profile_id()
        OR (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR EXISTS (
            SELECT 1 FROM public.patients p
            WHERE p.patient_id = appointments.patient_id
              AND p.owner_uid = private.current_firebase_uid()
        )
        OR EXISTS (
            SELECT 1 FROM public.family_members fm
            WHERE fm.member_id = appointments.patient_id
              AND fm.patient_id = private.current_profile_id()
        )
        OR private.is_super_admin()
    )
    WITH CHECK (
        (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR (
            (
                patient_id = private.current_profile_id()
                OR EXISTS (
                    SELECT 1 FROM public.patients p
                    WHERE p.patient_id = appointments.patient_id
                      AND p.owner_uid = private.current_firebase_uid()
                )
                OR EXISTS (
                    SELECT 1 FROM public.family_members fm
                    WHERE fm.member_id = appointments.patient_id
                      AND fm.patient_id = private.current_profile_id()
                )
            )
            AND patient_status = 'cancelled'
        )
        OR private.is_super_admin()
    );

-- ---------------------------------------------------------------------------
-- Prescriptions SELECT (base: 20261021000002_phase_d_pharmacy_lab_ambulance.sql)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "prescriptions_select" ON public.prescriptions;
CREATE POLICY "prescriptions_select" ON public.prescriptions
    FOR SELECT TO authenticated
    USING (
        patient_id = private.current_profile_id()
        OR (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR EXISTS (
            SELECT 1 FROM public.pharmacy_deliveries pd
            WHERE pd.prescription_id = prescriptions.prescription_id
              AND (
                  pd.store_id = private.current_profile_id()
                  OR EXISTS (
                      SELECT 1 FROM public.medical_stores ms
                      WHERE ms.store_id = pd.store_id AND ms.owner_uid = (auth.jwt() ->> 'sub')
                  )
              )
        )
        OR private.is_super_admin()
    );

-- ---------------------------------------------------------------------------
-- Lab bookings UPDATE (base: 20260930000004_access_gap_fixes.sql)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "lab_bookings_update" ON public.lab_bookings;
CREATE POLICY "lab_bookings_update" ON public.lab_bookings
    FOR UPDATE TO authenticated
    USING (
        (lab_id = private.current_profile_id() AND private.is_verified_lab())
        OR patient_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        (lab_id = private.current_profile_id() AND private.is_verified_lab())
        OR (patient_id = private.current_profile_id() AND status = 'cancelled')
        OR private.is_super_admin()
    );

-- ---------------------------------------------------------------------------
-- Lab orders (base: 20261020000001 consolidated lab_orders_*)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "lab_orders_insert" ON public.lab_orders;
CREATE POLICY "lab_orders_insert" ON public.lab_orders
    FOR INSERT TO authenticated
    WITH CHECK (
        (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "lab_orders_update" ON public.lab_orders;
CREATE POLICY "lab_orders_update" ON public.lab_orders
    FOR UPDATE TO authenticated
    USING (
        (lab_id = private.current_profile_id() AND private.is_verified_lab())
        OR (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR private.is_super_admin()
    )
    WITH CHECK (
        (lab_id = private.current_profile_id() AND private.is_verified_lab())
        OR (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR private.is_super_admin()
    );

-- ---------------------------------------------------------------------------
-- Pharmacy connections — drop ALL legacy names (609230002 pharmacy_conn_policy + consolidated)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "pharmacy_conn_policy" ON public.pharmacy_connections;
DROP POLICY IF EXISTS "pharmacy_connections_select" ON public.pharmacy_connections;
DROP POLICY IF EXISTS "pharmacy_connections_write" ON public.pharmacy_connections;
CREATE POLICY "pharmacy_connections_select" ON public.pharmacy_connections
    FOR SELECT TO authenticated
    USING (
        (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR (medical_store_id = private.current_profile_id() AND private.is_verified_medical_store())
        OR private.is_super_admin()
    );
CREATE POLICY "pharmacy_connections_write" ON public.pharmacy_connections
    FOR ALL TO authenticated
    USING (
        (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR (medical_store_id = private.current_profile_id() AND private.is_verified_medical_store())
        OR private.is_super_admin()
    )
    WITH CHECK (
        (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR (medical_store_id = private.current_profile_id() AND private.is_verified_medical_store())
        OR private.is_super_admin()
    );

-- ---------------------------------------------------------------------------
-- Lab connections — drop legacy lab_conn_policy + consolidated names
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "lab_conn_policy" ON public.lab_connections;
DROP POLICY IF EXISTS "lab_connections_select" ON public.lab_connections;
DROP POLICY IF EXISTS "lab_connections_write" ON public.lab_connections;
CREATE POLICY "lab_connections_select" ON public.lab_connections
    FOR SELECT TO authenticated
    USING (
        (private.is_verified_doctor() AND doctor_id = private.current_profile_id())
        OR (lab_id = private.current_profile_id() AND private.is_verified_lab())
        OR private.is_super_admin()
    );
CREATE POLICY "lab_connections_write" ON public.lab_connections
    FOR ALL TO authenticated
    USING (
        (private.is_verified_doctor() AND doctor_id = private.current_profile_id())
        OR (lab_id = private.current_profile_id() AND private.is_verified_lab())
        OR private.is_super_admin()
    )
    WITH CHECK (
        (private.is_verified_doctor() AND doctor_id = private.current_profile_id())
        OR (lab_id = private.current_profile_id() AND private.is_verified_lab())
        OR private.is_super_admin()
    );

-- ---------------------------------------------------------------------------
-- Patient doctor links — drop doc_links_select (609230002) + pdl_select (consolidated)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "doc_links_select" ON public.patient_doctor_links;
DROP POLICY IF EXISTS "pdl_select" ON public.patient_doctor_links;
CREATE POLICY "pdl_select" ON public.patient_doctor_links
    FOR SELECT TO authenticated
    USING (
        (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR EXISTS (
            SELECT 1 FROM public.patients p
            WHERE p.patient_id = patient_doctor_links.patient_id
              AND p.owner_uid = (auth.jwt() ->> 'sub')
        )
        OR private.is_super_admin()
    );
```

---

## Full text: `db/proposed/20261103000015_proposed_lab_report_storage_key.sql`

```sql
-- PROPOSED (do not apply): report_storage_key + RPC hardening.
-- Base RPC bodies: db/migrations/20261026000001_rpc_null_safe_authz.sql (latest deployed).
-- S3 key shape: lab_reports/{patientId}/{bookingId|orderId}/{filename} (backend/functions/s3_storage.js).

DROP FUNCTION IF EXISTS public.update_lab_booking_status(VARCHAR, VARCHAR, TEXT);
DROP FUNCTION IF EXISTS public.update_lab_booking_status(character varying, character varying, text);

DROP FUNCTION IF EXISTS public.update_lab_order_status(VARCHAR, VARCHAR, TEXT);
DROP FUNCTION IF EXISTS public.update_lab_order_status(character varying, character varying, text);

ALTER TABLE public.lab_bookings
  ADD COLUMN IF NOT EXISTS report_storage_key TEXT;

ALTER TABLE public.lab_orders
  ADD COLUMN IF NOT EXISTS report_storage_key TEXT;

UPDATE public.lab_bookings
SET report_storage_key = notes
WHERE report_storage_key IS NULL
  AND notes IS NOT NULL
  AND notes ~ '^lab_reports/[^[:space:]]+$';

UPDATE public.lab_orders
SET report_storage_key = notes
WHERE report_storage_key IS NULL
  AND notes IS NOT NULL
  AND notes ~ '^lab_reports/[^[:space:]]+$';

CREATE OR REPLACE FUNCTION public.update_lab_booking_status(
    p_booking_id VARCHAR(64),
    p_new_status VARCHAR(32),
    p_notes TEXT DEFAULT NULL,
    p_report_storage_key TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_caller_uid TEXT;
    v_profile_id TEXT;
    v_booking public.lab_bookings%ROWTYPE;
    v_is_lab BOOLEAN;
    v_is_patient BOOLEAN;
    v_is_admin BOOLEAN;
    v_key TEXT;
    v_expected_prefix TEXT;
BEGIN
    v_caller_uid := NULLIF(COALESCE(
        auth.jwt() ->> 'sub',
        auth.jwt() ->> 'uid',
        current_setting('request.jwt.claims', true)::jsonb ->> 'sub'
    ), '');
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    v_profile_id := private.current_profile_id();
    v_is_admin := COALESCE(private.is_super_admin(), FALSE);

    IF v_profile_id IS NULL AND NOT v_is_admin THEN
        RAISE EXCEPTION 'FORBIDDEN: Caller has no registered profile.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_booking
    FROM public.lab_bookings
    WHERE booking_id = p_booking_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Lab booking % not found', p_booking_id USING ERRCODE = 'P0002';
    END IF;

    v_is_lab := (v_booking.lab_id IS NOT DISTINCT FROM v_profile_id) OR EXISTS (
        SELECT 1 FROM public.labs l WHERE l.lab_id = v_booking.lab_id AND l.owner_uid = v_caller_uid
    );
    v_is_patient := (v_booking.patient_id IS NOT DISTINCT FROM v_profile_id) OR EXISTS (
        SELECT 1 FROM public.patients p WHERE p.patient_id = v_booking.patient_id AND p.owner_uid = v_caller_uid
    );

    IF NOT (COALESCE(v_is_lab, FALSE) OR COALESCE(v_is_patient, FALSE) OR v_is_admin) THEN
        RAISE EXCEPTION 'Unauthorized to update lab booking' USING ERRCODE = '42501';
    END IF;

    v_key := NULLIF(trim(both from p_report_storage_key), '');
    IF v_key IS NOT NULL THEN
        IF COALESCE(v_is_patient, FALSE) AND NOT v_is_admin THEN
            RAISE EXCEPTION 'Patients cannot set report storage key' USING ERRCODE = '42501';
        END IF;
        IF NOT (COALESCE(v_is_lab, FALSE) OR v_is_admin) THEN
            RAISE EXCEPTION 'Only the assigned lab or an admin may set report storage key' USING ERRCODE = '42501';
        END IF;
        v_expected_prefix := 'lab_reports/' || v_booking.patient_id || '/' || p_booking_id || '/';
        IF v_key NOT LIKE v_expected_prefix || '%' OR position(E'\n' in v_key) > 0 OR position(E'\t' in v_key) > 0 THEN
            RAISE EXCEPTION 'Invalid report_storage_key prefix for booking %', p_booking_id USING ERRCODE = '22023';
        END IF;
    END IF;

    IF v_is_patient AND NOT v_is_admin THEN
        IF p_new_status != 'cancelled' THEN
            RAISE EXCEPTION 'Patients can only cancel lab bookings' USING ERRCODE = '42501';
        END IF;
        IF v_booking.status IS DISTINCT FROM 'confirmed' THEN
            RAISE EXCEPTION 'Patient cannot cancel after sample collection (status: %)', v_booking.status
                USING ERRCODE = '42501';
        END IF;
        IF v_key IS NOT NULL THEN
            RAISE EXCEPTION 'Patients cannot set report storage key' USING ERRCODE = '42501';
        END IF;
    ELSIF v_is_lab THEN
        IF v_booking.status = 'confirmed' AND p_new_status NOT IN ('sampleCollected', 'cancelled') THEN
            RAISE EXCEPTION 'Invalid transition from confirmed to %', p_new_status USING ERRCODE = '22023';
        ELSIF v_booking.status = 'sampleCollected' AND p_new_status NOT IN ('inAnalysis') THEN
            RAISE EXCEPTION 'Invalid transition from sampleCollected to %', p_new_status USING ERRCODE = '22023';
        ELSIF v_booking.status = 'inAnalysis' AND p_new_status NOT IN ('completed') THEN
            RAISE EXCEPTION 'Invalid transition from inAnalysis to %', p_new_status USING ERRCODE = '22023';
        ELSIF v_booking.status IN ('completed', 'cancelled') THEN
            RAISE EXCEPTION 'Booking is already in terminal state: %', v_booking.status USING ERRCODE = '22023';
        END IF;
    END IF;

    PERFORM set_config('app.allow_lab_status_change', 'true', true);

    UPDATE public.lab_bookings
    SET status = p_new_status,
        notes = CASE
            WHEN p_notes IS NOT NULL AND (p_notes !~ '^lab_reports/') THEN p_notes
            ELSE notes
        END,
        report_storage_key = COALESCE(v_key, report_storage_key),
        report_s3_key = COALESCE(v_key, report_s3_key),
        updated_at = CURRENT_TIMESTAMP
    WHERE booking_id = p_booking_id;

    PERFORM set_config('app.allow_lab_status_change', '', true);

    RETURN jsonb_build_object(
        'success', true,
        'booking_id', p_booking_id,
        'old_status', v_booking.status,
        'new_status', p_new_status
    );
END;
$$;

REVOKE ALL ON FUNCTION public.update_lab_booking_status(VARCHAR, VARCHAR, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_lab_booking_status(VARCHAR, VARCHAR, TEXT, TEXT) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.update_lab_order_status(
    p_order_id VARCHAR(64),
    p_new_status VARCHAR(32),
    p_notes TEXT DEFAULT NULL,
    p_report_storage_key TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_caller_uid TEXT;
    v_profile_id TEXT;
    v_order public.lab_orders%ROWTYPE;
    v_is_lab BOOLEAN;
    v_is_doctor BOOLEAN;
    v_is_admin BOOLEAN;
    v_key TEXT;
    v_patient_id TEXT;
    v_expected_prefix TEXT;
BEGIN
    v_caller_uid := NULLIF(COALESCE(
        auth.jwt() ->> 'sub',
        auth.jwt() ->> 'uid',
        current_setting('request.jwt.claims', true)::jsonb ->> 'sub'
    ), '');
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    v_profile_id := private.current_profile_id();
    v_is_admin := COALESCE(private.is_super_admin(), FALSE);

    IF v_profile_id IS NULL AND NOT v_is_admin THEN
        RAISE EXCEPTION 'FORBIDDEN: Caller has no registered profile.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_order
    FROM public.lab_orders
    WHERE order_id = p_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Lab order % not found', p_order_id USING ERRCODE = 'P0002';
    END IF;

    v_is_lab := (v_order.lab_id IS NOT DISTINCT FROM v_profile_id) OR EXISTS (
        SELECT 1 FROM public.labs l WHERE l.lab_id = v_order.lab_id AND l.owner_uid = v_caller_uid
    );
    v_is_doctor := (v_order.doctor_id IS NOT DISTINCT FROM v_profile_id) OR EXISTS (
        SELECT 1 FROM public.doctors d WHERE d.doctor_id = v_order.doctor_id AND d.owner_uid = v_caller_uid
    );

    IF NOT (COALESCE(v_is_lab, FALSE) OR COALESCE(v_is_doctor, FALSE) OR v_is_admin) THEN
        RAISE EXCEPTION 'Unauthorized to update lab order' USING ERRCODE = '42501';
    END IF;

    v_key := NULLIF(trim(both from p_report_storage_key), '');
    v_patient_id := v_order.patient_id;
    IF v_key IS NOT NULL THEN
        IF NOT (COALESCE(v_is_lab, FALSE) OR v_is_admin) THEN
            RAISE EXCEPTION 'Only the assigned lab or an admin may set report storage key' USING ERRCODE = '42501';
        END IF;
        IF v_patient_id IS NULL OR v_patient_id = '' THEN
            RAISE EXCEPTION 'Lab order has no patient_id for report key validation' USING ERRCODE = '22023';
        END IF;
        v_expected_prefix := 'lab_reports/' || v_patient_id || '/' || p_order_id || '/';
        IF v_key NOT LIKE v_expected_prefix || '%' OR position(E'\n' in v_key) > 0 OR position(E'\t' in v_key) > 0 THEN
            RAISE EXCEPTION 'Invalid report_storage_key prefix for order %', p_order_id USING ERRCODE = '22023';
        END IF;
    END IF;

    IF v_is_doctor AND NOT v_is_admin THEN
        IF p_new_status != 'cancelled' THEN
            RAISE EXCEPTION 'Doctor can only cancel lab order' USING ERRCODE = '42501';
        END IF;
        IF v_order.status IN ('inProgress', 'completed') THEN
            RAISE EXCEPTION 'Cannot cancel order after lab processing has begun (status: %)', v_order.status
                USING ERRCODE = '42501';
        END IF;
        IF v_key IS NOT NULL THEN
            RAISE EXCEPTION 'Doctors cannot set report storage key' USING ERRCODE = '42501';
        END IF;
    ELSIF v_is_lab THEN
        IF v_order.status = 'ordered' AND p_new_status NOT IN ('received', 'cancelled') THEN
            RAISE EXCEPTION 'Invalid transition from ordered to %', p_new_status USING ERRCODE = '22023';
        ELSIF v_order.status = 'received' AND p_new_status NOT IN ('inProgress') THEN
            RAISE EXCEPTION 'Invalid transition from received to %', p_new_status USING ERRCODE = '22023';
        ELSIF v_order.status = 'inProgress' AND p_new_status NOT IN ('completed') THEN
            RAISE EXCEPTION 'Invalid transition from inProgress to %', p_new_status USING ERRCODE = '22023';
        ELSIF v_order.status IN ('completed', 'cancelled') THEN
            RAISE EXCEPTION 'Order is in terminal state: %', v_order.status USING ERRCODE = '22023';
        END IF;
    END IF;

    PERFORM set_config('app.allow_lab_status_change', 'true', true);

    UPDATE public.lab_orders
    SET status = p_new_status,
        notes = CASE
            WHEN p_notes IS NOT NULL AND (p_notes !~ '^lab_reports/') THEN p_notes
            ELSE notes
        END,
        report_storage_key = COALESCE(v_key, report_storage_key),
        report_s3_key = COALESCE(v_key, report_s3_key),
        updated_at = CURRENT_TIMESTAMP
    WHERE order_id = p_order_id;

    PERFORM set_config('app.allow_lab_status_change', '', true);

    RETURN jsonb_build_object(
        'success', true,
        'order_id', p_order_id,
        'old_status', v_order.status,
        'new_status', p_new_status
    );
END;
$$;

REVOKE ALL ON FUNCTION public.update_lab_order_status(VARCHAR, VARCHAR, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_lab_order_status(VARCHAR, VARCHAR, TEXT, TEXT) TO authenticated, service_role;
```

---

## Full text: `db/proposed/20261103000016_proposed_ambulance_in_app_notifications_supabase.sql`

```sql
-- PROPOSED (do not apply): Supabase RLS + schema hooks for in-app inbox and ambulance data
-- (replaces client Firestore where still referenced).
-- Base in_app_notifications + policies: db/migrations/20261020000001_consolidated_firebase_schema_and_rls.sql,
--   enhanced policies: db/migrations/20261021000004_phase_e2_support_and_notifications.sql
-- Base ambulance_requests RLS: db/migrations/20261020000001_consolidated_firebase_schema_and_rls.sql (amb_requests_*)

-- ---------------------------------------------------------------------------
-- In-app notifications: extend EXISTING public.in_app_notifications (recipient_uid, is_read, type, …)
-- Client maps AppNotification to these columns; do not introduce a second table.
-- ---------------------------------------------------------------------------
ALTER TABLE public.in_app_notifications
    ADD COLUMN IF NOT EXISTS category TEXT,
    ADD COLUMN IF NOT EXISTS deep_link TEXT,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_in_app_notifications_recipient_created
    ON public.in_app_notifications (recipient_uid, created_at DESC);

DROP POLICY IF EXISTS "notifications_select" ON public.in_app_notifications;
CREATE POLICY "notifications_select" ON public.in_app_notifications
    FOR SELECT TO authenticated
    USING (
        (recipient_uid = (auth.jwt() ->> 'sub'))
        OR (recipient_uid = (
            SELECT u.id::text FROM public.users u WHERE u.firebase_uid = (auth.jwt() ->> 'sub')
        ))
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "notifications_update" ON public.in_app_notifications;
CREATE POLICY "notifications_update" ON public.in_app_notifications
    FOR UPDATE TO authenticated
    USING (
        (recipient_uid = (auth.jwt() ->> 'sub'))
        OR (recipient_uid = (
            SELECT u.id::text FROM public.users u WHERE u.firebase_uid = (auth.jwt() ->> 'sub')
        ))
        OR private.is_super_admin()
    )
    WITH CHECK (
        (recipient_uid = (auth.jwt() ->> 'sub'))
        OR (recipient_uid = (
            SELECT u.id::text FROM public.users u WHERE u.firebase_uid = (auth.jwt() ->> 'sub')
        ))
        OR private.is_super_admin()
    );

-- Inserts remain server-only (FCN/outbox/triggers); no client INSERT policy added here.

-- ---------------------------------------------------------------------------
-- Ambulance: optional legacy / app columns; RLS uses driver_id (FK to ambulances), not ambulance_id
-- ---------------------------------------------------------------------------
ALTER TABLE public.ambulance_requests
    ADD COLUMN IF NOT EXISTS firestore_legacy_id TEXT,
    ADD COLUMN IF NOT EXISTS broadcast_id TEXT,
    ADD COLUMN IF NOT EXISTS patient_location JSONB,
    ADD COLUMN IF NOT EXISTS status TEXT;

ALTER TABLE public.ambulance_broadcasts
    ADD COLUMN IF NOT EXISTS firestore_legacy_id TEXT,
    ADD COLUMN IF NOT EXISTS payload JSONB,
    ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

-- Deployed names: amb_requests_select, amb_requests_update (see consolidated migration)
DROP POLICY IF EXISTS "amb_requests_select" ON public.ambulance_requests;
CREATE POLICY "amb_requests_select" ON public.ambulance_requests
    FOR SELECT TO authenticated
    USING (
        driver_id = private.current_profile_id()
        OR patient_id = private.current_profile_id()
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "amb_requests_update" ON public.ambulance_requests;
CREATE POLICY "amb_requests_update" ON public.ambulance_requests
    FOR UPDATE TO authenticated
    USING (driver_id = private.current_profile_id() OR private.is_super_admin())
    WITH CHECK (driver_id = private.current_profile_id() OR private.is_super_admin());

-- Flutter: AmbulanceRepository → PostgREST on ambulance_requests / ambulance_broadcasts / ambulances
-- Flutter: InAppNotificationService → Supabase select/update on in_app_notifications WHERE recipient_uid = jwt.sub
```

---

## Full text: `scripts/audit/rls_staging_verified_role_matrix.sql`

```sql
-- STAGING ONLY — apply db/proposed/20261103000014_proposed_role_verified_rls_hardening.sql first (manual).
-- Replace fixture IDs/UIDs below, then run: psql "$STAGING_SUPABASE_DB_URL" -f scripts/audit/rls_staging_verified_role_matrix.sql
-- Ends with ROLLBACK so probes are non-destructive unless you change the final line to COMMIT.

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.set_jwt(sub text, role text DEFAULT 'authenticated')
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', sub, 'role', role)::text, true);
  PERFORM set_config('role', role, true);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.assert_count(
  probe text,
  sql text,
  expected bigint
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v bigint;
BEGIN
  EXECUTE 'SELECT count(*)::bigint FROM (' || sql || ') q' INTO v;
  IF v IS DISTINCT FROM expected THEN
    RAISE EXCEPTION 'FAIL [%]: expected count %, got %', probe, expected, v;
  END IF;
  RAISE NOTICE 'PASS [%]: count=%', probe, v;
END;
$$;

-- Fixture map (edit):
-- uid-patient-staging -> patient p_staging_patient (owner_uid)
-- uid-patient-owner-staging -> guardian profile; family member fm_staging_1.member_id books as patient
-- uid-doctor-verified / uid-doctor-unverified
-- uid-lab-verified / uid-lab-unverified
-- appointment appt_staging_family on patient_id=fm_staging_1.member_id

-- ---------------------------------------------------------------------------
-- Patient via owner_uid: SELECT child appointment
-- ---------------------------------------------------------------------------
SELECT pg_temp.set_jwt('uid-patient-staging');
SET LOCAL role authenticated;
SELECT pg_temp.assert_count(
  'patient_owner_uid_appointments',
  $$SELECT 1 FROM public.appointments a
    JOIN public.patients p ON p.patient_id = a.patient_id
    WHERE p.owner_uid = 'uid-patient-staging'$$,
  1::bigint
);

-- ---------------------------------------------------------------------------
-- Patient via family member: SELECT appointment for member_id
-- ---------------------------------------------------------------------------
SELECT pg_temp.set_jwt('uid-patient-guardian-staging');
SET LOCAL role authenticated;
SELECT pg_temp.assert_count(
  'patient_family_member_appointments',
  $$SELECT 1 FROM public.appointments WHERE patient_id = 'fm_staging_member_id'$$,
  1::bigint
);

-- ---------------------------------------------------------------------------
-- Unverified doctor: cannot read/update as doctor_id (post-000014 expect 0)
-- ---------------------------------------------------------------------------
SELECT pg_temp.set_jwt('uid-doctor-unverified-staging');
SET LOCAL role authenticated;
SELECT pg_temp.assert_count(
  'unverified_doctor_appointments_select',
  $$SELECT 1 FROM public.appointments WHERE doctor_id = 'd_staging_unverified'$$,
  0::bigint
);

DO $$
DECLARE v bigint;
BEGIN
  UPDATE public.appointments SET patient_status = patient_status
  WHERE appointment_id = 'appt_staging_doctor_unverified';
  GET DIAGNOSTICS v = ROW_COUNT;
  IF v <> 0 THEN
    RAISE EXCEPTION 'FAIL [unverified_doctor_appointments_update]: expected ROW_COUNT 0, got %', v;
  END IF;
  RAISE NOTICE 'PASS [unverified_doctor_appointments_update]: ROW_COUNT=0';
END;
$$;

-- ---------------------------------------------------------------------------
-- Unverified doctor: still read/update OWN doctors row
-- ---------------------------------------------------------------------------
SELECT pg_temp.assert_count(
  'unverified_doctor_own_profile_select',
  $$SELECT 1 FROM public.doctors WHERE doctor_id = 'd_staging_unverified'$$,
  1::bigint
);

DO $$
DECLARE v bigint;
BEGIN
  UPDATE public.doctors SET updated_at = updated_at WHERE doctor_id = 'd_staging_unverified';
  GET DIAGNOSTICS v = ROW_COUNT;
  IF v <> 1 THEN
    RAISE EXCEPTION 'FAIL [unverified_doctor_own_profile_update]: expected 1, got %', v;
  END IF;
  RAISE NOTICE 'PASS [unverified_doctor_own_profile_update]: ROW_COUNT=1';
END;
$$;

-- ---------------------------------------------------------------------------
-- Verified lab: UPDATE booking (expect 1)
-- ---------------------------------------------------------------------------
SELECT pg_temp.set_jwt('uid-lab-verified-staging');
SET LOCAL role authenticated;
DO $$
DECLARE v bigint;
BEGIN
  UPDATE public.lab_bookings SET status = status
  WHERE booking_id = 'lb_staging_verified' AND lab_id = 'l_staging_verified';
  GET DIAGNOSTICS v = ROW_COUNT;
  IF v <> 1 THEN
    RAISE EXCEPTION 'FAIL [verified_lab_booking_update]: expected 1, got %', v;
  END IF;
  RAISE NOTICE 'PASS [verified_lab_booking_update]: ROW_COUNT=1';
END;
$$;

-- ---------------------------------------------------------------------------
-- Unverified lab: UPDATE booking (expect 0 post-000014)
-- ---------------------------------------------------------------------------
SELECT pg_temp.set_jwt('uid-lab-unverified-staging');
SET LOCAL role authenticated;
DO $$
DECLARE v bigint;
BEGIN
  UPDATE public.lab_bookings SET status = status
  WHERE booking_id = 'lb_staging_unverified' AND lab_id = 'l_staging_unverified';
  GET DIAGNOSTICS v = ROW_COUNT;
  IF v <> 0 THEN
    RAISE EXCEPTION 'FAIL [unverified_lab_booking_update]: expected 0, got %', v;
  END IF;
  RAISE NOTICE 'PASS [unverified_lab_booking_update]: ROW_COUNT=0';
END;
$$;

-- ---------------------------------------------------------------------------
-- Unverified lab: still UPDATE own labs row
-- ---------------------------------------------------------------------------
DO $$
DECLARE v bigint;
BEGIN
  UPDATE public.labs SET updated_at = updated_at WHERE lab_id = 'l_staging_unverified';
  GET DIAGNOSTICS v = ROW_COUNT;
  IF v <> 1 THEN
    RAISE EXCEPTION 'FAIL [unverified_lab_own_profile_update]: expected 1, got %', v;
  END IF;
  RAISE NOTICE 'PASS [unverified_lab_own_profile_update]: ROW_COUNT=1';
END;
$$;

ROLLBACK;
```
