# Redis key catalog (generated)

Machine-assisted inventory from `backend/functions`. Keys are prefixed via `redisKey()` from `src/config/redis_keys.js` unless noted.

| Area | Key pattern | TTL |
|------|-------------|-----|
| Webhook dedupe | `webhook:dedupe:{sha256}` | 86400s (`EX`) |
| Abuse / rate limit | `ratelimit:{category}:{hash}` | windowMs via `PEXPIRE` |
| OTP mirror | see `registration_otp.js` | per-key `PEXPIRE` |
| S3 URL cache | see `s3_url_cache.js` | configurable |

Regenerate raw matches:

```powershell
rg "redisKey\(|setex|pexpire|expire\(" backend/functions --glob "!**/node_modules/**"
```
