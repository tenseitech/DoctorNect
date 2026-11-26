# Audit 5 follow-up — Remaining performance optimizations

**Date:** 2026-11-26  
**Branch:** `audit5/performance-followup`  
**Parent:** `3604f92` (`audit5/performance-scalability`) — **unchanged**

**Status:** **AUDIT 5 FOLLOW-UP COMPLETE** (code + tests). Flutter DevTools profiling **not performed**.

---

## 1. Executive summary

Implemented keyset cursor pagination across high-traffic Supabase repositories, wired medical-directory `startAfterCursor`, extended column projections, relocated non-shipping ICD-10 raw asset to test fixtures, and documented dependency footprint. **Audit 4 remains ON HOLD.**

---

## 2. Follow-up tracking

| Finding | Evidence | Remediation | Tests | Status |
|---------|----------|-------------|-------|--------|
| PERF-02 | Fixed `.limit()` without cursors | `supabase_keyset_pagination.dart` + page APIs | `supabase_keyset_pagination_test.dart` | **Mostly fixed** |
| PERF-04 | Broad `.select()` | Appointment, doctor directory, medical directory columns | Mapper/phase E tests | **Partial** |
| PERF-01 | 13.7 MB raw ICD-10 in `assets/` | Moved to `test/fixtures/data/` | `icd10_loader_comparison_test.dart` path | **Fixed** |
| PERF-03 | Heavy pubspec | Inventory only | `flutter analyze` | **Documented** |
| Runtime profiling | Pending | Local micro-benches only | Gateway from Audit 5 | **Limited** |

---

## 3. PERF-02 — Pagination

### New infrastructure

- `frontend/lib/core/supabase/supabase_keyset_pagination.dart` — `KeysetCursor`, descending/ascending filters, `collectPages`.

### Repositories updated

| Repository | Methods | Ordering | Notes |
|------------|---------|----------|-------|
| `supabase_appointment_repository` | `fetchPageForDoctor/Patient`, list APIs use `collectPages` | `date_time`, `appointment_id` | Max 200 doctor / 200 patient |
| `supabase_health_records_repository` | `fetchPageForPatient` | `date`, `record_id` | Max 500 via pages |
| `supabase_prescription_repository` | `startAfter` cursor honored | `prescription_date`, `prescription_id` | Fixes ignored cursor |
| `supabase_medical_directory_repository` | Keyset replaces offset `range` | `name`, `entry_id` | Fixes ignored `startAfterCursor` |
| `in_app_notification_supabase_repository` | `fetchPageForRecipient` | `created_at`, `notification_id` | List API up to 200 |

### Remaining

Lab, pharmacy, ambulance repos still use fixed limits — document in `PERF_FOLLOWUP_RECOMMENDATIONS.md`.

---

## 4. PERF-04 — Column projections

| Repository | Change |
|------------|--------|
| `AppointmentSupabaseMapper.listSelectColumns` | Appointments list + `streamTable` |
| `SupabaseDoctorRepository` | `doctor_directory` narrow select |
| `supabase_medical_directory_repository` | `_medicalDirectoryListColumns` |
| Prior Audit 5 | notifications, health records, `streamTable` |

Prescriptions retain embedded `prescription_*(*)` select (required for mapper).

---

## 5. PERF-01 — Assets (measured)

| Metric | Before | After |
|--------|--------|-------|
| `frontend/assets/` total bytes | **30,342,401** | **16,265,937** |
| Reduction | — | **~46.4%** (~13.4 MB) |
| Action | `icd10_diagnoses.txt` in assets (not in pubspec bundle list) | Moved to `frontend/test/fixtures/data/icd10_diagnoses.txt` |

Runtime app bundle unchanged (only `.gz` was already declared in `pubspec.yaml`). Workspace and clone size improved.

---

## 6. PERF-03 — Dependencies

See `docs/audit/DEPENDENCY_FOOTPRINT_AUDIT5.md`. **No removals.**

---

## 7. Profiling & benchmarks

| Type | Result |
|------|--------|
| Flutter DevTools | **Not run** (environment) |
| Gateway rate limiter 10k keys | ~259 ms (Audit 5 test, unchanged) |
| Asset filesystem | Measured above |

---

## 8. Tests

| Suite | Command | Pass | Fail |
|-------|---------|-----:|-----:|
| Keyset + watcher | `flutter test test/core/supabase/*.dart` | 5 | 0 |
| Phase E notifications | `flutter test test/phase_e_supabase_support_and_notifications_test.dart` | 6 | 0 |
| Analyzer | `flutter analyze lib/core/supabase` | — | 0 issues |

---

## 9. Files changed (follow-up)

- `frontend/lib/core/supabase/supabase_keyset_pagination.dart` (new)
- Repositories: appointment, health records, prescription, medical directory, doctor, in-app notifications
- `frontend/lib/core/supabase/mappers/appointment_supabase_mapper.dart`
- `frontend/lib/core/firebase/repositories/medical_directory_repository.dart`
- `frontend/test/core/supabase/supabase_keyset_pagination_test.dart` (new)
- `frontend/test/icd10_loader_comparison_test.dart`
- `frontend/test/fixtures/data/icd10_diagnoses.txt` (moved)
- Docs: this report, checklist, dependency doc, updated `PERF_FOLLOWUP_RECOMMENDATIONS.md`

---

## 10. Audit preservation

| Audit | Status |
|-------|--------|
| Audit 1–3 | Not in commit scope |
| Audit 4 | **ON HOLD — untouched** |
| Audit 5 commit `3604f92` | **Not amended** |

---

## 11. Final status

**AUDIT 5 FOLLOW-UP COMPLETE** — Lab/pharmacy/ambulance pagination and Flutter runtime profiling remain future work.