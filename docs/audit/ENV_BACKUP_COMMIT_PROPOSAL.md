# Env backup hygiene — commit proposal (pending operator confirm)

**Do not apply** until you confirm the `.env.bak` finding and approve the move.

## Inventory (`backend/functions`, names only)

| Path | Git status |
|------|------------|
| `.env.example` | **Tracked** (template, no secrets) |
| `.secret.local.example` | **Tracked** |
| `.env` | **Ignored** (untracked if present locally) |
| `.secret.local` | **Ignored** (untracked if present locally) |
| `.env.bak*` / `.env.*.bak*` / `*.bak-before-*` | **Not present** in workspace scan; `docs/ops/CLEANUP_MANIFEST.md` references `.env.bak-before-guard-fix` as historical untracked backup |

Root `.gitignore` already includes `backend/functions/.env.bak*` (line 147).

## Proposed commit (after confirm)

### `.gitignore` additions (repo root)

```gitignore
# Env backup artifacts (never commit)
.env.bak*
.env.*.bak*
*.bak-before-*
**/.env.bak*
**/.env.*.bak*
```

Note: overlaps with existing `**/.env.*` and `backend/functions/.env.bak*` — additive for clarity and `*.bak-before-*`.

### Move local backup (operator only, after confirm)

**Do not open or print file contents.**

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\doctornect-env-backup"
Move-Item -Path "C:\Users\khije\Downloads\DoctorNect\doctor\backend\functions\.env.bak-before-guard-fix" `
  -Destination "$env:USERPROFILE\doctornect-env-backup\functions.env.bak-before-guard-fix" `
  -ErrorAction Stop
```

Adjust source path if your backup filename differs.

### Related doc

- Deploy bundle ignores: [FIREBASE_IGNORE_PROPOSAL.md](./FIREBASE_IGNORE_PROPOSAL.md)
