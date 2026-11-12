const { execSync } = require('child_process');

const tables = [
  'admin_users',
  'provisioning_errors',
  'ambulance_trip_contacts',
  'doctor_invites',
  'facilities',
  'otp_verification_sessions',
  'patient_care_team',
  'pharmacy_doctor_invites'
];

for (const t of tables) {
  console.log(`\n================================================================================`);
  console.log(`TABLE: ${t}`);
  console.log(`================================================================================`);
  try {
    const out = execSync(`git grep -n -w "${t}" frontend/ backend/functions/`, { encoding: 'utf8' });
    console.log(out.trim());
  } catch (err) {
    console.log(`ZERO MATCHES in frontend/ and backend/functions/ (Table is completely unreferenced by client and backend runtime)`);
  }
}
