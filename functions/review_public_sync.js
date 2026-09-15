const { FieldValue } = require('firebase-admin/firestore');

function maskReviewPatientName(patientName) {
  const parts = String(patientName || 'Patient').trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return 'Patient';
  if (parts.length === 1) return `${parts[0][0]}.`;
  return `${parts[0][0]}. ${parts[parts.length - 1][0]}.`;
}

function buildPublicReviewData(data) {
  const patientName = String(data?.patientName || 'Patient').trim();
  return {
    doctorId: String(data?.doctorId || '').trim(),
    rating: Number(data?.rating) || 0,
    comment: String(data?.comment || 'No written comment.'),
    maskedName: maskReviewPatientName(patientName),
    helpfulCount: Number(data?.helpfulCount) || 0,
    doctorReply: data?.doctorReply || null,
    createdAt: data?.createdAt || FieldValue.serverTimestamp(),
    updatedAt: data?.updatedAt || FieldValue.serverTimestamp(),
  };
}

async function syncReviewPublicDoc(db, reviewId, data) {
  const doctorId = String(data?.doctorId || '').trim();
  if (!reviewId || !doctorId) return;

  await db.collection('review_public').doc(reviewId).set(
    buildPublicReviewData(data),
    { merge: true },
  );
}

async function deleteReviewPublicDoc(db, reviewId) {
  if (!reviewId) return;
  await db.collection('review_public').doc(reviewId).delete().catch(() => {});
}

module.exports = {
  buildPublicReviewData,
  syncReviewPublicDoc,
  deleteReviewPublicDoc,
  maskReviewPatientName,
};
