# Ambulance drivers on real accounts (H3 option b) - design and migration plan

Status: design + off-by-default server groundwork only. The app still signs ambulance drivers in
anonymously, and the demo-plane marker (D1 a, `scripts/lib/demo_plane_marker.js`) keeps the demo
ambulance on staging. Do not start this before the first green production deploy.

## Why

Today an ambulance driver gets a fresh anonymous Firebase user per device. `ambulances.auth_uid`
is rebound to that uid at every OTP login (`completeAmbulanceMobileOtpLogin`). Consequences:
- the uid is not the account: logging in on a second phone silently takes the vehicle away from
  the first; nothing ties audit logs, push tokens or deletion to one stable identity;
- demo routing needs a special marker (D1 a) instead of the fixed uid allowlist;
- every other role already uses the account owner uid (`users.id`) via a custom token.

## Target

The driver signs in exactly like the other roles: phone OTP -> `verifyUserRegistrationOtp` mints a
custom token for the ambulance account owner (`users.id`, role `ambulance`, `profile_id` =
`ambulance_id`) -> `signInWithCustomToken`. The PIN stays as a quick re-login / second factor on the
same account. The demo ambulance becomes `rev_fb_amb_001` like the other demo accounts; the marker
is removed.

## What already exists

- `verifyUserRegistrationOtp` already returns `customToken` + `role: 'ambulance'` for an existing
  ambulance account (see `npm run test:demo-login`, 9999900005 -> `rev_fb_amb_001`).
- RLS: `ambulances_update` already allows `ambulance_id = private.current_profile_id()` (the owner
  account); `ambulances_select` allows `auth_uid = private.current_user_id()`.
- Gateway and Functions route the five demo uids to staging by uid.

## Changes, in rollout order

1. **Server groundwork (done, OFF):** `backend/functions/ambulance_session.js`:
   `AMBULANCE_REAL_ACCOUNT_SIGNIN = false` and `classifyAmbulanceSession(auth, ownerUid)` ->
   `anonymous` | `owner` | `other`. Tests in `test/ambulance_session.test.js`.
2. **Functions (flip the constant):** `completeAmbulanceMobileOtpLogin` accepts an `owner` session
   (caller uid = `users.id` of the account whose `profile_id` is the ambulance) without rewriting
   `ambulances.auth_uid`; `anonymous` keeps today's behaviour for old app builds; `other` (a signed-in
   account that does not own the ambulance) is refused. `verifyAmbulanceDriverLogin` (PIN) follows the
   same rule. All ambulance callables use `getDatabaseClientForCallable` (uid routing).
3. **Database (new migration, then SQL tests):** `ambulances.owner_uid` (FK `users.id`), backfilled
   from `users.profile_id`; policies `ambulances_select/update`, `ambulance_locations`,
   `ambulance_broadcasts` accept `owner_uid = private.current_user_id()` OR the old `auth_uid` rule.
   Index `owner_uid`. Keep `auth_uid` for one release.
4. **Client:** sign in with the custom token from the verify response (like
   `_completeLoginAfterVerifiedOtp`), remove the anonymous requirement in `AmbulanceAuthHelper`,
   `role_session_guard.dart`, `ambulance_shell.dart` and the ~15 `ensureSignedIn` call sites; keep the
   PIN screen. Ship behind a client flag defaulting to the anonymous path for one release.
5. **Gateway:** nothing to change (uid routing); keep the marker branch until no app build older than
   step 4 is in use, then delete it.
6. **Cleanup release:** drop the anonymous path, the marker (`demo_plane_marker.js` in three places
   and its tests), `ambulances.auth_uid` policies, and `resyncAmbulanceAuthUid`.

## Tests to add with each step

- Functions: owner session accepted without auth_uid rewrite; other account refused; anonymous path
  unchanged; demo ambulance owner `rev_fb_amb_001` -> staging plane without a marker.
- SQL (`db/tests`): owner_uid policies for select/update/location/broadcast; another provider and a
  patient cannot read or move the vehicle; backfill is idempotent.
- Gateway E2E: owner uid -> RDS; `rev_fb_amb_001` -> demo upstream.
- Flutter: login flow signs in with the custom token; ambulance shell works with a non-anonymous user.
- Phone: 9999900005 logs in, sees the dashboard, toggles availability.

## Rollback

Each step is independent: set the constant / client flag back, the old anonymous path keeps working
until the cleanup release.
