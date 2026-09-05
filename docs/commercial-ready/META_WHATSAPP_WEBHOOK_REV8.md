# StayQR Meta WhatsApp Webhook REV8

## Purpose

Close the remaining software-side webhook reliability boundary before real Meta Cloud activation.

REV8 makes a signed Meta delivery callback fail-closed and transactionally durable:

- Meta `x-hub-signature-256` is verified against the exact raw request body before service-role access.
- Delivery state changes are delegated to one service-role-only database RPC.
- Recipient state and delivery-event evidence persist inside the same PostgreSQL transaction.
- A late `failed` callback cannot downgrade `sent`, `delivered` or `read`.
- A lower-rank `sent`/`delivered` callback cannot downgrade a later successful state.
- A failed provider message id is terminal; a retry receives a new provider message id.
- Duplicate callbacks are idempotent.
- Unknown provider message ids are safely acknowledged without mutating another hotel/guest.
- Any matched persistence error returns HTTP 503 so Meta can retry; HTTP 200 is returned only after all matched writes succeed.
- Raw provider error strings are not persisted from the webhook.

## Staging sequence

1. Apply Migration 114 plus the acceptance query to StayQR Staging only.
2. Require 12/12 PASS.
3. Deploy only `whatsapp-status-webhook` to staging.
4. Keep `WHATSAPP_AUTOMATION_ENABLED=false` until real Meta credentials, approved template and sender readiness are configured.
5. Production remains untouched until explicit rollout authorization.

## External dependency after REV8

Real Meta Cloud end-to-end acceptance still requires the approved StayQR WABA/number, app secret, access token, webhook verify token, Graph API version, approved template and provider readiness evidence. REV8 does not invent or expose those secrets.
