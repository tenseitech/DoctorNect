# Pre-publish status — DoctorNect

**Date:** 2026-11-07  
**Branch:** `fix/pre-accept-gate-lab-auth`  
**Rating:** **6.9 / 10** (smoke covers all MIGRATED entry screens; booking/clinical/prefetch POST_LAUNCH paths remain)

---

## Verification

| Suite | Result |
|-------|--------|
| Flutter full suite (`flutter test`) | **670 passed, 0 failed** (guard ON globally; re-run after smoke add) |
| `release_firestore_forbidden_smoke_test.dart` | **16 passed** (13 MIGRATED entry screens pumped + 3 guard/ambulance unit tests) |
| `backend/functions` `npm test` | **496 pass, 22 skip** |
| Docker integration (4 files per `DOCKER_RUN.md`) | **24 pass, 5 skip** — Docker daemon down; Postgres **:54322 unreachable** |
| `npx supabase start` | **FAILED** — `DockerLifecycleInspectError` (Docker Desktop Linux engine pipe missing) |
| `npm run audit:firestore-reachability` | **136 LIVE_AND_THROWS**, 54 DEAD, 5 TEST_ONLY (last run at `3f8df1a`; re-run after this commit recommended) |

---

## Highlights this pass

- **000016** trigger: `service_role` exempt alongside `postgres` / `supabase_admin` (server + SECURITY DEFINER).
- Staging probes **(a)–(d)** for in-app notification title/read rules.
- Lab shell/worklist: `LabRepository`, `LabOrderRepository`, `LabBookingRepository`, `LabConnectionRepository` (no gateway on shell pump).
- Smoke pumps: Welcome, PatientHome, DoctorSearch, MyLabs, LabHome, LabBookingFlow, EditProfile, DoctorVerificationGate/Pending, **DoctorAppointmentsScreen**, DoctorConnectedStores, MedicalStoreShell, **LabShell**.

---

## Remaining

1. **POST_LAUNCH** flows: patient appointment booking, prescription opener, doctor home prefetch, connected labs orders sub, unified auth deep steps — see `FIRESTORE_LAUNCH_FLOWS.md`.
2. Apply **000014–000018** on staging/RDS per `DEPLOY_ORDER.md`.
3. Start **Docker Desktop** + `cd backend && npx -y supabase start` before Docker integration tests.
