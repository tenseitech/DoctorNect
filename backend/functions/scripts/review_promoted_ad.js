#!/usr/bin/env node
'use strict';

/**
 * Approve or reject a paid promoted ad until an admin UI exists.
 *
 * Usage:
 *   node scripts/review_promoted_ad.js <adId> approve
 *   node scripts/review_promoted_ad.js <adId> reject [reason]
 *
 * Uses Application Default Credentials / GOOGLE_APPLICATION_CREDENTIALS.
 */

const admin = require('firebase-admin');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');

const AD_PRICING_TABLE = {
  6: 100,
  12: 180,
  24: 300,
  72: 750,
  168: 1500,
};

function usage() {
  console.error('Usage: node scripts/review_promoted_ad.js <adId> approve|reject [reason]');
  process.exit(1);
}

async function main() {
  const adId = String(process.argv[2] || '').trim();
  const decision = String(process.argv[3] || '').trim().toLowerCase();
  const reason = process.argv.slice(4).join(' ').trim();

  if (!adId || (decision !== 'approve' && decision !== 'reject')) {
    usage();
  }

  if (!admin.apps.length) {
    admin.initializeApp();
  }

  const db = getFirestore();
  const adRef = db.collection('promotedAds').doc(adId);
  const snap = await adRef.get();
  if (!snap.exists) {
    console.error(`Ad not found: ${adId}`);
    process.exit(1);
  }

  const ad = snap.data() || {};
  if (ad.status !== 'pending_approval') {
    console.error(`Ad ${adId} is not pending approval (status: ${ad.status}).`);
    process.exit(1);
  }

  if (decision === 'approve') {
    const hours = parseInt(ad.durationHours, 10);
    if (!AD_PRICING_TABLE[hours]) {
      console.error(`Ad ${adId} has invalid durationHours: ${ad.durationHours}`);
      process.exit(1);
    }
    const now = Timestamp.now();
    const endTime = Timestamp.fromMillis(now.toMillis() + hours * 3600 * 1000);
    await adRef.update({
      status: 'active',
      startTime: now,
      endTime,
      reviewedBy: 'script',
      reviewedAt: FieldValue.serverTimestamp(),
      reviewDecision: 'approve',
      ...(reason ? { reviewReason: reason } : {}),
      updatedAt: FieldValue.serverTimestamp(),
    });
    console.log(`Approved ${adId}; status=active`);
    return;
  }

  await adRef.update({
    status: 'rejected',
    reviewReason: reason || 'Rejected by admin',
    reviewedBy: 'script',
    reviewedAt: FieldValue.serverTimestamp(),
    reviewDecision: 'reject',
    updatedAt: FieldValue.serverTimestamp(),
  });
  console.log(`Rejected ${adId}; status=rejected`);
}

main().catch((err) => {
  console.error(err?.message || 'review_promoted_ad failed');
  process.exit(1);
});
