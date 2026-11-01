# Supabase service role — one concept, two names

## Readers (runtime)

| Name | Where read |
|------|------------|
| `SUPABASE_SERVICE_ROLE_KEY` | `secure_config.readSupabaseServiceRoleKey()`, `src/db/client.js`, `delete_my_account.js`, Secret Manager binding `defineSecret('SUPABASE_SERVICE_ROLE_KEY')` |
| `SUPABASE_SECRET_KEY` | **Only** as fallback inside `readSupabaseServiceRoleKey()` in `secure_config.js` (after `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_SERVICE_KEY`) |

Both names refer to the **same credential**: Supabase **service role** (bypasses RLS). The Flutter/client-facing **anon/publishable** keys are separate.

## Canonical proposal (deploy rename later)

- **Canonical env / secret id:** `SUPABASE_SERVICE_ROLE_KEY` (matches Firebase secret binding and Supabase docs terminology).
- **Legacy alias (examples + local only until migrated):** `SUPABASE_SECRET_KEY`.

Already in `scripts/check_env_parity.js` → `ENV_CONCEPT_GROUPS`:

```javascript
{ canonical: 'SUPABASE_SERVICE_ROLE_KEY', aliases: ['SUPABASE_SECRET_KEY', 'SUPABASE_SERVICE_KEY'] }
```

Do not rename Secret Manager or deployed bindings until a dedicated secrets migration branch.
