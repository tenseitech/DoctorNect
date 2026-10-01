-- ============================================================================
-- CHECK RECENT PROVISIONING ERRORS
-- Query private.provisioning_errors to inspect any auth signup trigger failures
-- ============================================================================

SELECT * 
FROM private.provisioning_errors 
ORDER BY id DESC;
