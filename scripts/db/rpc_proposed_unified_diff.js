const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ROOT = path.resolve(__dirname, '../..');
const fn = process.argv[2];
if (!fn) {
  console.error('Usage: node rpc_proposed_unified_diff.js <function_name>');
  process.exit(1);
}

const latest = {
  reschedule_appointment_atomic: 'db/migrations/20261026000001_rpc_null_safe_authz.sql',
  update_pharmacy_delivery_status: 'db/migrations/20261026000001_rpc_null_safe_authz.sql',
  create_prescription_atomic: 'db/migrations/20261029000001_guard_and_drift_fixes.sql',
  update_lab_booking_status: 'db/proposed/20261103000015_proposed_lab_report_storage_key.sql',
  update_lab_order_status: 'db/proposed/20261103000015_proposed_lab_report_storage_key.sql',
};

const proposed = 'db/proposed/20261103000017_proposed_rpc_verified_checks.sql';

function extract(sql, name) {
  const text = fs.readFileSync(path.join(ROOT, sql), 'utf8');
  const start = text.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  if (start < 0) throw new Error(`missing ${name} in ${sql}`);
  const end = text.indexOf('$$;', start);
  return text.slice(start, end + 3);
}

const a = path.join(ROOT, '_rpc_diff_a.sql');
const b = path.join(ROOT, '_rpc_diff_b.sql');
fs.writeFileSync(a, extract(latest[fn], fn));
fs.writeFileSync(b, extract(proposed, fn));
try {
  execSync(`git diff --no-index -- "${a}" "${b}"`, {
    cwd: ROOT,
    stdio: 'inherit',
  });
} catch (e) {
  process.exit(typeof e.status === 'number' ? e.status : 1);
} finally {
  fs.unlinkSync(a);
  fs.unlinkSync(b);
}
