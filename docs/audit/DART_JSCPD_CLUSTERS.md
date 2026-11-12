# Dart jscpd clusters (document only — no refactors)

Extended scan paths: `frontend/lib/features`, `frontend/lib/core`, `frontend/lib/widgets`, `frontend/lib/core/supabase/repositories`.

| Metric | Value |
|--------|--------|
| Files | 504 |
| Clones | 397 (~5.67% duplicated lines) |
| Cross-role basename dupes | 0 |

## Within-patient (records / search)

- `patient_blood_test_sheet.dart` ↔ `patient_lab_order_sheet.dart` — shared form layout and submit blocks.
- `health_record_file_store.dart` — repeated store method blocks.
- `health_record_row.dart` ↔ `lab_search_result_tile.dart` — list tile chrome.

## Within-pharmacy

- `connect_doctors_screen.dart` — duplicated section blocks in one screen.
- `pharmacy_connection_store.dart` — parallel connection-store methods.

## Features-only pass (narrower scope)

~63 clones / ~1.7% under `features/` alone; notable pairs: patient `edit_profile` ↔ `patient_profile`, pharmacy dashboard ↔ notifications.

SQL duplicate policy names: flag-only; `pg_policies` diff when Docker Postgres is up.
