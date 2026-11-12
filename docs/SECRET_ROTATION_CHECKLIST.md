# Secret rotation checklist

No history rewrite. Tick a line only after the old value is revoked and the new value is stored in Secret Manager or the vendor dashboard. Do not paste values into git, chat, or this file.

- [ ] MSG91 — rotated and old value revoked
- [ ] Razorpay — rotated and old value revoked
- [ ] CCAvenue — rotated and old value revoked
- [ ] AWS — rotated and old value revoked
- [ ] Redis — rotated and old value revoked
- [ ] Supabase — rotated and old value revoked
- [ ] Firebase keys — rotated and old value revoked

`.gitignore` still ignores `frontend/lib/firebase_options.secrets.dart`, `**/firebase_options.secrets.dart`, `baseline_functions.json`, `secrets.txt`, and `secrets*.txt`. `secrets.txt` must not be a tracked file (`git ls-files secrets.txt` is empty).
