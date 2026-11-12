# Dedupe checklist — pending items (D, J, assets, gitignore)

## Item D — unused Dart files (proof first)

**Result:** **COMPLETE (already deleted)** — Phase 4 commit **`2e29ac6`** removed **23** zero-importer files listed in `docs/ops/CLEANUP_MANIFEST.md`.

**Re-verification (2026-11-01):**

- Glob: `registration_legal_consent_checkbox.dart`, `medicine_row_card.dart`, `form_scroll_helper.dart` → **0 files** under `frontend/lib/`
- `rg` imports for manifest basenames → **0** inbound references in `frontend/lib` and `frontend/test/`

**No further Dart deletes** on this pass. Stale list `frontend/scripts/refactor/unused_dart_files.txt` uses old `c:\doctor\doctor\` paths — **do not trust**; use manifest + import graph.

---

## Item J — gitignore generated audit artifacts

**Result:** **COMPLETE** on branch — commit **`cd7875d`** adds gitignore for jscpd / phase1 SQL audit outputs (`docs/audit/_jscpd_features/`, `docs/audit/_phase1_sql_policies.json`, etc.).

**Also done:** `docs/audit/_runs/` for `extract_backend_failures.js` default output.

---

## Duplicate WebP pair (phase1 scan hash `ac6c28f5c243`)

**Byte-identical group:** `app_icon.webp`, `logo_icon.webp`, `logo_splash.webp`, `logo_splash_android12.webp`

**References:**

- `frontend/pubspec.yaml` — **PNG** paths for launcher/splash (`logo_icon.png`, `logo_splash.png`, …) — **not** `.webp`
- `frontend/lib/core/utils/asset_webp_manifest.dart` — lists all four `.webp` paths
- No `app_icon.webp` string in `lib/` besides manifest

**Proposal:** **Do not delete** any member yet. To dedupe safely: pick **`logo_icon.webp`** as canonical runtime logo, remove **`app_icon.webp`** from manifest only after confirming no platform tool references `assets/images/app_icon.webp`. Splash variants share hash but serve distinct layout roles — keep until PNG/WebP roles consolidated.

**Other WebP dupes:** `bone_joint.webp` / `bone_joint_icon.webp` — code uses **`bone_joint_icon.png`** + resolver; `_icon.webp` required for AssetResolver — **keep both**.

---

## Gitignore — `adapters/` / `scratch/` leftovers

| Path | Status |
|------|--------|
| `scratch/` | Already in `.gitignore` (repo root) |
| `adapters/` | **Tracked** — only `GEMINI.md`, `GPT_OSS.md`, `CLAUDE.md`; referenced by `.gemini/GEMINI.md` — **not ignored** |
| `adapters/scratch/` | **N/A** — directory does not exist |

**Added:** `adapters/scratch/` pattern to `.gitignore` for future local drops (no moves).

**Not ignored:** whole `adapters/` (still documentation, not secrets).
