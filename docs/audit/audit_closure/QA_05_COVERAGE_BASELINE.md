# QA-05 — Flutter coverage baseline

**Measured:** 2026-11-27 (`flutter test --coverage` on `audit-closure/remaining-audits`)

| Metric | Value |
|--------|------:|
| Scope | `frontend/lib` |
| Lines found | 62,631 |
| Lines hit | 16,440 |
| **Line %** | **26.25% |
| CI gate (`FLUTTER_COVERAGE_MIN_LINES`) | **26** |

Gate script: `scripts/audit_closure/flutter_coverage_gate.js`

Goal: raise baseline over time; do not lower threshold without measured regression review.