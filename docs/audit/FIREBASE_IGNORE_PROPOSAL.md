# `firebase.json` functions ignore (applied in repo)

**Note:** `firebase.json` `functions.ignore` controls the **upload bundle only**. The Firebase CLI still **loads** `backend/functions/.env` and `.env.<projectId>` from disk at deploy time for Cloud Run env injection ([Configure your environment](https://firebase.google.com/docs/functions/config-env)) — those reads are independent of the ignore list. Keeping `.env.example` tracked in git is fine; broad `**/.env*` in ignore excludes `.env.example` from the **uploaded zip** unless you add negation rules.

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
