'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { supabaseCompatibleCustomClaims } = require('../registration_otp');

test('custom token role is authenticated and the app role is a separate claim', () => {
  assert.deepEqual(supabaseCompatibleCustomClaims('patient'), {
    role: 'authenticated',
    app_role: 'patient',
  });
  assert.deepEqual(
    supabaseCompatibleCustomClaims('super_admin', { loginMethod: 'mobile_otp' }),
    {
      role: 'authenticated',
      app_role: 'super_admin',
      loginMethod: 'mobile_otp',
    },
  );
});
