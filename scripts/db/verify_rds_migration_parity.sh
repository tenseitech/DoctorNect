#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
echo "RDS scratch replay..."
node scripts/db/rds_scratch_replay.js
echo "RLS harness (replay_check)..."
node scripts/db/rls_sql_harness.js --target=replay_check
echo "Done — expect zero statement failures (see runbook)."
