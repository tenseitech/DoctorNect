# Proposal: pre-commit env guards (no Husky/Lefthook in repo today)

## Problem

`.env.example` must stay placeholder-only. Accidental regeneration or copy-from-`.env` can commit secrets.

## Recommended hook

Repo has **no** `.husky/` or `lefthook.yml`. Use a plain Git hook:

```sh
#!/bin/sh
# .githooks/pre-commit (install: git config core.hooksPath .githooks)
node scripts/env/staged_env_file_guard.js || exit 1
node scripts/env/guard_env_example_secrets.js || exit 1
exit 0
```

`staged_env_file_guard.js` blocks committing `.env` and similar; `guard_env_example_secrets.js` scans `.env.example`.

## CI parity

Root `npm run env:verify` and `npm run env:ci` already run the same guards server-side.

## Optional future

Add `husky` devDependency + `prepare` script only if the team wants automatic `core.hooksPath` setup on `npm install`.