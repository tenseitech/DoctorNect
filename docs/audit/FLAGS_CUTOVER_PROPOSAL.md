# USE_SUPABASE_DB_DOCTOR_PATIENT / FIRESTORE_FORBIDDEN — defaults (pending human decision)

No values changed in code on the dedupe branch; templates aligned to **postgres-only current release** where noted.

## Current effective defaults

| Name | Flutter client | Backend Functions |
|------|----------------|-------------------|
| `FIRESTORE_FORBIDDEN` | `bool.fromEnvironment('FIRESTORE_FORBIDDEN', defaultValue: **true**)` in `firestore_forbidden_guard.dart`; native also checks `Platform.environment['FIRESTORE_FORBIDDEN'] == '1'` | `process.env.FIRESTORE_FORBIDDEN === '1'` in guards; **template now `1`** |
| `USE_SUPABASE_DB_DOCTOR_PATIENT` | Not read via `fromEnvironment` in `frontend/lib` today; **template `true`** for `--dart-define` parity | `isDoctorPatientSupabasePrimary()` returns **true** regardless; env fallback via `_getEnvCutoverFallback()` if that ever reverts |

## Documented template defaults after consolidation (placeholders)

| File | `FIRESTORE_FORBIDDEN` | `USE_SUPABASE_DB_DOCTOR_PATIENT` |
|------|----------------------|----------------------------------|
| `frontend/.env.example` | `true` (dart-define) | `true` |
| `backend/functions/.env.example` | `1` | `1` |

## Prior split (why hashes differed)

| Location | Old placeholder |
|----------|-----------------|
| Root `.env.example` (removed) | `FIRESTORE_FORBIDDEN=1`, `USE_SUPABASE_DB_DOCTOR_PATIENT=false` |
| `backend/functions/.env.example` | `FIRESTORE_FORBIDDEN=0`, `USE_SUPABASE_DB_DOCTOR_PATIENT=1` |

## Options (pick one before merge)

**A — One value per environment (documented matrix, same names)**

| Environment | Client `FIRESTORE_FORBIDDEN` | Client cutover define | Functions `FIRESTORE_FORBIDDEN` | Functions `USE_SUPABASE_DB_DOCTOR_PATIENT` |
|-------------|------------------------------|------------------------|-----------------------------------|---------------------------------------------|
| local/staging | true / `1` | true | `1` | `1` |
| production | true / `1` | true | `1` | `1` |

**B — Split client vs server names**

| Purpose | Client | Server |
|---------|--------|--------|
| Block Firestore SDK | `CLIENT_FIRESTORE_FORBIDDEN` | `FIRESTORE_FORBIDDEN` |
| Cutover hint | `CLIENT_SUPABASE_PRIMARY` | `USE_SUPABASE_DB_DOCTOR_PATIENT` |

Requires dart-define renames + CI/deploy doc updates.

**Recommendation:** **A** for postgres-only release (templates already aligned); keep names, enforce via runbooks/build scripts.
