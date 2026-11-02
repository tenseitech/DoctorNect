# Proposed `firebase.json` functions ignore (not applied)

**Do not edit `firebase.json` until operator confirms** (see `ENV_BACKUP_COMMIT_PROPOSAL.md`).

## Current ignore list (`firebase.json` → `functions[0].ignore`)

```json
[
  "node_modules",
  ".git",
  "firebase-debug.log",
  "firebase-debug.*.log",
  "*.local",
  ".env",
  ".env.local",
  ".env.production",
  ".env.medibond-45fad",
  ".secret.local",
  "secrets/**",
  "*.p12",
  "service-account*.json"
]
```

## Proposed additions

```diff
       "ignore": [
         "node_modules",
         ".git",
         "firebase-debug.log",
         "firebase-debug.*.log",
         "*.local",
         ".env",
         ".env.local",
         ".env.production",
         ".env.medibond-45fad",
+        "**/.env*",
+        "**/.secret*",
+        "**/*.bak*",
         ".secret.local",
         "secrets/**",
         "*.p12",
         "service-account*.json"
       ]
```

### Rationale

| Pattern | Why |
|---------|-----|
| `**/.env*` | Catches nested env files and variants (`.env.bak`, `.env.staging`) under `backend/functions` without listing every name. |
| `**/.secret*` | Matches `.secret.local` and any other secret sidecar files. |
| `**/*.bak*` | Backup copies of env or config must never ship in the Cloud Functions bundle. |

### `.env.example` and deploy

Firebase **ignore** is a deny list. Adding `**/.env*` would also exclude `.env.example` from the upload bundle.

- **Runtime:** Functions read env from Cloud Run / Secret Manager / Firebase params — not from `.env.example` in the deployed artifact.
- **If the team relies on `.env.example` inside the uploaded zip** (unusual), add an explicit negation after the broad rule, e.g. `!.env.example` and `!**/.env.example`, and verify with `firebase deploy --only functions --dry-run` (operator).

Default recommendation: **exclude all `.env*` from deploy**; keep `.env.example` **git-tracked only** for local `npm test` / onboarding.
