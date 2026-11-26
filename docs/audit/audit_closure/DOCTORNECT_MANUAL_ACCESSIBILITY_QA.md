# Manual accessibility QA matrix (Audit 9)

Execute on staging or local release builds with **test accounts only**.

## Android — TalkBack

| # | Screen | Steps | Pass criteria |
|---|--------|-------|---------------|
| 1 | Welcome | Swipe through roles | Each role announced |
| 2 | Auth back | Activate back control | Returns; label "Back" |
| 3 | Booking flow | Open book appointment | Back + step header readable |
| 4 | Notifications | Open bell | Unread count in label |
| 5 | Logout | Focus logout control | "Log out" action |

## iOS — VoiceOver

Repeat table above.

## Keyboard (Web/desktop)

| # | Flow | Keys | Pass |
|---|------|------|------|
| 1 | Auth layout | Tab to back, Enter | Navigates back |
| 2 | Theme toggle | Focus visible | 48dp target |
| 3 | Modal dialog | Esc / focus trap | No focus escape to void |

## Text scaling

System font 1.3x — verify auth and booking without clipping (known clamp 0.9–1.3 in app).

Record: device, OS, build SHA, pass/fail per row. Attach to `DOCTORNECT_FINAL_AUDIT_EVIDENCE.md`.