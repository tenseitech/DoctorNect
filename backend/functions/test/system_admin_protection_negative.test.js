'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { HttpsError } = require('firebase-functions/v2/https');

const { guardTargetNotSystemAdmin, isSystemAdminRecord } = require('../admin_platform_actions');
const { isSystemAdminAuthUser } = require('../system_admin_auth_guard');

function mockSupabaseForSystemAdmin() {
  const systemRow = {
    id: 'admin-uid',
    email: 'admin@doctornect.com',
    role: 'super_admin',
    is_system_admin: true,
    display_name: 'Platform Admin',
  };
  return {
    from() {
      return {
        select() {
          return {
            eq() {
              return {
                maybeSingle: async () => ({ data: systemRow, error: null }),
              };
            },
          };
        },
        insert: async () => ({ error: null }),
      };
    },
  };
}

test('guardTargetNotSystemAdmin rejects protected user mutations', async () => {
  const supabase = mockSupabaseForSystemAdmin();
  const caller = { id: 'other-admin', email: 'ops@doctornect.com' };
  const auth = { token: { email: 'ops@doctornect.com' } };

  await assert.rejects(
    () => guardTargetNotSystemAdmin(supabase, caller, 'admin-uid', 'USER_SUSPEND', auth),
    (err) => err instanceof HttpsError && err.code === 'permission-denied',
  );
});

test('auth guard identifies system admin email', () => {
  assert.equal(isSystemAdminRecord({ email: 'admin@doctornect.com' }), true);
  assert.equal(isSystemAdminAuthUser({ email: 'admin@doctornect.com' }), true);
});
