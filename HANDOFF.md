# HANDOFF (2026-11-26, usage limit reached)

Branch `security/full-audit-fix`, nothing pushed.

## Done this round
- D2/M3: cold-start completeness check wired in, OFF by code constant (c5938e4).
- L5: analyzer triage, all 338 infos are the material/cupertino split (6c524f7).
- L6: Kotlin shim re-check, blocked upstream (c954d55).
- H3(b): docs/AMBULANCE_REAL_ACCOUNT_SIGNIN.md + OFF groundwork (c46a435).
- Tests: provider deletion (e41faa8), RLS role-pair matrix (83abb07).
- N1: release build reads FIREBASE_PROJECT_ID; release AAB now builds, release-key signed (b416d65).
- D3 stage 1 backend/web (b99e6bd), stage 2 client shims (ba9e94e), stage 3 docs banners (last commit).

## Left (D3 later stages)
- Client renames: FirestoreScreenSync, FirestoreQueryLimits, PharmacyFirestoreRepository,
  mergeFromFirestore/refreshFromFirestore/attachFirestoreSync, files firestore_*.dart.
- FirestoreUi (only used by a test) and the FIRESTORE_FORBIDDEN client guard review.
- Final full gate after those stages (backend, gateway, test:db with audits, flutter, APKs).
