# Deploy Firestore rules, Storage rules, and Cloud Functions.
# Run from the project root: .\tool\deploy-backend.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Push-Location $PSScriptRoot\..

Write-Host 'Deploying Firestore rules, Storage rules, and Cloud Functions...'
firebase deploy --only firestore:rules,storage,functions

Write-Host ''
Write-Host 'Post-deploy checklist:'
Write-Host '  1. Firebase Console -> Authentication -> Sign-in method -> enable Anonymous (ambulance drivers)'
Write-Host '  2. Firebase Console -> App Check -> register apps and enable enforcement when ready'
Write-Host '  3. Run care-team backfill once: backfillPatientCareTeams({ confirm: true })'
Write-Host '     (set BACKFILL_ADMIN_EMAILS on the function first)'
Write-Host '  4. Approve accounts after 24-48 hr review: approveUserAccount({ role, profileId })'
Write-Host '     Roles: patient | doctor | lab | medicalStore'
Write-Host '     (set ACCOUNT_APPROVAL_ADMIN_EMAILS on the function)'
Write-Host ''
Write-Host 'Manual approval (Firebase Console -> Firestore):'
Write-Host '  Pending users have: verified=false, status=pending_review'
Write-Host '  Collections: users, patients, doctors, labs, medical_stores'
Write-Host '  To approve: set verified=true, verifiedAt=now, status=active on role doc + users/{uid}'
Write-Host '  Or call Cloud Function: approveUserAccount({ role, profileId })'
Write-Host '  5. OTP: production uses functions/.env OTP_TEST_MODE=false (random OTPs).'
Write-Host '     Staging QA only: set OTP_TEST_MODE=true in functions/.env.<project_id> before deploy.'

Pop-Location
