# DoctorNect Production Cutover: Progress Ledger

**Tracking File:** `docs/ops/PROGRESS.md`  
**Current Phase:** Phase 1: Preflight (Read-Only)  
**Execution Engine:** Gravitas  
**Scope:** Doctor, Patient, Pharmacy, Lab, Ambulance (Admin console out of scope)  

---

## Architecture Decisions (Locked)
1. **Current Supabase (`rnltknemwnjrjxthtull`) -> STAGING:** Holds test data only.
2. **New Amazon RDS PostgreSQL -> PRODUCTION:** Plain PostgreSQL. Tables, roles, `auth` shim, RLS must be provisioned via code.
3. **Production Access Layer = Option A:** PostgREST on AWS in front of RDS + Node auth gateway (Firebase token verification) + adaptive polling replacement for Realtime.
4. **Unchanged:** Firebase Auth, Redis for ephemeral rate limits/locations, AWS S3 for documents.
5. **Write Gate:** Zero writes to staging or production databases until Phase 2 backup is verified.

---

## Phase Status Summary

| Phase | Description | Status | Blocked Reason / Action Needed |
|---|---|---|---|
| **Phase 1** | Preflight (Source facts, tooling, RDS preflight, migration compatibility) | **IN PROGRESS** | Checking native client tools & RDS connectivity |
| **Phase 2** | Full Backup of Current Supabase (`schema_public`, `full.dump`, catalog, manifest, restore verification) | **PENDING** | Gated on native pg_dump / tools |
| **Phase 3** | Configuration Cutover: Current Supabase becomes STAGING | **PENDING** | Gated on Phase 2 backup verification |
| **Phase 4** | Repository Cleanup and Restructure (zero behavior change) | **PENDING** | Baseline tests to be locked before restructure |
| **Phase 5** | RDS becomes PRODUCTION Database (Bootstrap, migrations, SQL harness, parity) | **PENDING** | Awaiting RDS configuration & rehearsal database |
| **Phase 6** | Production Access Layer (Option A: Gateway, PostgREST, Realtime polling, local E2E) | **PENDING** | Follows Phase 5 |
| **Phase 7** | Cutover Readiness, Runbooks, and Final Verification Report | **PENDING** | Follows Phase 6 |

---

## Log of Executed Phases & Evidence
*(Updated continuously after each phase)*
