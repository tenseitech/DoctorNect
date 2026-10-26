# DoctorNect Repository Restructure & Architecture Plan

**Document:** `STRUCTURE_PLAN.md`  
**Branch:** `chore/restructure-cleanup`  
**Safety Baseline Tag:** `pre-restructure-2026-10-26T07-44-20Z` (Commit `73860fc`)  
**Scope:** Doctor, Patient, Pharmacy, Lab, Ambulance (Admin console strictly out of scope)

---

## 1. Current Tree Analysis & Architectural Debt

An analysis of the existing repository structure identified five key operational problems:
1. **Redundant & Overlapping Folders:**
   - Database migrations exist in both `supabase/` and `backend/supabase/migrations/`.
   - Frontend widgets are split across `lib/widgets/` and `lib/shared/widgets/`.
2. **Naming Divergence in Storage Adapters:**
   - Several repositories retain names like `*_firestore_repository.dart` even though they have migrated internally to Supabase PostgREST.
3. **Flat Module Organization in Backend Functions:**
   - `backend/functions/` houses 36+ files directly in its root alongside tests, rather than domain-scoped namespaces.
4. **Root Pollution from Audit Iterations:**
   - 14 historical audit and verification reports, 8 `.log` files, and generated JSON ledgers reside at the root of the repo.
5. **Lack of Isolated Service & Infrastructure Boundaries:**
   - Docker and cloud configuration were previously absent; Phase 6 now introduces `services/api-gateway/` and `infra/aws/`.

---

## 2. Target Architecture Layout

```text
/                   README.md, .gitignore, .env.example, firebase.json, .firebaserc
frontend/           Flutter mobile application
  lib/core/         Shared core utilities (auth, supabase, streamTable, theme)
  lib/shared/       Shared reusable design system components
  lib/features/     Domain feature modules:
    doctor/         clinical, profile, appointments
    patient/        booking, appointments, records, home
    pharmacy/       deliveries, catalog, orders
    lab/            tests, orders, reports
    ambulance/      emergency broadcasts, driver tracking
backend/functions/  Firebase Cloud Functions (Node 22)
  src/domain/       Domain handlers: auth, notification, storage, billing
  src/db/           Unified DatabaseClient abstraction (Staging Supabase vs Production Gateway)
  index.js          Stable export boundary (86 exported functions preserved exactly)
  test/             Node:test suites mirroring src/
backend/firestore/  Legacy Firestore security rules & indexes
db/                 PostgreSQL Database Management
  migrations/       Numbered schema migrations (1-to-1 parity with Supabase)
  rds_bootstrap/    Plain PostgreSQL bootstrap (roles, extensions, auth shim)
  rds_overrides/    RDS-specific override DDL (if required)
  seeds/            Reference & config tables only (system_config, specializations)
services/
  api-gateway/      Node.js Auth Gateway (Firebase RS256 JWKS verification + PostgREST proxy)
infra/aws/          Terraform Infrastructure as Code (ECS Fargate, ALB, Secrets Manager)
scripts/
  db/               migrate.js, rds_preflight.js, schema_diff.js, rls_sql_harness.js
  verify/           api_e2e.js, prod_smoke.js
  release/          release_build.ps1, release_build.sh
  ops/              Environment guards, log inspectors, cleanup tools
  lib/              env_loader.js, env_guard.js
docs/               Living Documentation
  architecture/     Option A Access Layer, DB architecture, Realtime polling design
  runbooks/         PRODUCTION_CUTOVER_RDS.md, LAUNCH_RUNBOOK.md
  checklists/       RDS_PRODUCTION_CHECKLIST.md, PRE_LAUNCH_CHECKLIST.md
  ops/              PROGRESS.md, MANUAL_ACTIONS.md, baselines.json
backups/            Physical and logical dumps (strictly gitignored)
```

---

## 3. Preserved Symbols & Safety Guardrails
Per Gravitas invariant and project contract, the following must NEVER be renamed, moved, or deleted:
- **Cloud Functions:** All 86 exported names in `backend/functions/index.js` remain byte-identical.
- **Database Schema:** Table names, column names, constraint names, and view names.
- **Flutter Persisted Classes:** Model classes serialized to/from JSON or local storage.
- **Root Tool Entry Points:** `firebase.json`, `.firebaserc`, `frontend/pubspec.yaml`, `android/`, `ios/`.
- **Secrets & Credentials:** Any `.env*`, keystores, or service accounts.

---

## 4. Decommissioning Plan for Legacy Firestore (`legacy_firestore/`)
Legacy Firestore repositories and rules are isolated. They may only be completely deleted when:
1. `isDoctorPatientSupabasePrimary` flag is locked to 100% in production for 30 consecutive days.
2. Firestore read/write metrics in Google Cloud Console drop to 0 across all collections.
3. The offline queue sync confirms zero dead-letters.
