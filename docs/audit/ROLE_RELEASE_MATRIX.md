# Role release matrix vs Oct 24 deployed backend

**Client default:** `FIRESTORE_FORBIDDEN=true` (`firestore_forbidden_guard.dart`).  
**Deployed reference:** `docs/ops/baseline_cloud_functions.json` + gaps **G1–G5** in `docs/audit/APP_BACKEND_CONTRACT.md`.  
**Legend:** **Works** = primary flows usable; **Broken** = hard fail or empty data; **Unknown** = needs manual smoke on device.

---

## Patient

| Flow | Client data path | vs Oct 24 backend | Status | Needs deploy / change |
|------|------------------|-------------------|--------|------------------------|
| OTP register / login | Callables + Supabase profile | G1: `exists`/`role` may be missing on verify/login | **Works** with legacy lookup fallback; **degraded** without hotfix | Optional: login hotfix on `verifyUserRegistrationOtp` / `completeMobileOtpLogin` |
| Registration rollback | `cleanupPendingRegistration` + Supabase | G2: callable **not** deployed | **Broken** on failed finalize (orphan rows) | **`cleanupPendingRegistration` canary** |
| Appointments / booking | Supabase-primary + callables `bookAppointment` | Callable on baseline | **Works** | — |
| Records / vitals (Supabase) | Supabase | RLS on branch DB | **Works** if Supabase URL matches prod | Env parity |
| Legacy Firestore reads | Some refresh/cancel tests still Firestore-shaped | Deny-all client rules | **Unknown** / partial | Finish cutover or guard paths |

---

## Doctor

| Flow | Client data path | vs Oct 24 backend | Status | Needs deploy / change |
|------|------------------|-------------------|--------|------------------------|
| OTP login | Same as patient | G1 | **Works** / degraded same as patient | Hotfix optional |
| Verification gate | Supabase + `doctor_verification_gate` | Mixed Firestore watch in gate tests fail locally | **Unknown** | Supabase-only gate verification |
| Schedule / availability | Supabase + slots callables | Backend on baseline | **Works** | — |
| Clinical Firestore stores | `clinical_prescription_store`, community repos | Firestore forbidden | **Broken** if screens still read Firestore | Migrate reads or disable forbidden guard in dev only |
| Notifications shell | `doctor_shell` Firestore watches | Backend may still write Firestore | **Broken** / empty streams | Supabase notifications cutover |

---

## Lab

| Flow | Client data path | vs Oct 24 backend | Status | Needs deploy / change |
|------|------------------|-------------------|--------|------------------------|
| OTP login | Callables + Supabase | G1 | **Works** / degraded | Hotfix optional |
| Dashboard / walk-in | Supabase phase-D repos + legacy lab repos | Mixed | **Partial** | Complete lab module Supabase reads |
| Report upload (S3) | S3 callables + **Firestore** ordering tests failing | S3 callables on baseline | **Works** server-side; **client tests** show Firestore ordering assumptions | Production: Supabase lab orders; tests are baseline debt |

---

## Pharmacy (medical store)

| Flow | Client data path | vs Oct 24 backend | Status | Needs deploy / change |
|------|------------------|-------------------|--------|------------------------|
| OTP login | Callables | G1 | **Works** / degraded | Hotfix optional |
| Store dashboard / profile | Supabase + registry stores | Partial Firestore registry | **Partial** | Supabase pharmacy cutover |
| Connections / deliveries | Legacy Firestore connection stores | Backend sync varies | **Unknown** | Manual smoke + Supabase reads |

---

## Ambulance

| Flow | Client data path | vs Oct 24 backend | Status | Needs deploy / change |
|------|------------------|-------------------|--------|------------------------|
| Driver OTP / PIN | Callables on baseline | Present | **Works** | — |
| Booking / broadcasts | **Firestore** repositories + Supabase mapping | Backend triggers still Firestore-heavy | **Broken** under `FIRESTORE_FORBIDDEN` for realtime UI | Deploy Supabase sync triggers **or** allow Firestore for ambulance until cutover |
| Location / profile | Firestore + Supabase | Mixed | **Partial** | Ambulance module cutover plan |

---

## Admin / super-admin

| Flow | Client data path | vs Oct 24 backend | Status | Needs deploy / change |
|------|------------------|-------------------|--------|------------------------|
| Promoted ad review | Firestore / admin services | `reviewPromotedAd` on baseline | **Broken** if client cannot read `promoted_ads` | Supabase admin reads or Firestore exception |
| User verification queue | `super_admin_verification_service` Firestore | Backend approval callables exist | **Broken** under forbidden guard | Admin Supabase queue |
| Approvals | `approveUserAccount` / `approvePatientAccount` | On baseline | **Works** (server-side) | Client UI must call callables |

---

## Cross-role deploy minimum (app on this branch vs Oct 24 backend)

1. **`cleanupPendingRegistration`** — required for **patient** (and any role) registration rollback (**G2/G3**).  
2. **Login hotfix (G1)** — recommended before marketing login UX that depends on post-OTP `exists`/`role`.  
3. **Do not** full-fleet deploy **`4dfae67`** postgres-only tree without cutover (**G5**).  
4. **Role matrix manual test** — one smoke per role after (1) and optional (2).
