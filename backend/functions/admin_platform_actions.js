'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const { getAuth } = require('firebase-admin/auth');
const { resolveCallerIdentity } = require('./caller_identity');
const { assertFirebaseAuthUserMutable } = require('./system_admin_auth_guard');
const { invalidatePromotedAdsCache } = require('./banner_cache_invalidation');
const { assertAppCheck } = require('./abuse_rate_limit');
const { getFirestore } = require('firebase-admin/firestore');

const SYSTEM_ADMIN_EMAIL = 'admin@doctornect.com';
const supabaseServiceRoleKey = defineSecret('SUPABASE_SERVICE_ROLE_KEY');

const ENFORCE_ABUSE_APP_CHECK = String(
  process.env.ENFORCE_ABUSE_APP_CHECK || process.env.ENFORCE_OTP_APP_CHECK || 'true',
)
  .trim()
  .toLowerCase() !== 'false';

function getSupabaseAdmin() {
  const { getDatabaseClient } = require('./src/db/client');
  return getDatabaseClient();
}

function normalizeEmail(email) {
  return String(email || '').trim().toLowerCase();
}

function isSystemAdminRecord(userRow) {
  if (!userRow) return false;
  if (userRow.is_system_admin === true) return true;
  return normalizeEmail(userRow.email) === SYSTEM_ADMIN_EMAIL;
}

function isSuperAdminCaller(auth, callerRow) {
  const email = normalizeEmail(auth?.token?.email);
  const emailVerified = auth?.token?.email_verified === true;
  if (emailVerified && email === SYSTEM_ADMIN_EMAIL) return true;
  const role = String(callerRow?.role || '').toLowerCase();
  return role === 'super_admin' || role === 'superadmin';
}

async function fetchUserById(supabase, userId) {
  const { data, error } = await supabase
    .from('users')
    .select('*')
    .eq('id', userId)
    .maybeSingle();
  if (error) throw new HttpsError('internal', error.message);
  return data;
}

async function insertAuditLog(supabase, row) {
  const logId = `adm_${Date.now()}_${Math.floor(Math.random() * 10000)}`;
  try {
    await supabase.from('admin_audit_logs').insert({
      log_id: logId,
      admin_uid: row.adminUid,
      admin_email: row.adminEmail,
      action: row.action,
      target_type: row.targetType,
      target_id: row.targetId,
      target_name: row.targetName,
      details: row.details,
      metadata: row.metadata || {},
      created_at: new Date().toISOString(),
    });
  } catch (e) {
    // Audit failure must not mask primary security decision.
    console.warn('[admin_platform_actions] audit insert failed', e?.message || e);
  }
}

async function assertSuperAdminPlatform(request) {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required.');
  }
  assertAppCheck(request, { enforce: ENFORCE_ABUSE_APP_CHECK });
  const supabase = getSupabaseAdmin();
  const caller = await resolveCallerIdentity({
    uid: request.auth.uid,
    supabaseClient: supabase,
    forceSupabase: true,
  });
  if (!isSuperAdminCaller(request.auth, caller)) {
    throw new HttpsError('permission-denied', 'Super admin access required.');
  }
  return { supabase, caller };
}

async function guardTargetNotSystemAdmin(supabase, caller, targetUserId, action, auth) {
  const target = await fetchUserById(supabase, targetUserId);
  if (!target) {
    throw new HttpsError('not-found', 'User not found.');
  }
  if (isSystemAdminRecord(target)) {
    await insertAuditLog(supabase, {
      adminUid: caller.id,
      adminEmail: caller.email || auth?.token?.email || '',
      action: 'SYSTEM_ADMIN_PROTECTED_BLOCK',
      targetType: 'user',
      targetId: target.id,
      targetName: target.display_name || target.email || SYSTEM_ADMIN_EMAIL,
      details: `Blocked ${action}: platform system admin cannot be modified.`,
      metadata: { attemptedAction: action, blocked: true },
    });
    throw new HttpsError(
      'permission-denied',
      'SYSTEM_ADMIN_PROTECTED: This account cannot be modified.',
    );
  }
  return target;
}

function roleTable(role) {
  const r = String(role || '').toLowerCase();
  if (r === 'doctor') return { table: 'doctors', idCol: 'doctor_id' };
  if (r === 'lab') return { table: 'labs', idCol: 'lab_id' };
  if (r === 'medicalstore' || r === 'pharmacy' || r === 'medical') {
    return { table: 'medical_stores', idCol: 'store_id' };
  }
  if (r === 'ambulance') return { table: 'ambulances', idCol: 'ambulance_id' };
  if (r === 'patient') return { table: 'patients', idCol: 'patient_id' };
  return null;
}

async function adminUpdateUserRoleHandler(request) {
  const { supabase, caller } = await assertSuperAdminPlatform(request);
  const data = request.data || {};
  const targetUserId = String(data.targetUserId || '').trim();
  const newRole = String(data.newRole || '').trim();
  const reason = String(data.reason || '').trim();
  if (!targetUserId || !newRole) {
    throw new HttpsError('invalid-argument', 'targetUserId and newRole are required.');
  }
  if (newRole === 'super_admin' || newRole === 'superAdmin') {
    throw new HttpsError('permission-denied', 'Assigning Super Admin via console is disabled.');
  }
  const target = await guardTargetNotSystemAdmin(
    supabase,
    caller,
    targetUserId,
    'USER_ROLE_CHANGE',
    request.auth,
  );

  const { error } = await supabase
    .from('users')
    .update({ role: newRole, updated_at: new Date().toISOString() })
    .eq('id', targetUserId);
  if (error) throw new HttpsError('internal', error.message);

  await insertAuditLog(supabase, {
    adminUid: caller.id,
    adminEmail: caller.email || request.auth.token?.email || '',
    action: 'USER_ROLE_CHANGE',
    targetType: 'user',
    targetId: targetUserId,
    targetName: target.display_name || target.email || targetUserId,
    details: `Role changed to ${newRole}${reason ? ` (${reason})` : ''}`,
    metadata: { previousRole: target.role, newRole, reason },
  });

  return { ok: true, message: 'Role updated.' };
}

async function adminToggleUserSuspensionHandler(request) {
  const { supabase, caller } = await assertSuperAdminPlatform(request);
  const data = request.data || {};
  const targetUserId = String(data.targetUserId || '').trim();
  const suspend = data.suspend === true;
  const reason = String(data.reason || '').trim();
  const profileId = String(data.profileId || '').trim();
  const role = String(data.role || '').trim();
  if (!targetUserId) throw new HttpsError('invalid-argument', 'targetUserId is required.');

  const target = await guardTargetNotSystemAdmin(
    supabase,
    caller,
    targetUserId,
    suspend ? 'USER_SUSPEND' : 'USER_ACTIVATE',
    request.auth,
  );

  const { error } = await supabase
    .from('users')
    .update({
      deactivated: suspend,
      status: suspend ? 'suspended' : 'approved',
      updated_at: new Date().toISOString(),
    })
    .eq('id', targetUserId);
  if (error) throw new HttpsError('internal', error.message);

  const mapped = roleTable(role || target.role);
  if (mapped && profileId) {
    await supabase
      .from(mapped.table)
      .update({
        deactivated: suspend,
        status: suspend ? 'suspended' : 'approved',
        updated_at: new Date().toISOString(),
      })
      .eq(mapped.idCol, profileId);
  }

  if (suspend) {
    try {
      await assertFirebaseAuthUserMutable(targetUserId, { action: 'disable' });
      const userRecord = await getAuth().getUser(targetUserId);
      if (userRecord && !userRecord.disabled) {
        await getAuth().updateUser(targetUserId, { disabled: true });
      }
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.warn('[adminToggleUserSuspension] auth disable skipped', e?.message || e);
    }
  } else {
    try {
      await getAuth().updateUser(targetUserId, { disabled: false });
    } catch (_) {}
  }

  await insertAuditLog(supabase, {
    adminUid: caller.id,
    adminEmail: caller.email || request.auth.token?.email || '',
    action: suspend ? 'USER_SUSPEND' : 'USER_ACTIVATE',
    targetType: 'user',
    targetId: targetUserId,
    targetName: target.display_name || target.email || targetUserId,
    details: suspend
      ? `Account suspended${reason ? `: ${reason}` : ''}`
      : 'Account reactivated',
    metadata: { suspended: suspend, reason },
  });

  return { ok: true, message: suspend ? 'User suspended.' : 'User reactivated.' };
}

async function adminUpdateUserPhoneHandler(request) {
  const { supabase, caller } = await assertSuperAdminPlatform(request);
  const data = request.data || {};
  const targetUserId = String(data.targetUserId || '').trim();
  let mobile = String(data.mobile || '').replace(/\D/g, '');
  const profileId = String(data.profileId || '').trim();
  const role = String(data.role || '').trim();
  if (!targetUserId || mobile.length < 10) {
    throw new HttpsError('invalid-argument', 'Valid targetUserId and 10-digit mobile required.');
  }
  if (mobile.length > 10) mobile = mobile.slice(-10);

  const target = await guardTargetNotSystemAdmin(
    supabase,
    caller,
    targetUserId,
    'USER_PHONE_CHANGE',
    request.auth,
  );

  const { error } = await supabase
    .from('users')
    .update({ mobile, updated_at: new Date().toISOString() })
    .eq('id', targetUserId);
  if (error) throw new HttpsError('internal', error.message);

  const mapped = roleTable(role || target.role);
  if (mapped && profileId) {
    await supabase
      .from(mapped.table)
      .update({ mobile, updated_at: new Date().toISOString() })
      .eq(mapped.idCol, profileId);
  }

  await insertAuditLog(supabase, {
    adminUid: caller.id,
    adminEmail: caller.email || request.auth.token?.email || '',
    action: 'USER_PHONE_CHANGE',
    targetType: 'user',
    targetId: targetUserId,
    targetName: target.display_name || target.email || targetUserId,
    details: `Updated registered phone to ${mobile}`,
    metadata: { newMobile: mobile, previousMobile: target.mobile || '' },
  });

  return { ok: true, message: 'Phone updated.' };
}

async function adminUpdateOwnProfileHandler(request) {
  const { supabase, caller } = await assertSuperAdminPlatform(request);
  const data = request.data || {};
  const displayName = data.displayName != null ? String(data.displayName).trim() : undefined;
  let mobile = data.mobile != null ? String(data.mobile).replace(/\D/g, '') : undefined;
  const photoUrl = data.photoUrl != null ? String(data.photoUrl).trim() : undefined;
  const photoKey = data.photoKey != null ? String(data.photoKey).trim() : undefined;

  if (mobile != null && mobile.length > 0 && mobile.length < 10) {
    throw new HttpsError('invalid-argument', 'Mobile must be 10 digits.');
  }
  if (mobile != null && mobile.length > 10) mobile = mobile.slice(-10);

  const patch = { updated_at: new Date().toISOString() };
  if (displayName != null && displayName.length > 0) patch.display_name = displayName;
  if (mobile != null && mobile.length >= 10) patch.mobile = mobile;
  if (photoUrl != null && photoUrl.length > 0) patch.photo_url = photoUrl;

  const { error } = await supabase.from('users').update(patch).eq('id', caller.id);
  if (error) throw new HttpsError('internal', error.message);

  await insertAuditLog(supabase, {
    adminUid: caller.id,
    adminEmail: caller.email || request.auth.token?.email || '',
    action: 'ADMIN_PROFILE_UPDATE',
    targetType: 'admin',
    targetId: caller.id,
    targetName: caller.display_name || caller.email || 'Super Admin',
    details: 'Updated console profile',
    metadata: {
      displayName: displayName || null,
      mobile: mobile || null,
      photoKey: photoKey || null,
    },
  });

  return { ok: true, message: 'Profile saved.' };
}

async function adminSetProviderVerificationHandler(request) {
  const { supabase, caller } = await assertSuperAdminPlatform(request);
  const data = request.data || {};
  const approve = data.approve === true;
  const ownerUid = String(data.ownerUid || data.targetUserId || '').trim();
  const profileId = String(data.profileId || '').trim();
  const role = String(data.role || 'doctor').trim();
  const reason = String(data.reason || '').trim();
  const providerName = String(data.providerName || '').trim();
  if (!ownerUid) throw new HttpsError('invalid-argument', 'ownerUid is required.');

  await guardTargetNotSystemAdmin(
    supabase,
    caller,
    ownerUid,
    approve ? 'VERIFICATION_APPROVE' : 'VERIFICATION_REJECT',
    request.auth,
  );

  const now = new Date().toISOString();
  const userPatch = approve
    ? { verified: true, status: 'approved', verified_at: now, updated_at: now }
    : { verified: false, status: 'rejected', updated_at: now };

  const { error: userErr } = await supabase.from('users').update(userPatch).eq('id', ownerUid);
  if (userErr) throw new HttpsError('internal', userErr.message);

  const mapped = roleTable(role);
  const roleId = profileId || ownerUid;
  if (mapped && roleId) {
    await supabase
      .from(mapped.table)
      .update({
        verified: approve,
        status: approve ? 'approved' : 'rejected',
        updated_at: now,
      })
      .eq(mapped.idCol, roleId);
  }

  await insertAuditLog(supabase, {
    adminUid: caller.id,
    adminEmail: caller.email || request.auth.token?.email || '',
    action: approve ? 'VERIFICATION_APPROVE' : 'VERIFICATION_REJECT',
    targetType: role,
    targetId: ownerUid,
    targetName: providerName || ownerUid,
    details: approve
      ? `Approved ${role} verification`
      : `Rejected ${role} verification${reason ? `: ${reason}` : ''}`,
    metadata: { profileId: roleId, reason: reason || null },
  });

  return { ok: true, message: approve ? 'Provider approved.' : 'Provider rejected.' };
}

async function adminUpdateBannerConfigHandler(request) {
  const { supabase, caller } = await assertSuperAdminPlatform(request);
  const configValue = request.data?.configValue;
  if (!configValue || typeof configValue !== 'object') {
    throw new HttpsError('invalid-argument', 'configValue object is required.');
  }

  const { error } = await supabase.from('system_config').upsert(
    {
      config_key: 'promoted_ads',
      config_value: configValue,
      updated_at: new Date().toISOString(),
    },
    { onConflict: 'config_key' },
  );
  if (error) throw new HttpsError('internal', error.message);

  const cacheResult = await invalidatePromotedAdsCache();

  await insertAuditLog(supabase, {
    adminUid: caller.id,
    adminEmail: caller.email || request.auth.token?.email || '',
    action: 'BANNER_CONFIG_UPDATE',
    targetType: 'system_config',
    targetId: 'promoted_ads',
    targetName: 'promoted_ads',
    details: 'Banner configuration updated',
    metadata: { cache: cacheResult },
  });

  return { ok: true, message: 'Banner config saved.', cache: cacheResult };
}

async function adminLogAuditEventHandler(request) {
  const { supabase, caller } = await assertSuperAdminPlatform(request);
  const data = request.data || {};
  const action = String(data.action || '').trim();
  const targetType = String(data.targetType || '').trim();
  const targetId = String(data.targetId || '').trim();
  const details = String(data.details || '').trim();
  if (!action || !targetType || !targetId) {
    throw new HttpsError('invalid-argument', 'action, targetType, and targetId are required.');
  }
  await insertAuditLog(supabase, {
    adminUid: caller.id,
    adminEmail: caller.email || request.auth.token?.email || '',
    action,
    targetType,
    targetId,
    targetName: String(data.targetName || '').trim(),
    details: details || action,
    metadata: data.metadata && typeof data.metadata === 'object' ? data.metadata : {},
  });
  return { ok: true, message: 'Audit recorded.' };
}

async function adminMutatePromotedAdHandler(request) {
  const { supabase, caller } = await assertSuperAdminPlatform(request);
  const data = request.data || {};
  const adId = String(data.adId || '').trim();
  const action = String(data.action || '').trim().toLowerCase();
  if (!adId || !action) {
    throw new HttpsError('invalid-argument', 'adId and action are required.');
  }

  const now = new Date().toISOString();
  if (action === 'delete') {
    const { error } = await supabase.from('promoted_ads').delete().eq('ad_id', adId);
    if (error) throw new HttpsError('internal', error.message);
  } else if (action === 'update_status') {
    const newStatus = String(data.newStatus || '').trim().toLowerCase();
    const patch = { status: newStatus, updated_at: now };
    if (newStatus === 'active') patch.payment_status = 'verified';
    if (data.startTime) patch.start_time = data.startTime;
    if (data.endTime) patch.end_time = data.endTime;
    if (data.reason) patch.admin_remark = String(data.reason).trim();
    const { error } = await supabase.from('promoted_ads').update(patch).eq('ad_id', adId);
    if (error) throw new HttpsError('internal', error.message);
  } else {
    throw new HttpsError('invalid-argument', `Unknown action: ${action}`);
  }

  const cacheResult = await invalidatePromotedAdsCache();

  await insertAuditLog(supabase, {
    adminUid: caller.id,
    adminEmail: caller.email || request.auth.token?.email || '',
    action: action === 'delete' ? 'BANNER_AD_DELETE' : 'BANNER_AD_STATUS',
    targetType: 'promoted_ad',
    targetId: adId,
    targetName: adId,
    details: `Promoted ad ${action}`,
    metadata: { action, newStatus: data.newStatus || null, cache: cacheResult },
  });

  return { ok: true, message: 'Promoted ad updated.', cache: cacheResult };
}

const callableOpts = {
  region: 'asia-south1',
  enforceAppCheck: ENFORCE_ABUSE_APP_CHECK,
  secrets: [supabaseServiceRoleKey],
};

const adminUpdateUserRole = onCall(callableOpts, (request) => adminUpdateUserRoleHandler(request));
const adminToggleUserSuspension = onCall(callableOpts, (request) => adminToggleUserSuspensionHandler(request));
const adminUpdateUserPhone = onCall(callableOpts, (request) => adminUpdateUserPhoneHandler(request));
const adminUpdateOwnProfile = onCall(callableOpts, (request) => adminUpdateOwnProfileHandler(request));
const adminSetProviderVerification = onCall(callableOpts, (request) =>
  adminSetProviderVerificationHandler(request),
);
const adminUpdateBannerConfig = onCall(callableOpts, (request) => adminUpdateBannerConfigHandler(request));
const adminMutatePromotedAd = onCall(callableOpts, (request) => adminMutatePromotedAdHandler(request));
const adminLogAuditEvent = onCall(callableOpts, (request) => adminLogAuditEventHandler(request));

module.exports = {
  adminUpdateUserRole,
  adminToggleUserSuspension,
  adminUpdateUserPhone,
  adminUpdateOwnProfile,
  adminSetProviderVerification,
  adminUpdateBannerConfig,
  adminMutatePromotedAd,
  adminLogAuditEvent,
  SYSTEM_ADMIN_EMAIL,
  isSystemAdminRecord,
  adminUpdateUserRoleHandler,
  adminToggleUserSuspensionHandler,
  adminUpdateUserPhoneHandler,
  adminUpdateOwnProfileHandler,
  adminSetProviderVerificationHandler,
  adminUpdateBannerConfigHandler,
  adminMutatePromotedAdHandler,
  adminLogAuditEventHandler,
  guardTargetNotSystemAdmin,
};
