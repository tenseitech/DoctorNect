/**
 * DoctorNect: Production Pre-Flight & Build Configuration Validator
 * 
 * Verifies that the client release configuration and production backend secrets
 * point to live production infrastructure and do NOT package staging/sandbox defaults.
 * 
 * Precedence Order:
 * 1. CLI flags (--supabase-url=..., --supabase-anon-key=...) [HIGHEST]
 * 2. Explicit environment variables (process.env.SUPABASE_URL, $env:SUPABASE_URL)
 * 3. File-based defaults loaded by load_env.js (.env.migration, .env, functions/.env) [LOWEST]
 * 
 * Usage:
 *   node scripts/verify_production_build_config.js
 *   node scripts/verify_production_build_config.js --client-only
 *   node scripts/verify_production_build_config.js --supabase-url="https://prod.supabase.co" --supabase-anon-key="..."
 * 
 * Returns:
 *   Exit code 0 on success.
 *   Exit code 1 on failure with actionable error messages.
 */

const fs = require('fs');
const path = require('path');

// 1. Snapshot explicit environment variables present in process.env BEFORE .env loader runs
const explicitProcessEnv = {};
for (const key of Object.keys(process.env)) {
  if (process.env[key] !== undefined && process.env[key] !== '') {
    explicitProcessEnv[key] = process.env[key];
  }
}

// 2. Parse command-line override flags (highest priority)
const cliOverrides = {};
for (const arg of process.argv.slice(2)) {
  if (arg.startsWith('--supabase-url=')) {
    cliOverrides.SUPABASE_URL = arg.slice('--supabase-url='.length).trim();
  } else if (arg.startsWith('--supabase-anon-key=')) {
    cliOverrides.SUPABASE_ANON_KEY = arg.slice('--supabase-anon-key='.length).trim();
  } else if (arg.startsWith('--msg91-proxy-url=')) {
    cliOverrides.MSG91_PROXY_URL = arg.slice('--msg91-proxy-url='.length).trim();
  } else if (arg.startsWith('--proxy-secret=')) {
    cliOverrides.PROXY_SECRET = arg.slice('--proxy-secret='.length).trim();
  } else if (arg.startsWith('--razorpay-key-id=')) {
    cliOverrides.RAZORPAY_KEY_ID = arg.slice('--razorpay-key-id='.length).trim();
  } else if (arg.startsWith('--razorpay-key-secret=')) {
    cliOverrides.RAZORPAY_KEY_SECRET = arg.slice('--razorpay-key-secret='.length).trim();
  } else if (arg.startsWith('--razorpay-webhook-secret=')) {
    cliOverrides.RAZORPAY_WEBHOOK_SECRET = arg.slice('--razorpay-webhook-secret='.length).trim();
  }
}

// 3. Load fallback values from .env files (.env.migration, .env, functions/.env)
try {
  require('./load_env').loadEnv();
} catch (e) {
  // Fallback if run from a different CWD
  const loadEnvPath = path.join(__dirname, 'load_env.js');
  if (fs.existsSync(loadEnvPath)) {
    require(loadEnvPath).loadEnv();
  }
}

// 4. Enforce strict precedence: explicit process.env variables override .env files
for (const [key, val] of Object.entries(explicitProcessEnv)) {
  if (val !== undefined && val !== '') {
    process.env[key] = val;
  }
}

// 5. Enforce CLI overrides as highest precedence over everything
for (const [key, val] of Object.entries(cliOverrides)) {
  if (val !== undefined && val !== '') {
    process.env[key] = val;
  }
}

const {
  isSupabaseCloudUrl,
  resolveStagingProjectRefFromEnv,
  urlContainsStagingProjectRef,
} = require('../../scripts/lib/infra_url_policy');

const DEFAULT_PLACEHOLDER_URL = 'https://your-project-ref.supabase.co';
const HEX_TEMPLATE_REGEX = /^[a-fA-F0-9]{20,32}$/;

/** Project ref from STAGING_SUPABASE_URL / STAGING_SUPABASE_DB_URL (env), not hardcoded. */
function resolveStagingProjectRef(options = {}) {
  const stagingUrlRes = resolveParam('STAGING_SUPABASE_URL', options);
  const stagingDbRes = resolveParam('STAGING_SUPABASE_DB_URL', options);
  return resolveStagingProjectRefFromEnv({
    STAGING_SUPABASE_URL: stagingUrlRes.value,
    STAGING_SUPABASE_DB_URL: stagingDbRes.value,
  });
}

/**
 * Resolves a configuration key and identifies its source origin
 */
function resolveParam(key, options = {}) {
  if (options[key] !== undefined && options[key] !== '') {
    return { value: options[key], source: 'Programmatic Option' };
  }
  if (cliOverrides[key] !== undefined && cliOverrides[key] !== '') {
    return { value: cliOverrides[key], source: 'CLI Flag' };
  }
  if (explicitProcessEnv[key] !== undefined && explicitProcessEnv[key] !== '') {
    return { value: explicitProcessEnv[key], source: 'Explicit process.env' };
  }
  if (process.env[key] !== undefined && process.env[key] !== '') {
    return { value: process.env[key], source: '.env File Default' };
  }
  return { value: '', source: 'None' };
}

function verifyProductionConfig(options = {}) {
  const isClientOnly = options.clientOnly !== undefined
    ? options.clientOnly
    : process.argv.includes('--client-only');

  const allowStaging = options.allowStaging !== undefined
    ? options.allowStaging
    : (process.argv.includes('--allow-staging') || process.env.ALLOW_STAGING_BUILD === 'true');

  console.log('================================================================');
  console.log(`DOCTORNECT: PRODUCTION PRE-FLIGHT VALIDATION [${isClientOnly ? 'CLIENT-ONLY' : 'FULL STACK'}]`);
  if (allowStaging) {
    console.log('MODE: STAGING-PERMITTED (--allow-staging active)');
  }
  console.log('================================================================\n');

  const errors = [];
  const warnings = [];
  const stagingProjectRef = resolveStagingProjectRef(options);
  const prodGatewayRes = resolveParam('PROD_GATEWAY_URL', options);
  const prodGatewayUrl = prodGatewayRes.value;

  // ===========================================================================
  // 1. SUPABASE CLIENT CREDENTIALS (for Flutter release bundle)
  // ===========================================================================
  const urlRes = resolveParam('SUPABASE_URL', options);
  const anonRes = resolveParam('SUPABASE_ANON_KEY', options);

  const supabaseUrl = urlRes.value;
  const supabaseAnonKey = anonRes.value;

  console.log('--- 1. Checking Supabase Client Credentials ---');
  if (stagingProjectRef) {
    console.log(`  ℹ️  Staging anchor (from env): project ref '${stagingProjectRef.slice(0, 4)}****'`);
  } else if (!allowStaging) {
    console.log('  ℹ️  STAGING_SUPABASE_URL not set; staging ref comparisons use *.supabase.co rule only.');
  }

  if (!supabaseUrl) {
    errors.push('[SUPABASE_URL] Missing: SUPABASE_URL is not set in environment or flags.');
  } else if (supabaseUrl === DEFAULT_PLACEHOLDER_URL || supabaseUrl.includes('your-project-ref')) {
    errors.push(`[SUPABASE_URL] Placeholder Value: SUPABASE_URL (${urlRes.source}) is set to default placeholder text.`);
  } else if (!supabaseUrl.startsWith('https://')) {
    errors.push(`[SUPABASE_URL] Insecure Protocol: SUPABASE_URL (${urlRes.source}) must use https://.`);
  } else if (!allowStaging && isSupabaseCloudUrl(supabaseUrl)) {
    errors.push(`[SUPABASE_URL] Supabase Cloud Blocked: Production client builds must use the Auth Gateway (PROD_GATEWAY_URL), not a *.supabase.co REST endpoint. (${urlRes.source})`);
  } else if (!allowStaging && stagingProjectRef && urlContainsStagingProjectRef(supabaseUrl, stagingProjectRef)) {
    errors.push(`[SUPABASE_URL] Staging Leak: SUPABASE_URL (${urlRes.source}) matches STAGING_SUPABASE_URL project ref '${stagingProjectRef}'. Pass --allow-staging only for deliberate staging artifacts.`);
  } else if (allowStaging && (isSupabaseCloudUrl(supabaseUrl) || (stagingProjectRef && urlContainsStagingProjectRef(supabaseUrl, stagingProjectRef)))) {
    warnings.push(`[SUPABASE_URL] Staging Supabase URL permitted via --allow-staging (${urlRes.source}). DO NOT publish to Play production track.`);
    const maskedUrl = supabaseUrl.replace(/^(https:\/\/[a-z0-9]{4})[a-z0-9]+(\..*)$/, '$1****$2');
    console.log(`  ⚠️  SUPABASE_URL: ${maskedUrl} (STAGING PERMITTED, Source: ${urlRes.source})`);
  } else {
    const maskedUrl = supabaseUrl.replace(/^(https:\/\/[a-z0-9]{4})[a-z0-9]+(\..*)$/, '$1****$2');
    const label = prodGatewayUrl && supabaseUrl.trim() === prodGatewayUrl.trim()
      ? 'Auth Gateway aligned'
      : 'Non-Supabase-cloud client API base';
    console.log(`  ✓ SUPABASE_URL: ${maskedUrl} (${label}, Source: ${urlRes.source})`);
  }

  if (!supabaseAnonKey) {
    errors.push('[SUPABASE_ANON_KEY] Missing: SUPABASE_ANON_KEY is not set.');
  } else if (supabaseAnonKey === 'your-anon-key' || supabaseAnonKey.length < 30) {
    errors.push(`[SUPABASE_ANON_KEY] Invalid: SUPABASE_ANON_KEY (${anonRes.source}) is placeholder or suspiciously short.`);
  } else {
    console.log(`  ✓ SUPABASE_ANON_KEY: ${supabaseAnonKey.slice(0, 8)}...${supabaseAnonKey.slice(-4)} (Present, Source: ${anonRes.source})`);
  }

  // If running in client-only mode (called during flutter build), we can finish early if no backend keys needed
  if (!isClientOnly) {
    // =========================================================================
    // 2. MSG91 SMS GATEWAY & PROXY CREDENTIALS (for Cloud Functions / MSG91 egress)
    // =========================================================================
    console.log('\n--- 2. Checking MSG91 Gateway & Egress Proxy Configuration ---');
    const proxyUrlRes = resolveParam('MSG91_PROXY_URL', options);
    const proxySecretRes = resolveParam('PROXY_SECRET', options);
    const templateRegRes = resolveParam('MSG91_TEMPLATE_ID_REGISTRATION', options);
    const templateLoginRes = resolveParam('MSG91_TEMPLATE_ID_LOGIN', options);
    const templateResetRes = resolveParam('MSG91_TEMPLATE_ID_PASSWORD_RESET', options);

    const proxyUrl = proxyUrlRes.value;
    const proxySecret = proxySecretRes.value;

    if (!proxyUrl) {
      warnings.push('[MSG91_PROXY_URL] Not set in local env. Ensure this is configured in Supabase secrets (supabase secrets set).');
    } else if (proxyUrl.includes('localhost') || proxyUrl.includes('127.0.0.1')) {
      errors.push('[MSG91_PROXY_URL] Invalid: MSG91_PROXY_URL points to localhost/mock. Must point to production Cloud Run proxy.');
    } else {
      console.log(`  ✓ MSG91_PROXY_URL: ${proxyUrl} (Source: ${proxyUrlRes.source})`);
    }

    if (!proxySecret) {
      warnings.push('[PROXY_SECRET] Not set in local env. Ensure it is configured via Supabase secrets.');
    } else if (proxySecret === 'your-secret' || proxySecret.toLowerCase().includes('placeholder')) {
      errors.push('[PROXY_SECRET] Insecure: PROXY_SECRET uses placeholder dummy text.');
    } else {
      console.log(`  ✓ PROXY_SECRET: [Configured] (Source: ${proxySecretRes.source})`);
    }

    const templates = [
      { name: 'MSG91_TEMPLATE_ID_REGISTRATION', res: templateRegRes },
      { name: 'MSG91_TEMPLATE_ID_LOGIN', res: templateLoginRes },
      { name: 'MSG91_TEMPLATE_ID_PASSWORD_RESET', res: templateResetRes },
    ];

    for (const t of templates) {
      if (!t.res.value) {
        warnings.push(`[${t.name}] Not set in local env. Confirm it exists in Supabase secrets.`);
      } else if (!HEX_TEMPLATE_REGEX.test(t.res.value)) {
        errors.push(`[${t.name}] Invalid format: '${t.res.value}' (${t.res.source}) is not a valid 24-character hexadecimal DLT template ID.`);
      } else {
        console.log(`  ✓ ${t.name}: ${t.res.value} (Source: ${t.res.source})`);
      }
    }

    // =========================================================================
    // 3. RAZORPAY PAYMENT GATEWAY CREDENTIALS (for razorpay-payments Edge Function)
    // =========================================================================
    console.log('\n--- 3. Checking Razorpay Payment Gateway Credentials ---');
    const rzpKeyIdRes = resolveParam('RAZORPAY_KEY_ID', options);
    const rzpKeySecretRes = resolveParam('RAZORPAY_KEY_SECRET', options);
    const rzpWebhookSecretRes = resolveParam('RAZORPAY_WEBHOOK_SECRET', options);

    const rzpKeyId = rzpKeyIdRes.value;
    const rzpKeySecret = rzpKeySecretRes.value;
    const rzpWebhookSecret = rzpWebhookSecretRes.value;

    if (!rzpKeyId) {
      warnings.push('[RAZORPAY_KEY_ID] Not set in local env. Confirm it exists in Supabase secrets.');
    } else if (rzpKeyId.startsWith('rzp_test_')) {
      errors.push(`[RAZORPAY_KEY_ID] Test Key Detected: '${rzpKeyId}' (${rzpKeyIdRes.source}) is a TEST key. Production must use live key ('rzp_live_...').`);
    } else if (!rzpKeyId.startsWith('rzp_live_')) {
      errors.push(`[RAZORPAY_KEY_ID] Invalid format: Live Razorpay key should start with 'rzp_live_'. (Source: ${rzpKeyIdRes.source})`);
    } else {
      console.log(`  ✓ RAZORPAY_KEY_ID: ${rzpKeyId.slice(0, 12)}**** (Live key confirmed, Source: ${rzpKeyIdRes.source})`);
    }

    if (!rzpKeySecret) {
      warnings.push('[RAZORPAY_KEY_SECRET] Not set in local env. Confirm it exists in Supabase secrets.');
    } else if (rzpKeySecret.length < 15 || rzpKeySecret.includes('placeholder')) {
      errors.push(`[RAZORPAY_KEY_SECRET] Invalid or placeholder secret detected. (Source: ${rzpKeySecretRes.source})`);
    } else {
      console.log(`  ✓ RAZORPAY_KEY_SECRET: [Configured] (Source: ${rzpKeySecretRes.source})`);
    }

    if (!rzpWebhookSecret) {
      warnings.push('[RAZORPAY_WEBHOOK_SECRET] Not set in local env. Webhook validation requires this secret.');
    } else {
      console.log(`  ✓ RAZORPAY_WEBHOOK_SECRET: [Configured] (Source: ${rzpWebhookSecretRes.source})`);
    }

    // =========================================================================
    // 4. DATABASE & JWKS STAGING CHECKS
    // =========================================================================
    const backendUrlChecks = [
      { key: 'SUPABASE_JWKS_URL', res: resolveParam('SUPABASE_JWKS_URL', options) },
      { key: 'DATABASE_URL', res: resolveParam('DATABASE_URL', options) },
      { key: 'SUPABASE_DB_URL', res: resolveParam('SUPABASE_DB_URL', options) },
      { key: 'STAGING_SUPABASE_DB_URL', res: resolveParam('STAGING_SUPABASE_DB_URL', options) },
    ];

    for (const { key, res } of backendUrlChecks) {
      const val = res.value;
      if (!val) continue;
      if (!allowStaging && isSupabaseCloudUrl(val) && key !== 'STAGING_SUPABASE_DB_URL') {
        errors.push(`[${key}] Supabase Cloud Blocked: Production must not use hosted Supabase URLs in server config (${res.source}). Use RDS + Auth Gateway.`);
      } else if (!allowStaging && stagingProjectRef && urlContainsStagingProjectRef(val, stagingProjectRef)) {
        errors.push(`[${key}] Staging Leak: ${key} (${res.source}) matches staging project ref '${stagingProjectRef}'.`);
      } else if (allowStaging && stagingProjectRef && urlContainsStagingProjectRef(val, stagingProjectRef)) {
        warnings.push(`[${key}] Staging reference permitted via --allow-staging.`);
      }
    }

    // =========================================================================
    // 5. DEPLOYED CLOUD FUNCTIONS INVENTORY AUDIT (baseline_functions.json)
    // =========================================================================
    console.log('\n--- 4. Checking Deployed Cloud Functions Inventory ---');
    const skipBaseline = options.skipDeployedBaseline !== undefined
      ? options.skipDeployedBaseline
      : process.argv.includes('--skip-deployed-baseline');

    const candidatePaths = [
      path.resolve(process.cwd(), 'baseline_functions.json'),
      path.resolve(__dirname, '../../baseline_functions.json'),
      path.resolve(__dirname, '../baseline_functions.json'),
    ];

    const baselineFile = candidatePaths.find(p => fs.existsSync(p));
    if (!baselineFile) {
      console.log('  ℹ️  No baseline_functions.json found (Skipping deployed function inventory audit).');
    } else if (skipBaseline) {
      console.log('  ℹ️  --skip-deployed-baseline active: Skipping deployed functions inventory audit.');
    } else {
      try {
        const raw = fs.readFileSync(baselineFile, 'utf8');
        const parsed = JSON.parse(raw);
        const list = Array.isArray(parsed) ? parsed : (parsed.result || []);
        const staleFns = [];

        for (const fn of list) {
          const env = fn.environmentVariables || {};
          const sUrl = env.SUPABASE_URL || '';
          const jwks = env.SUPABASE_JWKS_URL || '';
          const hitsSupabaseCloud = isSupabaseCloudUrl(sUrl) || isSupabaseCloudUrl(jwks);
          const hitsStagingRef = stagingProjectRef && (
            urlContainsStagingProjectRef(sUrl, stagingProjectRef)
            || urlContainsStagingProjectRef(jwks, stagingProjectRef)
          );
          if (hitsSupabaseCloud || hitsStagingRef) {
            const idParts = (fn.id || fn.entryPoint || fn.name || '').split('/');
            staleFns.push(idParts[idParts.length - 1]);
          }
        }

        if (staleFns.length > 0) {
          if (allowStaging) {
            warnings.push(`[DEPLOYED_FUNCTIONS_BASELINE] Staging Permitted: ${staleFns.length} deployed Cloud Functions still reference *.supabase.co or staging project ref '${stagingProjectRef || '(unknown)'}'.`);
            console.log(`  ⚠️  DEPLOYED FUNCTIONS: ${staleFns.length} functions reference Supabase cloud/staging (STAGING PERMITTED via --allow-staging).`);
          } else {
            errors.push(`[DEPLOYED_FUNCTIONS_BASELINE] Staging/Supabase Cloud Leak: ${staleFns.length} deployed Cloud Functions still point at *.supabase.co or staging ref '${stagingProjectRef || '(set STAGING_SUPABASE_URL to detect ref)'}' (e.g. ${staleFns.slice(0, 5).join(', ')}...). Redeploy with PROD_GATEWAY_URL / RDS-backed config.`);
            console.error(`  ❌ DEPLOYED FUNCTIONS: ${staleFns.length} functions reference Supabase cloud or staging!`);
          }
        } else {
          console.log(`  ✓ DEPLOYED FUNCTIONS: ${list.length} functions checked in ${path.basename(baselineFile)} — 0 staging leaks.`);
        }
      } catch (err) {
        warnings.push(`[DEPLOYED_FUNCTIONS_BASELINE] Could not parse ${path.basename(baselineFile)}: ${err.message}`);
      }
    }
  }

  // ===========================================================================
  // EVALUATION & REPORTING
  // ===========================================================================
  console.log('\n================================================================');
  console.log('VALIDATION AUDIT SUMMARY');
  console.log('================================================================');

  if (warnings.length > 0) {
    console.log('\n⚠️  WARNINGS / ADVISORIES (Check Supabase Cloud Secrets):');
    for (const w of warnings) {
      console.log(`   - ${w}`);
    }
  }

  if (errors.length > 0) {
    console.error('\n❌ FATAL CONFIGURATION ERRORS:');
    for (const e of errors) {
      console.error(`   - ${e}`);
    }
    console.error('\nResult: FAILED. One or more fatal production readiness checks failed.');
    console.error('Aborting process. Fix the errors above before continuing.\n');

    if (require.main === module) {
      process.exit(1);
    }
    return { success: false, errors, warnings };
  }

  console.log('\n✅ All Critical Pre-Flight Checks PASSED!');
  if (allowStaging) {
    console.log('   Staging-permitted build (--allow-staging). Not for Play production track.');
  } else {
    console.log('   Client API base is not Supabase cloud (Auth Gateway / RDS cutover ready).');
  }
  console.log('   Safe to proceed.\n');

  if (require.main === module) {
    process.exit(0);
  }
  return { success: true, errors, warnings };
}

if (require.main === module) {
  verifyProductionConfig();
}

module.exports = {
  verifyProductionConfig,
  resolveParam,
  resolveStagingProjectRef,
  isSupabaseCloudUrl,
  urlContainsStagingProjectRef,
};
