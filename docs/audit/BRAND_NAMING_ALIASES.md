# DoctorNect / Medibond naming aliases

**Audit 3 (CQ-06)** — intentional identifiers vs user-facing branding.

| Surface | Identifier | Classification | Action |
|---------|------------|------------------|--------|
| Flutter package | `medibond` (`pubspec.yaml`) | Legacy technical package name | **Keep** — renaming breaks imports, stores, CI |
| Product / legal copy | DoctorNect | User-facing brand | **Keep** — primary brand in UI and legal |
| Firebase GCP project | `medibond-45fad` | Production technical ID | **Keep** — no migration in Audit 3 |
| Cloud Functions npm package | `medibond-functions` | Internal artifact name | **Keep** |
| Auth placeholder emails | `*@auth.doctornect.com`, `*@patient.doctornect.com` | Technical routing | **Keep** |
| Hosting URLs | `medibond-45fad.web.app` | Firebase default hostnames | **Keep** — CSP/connect-src allowlist |
| Public marketing domain | `doctornect.com` | User-facing web + deep links | **Configurable** via `PUBLIC_WEB_ORIGIN` (`app_web_urls.dart`) |
| Support email | `support@doctornect.com` | User-facing | **Keep** in `AppWebUrls.supportEmail` |

**Do not rename without migration plan:** Android/iOS bundle IDs, Supabase schema objects, AWS resource tags tied to `medibond`, Firebase function export names, stored deep links in production SMS.

**Documentation rule:** Audit reports and operator docs should say **DoctorNect (package: medibond)** on first mention where confusion is likely.