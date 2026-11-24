# DoctorNect Security Audit — 2026-11-23

**Mode:** Read-only (static analysis, config review, non-destructive AWS/RDS checks).  
**AWS profile used:** `doctornect-terraform` (where permitted).  
**No secret values** are reproduced in this document.

---

## 1. Executive summary

| Severity | Count |
|----------|------:|
| Critical | 1 |
| High | 8 |
| Medium | 14 |
| Low | 8 |
| Info | 9 |
| **Total findings** | **40** |

_Counts computed from §2 table (SEC-001 … SEC-040): PowerShell regex parse — Critical **1**, High **8**, Medium **14**, Low **8**, Info **9**, total **40**._

### Launch se pehle zaroor fix (blockers / near-blockers)

1. **SEC-001** — Bastion security group allows SSH from `0.0.0.0/0`.
2. **SEC-003** — AWS production Secrets Manager secrets empty (no versions).
3. **SEC-005** — ECS API service not running (`desiredCount=0`).
4. **SEC-006** — WAF disabled on public ALB.
5. **SEC-002** — `doctornect-terraform` IAM wildcards (`ecs:*`, `elasticloadbalancing:*`, `wafv2:*`).
6. **SEC-009** — Reviewer fixed OTP window active (limit `REVIEW_ACCESS_UNTIL`; disable after Play review).

**Part B (2026-11-23, approved — committed locally, not deployed):** SEC-004, SEC-029, SEC-012, SEC-016, SEC-025.

**Part C FORCE RLS (PC-01):** **Deferred to Phase 2** — apply `20261123101500` only after **staging `rls_sql_harness` pass** (see §9).

### Follow-up artefacts (read-only)

- [`PROD_RDS_CATALOG_SECURITY_2026-11-23.md`](./PROD_RDS_CATALOG_SECURITY_2026-11-23.md) — live catalog snapshot (tunnel).
- `definer_force_rls_audit.js --target=production` — **0** definer hits on FORCE RLS tables (2026-11-23).

---

## 2. Findings table

| ID | Severity | Area | Title | Location | Fix (summary) | Effort |
|----|----------|------|-------|----------|---------------|--------|
| SEC-001 | Critical | AWS Network | Bastion SSH open to world | `sg-06822e3e49e0dc717` (live EC2 SG) | Restrict SSH to admin IP / SSM Session Manager only | M |
| SEC-002 | High | AWS IAM | Terraform operator wildcard ELB/ECS/WAF | `docs/ops/IAM_TERRAFORM_OPERATOR.json` | Remove `*` admin actions post-rollout; split preflight | S |
| SEC-003 | High | Secrets | AWS production secrets empty (no versions) | Secrets Manager `doctornect/production/*` | Run secret fill scripts before scale-up | S |
| SEC-004 | High | Gateway | Default PostgREST JWT secret in code | `services/api-gateway/src/config.js:21` | Production startup guard — **fixed (Part B approved)** | S |
| SEC-005 | High | AWS ECS | API not running (`desiredCount=0`) | ECS `doctornect-production-service` | Complete secrets + ECR + scale after verify | M |
| SEC-006 | High | AWS WAF | WAF not associated with ALB | `infra/aws/waf.tf`, `enable_waf=false` | Enable WAF + managed rule sets after smoke test | M |
| SEC-007 | High | Gateway | `service_role` key = full data plane bypass | `services/api-gateway/src/server.js:288-293` | Strong key rotation, IP allowlist for service_role, audit logs | M |
| SEC-008 | High | OTP / Firebase | Dual-plane OTP (Firestore + Postgres paths) | `backend/functions/registration_otp.js` | Complete Postgres-only OTP path; retire Firestore OTP collections | L |
| SEC-009 | High | Demo/Review | Fixed reviewer OTP + time window | `backend/functions/reviewer_otp_config.js` | Short `REVIEW_ACCESS_UNTIL`, rotate `REVIEW_FIXED_OTP`, disable after Play review | S |
| SEC-010 | Medium | Gateway | In-memory rate limits (per task) | `services/api-gateway/src/security.js:27-56` | Redis/ElastiCache or WAF rate-based rules when scaling >1 task | M |
| SEC-011 | Info | Gateway | X-Forwarded-For client IP behind ALB | `services/api-gateway/src/server.js:103-110` | **No change** — **Verified live:** `routing.http.xff_header_processing.mode = append` (2026-11-24); rightmost hop = connecting client; matches rate limiter | — |
| SEC-012 | Medium | Gateway | Auth errors echo verifier messages | `services/api-gateway/src/server.js:337-340` | Generic 401 message — **fixed (Part B approved)** | S |
| SEC-013 | Info | Gateway | Anonymous `system_config` via gateway allowlist | `config.js:37-38` + RDS policy | **Verified 2026-11-23:** anon SELECT only `patient_module_status`, `promoted_ads`; no `demo_accounts` | — |
| SEC-014 | Medium | AWS ALB | No port-80 redirect listener | `infra/aws/alb.tf` | Add HTTP listener → 301 to HTTPS (defense in depth) | S |
| SEC-015 | Medium | Firebase Fn | `invoker: 'public'` validation callables | `backend/functions/index.js:406` | Require App Check + auth where possible | S |
| SEC-016 | Medium | Firebase Fn | App Check enforcement env-toggle | `backend/functions/index.js:182-189` | `assertProductionAppCheckEnforcement` — **fixed (Part B approved)** | S |
| SEC-017 | Medium | OTP | No MSG91 daily spend cap in code | `backend/functions/registration_otp.js` (rates only) | MSG91 dashboard cap + billing alarm + server-side daily SMS budget | M |
| SEC-018 | Medium | Dependencies | npm moderate advisories (functions) | `backend/functions` (`npm audit`) | Bump `fast-xml-parser` / Firebase SDK chain | M |
| SEC-019 | Medium | Repo hygiene | Local secrets on disk (untracked) | `.env`, `upload-keystore.jks`, `scripts/service-account.json` | Verify `.gitignore`, pre-commit secret scan, remove duplicates from workspace | S |
| SEC-020 | Medium | Git history | Historical commits touch connection-string patterns | `git log -S postgresql://` | Run secret scanner on history; rotate if ever leaked | M |
| SEC-021 | Medium | Database | SECURITY DEFINER / search_path | `db/migrations/*.sql` | Catalog: **0** unpinned `search_path` / 51 definer; FORCE-RLS audit **0** hits. Part C: EXECUTE to PUBLIC/anon | M |
| SEC-022 | Medium | Database | `FOR ALL TO PUBLIC` migration vs prod | Migration `20261103000004_*` | **Catalog 2026-11-23:** no app-table PUBLIC ALL; only `cron.*` (see §3). Part C: `USING (true)` scan | S |
| SEC-023 | Medium | Compliance | DPDP consent/retention documentation gaps | `docs/` (no single DPDP artefact) | Privacy policy, consent logs, deletion SLA doc | L |
| SEC-024 | Medium | Mobile | No TLS certificate pinning | `frontend/` (no pinning code) | Document risk acceptance or add pinning for prod gateway | L |
| SEC-025 | Medium | Mobile | Android manifest lacks explicit `allowBackup=false` | `frontend/android/.../AndroidManifest.xml` | `allowBackup=false` + backup XML rules — **fixed (Part B approved)** | S |
| SEC-026 | Low | Dependencies | Gateway npm audit (low) | `services/api-gateway` | Routine `npm audit fix` | S |
| SEC-027 | Low | CI/CD | GitHub Actions not SHA-pinned | `.github/workflows/*.yml` | Pin actions to commit SHA | M |
| SEC-028 | Low | CI/CD | `build-apk` uses placeholder Firebase secrets | `.github/workflows/build-apk.yml:35-36` | Expected; ensure release not distributed from CI artifact | S |
| SEC-029 | Low | Gateway | Default anon key string in config | `services/api-gateway/src/config.js:24` | Same production startup guard as SEC-004 — **fixed (Part B approved)** | S |
| SEC-030 | Low | Firebase | Callable logs mobile last-4 + platform | `backend/functions/index.js:509-515` | Acceptable; avoid full mobile in logs | S |
| SEC-031 | Low | OTP | Legacy unsalted OTP hash rollback flag | `registration_otp.js` (`ALLOW_LEGACY_UNSALTED_OTP_HASH`) | Keep `false` in production | S |
| SEC-032 | Low | AWS RDS | IAM database authentication disabled | RDS `doctornect-prod` (live) | Optional: enable IAM auth for operators | L |
| SEC-033 | Low | Secrets | Secrets Manager rotation disabled | `doctornect/production/*` | Enable rotation for DB/JWT keys post-launch | M |
| SEC-034 | Info | Demo routing | Demo UID RDS block + service_role query guard | `scripts/lib/rds_demo_uid_guard.js` | Keep enabled; add integration tests | S |
| SEC-035 | Info | Firestore | Client rules deny-all | `backend/firestore.rules:7-9` | Maintain lockdown | S |
| SEC-036 | Info | Storage | Firebase Storage deny-all | `backend/storage.rules:6-8` | Maintain; PHI on S3 presigned only | S |
| SEC-037 | Info | Gateway | Timing-safe service key compare | `services/api-gateway/src/security.js:8-14` | Keep | — |
| SEC-038 | Info | OTP | OTP from `crypto.randomInt` | `registration_otp.js:405-406` | Keep | — |
| SEC-039 | Info | RDS (live) | Private, encrypted, deletion protection | RDS `doctornect-prod` | Maintain backups/MFA on restore | — |
| SEC-040 | Info | RDS (live) | Authenticator + RLS catalog snapshot | Tunnel 5434 + catalog MD | Authenticator **OK**; RLS 68/69; health-table grant matrix **not verified** (Part C) | S |

---

## 3. Finding details

### SEC-001 — Bastion SSH open to world (Critical)

- **Location:** AWS EC2 SG `doctornect-bastion-ec2-sg` (`sg-06822e3e49e0dc717`), ingress TCP/22 `0.0.0.0/0`.
- **Issue:** Any Internet host can attempt SSH brute force against the bastion.
- **Exploit:** Credential stuffing / CVE in sshd → lateral movement toward RDS/VPC.
- **Fix:** Replace with **SSM Session Manager** (no public SSH), or restrict to known office IP /32. Remove `0.0.0.0/0` rule.
- **Effort:** M

### SEC-002 — Terraform operator over-privileged (High)

- **Location:** `docs/ops/IAM_TERRAFORM_OPERATOR.json` — `elasticloadbalancing:*`, `ecs:*`, `wafv2:*` on `*`.
- **Issue:** Compromised access key can reshape entire production edge/compute.
- **Exploit:** Create rogue ECS service, exfil secrets via task definition, destroy ALB.
- **Fix:** Post-rollout replace wildcards with resource-scoped statements; keep state/IAM in separate policies (already split partially).
- **Effort:** S (policy edit) + M (verify no regressions)

### SEC-003 — Empty production secrets (High)

- **Location:** `doctornect/production/rds_credentials_*`, `postgrest_jwt_secret_*`, `gateway_service_key_*`, `demo-routing` (list-secrets: rotation `null`, versions **0** at audit time).
- **Issue:** ECS tasks cannot start safely; risk of operators testing with defaults.
- **Exploit:** Misconfiguration leads to weak or missing JWT verification.
- **Fix:** Follow `docs/ops/GATEWAY_DEMO_ROUTING_DEPLOY.md` secret order; verify version counts before scale-up.
- **Effort:** S

### SEC-004 — Default JWT secret fallback (High)

- **Location:** `services/api-gateway/src/config.js:21` — dev fallback string; production guard in `assert_production_config.js`.
- **Issue:** Predictable default if secret injection fails.
- **Status:** **Fixed (pending approved)** — production startup fails if missing, &lt;32 chars, or equals default.
- **Exploit:** Attacker mints PostgREST JWTs as `authenticated` / `service_role`.
- **Effort:** S

### SEC-005 — Gateway not in service (High)

- **Location:** ECS cluster `doctornect-production-cluster`, service `doctornect-production-service`, `desiredCount=0`, `runningCount=0`.
- **Issue:** No production API edge yet; cutover incomplete.
- **Exploit:** N/A (availability); risk is alternate misconfigured endpoints used by clients.
- **Fix:** Complete ECR push, secrets, scale-up, DNS, health checks.
- **Effort:** M

### SEC-006 — WAF disabled (High)

- **Location:** `infra/aws/variables.tf` / `waf.tf` — `enable_waf` default **false**; WAF ACL not associated.
- **Issue:** Public ALB exposed to generic web attacks (SQLi probes, bot traffic) without AWS managed rules.
- **Exploit:** Volumetric / application attacks against gateway; easier OTP/API abuse at edge.
- **Fix:** Enable `enable_waf`, associate ACL, tune exclusions for PostgREST paths.
- **Effort:** M

### SEC-007 — Service role key bypass (High)

- **Location:** `services/api-gateway/src/server.js` — valid `SERVICE_ROLE_KEY` grants PostgREST `service_role` without Firebase identity; bypasses per-user RLS context in gateway allowlists.
- **Issue:** Key leakage = full database API surface.
- **Exploit:** Steal key from logs/env → read/write all tables allowed to `service_role`.
- **Fix:** Rotate via `rotate_gateway_service_key.ps1`; never log; restrict which hosts can present service key; optional mTLS between Functions and gateway.
- **Effort:** M

### SEC-008 — Firestore still in OTP / auth paths (High)

- **Location:** `backend/functions/registration_otp.js` — `otp_challenges`, `otp_rate_limits`, `users` Firestore collections; `backend/firestore.rules` denies clients but Admin SDK still reads/writes.
- **Issue:** Dual data planes increase breach surface and consistency bugs.
- **Exploit:** Firestore rule mis-deploy could re-expose OTP metadata (rules currently deny-all).
- **Fix:** Finish Postgres-primary OTP storage; restrict Firestore to FCM-only where possible.
- **Effort:** L

### SEC-009 — Reviewer fixed OTP window (High)

- **Location:** `reviewer_otp_config.js`, Firebase secrets `REVIEW_FIXED_OTP`, env `REVIEW_ACCESS_UNTIL`, phones `9999900001-05`.
- **Issue:** Known OTP for five numbers while reviewer mode enabled.
- **Exploit:** Anyone with fixed OTP + eligible phone registers/logs in to **staging** demo plane; must not reach prod RDS (guards exist — see SEC-034).
- **Fix:** Minimum expiry window; disable `REVIEWER_OTP_ENABLED` immediately after Play approval; rotate secret.
- **Effort:** S

### SEC-010 — In-memory gateway rate limits (Medium)

- **Location:** `services/api-gateway/src/security.js` — `RateLimiter` Map in Node process.
- **Issue:** Multiple Fargate tasks = multiplied limits; restart clears state.
- **Exploit:** Abuse distributed across tasks or after redeploy.
- **Fix:** WAF rate rules + shared store (Redis) for failed service-key counter.
- **Effort:** M

### SEC-011 — X-Forwarded-For behind ALB (Info — no change)

- **Location:** `services/api-gateway/src/server.js:103-110` (rightmost XFF hop used as `clientIp`).
- **Terraform ALB:** `infra/aws/alb.tf:2-15` (`resource "aws_lb" "api"`) — **`xff_header_processing_mode` not set** (no repo match for `xff_header_processing_mode` / `enable_xff_client_port`). AWS provider default = **`append`** (ALB appends client IP; spoofed client values stay to the left).
- **Verification:** With **append** mode, **rightmost** XFF hop = TCP client of the ALB → matches gateway rate-limit key. **Verified live:** `routing.http.xff_header_processing.mode = append` (2026-11-24). **No code change.** If TF ever sets `preserve` or `remove`, revisit IP extraction (would be wrong for rightmost-hop logic).
- **Effort:** —

### SEC-012 — Verbose auth errors (Medium)

- **Location:** `services/api-gateway/src/server.js:337-340` (JWT verify catch).
- **Issue:** Verifier error text was returned to clients.
- **Status:** **Fixed (pending approved)** — client response `Authentication failed.` only (generic); detailed errors must stay server-side only (Part B will verify logging redaction).
- **Effort:** S

### SEC-013 — Anon `system_config` (Info — verified)

- **Location:** Gateway anon allowlist `config.js:37`; RDS policy `system_config_public_read`.
- **Live check (read-only, 2026-11-23):** Policy `FOR SELECT TO anon, authenticated` with `USING (config_key IN ('patient_module_status','promoted_ads'))`. Rows present: `patient_module_status`, `promoted_ads` only; **`demo_accounts` absent**. No integration secrets in visible keys.
- **Exploit:** Low — only non-sensitive module/ad pricing metadata exposed by design.
- **Fix:** Keep policy; avoid inserting sensitive keys; periodic catalog re-audit.
- **Effort:** —

### SEC-014 — No HTTP→HTTPS redirect (Medium)

- **Location:** `infra/aws/alb.tf` — HTTPS listener only on 443.
- **Issue:** Clients using `http://` may fail rather than upgrade (browser HSTS not set at gateway).
- **Exploit:** sslstrip less relevant for mobile; still a hygiene gap.
- **Fix:** Add :80 listener redirect action + optional `Strict-Transport-Security` at gateway.
- **Effort:** S

### SEC-015 — Public validation callables (Medium)

- **Location:** `index.js:406` `getValidationRules` `invoker: 'public'`.
- **Issue:** Unauthenticated callers can invoke (with App Check if enabled).
- **Exploit:** Scrape validation rules / DOS via callable quota.
- **Fix:** Require App Check always; consider auth for non-registration flows.
- **Effort:** S

### SEC-016 — App Check toggles (Medium)

- **Location:** `ENFORCE_OTP_APP_CHECK` / `ENFORCE_ABUSE_APP_CHECK` default true but can be set false via env.
- **Issue:** Mis-deploy opens callables to scripted abuse.
- **Exploit:** OTP SMS pumping without attestation.
- **Fix:** `assert_app_env.js` hard-fail production if enforcement false.
- **Effort:** S

### SEC-017 — MSG91 spend cap (Medium)

- **Location:** Rate limits `SEND_MOBILE_MAX=5` / hour in `registration_otp.js`; no daily account-wide SMS budget constant found.
- **Issue:** Distributed mobiles could still inflate SMS cost.
- **Exploit:** SMS pumping attack via many numbers.
- **Fix:** MSG91 account daily cap + Firebase monitoring + per-project billing alert.
- **Effort:** M

### SEC-018 — npm audit (functions) (Medium)

- **Location:** `backend/functions` — `npm audit` reports **7** vulnerabilities (0 critical, 0 high, moderate/low).
- **Issue:** Transitive deps (e.g. `fast-xml-parser`) may be exploitable in cloud functions parsing XML.
- **Exploit:** Depends on vulnerable code path usage.
- **Fix:** `npm audit fix` / dependency upgrades in controlled PR.
- **Effort:** M

### SEC-019 — Local untracked secrets (Medium)

- **Location:** Workspace contains `.env`, `upload-keystore.jks`, `scripts/service-account.json` (local GCP SA JSON with `private_key` — **not git-tracked**).
- **Issue:** Machine compromise exposes production credentials.
- **Exploit:** Malware exfiltrates local files.
- **Fix:** OS disk encryption, restrict file ACLs, use secret managers; delete duplicate `scripts/service-account.json` if unused.
- **Effort:** S

### SEC-020 — Git history patterns (Medium)

- **Location:** `git log -S postgresql://` shows commits touching docs/tests/scripts with placeholder URLs.
- **Issue:** Historical real credentials may exist in old commits (not verified line-by-line in this audit).
- **Exploit:** Clone + grep history for credentials.
- **Fix:** Run `gitleaks` / `trufflehog` on full history; rotate any exposed credentials.
- **Effort:** M

### SEC-021 — SECURITY DEFINER surface (Medium)

- **Location:** 150+ migration matches for `SECURITY DEFINER` / grants.
- **Issue:** Definer functions bypass RLS if `search_path` or ownership wrong.
- **Live catalog (2026-11-23):** [`PROD_RDS_CATALOG_SECURITY_2026-11-23.md`](./PROD_RDS_CATALOG_SECURITY_2026-11-23.md) — **0** of **51** `public`/`private` SECURITY DEFINER functions lack pinned `search_path` (`proconfig` `search_path=%`). `definer_force_rls_audit.js --target=production` → **0** definer owners without BYPASSRLS hitting FORCE RLS DML.
- **Exploit:** Call RPC as `authenticated` to escalate if function SQL unsafe.
- **Fix:** Part C — deeper EXECUTE grants to `PUBLIC`/`anon` and policy `USING (true)` scan; migration hardening if gaps found.
- **Effort:** M

### SEC-022 — `FOR ALL TO PUBLIC` in migration vs prod (Medium)

- **Migration reference:** `db/migrations/20261103000004_fix_claim_ambulance_driver_and_users_verified_guard.sql` contains `FOR ALL TO PUBLIC` syntax (historical).
- **Production `pg_policies` (2026-11-23 catalog):** **No** `FOR ALL` policies on `public` / `private` application tables with role `{public}`. Only PUBLIC-role policies found:
  - **`cron.job`** · policy **`cron_job_policy`** · cmd=**ALL** · roles=`{public}` · USING: `(username = CURRENT_USER)` · WITH CHECK: _(not in snapshot export)_
  - **`cron.job_run_details`** · policy **`cron_job_run_details_policy`** · cmd=**ALL** · roles=`{public}` · USING: `(username = CURRENT_USER)` · WITH CHECK: _(not in snapshot export)_
- **Assessment:** pg_cron extension self-policies only; **not** the ambulance/users concern from migration file. Policies with `USING (true)` on health tables — **not verified** in this snapshot (Part C).
- **Fix:** Part C full policy export; drop/revoke if any app-table PUBLIC ALL policies appear.
- **Effort:** S

### SEC-023 — DPDP / privacy documentation (Medium)

- **Location:** Legal/privacy scattered across `docs/`; no consolidated DPDP 2023 mapping in repo.
- **Issue:** Consent, purpose limitation, erasure (`deleteMyAccount` exists), breach notification not auditable from one doc.
- **Exploit:** Regulatory non-compliance (not direct technical exploit).
- **Fix:** Publish data inventory + retention + third parties (MSG91, Firebase, AWS, Supabase) for Play Data Safety.
- **Effort:** L

### SEC-024 — No certificate pinning (Medium)

- **Location:** Flutter client — no pinning implementation found.
- **Issue:** Corporate MITM or rogue CA could intercept API traffic on compromised devices.
- **Exploit:** MITM on untrusted networks.
- **Fix:** Pin `api.doctornect.com` SPKI or document accepted risk for MVP.
- **Effort:** L

### SEC-025 — `allowBackup` not explicit (Medium)

- **Location:** `frontend/android/app/src/main/AndroidManifest.xml` application tag.
- **Issue:** Default backup may export app sandbox data on older devices.
- **Status:** **Fixed (pending approved)** — `android:allowBackup="false"` + `android:fullBackupContent="@xml/backup_rules"` (Part B: confirm `dataExtractionRules` for Android 12+).
- **Exploit:** Backup extraction on rooted/shared devices.
- **Effort:** S

### SEC-026–SEC-033 — See table (Low)

Details align with locations in §2; fixes are hygiene and operational hardening.

### SEC-034 — Demo / RDS isolation (Info — control strength)

- **Location:** `demo_routing.js`, `rds_demo_uid_guard.js`, gateway `server.js:431-468`.
- **Behaviour:** Demo Firebase UIDs route to Supabase demo upstream; RDS path blocked for demo UIDs; `service_role` queries filtering demo UIDs on RDS.
- **Residual risk:** Mis-set allowlist env could route real users incorrectly — config review required at deploy.

### SEC-039 — RDS hardening verified (Info)

- **Live (read-only):** `doctornect-prod` — `PubliclyAccessible=false`, `StorageEncrypted=true`, `DeletionProtection=true`, backup retention **7** days.

### SEC-040 — PostgREST authenticator + catalog grants (Info)

- **Authenticator (2026-11-23):** `check_rds_postgrest_authenticator_readonly.js --target=production` → **OK** (roles `anon`, `authenticated`, `service_role`, `authenticator` + memberships) via tunnel `127.0.0.1:5434`.
- **Catalog snapshot:** [`PROD_RDS_CATALOG_SECURITY_2026-11-23.md`](./PROD_RDS_CATALOG_SECURITY_2026-11-23.md) — RLS enabled **68/69** tables (`public`+`private`); **9** tables RLS on but not FORCE; `information_schema` grant rows: **anon 4**, **authenticated 121** (table names not expanded in snapshot).
- **Not verified:** Per-table grant matrix on prescriptions/labs/patients/appointments/ambulance; drift vs `04_rds_runtime_grants.sql` — **Part C**.

---

## 4. Not verified (permission or scope)

| Item | Reason |
|------|--------|
| IAM root MFA / root access keys | `iam:GetAccountSummary` — **AccessDenied** |
| IAM users / access key age (`doctornect-admin`, `doctornect-terraform`) | `iam:ListUsers` — **AccessDenied** |
| CloudTrail enabled / multi-region | `cloudtrail:DescribeTrails` — **AccessDenied** |
| GuardDuty | No API called — **not verified** |
| S3 state bucket public access block | `s3:GetBucketPublicAccessBlock` — **AccessDenied** |
| S3 application PHI buckets policies | Not in terraform profile scope — **not verified** |
| Firebase Console (Auth providers, authorized domains, App Check attestation) | Console-only — **not verified** |
| Supabase staging project region / RLS live state | No staging credentials used — **not verified** |
| MSG91 account caps / template locks | Vendor console — **not verified** |
| Production RDS — full grant matrix on health tables | **Partial:** [`PROD_RDS_CATALOG_SECURITY_2026-11-23.md`](./PROD_RDS_CATALOG_SECURITY_2026-11-23.md) (PUBLIC policies, RLS counts, anon grant row counts). Per-table grants + `USING (true)` policies — **not verified** (Part C) |
| Penetration test / dynamic OWASP | Out of scope (static only) |
| `gitleaks` / `trufflehog` | Tools **not installed** on audit host; git pickaxe only |

**Permission proposals (do not attach without review):**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AuditReadOnlyIamCloudTrail",
      "Effect": "Allow",
      "Action": [
        "iam:ListUsers",
        "iam:ListAccessKeys",
        "iam:GetAccountSummary",
        "cloudtrail:DescribeTrails",
        "cloudtrail:GetTrailStatus"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AuditS3StateBucketRead",
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketPublicAccessBlock",
        "s3:GetBucketEncryption",
        "s3:GetBucketVersioning"
      ],
      "Resource": "arn:aws:s3:::doctornect-terraform-state-672027759702"
    }
  ]
}
```

---

## 5. Fix roadmap

### Phase 1 — Launch blockers (0–7 days)

- SEC-001 bastion SSH restriction  
- SEC-003 / SEC-005 secrets + ECS scale + DNS + health  
- SEC-004 / SEC-029 remove default crypto material in production  
- SEC-006 enable WAF  
- SEC-009 tighten reviewer OTP window; disable after Play review  
- SEC-002 narrow `doctornect-terraform` IAM after rollout  

### Phase 2 — First 30 days post-launch

- **PC-01 / SEC-021 (FORCE RLS):** `db/migrations/deferred/20261123101500_security_hardening_force_rls.sql` — staging harness **210/0** + definer re-home (`users`/`admin_users` per `20261103000007`) then `approved prod`
- SEC-010 gateway rate limits (distributed store / WAF); **SEC-012 fixed (Part B)** — optional Part E log redaction follow-up  
- SEC-011 verified correct — **Verified live:** `routing.http.xff_header_processing.mode = append` (2026-11-24); `infra/aws/alb.tf` — no `xff_header_processing_mode` override  
- **SEC-009 / SEC-017 (Part D, 2026-11-23):** Operator runbooks only — [`docs/ops/REVIEWER_OTP_DISABLE.md`](../ops/REVIEWER_OTP_DISABLE.md), [`docs/ops/MSG91_SMS_BUDGET_DESIGN.md`](../ops/MSG91_SMS_BUDGET_DESIGN.md) (no code)  
- SEC-017 MSG91 billing caps (implement Layer 3 when approved)  
- SEC-018 dependency patches  
- SEC-020 secret history scan + rotation  
- SEC-021 / SEC-022 — catalog baseline done; Part C policy/grant deep-dive + migration if needed  
- SEC-023 DPDP / Play Data Safety documentation  

### Phase 3 — Hardening

- SEC-008 Firestore OTP decommission  
- SEC-024 certificate pinning decision  
- SEC-033 secrets rotation automation  
- SEC-032 optional IAM DB auth  
- Continuous: RLS harness in CI, WAF tuning, GuardDuty + CloudTrail org trail  

---

## 6. Good practices (do not regress)

| Control | Evidence |
|---------|----------|
| Firestore/Storage client deny-all | `backend/firestore.rules`, `backend/storage.rules` |
| `.gitignore` excludes `.env`, `*.tfvars`, `*.tfstate`, `*.jks`, `google-services.json` | `.gitignore:60-100` |
| Tracked git files: no `.env` / `tfvars` / keystores | `git ls-files` check |
| Gateway: timing-safe service key compare | `security.js` |
| Gateway: header allowlist to PostgREST | `proxy.js:46-64` |
| Gateway: demo UID RDS block | `rds_demo_uid_guard.js` |
| Gateway: table/RPC allowlists | `config.js` |
| RDS not public, encrypted at rest | Live `describe-db-instances` |
| ECS task SG: 3000 from ALB only; RDS 5432 from ECS SG | `security_groups.tf` |
| OTP generation `crypto.randomInt` | `registration_otp.js` |
| OTP verify attempt cap (5) + PBKDF2 storage | `registration_otp.js` |
| Firebase `defineSecret` for gateway/demo keys | `demo_plane_secrets.js` |
| RLS inventory extensive | `docs/audit/RLS_TABLE_INVENTORY.json` |
| Terraform state S3 versioning **Enabled** | `get-bucket-versioning` |
| Approve-account callable uses email allowlist | `registration_otp.js:681-701` |
| Flutter uses `flutter_secure_storage` | `frontend/pubspec.yaml` |

---

## 7. Secrets scan summary (no values)

| Finding | Path | Type | Tracked | Mask hint |
|---------|------|------|---------|-----------|
| Local env file | `.env` | mixed config | **No** | n/a (not read) |
| Local GCP SA | `scripts/service-account.json` | GCP SA JSON | **No** | `priv…` (private_key present) |
| Local Android keystore | `upload-keystore.jks` | keystore | **No** | n/a |
| Local google services | `frontend/android/app/google-services.json` | Firebase client config | **No** | n/a |
| Example placeholders only in git | `.env.example`, `terraform.tfvars.example` | placeholders | **Yes** | safe |
| Test-only secrets | `services/api-gateway/test/*.js` | test strings | **Yes** | `test…` |

Automated scanners **gitleaks/trufflehog/trivy/osv-scanner** were **not** available on the audit workstation.

---

## 8. Demo / reviewer isolation assessment

| Control | Status |
|---------|--------|
| Demo phones hardcoded map | `reviewer_otp_config.js` `9999900001-05` |
| Fixed OTP via Firebase secret | `REVIEW_FIXED_OTP` (defineSecret) |
| Expiry | `REVIEW_ACCESS_UNTIL` enforced in code |
| Demo UID allowlist routing | `DEMO_FIREBASE_UID_ALLOWLIST` (AWS secret) |
| Demo → staging Supabase | `resolveDataPlane` → `supabase` |
| Real → RDS | default plane `rds` |
| Demo UID on RDS rejected | `assertRdsPathAllowed` / `demo_uid_rds_forbidden` |
| Real UID on demo upstream | Only if mis-listed in allowlist — **config-dependent** |
| Demo write to prod RDS via app gateway | **Blocked** for Firebase-auth demo UIDs on RDS path |
| `service_role` bypass | Still full power if key stolen (SEC-007) |

---

## 9. Fix status (Part F — auto-generated from §2)

| ID | Severity | Status | Notes (from §2 fix summary) |
|----|----------|--------|---------------------------|
| **PC-01** | Medium | **Deferred (Phase 2)** | `20261123101500` in `db/migrations/deferred/` — apply after staging `rls_sql_harness` pass |
| **Part D — SEC-009** | High | **Docs only** | [REVIEWER_OTP_DISABLE.md](../ops/REVIEWER_OTP_DISABLE.md) |
| **Part D — SEC-017** | Medium | **Design only** | [MSG91_SMS_BUDGET_DESIGN.md](../ops/MSG91_SMS_BUDGET_DESIGN.md) |
| SEC-001 | Critical | Open | Restrict SSH to admin IP / SSM Session Manager only |
| SEC-002 | High | Open | Remove `*` admin actions post-rollout; split preflight |
| SEC-003 | High | Open | Run secret fill scripts before scale-up |
| SEC-004 | High | Done (committed, not deployed) | Production startup guard — fixed (Part B approved) |
| SEC-005 | High | Open | Complete secrets + ECR + scale after verify |
| SEC-006 | High | Open | Enable WAF + managed rule sets after smoke test |
| SEC-007 | High | Open | Strong key rotation, IP allowlist for service_role, audit logs |
| SEC-008 | High | Open | Complete Postgres-only OTP path; retire Firestore OTP collections |
| SEC-009 | High | Open (ops) — runbook in docs/ops/REVIEWER_OTP_DISABLE.md | Short `REVIEW_ACCESS_UNTIL`, rotate `REVIEW_FIXED_OTP`, disable after Play review |
| SEC-010 | Medium | Open | Redis/ElastiCache or WAF rate-based rules when scaling >1 task |
| SEC-011 | Info | Verified | Verified live: routing.http.xff_header_processing.mode = append (2026-11-24) |
| SEC-012 | Medium | Done (committed, not deployed) | Generic 401 message — fixed (Part B approved) |
| SEC-013 | Info | Verified | Verified 2026-11-23: anon SELECT only `patient_module_status`, `promoted_ads`; no `demo_accounts` |
| SEC-014 | Medium | Open | Add HTTP listener → 301 to HTTPS (defense in depth) |
| SEC-015 | Medium | Open | Require App Check + auth where possible |
| SEC-016 | Medium | Done (committed, not deployed) | `assertProductionAppCheckEnforcement` — fixed (Part B approved) |
| SEC-017 | Medium | Open — Part D design in docs/ops/MSG91_SMS_BUDGET_DESIGN.md | MSG91 dashboard cap + billing alarm + server-side daily SMS budget |
| SEC-018 | Medium | Open | Bump `fast-xml-parser` / Firebase SDK chain |
| SEC-019 | Medium | Open | Verify `.gitignore`, pre-commit secret scan, remove duplicates from workspace |
| SEC-020 | Medium | Open | Run secret scanner on history; rotate if ever leaked |
| SEC-021 | Medium | Open — FORCE RLS deferred (Phase 2; staging harness) | Catalog: 0 unpinned `search_path` / 51 definer; FORCE-RLS audit 0 hits. Part C: EXECUTE to PUBLIC/anon |
| SEC-022 | Medium | Open | Catalog 2026-11-23: no app-table PUBLIC ALL; only `cron.*` (see §3). Part C: `USING (true)` scan |
| SEC-023 | Medium | Open | Privacy policy, consent logs, deletion SLA doc |
| SEC-024 | Medium | Open | Document risk acceptance or add pinning for prod gateway |
| SEC-025 | Medium | Done (committed, not deployed) | `allowBackup=false` + backup XML rules — fixed (Part B approved) |
| SEC-026 | Low | Open | Routine `npm audit fix` |
| SEC-027 | Low | Open | Pin actions to commit SHA |
| SEC-028 | Low | Open | Expected; ensure release not distributed from CI artifact |
| SEC-029 | Low | Done (committed, not deployed) | Same production startup guard as SEC-004 — fixed (Part B approved) |
| SEC-030 | Low | Open | Acceptable; avoid full mobile in logs |
| SEC-031 | Low | Maintain | Keep `false` in production |
| SEC-032 | Low | Open | Optional: enable IAM auth for operators |
| SEC-033 | Low | Open | Enable rotation for DB/JWT keys post-launch |
| SEC-034 | Info | Maintain | Keep enabled; add integration tests |
| SEC-035 | Info | Maintain | Maintain lockdown |
| SEC-036 | Info | Maintain | Maintain; PHI on S3 presigned only |
| SEC-037 | Info | Maintain | Keep |
| SEC-038 | Info | Maintain | Keep |
| SEC-039 | Info | Maintain | Maintain backups/MFA on restore |
| SEC-040 | Info | Open | Authenticator OK; RLS 68/69; health-table grant matrix not verified (Part C) |

---

*Report generated read-only. Request `fix SEC-xxx` in chat to implement individual remediations.*