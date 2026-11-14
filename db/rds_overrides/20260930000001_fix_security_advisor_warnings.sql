-- RDS replay override for 20260930000001_fix_security_advisor_warnings.sql
-- Skipped: depends on RLS helpers not created on RDS replay path before consolidated.
SELECT 1 AS rds_replay_skip_security_advisor;