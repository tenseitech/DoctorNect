-- RDS replay override for 20260930000006_column_locks.sql
-- Skipped: trigger bodies compare owner_uid to auth.uid() (uuid = text on RDS shim).
SELECT 1 AS rds_replay_skip_column_locks;