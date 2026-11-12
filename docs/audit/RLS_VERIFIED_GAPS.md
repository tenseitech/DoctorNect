# RLS verified-role gaps (machine-derived)

Policy inventory is generated from **`db/migrations/*.sql`** (final `CREATE POLICY` per name wins):

```bash
node scripts/audit/extract_public_policies.js > docs/audit/RLS_POLICY_GAP_MATRIX.md
```

Proposed hardening (not applied): `db/proposed/20261103000014_proposed_role_verified_rls_hardening.sql`

## Onboarding self-access (unchanged by 000014)

Unverified providers can still read/update **their own** profile rows via owner-scoped policies (not gated by `verified`):

| Table | Policy | Self access |
|-------|--------|-------------|
| `doctors` | `doctors_select` (`20261103000011`) | `owner_uid = jwt.sub` OR `doctor_id = current_profile_id()` |
| `doctors` | `doctors_update` (`round6`) | `WITH CHECK (owner_uid = jwt.sub OR doctor_id = current_profile_id())` |
| `labs` | `labs_update` (`round6`) | `owner_uid = jwt.sub` |
| `medical_stores` | `medical_stores_update` (`round6`) | `owner_uid = jwt.sub` |
| `ambulances` | `ambulances_update` (`round6`) | `auth_uid = jwt.sub` |
| `patients` | `patients_update` (`round6`) | `owner_uid = jwt.sub` |
| `users` | `users_update_owner_or_admin` | owner uid match |

## `deactivated` columns

`labs.deactivated` / `medical_stores.deactivated` referenced in proposed helpers:

```18:19:db/proposed/20261103000014_proposed_role_verified_rls_hardening.sql
          AND verified IS TRUE
          AND COALESCE(deactivated, FALSE) IS FALSE
```

Domain tables include `deactivated` / `deactivated_at` guards in `20261031000001_trusted_writers_and_domain_fixes.sql` and deactivation RPC in `20261102000001_round6_guards_and_kyc.sql`.

See **`docs/audit/RLS_POLICY_GAP_MATRIX.md`** for the full `pg_policies`-style table and GAP classifications.
