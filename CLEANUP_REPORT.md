# Structure cleanup report (no secrets)

**Branch:** `cleanup/structure`  
**Date:** 2026-10-31  
**Scope:** File/folder audit, deletion, and doc reorganization only — no app logic, migration SQL, infra, CI workflow, or env **value** changes. Admin module untouched.

## Summary

| Metric | Before (start of real cleanup pass) | After (this commit) |
|--------|-------------------------------------|---------------------|
| Tracked files (`git ls-files \| wc -l`) | **1748** | **1653** (−95) |
| Git pack size (`git count-objects -vH`) | **~1.42 GiB** | **~1.42 GiB** (unchanged) |

**Why pack size did not shrink:** `git rm` stops tracking blobs in new commits but leaves historical objects in `.git/objects` until `git filter-repo` / BFG. Largest historical blobs (e.g. removed `backend/updated_indian_medicine_data.csv` ~43 MiB, `docs/ops/test_runs/*.txt` up to ~0.76 MiB each) still occupy pack space.

## 1 — Twenty-three zero-importer Dart files (`CLEANUP_MANIFEST.md`)

| Result | Detail |
|--------|--------|
| **Deleted from git** | **0 files this pass** — all 23 paths already absent from tree and index (prior cleanup). |
| **Re-verification** | No `import` / `part` in `frontend/lib` or `frontend/test`; not listed individually in `pubspec.yaml`; no dynamic path hits beyond obsolete `frontend/scripts/refactor/unused_dart_files.txt`. |
| **Kept** | **None** from the manifest list. |

Post-pass: `flutter pub get`, `flutter analyze`, full `flutter test` — see §9.

## 2 — `docs/ops/test_runs/*`

| Action | Detail |
|--------|--------|
| **Removed from git** | **59** stdout/log captures (`git rm`). |
| **`.gitignore`** | `docs/ops/test_runs/`, `.artifacts/` (local harness output). |
| **Links** | Scrubbed in `docs/ops/REMAINING_WORK.md`, `docs/ops/PROGRESS.md`, `docs/runbooks/RDS_MIGRATION_RUNBOOK.md`, `CLEANUP_REPORT.md`; `scripts/db/rds_scratch_replay.js` writes failures to `.artifacts/test_runs/`; `scripts/db/scan_passwords.js` scans `.artifacts/test_runs/` when present. |
| **Link checker** | `node scripts/ops/check_markdown_links.js` — see §9. |

Untracked copies may remain on disk locally; they are ignored.

## 3 — Duplicate audit reports (`docs/reports/`)

| Kept (canonical) | Removed |
|------------------|---------|
| `DOCTORNECT_FINAL_AUDIT.md` | `DOCTORNECT_AUDIT_REPORT.md` |
| `DOCTORNECT_VERIFICATION_REPORT.md` | 30 older `rls_harness_staging_*` / `rls_harness_replay_check_*` timestamped reports |
| `rls_harness_staging_2026-10-31T07-00-11-064Z.md` (latest harness snapshot) | |

## 4 — `.agent/` and `adapters/`

**Kept** — referenced by production-adjacent tooling/docs:

| Referencer |
|------------|
| `scripts/validate-workflows.ps1`, `scripts/validate-workflows.sh` |
| `.gemini/GEMINI.md` |
| `docs/archive/planning/PROJECT_RULES.md` |
| `.agent/workflows/*` |

## 5 — `scripts/codemods/`

**Kept** — Firestore fallback removal not complete; `docs/reports/DOCTORNECT_FINAL_AUDIT.md` still documents ~45 Flutter files with Firestore branches. Codemods remain one-shot strippers for that migration.

## 6 — Large tracked files and history bloat

### Top tracked files (by size on HEAD, sample)

| Path | ~Size | Used? |
|------|-------|-------|
| `frontend/assets/data/icd10_diagnoses.txt` | 14 MiB | **Yes** — `frontend/test/icd10_loader_comparison_test.dart` (runtime bundle uses `.gz` only). |
| `frontend/assets/data/icd10_diagnoses.txt.gz` | 1.3 MiB | **Yes** — `pubspec.yaml` asset. |
| `frontend/assets/data/indian_medicines.txt.gz` | 1.2 MiB | **Yes** — pubspec. |
| Doctor/common PNG/WebP icons | 0.6–1.4 MiB each | **Yes** — UI + asset tests. |
| `frontend/web/assets/js/pdf/.../pdf.worker.min.js` | 1.0 MiB | **Yes** — web PDF viewing. |
| Font files under `frontend/assets/fonts/` | 0.6–0.7 MiB | **Yes** — pubspec fonts. |

### Binaries / archives tracked on HEAD

| Pattern | On HEAD |
|---------|---------|
| `.apk` / `.aab` / `.zip` / `.dump` / `.sqlite` | **None** tracked (`.gitignore` covers `*.zip`, build outputs). |
| `.pdf` | **Removed** `docs/Medibond_Legal_Review.pdf` (regenerable via `frontend/tool/generate_legal_pdf.dart`; gitignored). |

### Removed as unused duplicates (this pass)

| Path | Reason |
|------|--------|
| `frontend/assets/icons/doctor/digital_pass.png` / `.webp` | Byte-identical to `assets/icons/common/digital_pass.*`; app resolves common path. |
| `frontend/assets/images/neurologist_icon.png` | Byte-identical to `neurologist.png`; runtime uses `.webp` variants. |

### Largest blobs still in **git history** (no rewrite performed)

| ~Size | Path (historical) | Notes |
|-------|-------------------|-------|
| 42.9 MiB | `backend/updated_indian_medicine_data.csv` | No longer tracked; bloats pack until filter-repo. |
| 13.3 MiB | `frontend/assets/data/icd10_diagnoses.txt` | Still tracked (test fixture). |
| 4.3 MiB | `structure.txt` | Historical root artifact. |
| 1.7 MiB | `email_audit.txt` | Historical root artifact. |
| 0.76 MiB | `docs/ops/test_runs/rds_scratch_replay.txt` | Untracked now; remains in history. |

Helper: `node scripts/ops/top_git_blobs.js` (read-only inventory).

## 7 — Content-hash duplicates

`node scripts/ops/find_content_duplicates.js` found **50** groups (≥1 KiB). Action this pass: removed only **proven redundant** doctor `digital_pass` and `neurologist_icon` PNG duplicates. **Not deduplicated** (intentional platform copies): splash/icon PNG sets under `android/`, `ios/`, `web/`, `macos/`; logo variants; `.agent/` vs `.cursor/` skill mirrors (both referenced by IDE tooling).

## 8 — Out of scope (unchanged)

Application logic (except asset-path test/manifest alignment for deleted duplicates), dependency versions, Terraform, CI workflows, migration SQL, Admin module, Firestore fallback code paths.

## 9 — Verification (after cleanup commit)

| Check | Command | Result |
|-------|---------|--------|
| Flutter deps | `cd frontend && flutter pub get` | *(filled post-commit)* |
| Flutter analyze | `flutter analyze` | *(filled post-commit)* |
| Flutter tests | `flutter test` | *(filled post-commit)* |
| Backend tests | `cd backend/functions && CI=true npm test` | *(filled post-commit)* |
| Gateway tests | `cd services/api-gateway && npm test` | *(filled post-commit)* |
| Env parity | `node scripts/check_env_parity.js` | *(filled post-commit)* |
| Anon / guard unit tests | `node --test scripts/db/anon_surface_audit.test.js scripts/lib/db_connection_guard.test.js` | *(filled post-commit)* |
| Migrate dry-run | `node scripts/db/migrate.js --target=staging --dry-run-all` | *(filled post-commit)* |
| Markdown links | `node scripts/ops/check_markdown_links.js` | *(filled post-commit)* |
| `firebase.json` functions path | manual | `backend/functions` |
| Terraform validate | `terraform -chdir=infra/aws validate` (if init cached) | *(filled post-commit)* |

See **PROJECT_STRUCTURE.md** for layout.
