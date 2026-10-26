'use strict';

/**
 * DoctorNect Production Smoke Verification Script
 * Validates the live production environment end-to-end:
 * 1. Health check (/healthz) returns 200 OK
 * 2. Anonymous read of /rest/v1/doctor_directory succeeds
 * 3. Authenticated test call using a synthetic smoke test user
 * 4. Verifies zero residue: deletes the smoke test user row using service role key
 * 5. Asserts that the database has zero residue after the test
 */

const { getEnv } = require('../lib/env_loader');
const { createClient } = require('@supabase/supabase-js');
const crypto = require('node:crypto');

async function runProductionSmoke() {
  console.log('====================================================');
  console.log('DOCTORNECT PRODUCTION SMOKE TEST');
  console.log('====================================================\n');

  const gatewayUrl = getEnv('PROD_GATEWAY_URL');
  const serviceKey = getEnv('PROD_GATEWAY_SERVICE_KEY');
  const anonKey = getEnv('PROD_GATEWAY_ANON_KEY') || 'doctornect-anon-public-key';

  if (!gatewayUrl) {
    console.error('❌ BLOCKED: PROD_GATEWAY_URL is not configured.');
    process.exit(1);
  }

  console.log(`Target Gateway: ${gatewayUrl}`);

  // 1. Health Check
  console.log('\n--- Step 1: Health Check (/healthz) ---');
  try {
    const healthRes = await fetch(`${gatewayUrl}/healthz`, {
      signal: AbortSignal.timeout(5000),
    });
    if (!healthRes.ok) {
      throw new Error(`Health check returned HTTP ${healthRes.status}`);
    }
    const healthData = await healthRes.json();
    console.log(`✅ Gateway is healthy: ${JSON.stringify(healthData)}`);
  } catch (err) {
    console.error(`❌ Step 1 FAILED: ${err.message}`);
    process.exit(1);
  }

  // 2. Anonymous Read of doctor_directory
  console.log('\n--- Step 2: Anonymous Public Directory Read ---');
  try {
    const dirRes = await fetch(`${gatewayUrl}/rest/v1/doctor_directory?select=id,full_name,specialization&limit=5`, {
      headers: {
        'apikey': anonKey,
        'Accept': 'application/json',
      },
      signal: AbortSignal.timeout(5000),
    });
    if (!dirRes.ok) {
      throw new Error(`Anonymous directory read returned HTTP ${dirRes.status}`);
    }
    const directory = await dirRes.json();
    console.log(`✅ Anonymous read succeeded (${directory.length} doctors returned).`);
  } catch (err) {
    console.error(`❌ Step 2 FAILED: ${err.message}`);
    process.exit(1);
  }

  // 3 & 4. Authenticated Service Key Test + Zero Residue Cleanup
  if (!serviceKey) {
    console.log('\n⚠️ Step 3 & 4 SKIPPED: PROD_GATEWAY_SERVICE_KEY not provided.');
    console.log('Production smoke verification partial pass (public endpoints verified).');
    process.exit(0);
  }

  console.log('\n--- Step 3 & 4: Service Key Authenticated Flow & Zero Residue ---');
  const adminClient = createClient(gatewayUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const testSmokeUid = `smoke_test_${crypto.randomUUID()}`;
  const testEmail = `smoke_${Date.now()}@doctornect-verify.internal`;

  try {
    // Record count before
    const { count: beforeCount, error: countErr1 } = await adminClient
      .from('users')
      .select('id', { count: 'exact', head: true });

    if (countErr1) throw countErr1;
    console.log(`Baseline user count: ${beforeCount}`);

    // Insert smoke test row
    console.log(`Inserting temporary smoke record (uid: ${testSmokeUid})...`);
    const { data: inserted, error: insertErr } = await adminClient
      .from('users')
      .insert({
        id: testSmokeUid,
        mobile: '+919999900001',
        email: testEmail,
        role: 'patient',
        display_name: 'Smoke Test Patient',
        profile_id: testSmokeUid,
        verified: true,
      })
      .select();

    if (insertErr) throw insertErr;
    console.log(`✅ Temporary record inserted successfully.`);

    // Read back
    const { data: readBack, error: readErr } = await adminClient
      .from('users')
      .select('id, email, role')
      .eq('id', testSmokeUid)
      .single();

    if (readErr) throw readErr;
    console.log(`✅ Verified read back: id=${readBack.id}, role=${readBack.role}`);

    // Delete smoke record
    console.log(`Cleaning up smoke record...`);
    const { error: delErr } = await adminClient
      .from('users')
      .delete()
      .eq('id', testSmokeUid);

    if (delErr) throw delErr;

    // Verify zero residue
    const { count: afterCount, error: countErr2 } = await adminClient
      .from('users')
      .select('id', { count: 'exact', head: true });

    if (countErr2) throw countErr2;
    console.log(`Post-test user count: ${afterCount}`);

    if (afterCount !== beforeCount) {
      throw new Error(`Residue detected! Before: ${beforeCount}, After: ${afterCount}`);
    }

    console.log('✅ ZERO RESIDUE PROVEN: Count before and after are identical.');
    console.log('\n====================================================');
    console.log('ALL PRODUCTION SMOKE TESTS PASSED (VERDICT: PASS)');
    console.log('====================================================');
  } catch (err) {
    console.error(`❌ Step 3/4 FAILED: ${err.message}`);
    // Attempt emergency cleanup
    await adminClient.from('users').delete().eq('id', testSmokeUid).catch(() => {});
    process.exit(1);
  }
}

if (require.main === module) {
  runProductionSmoke().catch((e) => {
    console.error('Fatal production smoke error:', e);
    process.exit(1);
  });
}

module.exports = {
  runProductionSmoke,
};
