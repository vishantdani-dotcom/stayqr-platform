# StayQR Batch B — Super Admin Guest Guide QR Scan Metric REV1

## Existing telemetry used
StayQR already has `public.guest_guide_events` with the event type
`guide_opened`, plus `hotel_id`, `guest_session_id`, and
`guest_access_token_id`.

## Metric semantics
- **Guest guide QR scans**: total `guide_opened` events.
- **Unique guest access links**: distinct signed guest-access tokens with at
  least one `guide_opened` event.

This avoids using `guest_access_tokens.use_count`, which also increases during
token resolution/API usage and therefore is not a clean scan/open metric.

## Security
The existing `get_postlaunch_batch2_platform_metrics()` RPC remains protected by
`private.is_platform_admin()`.

## Production
Staging first. Do not apply to production until the v1.1 release gates approve it.
