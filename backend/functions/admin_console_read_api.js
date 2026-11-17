'use strict';

const { onRequest } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const {
  applyCors,
  assertSuperAdminHttp,
  parseLimit,
  assertUserId,
  isDirectoryExcludedRow,
  publicError,
} = require('./admin_console_read_security');

const supabaseServiceRoleKey = defineSecret('SUPABASE_SERVICE_ROLE_KEY');

const USER_LIST_COLUMNS =
  'id,email,display_name,mobile,role,profile_id,verified,status,deactivated,created_at,updated_at,photo_url,is_system_admin';

function getSupabaseAdmin() {
  const { getDatabaseClient } = require('./src/db/client');
  return getDatabaseClient();
}

function sendJson(res, status, body) {
  res.status(status).set('Content-Type', 'application/json');
  res.send(JSON.stringify(body));
}

async function buildPendingList(supabase) {
  const { data: users, error } = await supabase
    .from('users')
    .select('id,profile_id,role,display_name,email,mobile,status,verified,created_at')
    .in('role', ['doctor', 'lab', 'medicalStore', 'ambulance', 'medical'])
    .eq('verified', false)
    .limit(500);
  if (error) throw error;
  return (users || [])
    .filter((u) => !isDirectoryExcludedRow(u))
    .map((u) => ({
      id: u.profile_id || u.id,
      owner_uid: u.id,
      provider_type: u.role,
      name: u.display_name || u.email,
      email: u.email,
      phone: u.mobile,
      address: '',
      license_number: '',
      specialty_or_category: '',
      experience: '',
      status: u.status,
      verified: u.verified,
      submitted_at: u.created_at,
      raw_data: u,
    }));
}

async function buildUserSummary(supabase) {
  const { data, error } = await supabase
    .from('users')
    .select('role,deactivated,status,is_system_admin,email');
  if (error) throw error;
  const rows = (data || []).filter((r) => !isDirectoryExcludedRow(r));
  const byRole = {};
  let active = 0;
  let suspended = 0;
  for (const row of rows) {
    const role = String(row.role || 'unknown').toLowerCase();
    byRole[role] = (byRole[role] || 0) + 1;
    const deactivated = row.deactivated === true;
    const status = String(row.status || '').toLowerCase();
    if (deactivated || status === 'suspended') suspended += 1;
    else active += 1;
  }
  return {
    totalDirectory: rows.length,
    active,
    suspended,
    byRole,
  };
}

async function adminConsoleReadHandler(req, res) {
  applyCors(req, res);
  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }
  if (req.method !== 'GET') {
    sendJson(res, 405, { error: 'Method not allowed' });
    return;
  }

  const contentLength = parseInt(req.headers['content-length'] || '0', 10);
  if (contentLength > 4096) {
    sendJson(res, 413, { error: 'Request too large' });
    return;
  }

  try {
    const supabase = getSupabaseAdmin();
    await assertSuperAdminHttp(req, supabase);

    const rawPath = req.path || new URL(req.url || '/', 'http://localhost').pathname;
    const path = String(rawPath).replace(/\/adminConsoleRead\/?/i, '').replace(/\/+$/, '');
    const segments = path.split('/').filter(Boolean);
    const resource = segments[0] || '';

    if (resource === 'users') {
      const id = segments[1];
      if (id) {
        const userId = assertUserId(id);
        const { data, error } = await supabase
          .from('users')
          .select(USER_LIST_COLUMNS)
          .eq('id', userId)
          .maybeSingle();
        if (error) throw error;
        if (data && isDirectoryExcludedRow(data)) {
          sendJson(res, 404, { error: 'Not found' });
          return;
        }
        sendJson(res, 200, data);
        return;
      }
      const limit = parseLimit(req.query?.limit);
      const { data, error } = await supabase
        .from('users')
        .select(USER_LIST_COLUMNS)
        .order('created_at', { ascending: false })
        .limit(limit);
      if (error) throw error;
      sendJson(res, 200, (data || []).filter((r) => !isDirectoryExcludedRow(r)));
      return;
    }

    if (resource === 'verification' && segments[1] === 'pending') {
      const list = await buildPendingList(supabase);
      sendJson(res, 200, list);
      return;
    }

    if (resource === 'audit-logs') {
      const limit = parseLimit(req.query?.limit);
      const { data, error } = await supabase
        .from('admin_audit_logs')
        .select(
          'log_id,admin_uid,admin_email,action,target_type,target_id,target_name,details,metadata,created_at',
        )
        .order('created_at', { ascending: false })
        .limit(limit);
      if (error) throw error;
      sendJson(res, 200, data || []);
      return;
    }

    if (resource === 'banners') {
      if (segments[1] === 'config') {
        const { data, error } = await supabase
          .from('system_config')
          .select('config_key, config_value')
          .eq('config_key', 'promoted_ads')
          .maybeSingle();
        if (error) throw error;
        sendJson(res, 200, data?.config_value || {});
        return;
      }
      if (segments[1] === 'ads') {
        const limit = parseLimit(req.query?.limit);
        const { data, error } = await supabase
          .from('promoted_ads')
          .select('*')
          .order('created_at', { ascending: false })
          .limit(limit);
        if (error) throw error;
        sendJson(res, 200, data || []);
        return;
      }
    }

    if (resource === 'analytics') {
      if (segments[1] === 'appointments') {
        const limit = parseLimit(req.query?.limit);
        const { data, error } = await supabase.from('appointments').select('*').limit(limit);
        if (error) throw error;
        sendJson(res, 200, data || []);
        return;
      }
      if (segments[1] === 'summary') {
        const summary = await buildUserSummary(supabase);
        sendJson(res, 200, summary);
        return;
      }
    }

    if (resource === '' || resource === 'health') {
      sendJson(res, 200, { ok: true, service: 'adminConsoleRead' });
      return;
    }

    sendJson(res, 404, { error: 'Not found' });
  } catch (e) {
    const pub = publicError(e);
    const status =
      pub.code === 'permission-denied'
        ? 403
        : pub.code === 'unauthenticated'
          ? 401
          : pub.code === 'invalid-argument'
            ? 400
            : pub.code === 'resource-exhausted'
              ? 429
              : 500;
    if (status === 500) {
      console.warn('[adminConsoleRead] request failed', pub.code);
    }
    sendJson(res, status, { error: pub.message, code: pub.code });
  }
}

const adminConsoleRead = onRequest(
  {
    region: 'asia-south1',
    secrets: [supabaseServiceRoleKey],
    cors: false,
  },
  adminConsoleReadHandler,
);

module.exports = {
  adminConsoleRead,
  adminConsoleReadHandler,
  buildUserSummary,
};
