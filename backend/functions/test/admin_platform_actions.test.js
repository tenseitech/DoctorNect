'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { isSystemAdminRecord, SYSTEM_ADMIN_EMAIL } = require('../admin_platform_actions');

test('isSystemAdminRecord matches fixed email and flag', () => {
  assert.equal(isSystemAdminRecord({ email: SYSTEM_ADMIN_EMAIL }), true);
  assert.equal(isSystemAdminRecord({ email: 'Admin@DoctorNect.com' }), true);
  assert.equal(isSystemAdminRecord({ is_system_admin: true, email: 'ops@doctornect.com' }), true);
  assert.equal(isSystemAdminRecord({ email: 'user@example.com' }), false);
});
