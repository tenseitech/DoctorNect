-- ============================================================================
-- DoctorNect Platform — Duplicate Mobile Number Detection Script
-- File: scratch/users_mobile_dupes.sql
-- Run this query on STAGING / PRODUCTION before applying the unique index.
-- ============================================================================

SELECT 
    mobile,
    COUNT(*) AS duplicate_count,
    array_agg(id) AS user_ids,
    array_agg(role) AS roles,
    array_agg(profile_id) AS profile_ids,
    array_agg(created_at ORDER BY created_at ASC) AS creation_dates
FROM public.users
WHERE mobile IS NOT NULL 
  AND deactivated = FALSE
GROUP BY mobile
HAVING COUNT(*) > 1;

-- If 0 rows are returned, the data is clean and the partial unique index can be created:
-- CREATE UNIQUE INDEX idx_users_active_mobile 
-- ON public.users (mobile) 
-- WHERE deactivated = FALSE AND mobile IS NOT NULL;
