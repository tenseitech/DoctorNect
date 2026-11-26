# Audit 9 — Remediation Checklist

Branch: `audit9/ui-ux-accessibility`  
Base commit: `69b668192f5600b147d5f7e2fa48efbc5e46d64c`

| ID | Severity | Summary | Status | Tested | Verified |
|----|----------|---------|--------|--------|----------|
| UX-01 | P1 | Theme-level minimum 48×48 dp for icon/text buttons | FIXED | YES | YES (unit) |
| UX-02 | P1 | `ThemeToggleButton` used 44×44 constraints | FIXED | YES | YES (widget) |
| UX-03 | P1 | Booking flow AppBar back missing tooltip/semantics | FIXED | YES | PARTIAL |
| UX-04 | P1 | Create promoted ad back missing tooltip/semantics | FIXED | NO | PARTIAL |
| UX-05 | P2 | Notification bell missing tooltip/semantics; 44 dp | FIXED | NO | PARTIAL |
| UX-06 | P2 | Partner disconnect control 44 dp | FIXED | NO | PARTIAL |
| UX-07 | P2 | `RoleEmptyState` not announced to assistive tech | FIXED | YES | YES (widget) |
| UX-08 | P2 | Light theme lacked dialog/bottom sheet parity with dark | FIXED | YES | YES (unit) |
| UX-09 | P2 | Floating snackbars not consistent app-wide | FIXED | YES | YES (unit) |
| UX-10 | P2 | Shared `AccessibleIconButton` for icon-only controls | FIXED | YES | YES (widget) |
| UX-11 | P3 | ~70+ raw `IconButton` usages without shared wrapper | OPEN | — | — |
| UX-12 | P3 | Repo-wide `Semantics` coverage still low | PARTIALLY FIXED | — | — |
| UX-13 | INFO | `main.dart` text scaler clamp 0.9–1.3 | ACCEPTED RISK | — | — |
| UX-14 | INFO | `ResponsiveLayout` breakpoints present | VERIFIED | — | STATIC |
| UX-15 | INFO | Auth flows use `SingleChildScrollView` | VERIFIED | — | STATIC |
| UX-16 | P2 | Contrast not validated on all accent/secondary pairs | OPEN | — | — |
| UX-17 | — | Screen reader on-device validation | BLOCKED BY ENVIRONMENT | — | — |
| UX-18 | — | Multi-device responsive manual pass | BLOCKED BY ENVIRONMENT | — | — |
| UX-19 | — | Web keyboard/hover manual pass | BLOCKED BY ENVIRONMENT | — | — |
| UX-20 | — | Audit 4 database/infrastructure | ON HOLD (untouched) | — | — |