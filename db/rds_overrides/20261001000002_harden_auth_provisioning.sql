-- RDS replay override for 20261001000002_harden_auth_provisioning.sql
-- Skipped: owner_uid default type mismatch before UUID->TEXT consolidated pass.
SELECT 1 AS rds_replay_skip_harden_auth_provisioning;