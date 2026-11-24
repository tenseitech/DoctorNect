'use strict';

const { defineSecret } = require('firebase-functions/params');

/** Staging Supabase service role — demo data plane (login lookup + keepalive). */
const demoSupabaseServiceRoleKey = defineSecret('DEMO_SUPABASE_SERVICE_ROLE_KEY');

/** Production auth-gateway PostgREST service key (RDS plane). */
const prodGatewayServiceKey = defineSecret('PROD_GATEWAY_SERVICE_KEY');

module.exports = {
  demoSupabaseServiceRoleKey,
  prodGatewayServiceKey,
};