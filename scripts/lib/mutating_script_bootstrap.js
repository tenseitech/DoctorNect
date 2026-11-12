'use strict';

const { assertConfirmLiveData } = require('./live_data_guard');

/**
 * Call at the top of mutating ops scripts (before live connections).
 * Requires --confirm-live-data when STAGING_SUPABASE_* / SUPABASE_URL / DB URL or ADC is set.
 * Mutations run only with --confirm-live-data --execute (otherwise treat as dry-run intent).
 */
function bootstrapMutatingScript(scriptName) {
  return assertConfirmLiveData(scriptName);
}

function effectiveDryRun(existingDryRunFlag) {
  const args = process.argv.slice(2);
  if (args.includes('--execute')) return false;
  return existingDryRunFlag !== false;
}

module.exports = {
  bootstrapMutatingScript,
  effectiveDryRun,
};
