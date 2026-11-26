'use strict';

const { resolveCallerIdentity } = require('./caller_identity');
const crypto = require('crypto');
const { getAuth } = require('firebase-admin/auth');
const { logger } = require('firebase-functions');
const { HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const { readSupabaseServiceRoleKey } = require('./secure_config');


const supabaseServiceRoleKey = defineSecret('SUPABASE_SERVICE_ROLE_KEY');

let _testingSupabaseFetch = null;
function setSupabaseFetchForTesting(fn) {
  _testingSupabaseFetch = fn;
}
let _s3Sdk;
function getS3Sdk() {
  if (!_s3Sdk) {
    _s3Sdk = require('@aws-sdk/client-s3');
  }
  return _s3Sdk;
}

const { resolveS3BucketForUid } = require('./src/config/s3_bucket');
/** Bucket that holds this account's files (demo accounts: staging bucket in production). */
function s3Bucket(uid) {
  return resolveS3BucketForUid(uid);
}
let _testingS3Client = null;

function setS3ClientForTesting(client) {
  _testingS3Client = client;
}

function getS3Client() {
  if (_testingS3Client) return _testingS3Client;
  const { S3Client } = getS3Sdk();
  const region = process.env.AWS_REGION || 'ap-south-1';
  return new S3Client({
    region,
    credentials:
      process.env.AWS_ACCESS_KEY_ID && process.env.AWS_SECRET_ACCESS_KEY
        ? {
            accessKeyId: process.env.AWS_ACCESS_KEY_ID,
            secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
          }
        : undefined,
  });
}

/**
 * Deletes OTP challenge keys from Redis for the deleting user.
 * Best-effort, fail-soft.
 */
async function cleanupUserRedisKeys({ mobileDigits }) {
  const digits = normalizeMobileDigits(mobileDigits);
  if (!digits) return;
  try {
    // Uses the same env-prefixed / HMAC key derivation as the OTP module (previous raw keys never matched).
    await require('./registration_otp').purgeOtpStateForMobile(digits);
  } catch (err) {
    logger.warn('deleteMyAccount: Redis cleanup failed (soft-fail)', {
      error: err?.message || 'unknown',
    });
  }
}


function hashKey(value) {
  return crypto.createHash('sha256').update(String(value || '')).digest('hex');
}

function normalizeMobileDigits(mobile) {
  const digits = String(mobile || '').replace(/\D/g, '');
  let normalized = digits;
  if (normalized.length === 12 && normalized.startsWith('91')) {
    normalized = normalized.slice(2);
  } else if (normalized.length === 11 && normalized.startsWith('0')) {
    normalized = normalized.slice(1);
  }
  if (normalized.length !== 10 || !/^[6-9]\d{9}$/.test(normalized)) return '';
  return normalized;
}

async function deleteS3PrefixVersions(s3, bucketName, prefix) {
  const normalizedPrefix = String(prefix || '').trim();
  if (!normalizedPrefix) return { success: true, count: 0, prefix: '' };

  let totalDeleted = 0;
  let keyMarker = undefined;
  let versionIdMarker = undefined;

  const { ListObjectVersionsCommand, DeleteObjectsCommand } = getS3Sdk();
  try {
    while (true) {
      const listCmd = new ListObjectVersionsCommand({
        Bucket: bucketName,
        Prefix: normalizedPrefix,
        KeyMarker: keyMarker,
        VersionIdMarker: versionIdMarker,
      });

      const res = await s3.send(listCmd);
      const items = [];

      if (res.Versions && Array.isArray(res.Versions)) {
        for (const v of res.Versions) {
          if (v.Key) {
            items.push({ Key: v.Key, VersionId: v.VersionId });
          }
        }
      }

      if (res.DeleteMarkers && Array.isArray(res.DeleteMarkers)) {
        for (const dm of res.DeleteMarkers) {
          if (dm.Key) {
            items.push({ Key: dm.Key, VersionId: dm.VersionId });
          }
        }
      }

      for (let i = 0; i < items.length; i += 1000) {
        const batch = items.slice(i, i + 1000);
        if (batch.length > 0) {
          const deleteCmd = new DeleteObjectsCommand({
            Bucket: bucketName,
            Delete: {
              Objects: batch,
              Quiet: true,
            },
          });
          await s3.send(deleteCmd);
          totalDeleted += batch.length;
          try {
            const { invalidateS3DownloadUrlCacheBatch } = require('./s3_storage');
            await invalidateS3DownloadUrlCacheBatch(batch.map((b) => b.Key));
          } catch (_) {}
        }
      }

      if (!res.IsTruncated) {
        break;
      }
      keyMarker = res.NextKeyMarker;
      versionIdMarker = res.NextVersionIdMarker;
    }

    return { success: true, count: totalDeleted, prefix: normalizedPrefix };
  } catch (err) {
    logger.warn('deleteMyAccount S3 prefix delete failed', {
      prefix: normalizedPrefix,
      message: err?.message || 'unknown',
    });
    return { success: false, error: err?.message || 'unknown', prefix: normalizedPrefix };
  }
}

/**
 * Deletes all versions and delete markers for a specific list of exact S3 keys.
 * Best-effort: catches errors per key/batch, logs warnings, and batches deletes up to 1000 items.
 */
async function deleteS3SpecificKeysVersions(s3, bucketName, keys) {
  const normalizedKeys = Array.from(
    new Set((keys || []).map((k) => String(k || '').trim()).filter(Boolean)),
  );
  if (normalizedKeys.length === 0) return { success: true, count: 0, failedKeys: [] };

  const itemsToDelete = [];
  const failedKeys = [];

  const { ListObjectVersionsCommand, DeleteObjectsCommand } = getS3Sdk();
  for (const key of normalizedKeys) {
    try {
      let keyMarker = undefined;
      let versionIdMarker = undefined;
      let keyFound = false;

      while (true) {
        const listCmd = new ListObjectVersionsCommand({
          Bucket: bucketName,
          Prefix: key,
          KeyMarker: keyMarker,
          VersionIdMarker: versionIdMarker,
        });

        const res = await s3.send(listCmd);

        if (res.Versions && Array.isArray(res.Versions)) {
          for (const v of res.Versions) {
            // Strictly match the exact key to prevent prefix collisions
            if (v.Key === key) {
              keyFound = true;
              itemsToDelete.push({ Key: v.Key, VersionId: v.VersionId });
            }
          }
        }

        if (res.DeleteMarkers && Array.isArray(res.DeleteMarkers)) {
          for (const dm of res.DeleteMarkers) {
            if (dm.Key === key) {
              keyFound = true;
              itemsToDelete.push({ Key: dm.Key, VersionId: dm.VersionId });
            }
          }
        }

        if (!res.IsTruncated) {
          break;
        }
        keyMarker = res.NextKeyMarker;
        versionIdMarker = res.NextVersionIdMarker;
      }

      // If ListObjectVersions didn't return version entries (e.g. unversioned), still target key
      if (!keyFound) {
        itemsToDelete.push({ Key: key });
      }
    } catch (err) {
      logger.warn('deleteS3SpecificKeysVersions list error', {
        key,
        message: err?.message || 'unknown',
      });
      failedKeys.push(key);
    }
  }

  let totalDeleted = 0;
  for (let i = 0; i < itemsToDelete.length; i += 1000) {
    const batch = itemsToDelete.slice(i, i + 1000);
    if (batch.length > 0) {
      try {
        const deleteCmd = new DeleteObjectsCommand({
          Bucket: bucketName,
          Delete: {
            Objects: batch,
            Quiet: true,
          },
        });
        await s3.send(deleteCmd);
        totalDeleted += batch.length;
        try {
          const { invalidateS3DownloadUrlCacheBatch } = require('./s3_storage');
          await invalidateS3DownloadUrlCacheBatch(batch.map((item) => item.Key));
        } catch (_) {}
      } catch (err) {
        logger.warn('deleteS3SpecificKeysVersions delete batch error', {
          batchSize: batch.length,
          message: err?.message || 'unknown',
        });
        for (const item of batch) {
          failedKeys.push(item.Key);
        }
      }
    }
  }

  return {
    success: failedKeys.length === 0,
    count: totalDeleted,
    failedKeys: Array.from(new Set(failedKeys)),
  };
}

/**
 * Physical key prefix for the account's data plane (production only): demo/ or prod/.
 * Objects created before plane prefixing are unprefixed and belong to prod/.
 */
function planeKeyPrefixes(uid) {
  if (String(process.env.APP_ENV || '').trim().toLowerCase() !== 'production') return [''];
  const { objectStoragePrefix } = require('./lib/demo_routing');
  const plane = objectStoragePrefix({ appEnv: 'production', firebaseUid: uid || null });
  return plane === 'prod/' ? ['prod/', ''] : [plane];
}

/**
 * S3 prefixes owned by the deleting account (matches getS3UploadUrlHandler key layout):
 * - patient: patients/{id}/, health_records/{id}/, lab_reports/{id}/  (the patient's own records)
 * - doctor_profiles/{id}/, labs/{id}/, pharmacies/{id}/, ambulances/{id}/  (provider media + KYC)
 * - promoted_ads/{uid|profileId}/
 * Lab report files uploaded by a LAB for patients are never deleted with the lab account:
 * they belong to the patient's medical record.
 */
async function resolveUserS3Prefixes(_db, { uid, role, profileId }) {
  const logical = new Set();
  const ids = Array.from(new Set([profileId, uid].filter(Boolean)));
  for (const id of ids) {
    logical.add(`promoted_ads/${id}/`);
    if (role === 'patient') {
      logical.add(`patients/${id}/`);
      logical.add(`health_records/${id}/`);
      logical.add(`lab_reports/${id}/`);
    } else if (role === 'doctor') {
      logical.add(`doctor_profiles/${id}/`);
    } else if (role === 'lab') {
      logical.add(`labs/${id}/`);
    } else if (role === 'medicalStore' || role === 'pharmacy' || role === 'medical') {
      logical.add(`pharmacies/${id}/`);
    } else if (role === 'ambulance') {
      logical.add(`ambulances/${id}/`);
    }
  }
  const out = [];
  for (const plane of planeKeyPrefixes(uid)) for (const p of logical) out.push(plane + p);
  return out;
}

/**
 * Cleans up all S3 prefixes for a user. Best-effort: soft-fails per prefix.
 */
async function cleanupUserS3Prefixes(s3, bucketName, prefixes) {
  const failedS3Prefixes = [];
  for (const prefix of prefixes) {
    const res = await deleteS3PrefixVersions(s3, bucketName, prefix);
    if (!res.success) {
      failedS3Prefixes.push(prefix);
    }
  }
  return failedS3Prefixes;
}

function readBoundSecret(secret, envName) {
  try {
    if (secret && typeof secret.value === 'function') {
      const bound = secret.value();
      if (bound) return String(bound).trim();
    }
  } catch (_) {}
  return String(process.env[envName] || '').trim();
}

/**
 * PostgREST target for the deleting account. Production demo/reviewer UIDs live on the staging
 * plane (DEMO_SUPABASE_*); everyone else in production is on RDS via the gateway.
 */
function getSupabaseServiceConfig(uid = null) {
  const isProduction = (process.env.APP_ENV || 'staging').toLowerCase() === 'production';
  let plane = isProduction ? 'rds' : 'staging';
  if (isProduction && uid) {
    try {
      const { resolveDataPlane } = require('./lib/demo_routing');
      if (resolveDataPlane({ appEnv: 'production', firebaseUid: uid }) === 'supabase') plane = 'demo';
    } catch (_) {}
  }

  let url;
  let key;
  if (plane === 'rds') {
    url = String(process.env.PROD_GATEWAY_URL || '').trim().replace(/\/+$/, '');
    key = String(process.env.PROD_GATEWAY_SERVICE_KEY || '').trim();
  } else if (plane === 'demo') {
    url = String(process.env.DEMO_SUPABASE_URL || process.env.STAGING_SUPABASE_URL || '').trim().replace(/\/+$/, '');
    key = String(process.env.DEMO_SUPABASE_SERVICE_ROLE_KEY || process.env.STAGING_SUPABASE_SERVICE_ROLE_KEY || '').trim();
  } else {
    url = String(process.env.STAGING_SUPABASE_URL || process.env.SUPABASE_URL || '').trim().replace(/\/+$/, '');
    key = readBoundSecret(supabaseServiceRoleKey, 'SUPABASE_SERVICE_ROLE_KEY') ||
      readSupabaseServiceRoleKey({ required: false }) ||
      String(process.env.STAGING_SUPABASE_SERVICE_ROLE_KEY || '').trim() ||
      String(process.env.SUPABASE_SERVICE_ROLE_KEY || '').trim();
  }
  if (!url || !key) return null;
  return { url, key, isProduction, plane };
}

function supabaseHeaders(key) {
  return {
    apikey: key,
    Authorization: `Bearer ${key}`,
    'Content-Type': 'application/json',
    Prefer: 'return=representation',
  };
}

async function supabaseRequest(config, method, pathAndQuery, body) {
  const doFetch = _testingSupabaseFetch || fetch;
  const resp = await doFetch(`${config.url}/rest/v1/${pathAndQuery}`, {
    method,
    headers: supabaseHeaders(config.key),
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await resp.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch (_) {
    json = null;
  }
  if (!resp.ok) {
    const err = new Error(`Supabase ${method} ${pathAndQuery.split('?')[0]} failed (${resp.status})`);
    err.status = resp.status;
    throw err;
  }
  return json;
}

function addIds(set, rows, field) {
  if (!Array.isArray(rows)) return;
  for (const row of rows) {
    const value = String(row?.[field] || '').trim();
    if (value) set.add(value);
  }
}

/**
 * Best-effort PostgREST cleanup of this user's Supabase rows.
 * Uses service-role credentials when present; soft-fails per table.
 */
async function cleanupUserSupabaseRows({ uid, role, profileId }) {
  const failedSupabaseTables = [];
  const config = getSupabaseServiceConfig(uid);
  if (!config) {
    return { skipped: true, failedSupabaseTables };
  }

  const recordFailure = (table, err) => {
    failedSupabaseTables.push(table);
    logger.warn('deleteMyAccount supabase cleanup failed', {
      table,
      uidHash: hashKey(uid).slice(0, 16),
      status: err?.status || 'unknown',
    });
  };

  const del = async (table, query) => {
    try {
      await supabaseRequest(config, 'DELETE', `${table}?${query}`);
    } catch (err) {
      if (err?.status === 403 || err?.status === 404) {
        throw err;
      }
      recordFailure(table, err);
    }
  };

  // Tables that live in the private schema on real Postgres (PostgREST answers 404 for them):
  // best effort, never abort the deletion because of them.
  const delOptional = async (table, query) => {
    try {
      await supabaseRequest(config, 'DELETE', `${table}?${query}`);
    } catch (err) {
      if (err?.status === 404) return;
      if (err?.status === 403) throw err;
      recordFailure(table, err);
    }
  };

  const getRows = async (table, query, field) => {
    try {
      return await supabaseRequest(config, 'GET', `${table}?${query}&select=${field}`);
    } catch (err) {
      if (err?.status === 403 || err?.status === 404) {
        throw err;
      }
      recordFailure(table, err);
      return [];
    }
  };

  let supabaseUserId = '';
  let supabaseProfileId = String(profileId || '').trim();
  let supabaseRole = String(role || '').trim();
  let supabaseMobile = '';

  try {
    const rows = await supabaseRequest(
      config,
      'GET',
      `users?firebase_uid=eq.${encodeURIComponent(uid)}&select=id,profile_id,role,mobile`,
    );
    if (Array.isArray(rows) && rows[0]) {
      supabaseUserId = String(rows[0].id || '').trim();
      if (!supabaseProfileId) supabaseProfileId = String(rows[0].profile_id || '').trim();
      if (!supabaseRole) supabaseRole = String(rows[0].role || '').trim();
      supabaseMobile = String(rows[0].mobile || '').trim();
    }
  } catch (err) {
    if (err?.status === 403 || err?.status === 404) {
      throw err;
    }
    recordFailure('users', err);
  }

  const patientIds = new Set();
  const doctorIds = new Set();
  const storeIds = new Set();
  const labIds = new Set();
  const ambulanceIds = new Set();

  if (supabaseRole === 'patient' && supabaseProfileId) patientIds.add(supabaseProfileId);
  if (supabaseRole === 'doctor' && supabaseProfileId) doctorIds.add(supabaseProfileId);
  if (
    (supabaseRole === 'medicalStore' || supabaseRole === 'medical' || supabaseRole === 'pharmacy')
    && supabaseProfileId
  ) {
    storeIds.add(supabaseProfileId);
  }
  if (supabaseRole === 'lab' && supabaseProfileId) labIds.add(supabaseProfileId);
  if (supabaseRole === 'ambulance' && supabaseProfileId) ambulanceIds.add(supabaseProfileId);

  if (supabaseUserId) {
    addIds(patientIds, await getRows('patients', `owner_uid=eq.${encodeURIComponent(supabaseUserId)}`, 'patient_id'), 'patient_id');
    addIds(doctorIds, await getRows('doctors', `owner_uid=eq.${encodeURIComponent(supabaseUserId)}`, 'doctor_id'), 'doctor_id');
    addIds(storeIds, await getRows('medical_stores', `owner_uid=eq.${encodeURIComponent(supabaseUserId)}`, 'store_id'), 'store_id');
    addIds(labIds, await getRows('labs', `owner_uid=eq.${encodeURIComponent(supabaseUserId)}`, 'lab_id'), 'lab_id');
    addIds(ambulanceIds, await getRows('ambulances', `auth_uid=eq.${encodeURIComponent(supabaseUserId)}`, 'ambulance_id'), 'ambulance_id');
  }

  const patch = async (table, query, body) => {
    try {
      await supabaseRequest(config, 'PATCH', `${table}?${query}`, body);
    } catch (err) {
      if (err?.status === 403 || err?.status === 404) {
        throw err;
      }
      recordFailure(table, err);
    }
  };

  /*
   * Retention policy: records that belong to a PATIENT's medical history (lab bookings/orders and
   * their report files, prescriptions, appointments, referrals, pharmacy deliveries, ambulance trips)
   * are deleted only when the PATIENT deletes their account. When a PROVIDER (lab, doctor, pharmacy,
   * ambulance) deletes theirs, the provider is anonymised and detached instead, so patients keep
   * access to their own records.
   */

  // 1. Patient-owned pharmacy deliveries
  const deliveryIds = new Set();
  for (const pid of patientIds) {
    addIds(deliveryIds, await getRows('pharmacy_deliveries', `patient_id=eq.${encodeURIComponent(pid)}`, 'delivery_id'), 'delivery_id');
  }
  for (const delId of deliveryIds) {
    await del('pharmacy_delivery_medicines', `delivery_id=eq.${encodeURIComponent(delId)}`);
    await del('pharmacy_deliveries', `delivery_id=eq.${encodeURIComponent(delId)}`);
  }

  // 2. Patient-owned lab bookings/orders; provider relationship rows only
  for (const pid of patientIds) {
    await del('lab_orders', `patient_id=eq.${encodeURIComponent(pid)}`);
    await del('lab_bookings', `patient_id=eq.${encodeURIComponent(pid)}`);
  }
  for (const lid of labIds) {
    await del('lab_connections', `lab_id=eq.${encodeURIComponent(lid)}`);
  }
  for (const did of doctorIds) {
    await del('lab_connections', `doctor_id=eq.${encodeURIComponent(did)}`);
    await del('pharmacy_connections', `doctor_id=eq.${encodeURIComponent(did)}`);
  }
  for (const sid of storeIds) {
    await del('pharmacy_connections', `medical_store_id=eq.${encodeURIComponent(sid)}`);
  }

  // 3. Patient referrals
  for (const pid of patientIds) {
    await del('referrals', `patient_id=eq.${encodeURIComponent(pid)}`);
  }

  // 4. Patient prescriptions
  const prescriptionIds = new Set();
  for (const patientId of patientIds) {
    addIds(
      prescriptionIds,
      await getRows('prescriptions', `patient_id=eq.${encodeURIComponent(patientId)}`, 'prescription_id'),
      'prescription_id',
    );
  }
  for (const prescriptionId of prescriptionIds) {
    const q = `prescription_id=eq.${encodeURIComponent(prescriptionId)}`;
    await del('prescription_medicines', q);
    await del('prescription_investigations', q);
    await del('prescription_referrals', q);
    await del('prescriptions', q);
  }

  // 4b. Patient ambulance trips (contacts + location trail)
  const broadcastIds = new Set();
  for (const pid of patientIds) {
    addIds(broadcastIds, await getRows('ambulance_broadcasts', `patient_id=eq.${encodeURIComponent(pid)}`, 'broadcast_id'), 'broadcast_id');
  }
  for (const bid of broadcastIds) {
    await del('ambulance_trip_contacts', `broadcast_id=eq.${encodeURIComponent(bid)}`);
    await del('ambulance_location_updates', `broadcast_id=eq.${encodeURIComponent(bid)}`);
  }
  if (supabaseMobile && patientIds.size > 0) {
    await del('ambulance_trip_contacts', `patient_phone=eq.${encodeURIComponent(supabaseMobile)}`);
  }

  // 5. Patient records & relationships
  for (const patientId of patientIds) {
    const q = `patient_id=eq.${encodeURIComponent(patientId)}`;
    await del('health_records', q);
    await del('family_members', q);
    await del('review_votes', q);
    await del('reviews', q);
    await del('patient_doctor_links', q);
    await del('patient_care_team', q);
    await del('medical_directory', q);
    await del('appointments', q);
    await del('ambulance_requests', q);
    await del('ambulance_broadcasts', q);
    await del('patients', q);
  }

  // 6. Doctor: delete doctor-private data and care links; anonymise the doctor row
  //    (appointments / prescriptions / referrals stay in the patients' history).
  for (const doctorId of doctorIds) {
    const q = `doctor_id=eq.${encodeURIComponent(doctorId)}`;
    await del('doctor_invites', q);
    await del('pharmacy_doctor_invites', q);
    await del('doctor_private', q);
    await del('doctor_availability', q);
    await del('doctor_facilities', q);
    await del('doctor_education', q);
    await del('doctor_blocked_dates', q);
    await del('patient_doctor_links', q);
    await del('patient_care_team', q);
    await del('medical_directory', q);
    await patch('doctors', q, {
      name: 'Deleted doctor',
      email: `deleted+${doctorId}@deleted.invalid`,
      mobile: 'deleted',
      photo_url: null,
      about: null,
      owner_uid: null,
      verified: false,
      deactivated: true,
    });
  }

  // 7. Pharmacy: anonymise (deliveries remain on the patient side)
  for (const storeId of storeIds) {
    await del('pharmacy_doctor_invites', `store_id=eq.${encodeURIComponent(storeId)}`);
    await patch('medical_stores', `store_id=eq.${encodeURIComponent(storeId)}`, {
      store_name: 'Deleted pharmacy',
      owner_name: 'Deleted',
      drug_license_number: 'deleted',
      gst_number: null,
      phone: 'deleted',
      email: `deleted+${storeId}@deleted.invalid`,
      owner_uid: null,
      verified: false,
      deactivated: true,
    });
  }

  // 8. Lab: anonymise; lab_bookings / lab_orders / report files stay with the patient
  for (const labId of labIds) {
    await patch('labs', `lab_id=eq.${encodeURIComponent(labId)}`, {
      lab_name: 'Deleted lab',
      license_number: 'deleted',
      gst_number: null,
      phone: 'deleted',
      email: `deleted+${labId}@deleted.invalid`,
      owner_uid: null,
      verified: false,
      deactivated: true,
    });
  }

  // 9. Ambulance: delete PIN / invites / live location; anonymise the vehicle row and the driver
  //    contact copied onto patients' past trips.
  for (const ambulanceId of ambulanceIds) {
    const q = `ambulance_id=eq.${encodeURIComponent(ambulanceId)}`;
    await del('ambulance_private_settings', q);
    await del('ambulance_invites', q);
    await del('ambulance_locations', `driver_id=eq.${encodeURIComponent(ambulanceId)}`);
    await del('ambulance_requests', `driver_id=eq.${encodeURIComponent(ambulanceId)}`);
    await patch('ambulance_broadcasts', `accepted_driver_id=eq.${encodeURIComponent(ambulanceId)}`, {
      accepted_driver_name: 'Deleted driver',
      accepted_driver_phone: null,
      accepted_vehicle_number: null,
    });
    await patch('ambulances', q, {
      service_name: 'Deleted ambulance',
      owner_name: null,
      driver_name: 'Deleted',
      phone: 'deleted',
      vehicle_number: 'deleted',
      license_number: null,
      insurance_number: null,
      username: `deleted_${ambulanceId}`,
      auth_uid: null,
      is_available: false,
      verified: false,
    });
  }
  if (supabaseMobile && ambulanceIds.size > 0) {
    await del('ambulance_trip_contacts', `driver_phone=eq.${encodeURIComponent(supabaseMobile)}`);
  }

  // 10. Support tickets & messages
  const ticketIds = new Set();
  for (const pid of patientIds) {
    addIds(ticketIds, await getRows('support_tickets', `patient_id=eq.${encodeURIComponent(pid)}`, 'ticket_id'), 'ticket_id');
  }
  for (const did of doctorIds) {
    addIds(ticketIds, await getRows('support_tickets', `doctor_id=eq.${encodeURIComponent(did)}`, 'ticket_id'), 'ticket_id');
  }
  for (const sid of storeIds) {
    addIds(ticketIds, await getRows('support_tickets', `store_id=eq.${encodeURIComponent(sid)}`, 'ticket_id'), 'ticket_id');
  }
  for (const lid of labIds) {
    addIds(ticketIds, await getRows('support_tickets', `lab_id=eq.${encodeURIComponent(lid)}`, 'ticket_id'), 'ticket_id');
  }
  for (const aid of ambulanceIds) {
    addIds(ticketIds, await getRows('support_tickets', `ambulance_id=eq.${encodeURIComponent(aid)}`, 'ticket_id'), 'ticket_id');
  }
  if (supabaseUserId) {
    addIds(ticketIds, await getRows('support_tickets', `user_id=eq.${encodeURIComponent(supabaseUserId)}`, 'ticket_id'), 'ticket_id');
  }
  for (const tid of ticketIds) {
    await del('support_ticket_messages', `ticket_id=eq.${encodeURIComponent(tid)}`);
    await del('support_tickets', `ticket_id=eq.${encodeURIComponent(tid)}`);
  }

  if (supabaseUserId) {
    await del('user_devices', `user_id=eq.${encodeURIComponent(supabaseUserId)}`);
  }
  await del('in_app_notifications', `recipient_uid=eq.${encodeURIComponent(uid)}`);

  // 11. Promoted ads & admin/provisioning records
  if (supabaseProfileId) {
    await del('promoted_ads', `provider_id=eq.${encodeURIComponent(supabaseProfileId)}`);
  }
  if (supabaseUserId) {
    await del('promoted_ads', `provider_id=eq.${encodeURIComponent(supabaseUserId)}`);
    await delOptional('admin_users', `user_id=eq.${encodeURIComponent(supabaseUserId)}`);
  }
  await del('promoted_ads', `provider_id=eq.${encodeURIComponent(uid)}`);
  await del('super_admins', `user_uid=eq.${encodeURIComponent(uid)}`);
  await delOptional('provisioning_errors', `auth_user_id=eq.${encodeURIComponent(uid)}`);

  // Anonymize payment records (PII minimization while retaining accounting audit history)
  try {
    await supabaseRequest(
      config,
      'PATCH',
      `razorpay_orders?user_uid=eq.${encodeURIComponent(uid)}`,
      { user_uid: null },
    );
  } catch (err) {
    if (err?.status === 403 || err?.status === 404) {
      throw err;
    }
    recordFailure('razorpay_orders', err);
  }

  try {
    await supabaseRequest(config, 'DELETE', `users?firebase_uid=eq.${encodeURIComponent(uid)}`);
  } catch (deleteErr) {
    if (deleteErr?.status === 403 || deleteErr?.status === 404) {
      throw deleteErr;
    }
    try {
      await supabaseRequest(
        config,
        'PATCH',
        `users?firebase_uid=eq.${encodeURIComponent(uid)}`,
        {
          display_name: 'Deleted User',
          email: `deleted-${uid}@deleted.invalid`,
          mobile: null,
          photo_url: null,
          deactivated: true,
          firebase_uid: null,
        },
      );
    } catch (patchErr) {
      if (patchErr?.status === 403 || patchErr?.status === 404) {
        throw patchErr;
      }
      recordFailure('users', patchErr || deleteErr);
    }
  }

  // TASK 1e: auth.users admin call removed (Firebase Auth is primary)

  return { skipped: false, failedSupabaseTables };
}

/**
 * Deletes only the authenticated user's personal/account data, then Auth.
 * Shared clinical/commerce/history records are intentionally preserved.
 * @param {string} uid Firebase Auth uid (must come from context.auth.uid)
 */
async function deleteMyAccountHandler(uid) {
  const normalizedUid = String(uid || '').trim();
  if (!normalizedUid) {
    throw new HttpsError('unauthenticated', 'Authentication required.');
  }

  const { isSystemAdminAuthUser } = require('./system_admin_auth_guard');
  try {
    const authUser = await getAuth().getUser(normalizedUid);
    if (isSystemAdminAuthUser(authUser)) {
      throw new HttpsError(
        'permission-denied',
        'SYSTEM_ADMIN_PROTECTED: Platform admin account cannot be deleted.',
      );
    }
  } catch (e) {
    if (e instanceof HttpsError) throw e;
  }

  let profile = null;
  try {
    profile = await resolveCallerIdentity({ uid: normalizedUid });
  } catch (err) {
    if (err instanceof HttpsError && err.code === 'unavailable') throw err;
    profile = null; // no Postgres profile row
  }

  if (!profile) {
    try {
      await getAuth().deleteUser(normalizedUid);
    } catch (err) {
      if (err?.code !== 'auth/user-not-found') {
        logger.error('deleteMyAccount auth cleanup failed for missing profile', {
          uidHash: hashKey(normalizedUid).slice(0, 16),
          code: err?.code || 'unknown',
        });
        throw new HttpsError('internal', 'Could not delete account. Please try again.');
      }
    }
    return { ok: true, alreadyDeleted: true };
  }

  const role = String(profile.role || '').trim();
  const profileId = String(profile.profileId || profile.profile_id || '').trim();
  const mobileDigits = normalizeMobileDigits(profile.mobile || profile.phone);

  // 1. S3 objects (all versions). Any failure keeps the Auth user so the deletion can be retried.
  let failedS3Prefixes = [];
  try {
    const s3 = getS3Client();
    const prefixes = await resolveUserS3Prefixes(null, { uid: normalizedUid, role, profileId });
    failedS3Prefixes = await cleanupUserS3Prefixes(s3, s3Bucket(normalizedUid), prefixes);
  } catch (s3Err) {
    failedS3Prefixes = ['*'];
    logger.error('deleteMyAccount S3 cleanup failed', {
      uidHash: hashKey(normalizedUid).slice(0, 16),
      message: s3Err?.message || 'unknown',
    });
  }
  if (failedS3Prefixes.length > 0) {
    throw new HttpsError('unavailable', 'Could not delete all account files. Please try again.');
  }

  // 2. Redis OTP / session state for the account's mobile number.
  await cleanupUserRedisKeys({ mobileDigits, role });

  // 3. Postgres rows. Fail closed: if any table could not be cleaned, keep the Auth user so the
  //    user can retry instead of leaving orphaned PHI behind an account they can no longer access.
  let supabaseCleanup;
  try {
    supabaseCleanup = await cleanupUserSupabaseRows({ uid: normalizedUid, role, profileId });
  } catch (sbErr) {
    logger.error('deleteMyAccount Postgres cleanup failed', {
      uidHash: hashKey(normalizedUid).slice(0, 16),
      status: sbErr?.status || 'unknown',
    });
    throw new HttpsError('unavailable', 'Could not delete account data. Please try again.');
  }
  const failedSupabaseTables = supabaseCleanup?.failedSupabaseTables || [];
  if (supabaseCleanup?.skipped || failedSupabaseTables.length > 0) {
    logger.error('deleteMyAccount Postgres cleanup incomplete; Auth user kept for retry', {
      uidHash: hashKey(normalizedUid).slice(0, 16),
      failedSupabaseTables,
      skipped: Boolean(supabaseCleanup?.skipped),
    });
    throw new HttpsError('unavailable', 'Could not delete all account data. Please try again.');
  }

  // 4. Firebase Auth user LAST.
  try {
    await getAuth().deleteUser(normalizedUid);
  } catch (authErr) {
    if (authErr?.code !== 'auth/user-not-found') {
      logger.error('deleteMyAccount Firebase Auth deletion failed', {
        uidHash: hashKey(normalizedUid).slice(0, 16),
        code: authErr?.code || 'unknown',
      });
      throw new HttpsError('internal', 'Could not delete account. Please try again.');
    }
  }

  logger.info('deleteMyAccount completed', { uidHash: hashKey(normalizedUid).slice(0, 16), role });
  return { ok: true };
}

module.exports = {
  deleteMyAccountHandler,
  deleteS3PrefixVersions,
  deleteS3SpecificKeysVersions,
  resolveUserS3Prefixes,
  planeKeyPrefixes,
  cleanupUserS3Prefixes,
  cleanupUserSupabaseRows,
  cleanupUserRedisKeys,
  setS3ClientForTesting,
  setSupabaseFetchForTesting,
  getS3Client,
  getSupabaseServiceConfig,

  supabaseServiceRoleKey,
};
