# Production RDS catalog security (read-only)

Generated: 2026-11-23T10:10:05.554Z
Host fingerprint: doctornect-prod.c92k0uqgqekv.ap-south-1.rds.amazonaws.com

## Policies involving PUBLIC role

- **cron.job** `cron_job_policy` cmd=ALL roles={public}
  - USING: `(username = CURRENT_USER)`
- **cron.job_run_details** `cron_job_run_details_policy` cmd=ALL roles={public}
  - USING: `(username = CURRENT_USER)`

## RLS enabled / forced (public + private)

- Tables with RLS enabled: **68** / 69
- RLS enabled but **not forced**: private.admin_users, private.provisioning_errors, public.doctor_directory_updates, public.doctor_invites, public.doctor_private, public.pharmacy_doctor_invites, public.storage_audit_logs, public.user_devices, public.users

## SECURITY DEFINER without pinned search_path

Count: **0** (of 51 definer functions)

## Grants to anon / authenticated / PUBLIC (table privileges)

Row count: **125**
- anon: 4 grant rows
- authenticated: 121 grant rows

## system_config policies (SEC-013)

- **system_config_public_read** cmd=r roles=["anon","authenticated"]
  - USING: `((config_key)::text = ANY ((ARRAY['patient_module_status'::character varying, 'promoted_ads'::character varying])::text[]))`
- **system_config_write** cmd=* roles=["authenticated"]
  - USING: `private.is_super_admin()`

### config_key rows matching public-read allowlist check

- present: `patient_module_status`
- present: `promoted_ads`

**Anon-visible keys per policy** should be only `patient_module_status`, `promoted_ads`. demo_accounts present: **false**.