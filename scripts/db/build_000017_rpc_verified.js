const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '../..');
const migration = fs.readFileSync(
  path.join(ROOT, 'db/migrations/20261026000001_rpc_null_safe_authz.sql'),
  'utf8',
);
const lab015 = fs.readFileSync(
  path.join(ROOT, 'db/proposed/20261103000015_proposed_lab_report_storage_key.sql'),
  'utf8',
);

function extractFunction(sql, name) {
  const start = sql.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  if (start < 0) throw new Error(`missing function ${name}`);
  const end = sql.indexOf('$$;', start);
  if (end < 0) throw new Error(`missing end for ${name}`);
  return sql.slice(start, end + 3);
}

function norm(s) {
  return s.replace(/\r\n/g, '\n');
}

function patchReschedule(body) {
  body = norm(body);
  const needle = `        RAISE EXCEPTION 'FORBIDDEN: You do not have permission to reschedule this appointment.' USING ERRCODE = '42501';
    END IF;

    -- 2. Validate slot capacity`;
  const insert = `        RAISE EXCEPTION 'FORBIDDEN: You do not have permission to reschedule this appointment.' USING ERRCODE = '42501';
    END IF;

    IF (v_appt.doctor_id IS NOT DISTINCT FROM v_profile_id)
       AND COALESCE(lower(p_rescheduled_by), '') LIKE 'doctor%'
       AND NOT v_is_admin
       AND NOT COALESCE(private.is_verified_doctor(), FALSE) THEN
        RAISE EXCEPTION 'FORBIDDEN: Verified doctor required' USING ERRCODE = '42501';
    END IF;

    -- 2. Validate slot capacity`;
  if (!body.includes(needle)) throw new Error('reschedule anchor missing');
  return body.replace(needle, insert);
}

function patchPharmacy(body) {
  body = norm(body);
  const needle = `    -- Validated State Machine
    IF v_is_store THEN`;
  const insert = `    -- Validated State Machine
    IF v_is_store THEN
        IF NOT COALESCE(private.is_verified_medical_store(), FALSE) AND NOT v_is_admin THEN
            RAISE EXCEPTION 'FORBIDDEN: Verified medical store required' USING ERRCODE = '42501';
        END IF;`;
  if (!body.includes(needle)) throw new Error('pharmacy anchor missing');
  return body.replace(needle, insert);
}

function patchPrescription(body) {
  body = norm(body);
  const needle = `    IF v_doctor_id IS NULL AND NOT v_is_admin THEN
        RAISE EXCEPTION 'FORBIDDEN: Caller "%" is not a registered doctor.', v_caller_uid
            USING ERRCODE = '42501';
    END IF;`;
  const insert = `${needle}

    IF NOT v_is_admin AND NOT COALESCE(private.is_verified_doctor(), FALSE) THEN
        RAISE EXCEPTION 'FORBIDDEN: Verified doctor required' USING ERRCODE = '42501';
    END IF;`;
  if (!body.includes(needle)) throw new Error('prescription anchor missing');
  return body.replace(needle, insert);
}

function patchLabBooking(body) {
  let out = norm(body);
  const labGuard = `    ELSIF v_is_lab THEN
        IF NOT COALESCE(private.is_verified_lab(), FALSE) AND NOT v_is_admin THEN
            RAISE EXCEPTION 'FORBIDDEN: Verified lab required' USING ERRCODE = '42501';
        END IF;`;
  out = out.replace('    ELSIF v_is_lab THEN\n', labGuard + '\n');

  const keyRule = `    v_key := NULLIF(trim(both from p_report_storage_key), '');
    IF v_key IS NOT NULL THEN`;
  const keyRuleNew = `    v_key := NULLIF(trim(both from p_report_storage_key), '');
    IF v_key IS NOT NULL AND p_new_status IS DISTINCT FROM 'completed' THEN
        RAISE EXCEPTION 'report_storage_key only allowed when p_new_status is completed' USING ERRCODE = '22023';
    END IF;
    IF v_key IS NOT NULL THEN`;
  out = out.replace(keyRule, keyRuleNew);

  const terminal = `        ELSIF v_booking.status IN ('completed', 'cancelled') THEN
            RAISE EXCEPTION 'Booking is already in terminal state: %', v_booking.status USING ERRCODE = '22023';
        END IF;`;
  const terminalNew = `        ELSIF v_booking.status = 'cancelled' THEN
            RAISE EXCEPTION 'Booking is already in terminal state: %', v_booking.status USING ERRCODE = '22023';
        ELSIF v_booking.status = 'completed' THEN
            IF p_new_status <> 'completed' OR v_key IS NULL THEN
                RAISE EXCEPTION 'Completed booking only allows completed status with a new report_storage_key' USING ERRCODE = '22023';
            END IF;
        END IF;`;
  out = out.replace(terminal, terminalNew);
  return out;
}

function patchLabOrder(body) {
  let out = norm(body);
  const labGuard = `    ELSIF v_is_lab THEN
        IF NOT COALESCE(private.is_verified_lab(), FALSE) AND NOT v_is_admin THEN
            RAISE EXCEPTION 'FORBIDDEN: Verified lab required' USING ERRCODE = '42501';
        END IF;`;
  out = out.replace('    ELSIF v_is_lab THEN\n', labGuard + '\n');

  const keyRule = `    v_key := NULLIF(trim(both from p_report_storage_key), '');
    v_patient_id := v_order.patient_id;
    IF v_key IS NOT NULL THEN`;
  const keyRuleNew = `    v_key := NULLIF(trim(both from p_report_storage_key), '');
    v_patient_id := v_order.patient_id;
    IF v_key IS NOT NULL AND p_new_status IS DISTINCT FROM 'completed' THEN
        RAISE EXCEPTION 'report_storage_key only allowed when p_new_status is completed' USING ERRCODE = '22023';
    END IF;
    IF v_key IS NOT NULL THEN`;
  out = out.replace(keyRule, keyRuleNew);

  const terminal = `        ELSIF v_order.status IN ('completed', 'cancelled') THEN
            RAISE EXCEPTION 'Order is in terminal state: %', v_order.status USING ERRCODE = '22023';
        END IF;`;
  const terminalNew = `        ELSIF v_order.status = 'cancelled' THEN
            RAISE EXCEPTION 'Order is in terminal state: %', v_order.status USING ERRCODE = '22023';
        ELSIF v_order.status = 'completed' THEN
            IF p_new_status <> 'completed' OR v_key IS NULL THEN
                RAISE EXCEPTION 'Completed order only allows completed status with a new report_storage_key' USING ERRCODE = '22023';
            END IF;
        END IF;`;
  out = out.replace(terminal, terminalNew);
  return out;
}

const labBooking = patchLabBooking(
  extractFunction(lab015, 'update_lab_booking_status'),
);
const labOrder = patchLabOrder(extractFunction(lab015, 'update_lab_order_status'));

const outPath = path.join(
  ROOT,
  'db/proposed/20261103000017_proposed_rpc_verified_checks.sql',
);

const header = `-- PROPOSED (do not apply): verified-provider guards on SECURITY DEFINER mutator RPCs.
-- Depends on private.is_verified_* helpers in db/proposed/20261103000014_proposed_role_verified_rls_hardening.sql
-- and lab report key rules in db/proposed/20261103000015_proposed_lab_report_storage_key.sql (column adds).
-- Ambulance mutators moved to db/proposed/later/20261103000017_later_rpc_ambulance_verified.sql

`;

const pharmacyRaw = extractFunction(migration, 'update_pharmacy_delivery_status');
const prescriptionRaw = patchPrescription(
  extractFunction(migration, 'create_prescription_atomic'),
);

function revokeBlock(fnName) {
  const fn = extractFunction(migration, fnName);
  const start = migration.indexOf(fn) + fn.length;
  const slice = migration.slice(start, start + 800);
  const rStart = slice.indexOf(`REVOKE ALL ON FUNCTION public.${fnName}`);
  if (rStart < 0) throw new Error(`missing revoke for ${fnName}`);
  const rEnd = slice.indexOf('service_role;', rStart);
  if (rEnd < 0) throw new Error(`missing revoke end for ${fnName}`);
  return slice.slice(rStart, rEnd + 'service_role;'.length) + '\n';
}

const revokeReschedule = revokeBlock('reschedule_appointment_atomic');
const revokePharmacy = revokeBlock('update_pharmacy_delivery_status');
const revokeRx = revokeBlock('create_prescription_atomic');

const labRevokes = `
REVOKE ALL ON FUNCTION public.update_lab_booking_status(VARCHAR, VARCHAR, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_lab_booking_status(VARCHAR, VARCHAR, TEXT, TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.update_lab_order_status(VARCHAR, VARCHAR, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_lab_order_status(VARCHAR, VARCHAR, TEXT, TEXT) TO authenticated, service_role;
`;

fs.writeFileSync(
  outPath,
  [
    header,
    patchReschedule(extractFunction(migration, 'reschedule_appointment_atomic')),
    revokeReschedule,
    '\n',
    patchPharmacy(pharmacyRaw),
    revokePharmacy,
    '\n',
    prescriptionRaw,
    revokeRx,
    '\n',
    labBooking,
    labOrder,
    labRevokes,
  ].join('\n'),
  'utf8',
);

console.log('Wrote', outPath);
