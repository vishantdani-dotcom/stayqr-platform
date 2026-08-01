# Day 7 exact source audit

## Audited source

Day 6 locked branch source uploaded as `StayQR_Day7_Current_Source.zip`.

The archive contained the completed Day 6 migrations, audits, Edge Function, frontend tenant context and no `.env`, `.git`, `dist`, `node_modules` or Supabase temporary link directory.

## Security-critical findings

1. **Guest URLs used public room numbers.** `GuestGuide.jsx`, `FoodMenu.jsx` and `QRGenerator.jsx` resolved `/guest/{roomNumber}` and `/food/{roomNumber}` by reading `rooms` and `guest_sessions` anonymously.
2. **Guest pages directly queried and modified production tables.** Anonymous browser code could read guest sessions, guest service requests, menu items and food orders, and insert service requests, notifications, food orders and order items.
3. **The original tenant migration deliberately preserved anonymous compatibility.** Day 1 explicitly excluded rooms, guests, guest sessions, hotel information, menus, food orders, service requests and notifications until signed guest access existed.
4. **Room-number guessing was therefore a valid discovery path.** A room number was both the public identifier and the access locator; no signed secret, stay binding, expiry, rotation or revocation was required.
5. **Guest realtime subscriptions depended on direct table visibility.** Service-request and food-order channels were scoped by guest UUID after the UUID had already been disclosed by the anonymous session query.
6. **QR creation sent the complete guest URL to a third-party QR image endpoint.** This is incompatible with secret-bearing guest tokens, so Stage 1 removes that token disclosure path and exposes secure link controls without remote QR rendering.
7. **Fixed hotel-profile fallbacks remained.** A production phone number and default Wi-Fi/stay values could appear for a hotel that had not configured its own profile.
8. **Supabase Storage had no StayQR bucket policy foundation.** The source had no hotel-folder-scoped private bucket policies.
9. **Authenticated tenant context was already substantially improved.** Day 6 had removed browser-selected global tenant state, linked staff identities to Supabase Auth, and added permission-aware RLS for reservation and financial modules. Day 7 builds on those helpers rather than replacing them.

## Stage 1 corrections

- Signed HMAC guest access token metadata bound to exactly one hotel, room and active guest session.
- Automatic issuance for active stays and automatic invalidation on checkout, expiry, reassignment or session changes.
- Hotel-slug plus opaque signed-token guest routes.
- Authenticated token rotation and revocation controls.
- Six narrowly granted guest RPCs; anonymous direct table access removed.
- Atomic, server-priced food ordering and server-validated service requests.
- Authenticated-only RLS for every former guest compatibility table.
- Private `hotel-assets` and `guest-documents` Storage buckets with hotel-folder policies.
- No fixed hotel identity, phone, Wi-Fi or stay-time fallback in the frontend.
- `Referrer-Policy: no-referrer` to reduce guest token leakage.

## Stage boundary

This package is the **Day 7 Stage 1 foundation**, not the Day 7 final lock. After migration and Audit 037 pass, browser acceptance must prove valid-token access, room-number rejection, tampered-token rejection, rotation, revocation, checkout invalidation and Hotel A/Hotel B isolation. Local QR image rendering and final automated isolation/cleanup gates follow in the next controlled stage.
