# StayQR Final Notification Closure REV11

## Purpose
REV11 closes the remaining launch-blocking notification UI defect without reopening completed product modules.

## Scope
- Removes corrupted/mojibake text-based notification glyphs.
- Uses SVG category icons for payments, food orders, service requests, reservations, housekeeping, maintenance, guest stays, invoices, rooms and support.
- Keeps unread badge/count synchronized with the trusted notification inbox.
- Makes both unread and already-read notifications actionable.
- Routes a notification to the relevant StayQR workspace where a safe destination is known.
- Limits the top-bar popup to the ten most recent items; the full history stays in Notification Centre.
- Adds visible retry/error handling for inbox operations.
- Improves read/unread hierarchy and mobile notification-drawer behaviour.
- Cleans the full Notification Centre card UI and removes technical event-key text from the receptionist-facing feed.

## Explicitly unchanged
- Notification database/outbox architecture.
- RLS and recipient-level inbox rules.
- Notification templates and delivery engine.
- Meta WhatsApp provider configuration.
- Cashfree configuration.
- Production environment.

## Launch policy
Meta automated campaigns, Cashfree AutoPay and formal online UIDAI provider authentication remain on hold/upcoming for the initial commercial launch.

## Acceptance
Required source gates:
- Day 17 final notification/security source gate PASS.
- REV9 Final Freeze PASS.
- REV10 Launch Corrections PASS.
- REV11 Notification Closure 24/24 PASS.
- REV11 Release Closure 15/15 PASS.
- Responsive Platform 77/77 PASS.
- Mobile UI 16/16 PASS.
- Relative imports PASS.
- ESLint PASS on the user's authoritative repo.
- Production build PASS on the user's authoritative repo.

Browser acceptance after staging deploy:
1. No corrupted characters in icons/footer.
2. Unread count is correct and capped at 9+ in the top-bar badge.
3. Mark all as read works and clears unread state.
4. Payment notification opens Payments.
5. Service request opens Service Requests.
6. Food order opens Food Orders.
7. View all notifications opens Notification Centre.
8. Mobile notification drawer is usable with no clipping/overflow.
9. Hotel switch does not leak the previous hotel's notifications.
