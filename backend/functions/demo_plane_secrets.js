'use strict';

const { defineSecret } = require('firebase-functions/params');

/** Staging Supabase service role — demo data plane (login lookup + keepalive). */
const demoSupabaseServiceRoleKey = defineSecret('DEMO_SUPABASE_SERVICE_ROLE_KEY');

/** Production auth-gateway PostgREST service key (RDS plane). */
const prodGatewayServiceKey = defineSecret('PROD_GATEWAY_SERVICE_KEY');

/**
 * Data-plane secrets every deployed function needs: the cold-start assert
 * (assertAppEnvDatabaseRouting) requires PROD_GATEWAY_SERVICE_KEY in production, and
 * src/db/client.js uses it for real users and DEMO_SUPABASE_SERVICE_ROLE_KEY for the five demo
 * accounts. Per-function `secrets` replace the global list in firebase-functions v2, so every
 * explicit list goes through withDataPlaneSecrets(); functions without a list get them from
 * setGlobalOptions in index.js.
 */
const DATA_PLANE_SECRETS = [prodGatewayServiceKey, demoSupabaseServiceRoleKey];

function withDataPlaneSecrets(...lists) {
  const out = [];
  const seen = new Set();
  for (const s of [...DATA_PLANE_SECRETS, ...lists.flat()]) {
    const name = typeof s === 'string' ? s : s.name;
    if (seen.has(name)) continue;
    seen.add(name);
    out.push(s);
  }
  return out;
}

module.exports = {
  demoSupabaseServiceRoleKey,
  prodGatewayServiceKey,
  DATA_PLANE_SECRETS,
  withDataPlaneSecrets,
};
