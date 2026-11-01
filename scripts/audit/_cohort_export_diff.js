'use strict';

const { execSync } = require('child_process');

const COHORT = `
notifyDoctorOnAppointmentCreated notifyDoctorOnReferralCreated notifyPatientOnAppointmentStatusChanged
notifyPatientOnLabBookingUpdate notifyPatientOnLabReportReady notifyPatientOnLabOrderCreated
notifyDoctorOnLabConnectionChanged notifyDoctorOnPharmacyConnectionChanged notifyPatientOnPharmacyDeliveryCreated
notifyDoctorOnPharmacyDeliveryUpdated notifyPatientOnPharmacyDeliveryUpdated notifyAmbulanceDriverOnNewRequest
markAmbulanceSiblingRequestsTakenOnAccept markAmbulanceSiblingRequestsOnBroadcastCancelled
aggregateDoctorRatingOnReviewCreate aggregateDoctorRatingOnReviewWrite syncReviewHelpfulCount processMailQueueMsg91
getValidationRules getValidationRulesHttp validateField validateFormFields validateVitalAdvisory consumeAiGenerationQuota
getS3UploadUrl getS3DownloadUrl getS3DownloadUrls deleteS3Object deleteMyAccount
createRazorpayOrder verifyRazorpayPayment lookupMobileRegistration completeMobileOtpLogin finalizePatientOtpVerification
resetUserPasswordWithOtp resetAmbulanceDriverPin completeAmbulanceMobileOtpLogin verifyAmbulanceDriverLogin
verifyAmbulanceDriverLoginHttp assertLoginAllowed recordFailedLogin clearFailedLogins
approveUserAccount approvePatientAccount assertAccountCreationAllowed backfillPatientCareTeams
getAmbulanceInvite resyncAmbulanceAuthUid sendMsg91EmailCallable submitAmbulanceRating
`.trim().split(/\s+/);

function exportNames(ref) {
  const idx = execSync(`git show ${ref}:backend/functions/index.js`, {
    encoding: 'utf8',
    maxBuffer: 15e6,
  });
  return new Set([...idx.matchAll(/exports\.(\w+)\s*=/g)].map((m) => m[1]));
}

function moduleFilesForExports(ref, exportSet) {
  const idx = execSync(`git show ${ref}:backend/functions/index.js`, {
    encoding: 'utf8',
    maxBuffer: 15e6,
  });
  const lines = idx.split('\n');
  const modules = new Set();
  for (const name of exportSet) {
    const re = new RegExp(`exports\\.${name}\\s*=`);
    const lineIdx = lines.findIndex((l) => re.test(l));
    if (lineIdx < 0) continue;
    let ctx = lines.slice(Math.max(0, lineIdx - 80), lineIdx).join('\n');
    const req = [...ctx.matchAll(/require\(['"]\.\/([^'"]+)['"]\)/g)].map((m) => m[1]);
    req.forEach((r) => modules.add(r.endsWith('.js') ? r : `${r}.js`));
  }
  return [...modules];
}

const fromRef = process.argv[2] || '4fc3a6b';
const toRef = process.argv[3] || '4dfae67';

const expFrom = exportNames(fromRef);
const expTo = exportNames(toRef);
const cohortInFrom = COHORT.filter((n) => expFrom.has(n));
const cohortInTo = COHORT.filter((n) => expTo.has(n));
const missingInTo = cohortInFrom.filter((n) => !expTo.has(n));
const addedInTo = cohortInTo.filter((n) => !expFrom.has(n));

const mods = moduleFilesForExports(fromRef, new Set(cohortInFrom));
const changedMods = execSync(`git diff --name-only ${fromRef}..${toRef} -- backend/functions`, {
  encoding: 'utf8',
})
  .trim()
  .split('\n')
  .filter(Boolean);

const changedSet = new Set(changedMods.map((f) => f.replace(/^backend\/functions\//, '')));
const modulesChanged = mods.filter((m) => changedSet.has(m));

console.log(
  JSON.stringify(
    {
      fromRef,
      toRef,
      cohortInFrom: cohortInFrom.length,
      cohortInTo: cohortInTo.length,
      exportsRemovedFromIndex: missingInTo.sort(),
      exportsAddedToIndex: addedInTo.sort(),
      cohortModuleFiles: mods.sort(),
      cohortModuleFilesChanged: modulesChanged.sort(),
    },
    null,
    2,
  ),
);
