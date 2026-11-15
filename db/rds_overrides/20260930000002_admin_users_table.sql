-- RDS replay: create TEXT-keyed admin_users (Firebase UID / public.users.id), no Supabase auth.users FK.
-- Transaction boundaries: migrate.js / rds_scratch_replay (no BEGIN/COMMIT here).

CREATE TABLE IF NOT EXISTS private.admin_users (
  user_id TEXT PRIMARY KEY,
  granted_by TEXT,
  granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE private.admin_users ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.admin_users FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE private.admin_users TO service_role;