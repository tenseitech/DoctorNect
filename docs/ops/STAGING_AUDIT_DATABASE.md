# Staging database — read-only audit access

Local **read-only** checks (`scripts/audit/verify_demo_login_chain_readonly.js`, etc.) should use **`STAGING_SUPABASE_DB_URL`** with a dedicated Postgres role — never the `service_role` key in SQL clients and never a superuser connection string in git.

## Create the role

Run once on the **staging** Supabase project (SQL Editor):

- Template: [staging_audit_readonly_role.sql](./staging_audit_readonly_role.sql)
- Replace the placeholder password before `COMMIT`.

## Grants

| Object | Permission |
|--------|------------|
| `public.users` | `SELECT` only |

No `INSERT`/`UPDATE`/`DELETE`. Audit scripts must not mutate staging data.

## Root `.env`

Set:

```env
STAGING_SUPABASE_DB_URL=postgresql://doctornect_audit.[PROJECT_REF]:...@...pooler.supabase.com:5432/postgres?sslmode=require
```

Use **Session pooler** or **Transaction pooler** URI from Supabase → Database → Connection string.

## Not for Cloud Functions

Functions use Firebase secrets (`DEMO_SUPABASE_SERVICE_ROLE_KEY`) for server-side Supabase REST. Audit SQL uses this read-only role only on your machine.