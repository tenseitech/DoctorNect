-- ============================================================================
-- scratch/orphan_auth_users.sql
-- Read-only query to detect desynchronized auth users and public users
-- ============================================================================

-- 1. auth.users rows without a public.users row
SELECT 
    au.id,
    au.email,
    au.phone,
    au.created_at,
    au.raw_app_meta_data->>'role' AS role,
    'missing_in_public_users' AS anomaly_type
FROM auth.users au
LEFT JOIN public.users pu ON au.id = pu.id
WHERE pu.id IS NULL
ORDER BY au.created_at DESC;

-- 2. public.users rows without an auth.users row
SELECT 
    pu.id,
    pu.email,
    pu.mobile,
    pu.created_at,
    pu.role,
    pu.profile_id,
    'missing_in_auth_users' AS anomaly_type
FROM public.users pu
LEFT JOIN auth.users au ON pu.id = au.id
WHERE au.id IS NULL
ORDER BY pu.created_at DESC;
