-- StayQR v1.1 Post-Launch Batch B
-- Migration 086 — Super Admin Guest Guide QR Scan Metrics
--
-- Staging first. Additive extension only.
--
-- Metric semantics:
--   guest_guide_qr_scans_total  = count of recorded guest-guide `guide_opened` events.
--   guest_guide_qr_scans_unique = distinct signed guest-access tokens that recorded
--                                 at least one `guide_opened` event.
--
-- This intentionally uses StayQR's existing guest_guide_events telemetry instead
-- of treating token resolutions, page refreshes, or API calls as physical QR scans.

create or replace function public.get_postlaunch_batch2_platform_metrics()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_platform_admin() then
    raise exception 'Platform administrator access is required.';
  end if;

  return jsonb_build_object(
    'active_hotels', (select count(*) from public.hotels where status = 'active'),
    'total_guests', (select count(*) from public.guests),
    'active_stays', (select count(*) from public.guest_sessions where status = 'active'),
    'document_scans', (select count(*) from public.guest_documents where deleted_at is null),
    'reservations', (select count(*) from public.reservations),
    'rooms', (select count(*) from public.rooms where is_active is true),
    'staff', (select count(*) from public.staff),
    'guest_guide_qr_scans_total', (
      select count(*)
      from public.guest_guide_events
      where event_type = 'guide_opened'
    ),
    'guest_guide_qr_scans_unique', (
      select count(distinct guest_access_token_id)
      from public.guest_guide_events
      where event_type = 'guide_opened'
        and guest_access_token_id is not null
    )
  );
end;
$$;

revoke all on function public.get_postlaunch_batch2_platform_metrics() from public;
grant execute on function public.get_postlaunch_batch2_platform_metrics() to authenticated;
