# Dependency footprint — Audit 5 follow-up (PERF-03)

**Scope:** `frontend/pubspec.yaml` direct dependencies. **Audit 2 lockfile work not modified.**

## Method

Static `rg` usage scan across `frontend/lib` and `frontend/test`. No package removals without proof of zero references and no plugin/native linkage.

## Inventory (sample)

| Dependency | Usage | Footprint concern | Action |
|------------|-------|-------------------|--------|
| `firebase_*` / `supabase_flutter` | Core data plane | Large | **Retain** |
| `pdf` / `printing` | Prescription/report export | Medium | **Retain** |
| `geolocator` / `geocoding` | Ambulance/maps | Medium | **Retain** |
| `screenshot` | Doctor profile share sheet | Small | **Retain** (1 import) |
| `smart_auth` | OTP autofill | Small | **Retain** |
| `archive` | ICD/medicine gzip loaders | Small | **Retain** |
| `cached_network_image` | Network images | Medium | **Retain** |
| `equatable` | Transitive / limited direct | Low | **Retain** (transitive) |

## Result

**No direct dependencies removed.** Risk of breaking Firebase plugins, Razorpay, or platform builds outweighs marginal bundle savings without a dedicated Audit 2–aligned dependency pass.

## Validation

`flutter analyze lib/core/supabase` — **no issues** (post follow-up).