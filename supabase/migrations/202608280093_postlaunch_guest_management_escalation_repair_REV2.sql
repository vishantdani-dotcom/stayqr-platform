-- ============================================================================
-- StayQR Post-Launch Stabilization
-- Migration 093 — Guest Management Escalation Catalogue Repair REV2
-- Date: 2026-08-28
--
-- REV2 FIX
-- For non-chargeable service types, StayQR's schema requires
-- default_charge_amount IS NULL. REV1 attempted 0.00 and was correctly rejected
-- by service_request_types_charge_amount_check.
--
-- PURPOSE
-- Fix the Guest Guide "Escalate to hotel management" CTA by ensuring every
-- hotel has exactly one active, guest-visible Management Escalation request
-- type routed to management with urgent priority.
--
-- SAFETY
-- - Forward-only and idempotent.
-- - No guest/reservation/folio/invoice data is edited.
-- - Existing matching catalogue rows are normalized rather than duplicated.
-- - Ambiguous duplicate matching rows abort the transaction.
-- - Future hotels are provisioned automatically.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '60s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202608280093:guest-management-escalation-repair-rev2')
);

do $preflight$
declare
  v_missing text;
begin
  if to_regclass('public.hotels') is null then
    raise exception 'Migration 093 REV2: public.hotels is missing.';
  end if;

  if to_regclass('public.service_request_types') is null then
    raise exception 'Migration 093 REV2: public.service_request_types is missing.';
  end if;

  if to_regprocedure('public.create_guest_service_request(text,text,text)') is null then
    raise exception 'Migration 093 REV2: create_guest_service_request(text,text,text) is missing.';
  end if;

  select string_agg(c.column_name, ', ' order by c.column_name)
  into v_missing
  from (
    values
      ('hotel_id'),('name'),('code'),('description'),('department'),
      ('default_priority'),('default_estimated_minutes'),('guest_visible'),
      ('is_active'),('sort_order'),('sla_minutes'),('escalation_minutes'),
      ('charge_enabled'),('default_charge_amount'),('updated_at')
  ) c(column_name)
  where not exists (
    select 1
    from information_schema.columns ic
    where ic.table_schema = 'public'
      and ic.table_name = 'service_request_types'
      and ic.column_name = c.column_name
  );

  if v_missing is not null then
    raise exception
      'Migration 093 REV2: service_request_types missing required column(s): %',
      v_missing;
  end if;
end;
$preflight$;

do $duplicate_guard$
declare
  v_problem text;
begin
  select string_agg(
    format('%s (%s matching rows)', h.slug, x.match_count),
    ', ' order by h.slug
  )
  into v_problem
  from public.hotels h
  join lateral (
    select count(*)::int as match_count
    from public.service_request_types srt
    where srt.hotel_id = h.id
      and (
        lower(trim(srt.name)) = 'management escalation'
        or lower(trim(srt.code)) in (
          'management_escalation',
          'management-escalation',
          'management escalation'
        )
      )
  ) x on true
  where x.match_count > 1;

  if v_problem is not null then
    raise exception
      'Migration 093 REV2: ambiguous Management Escalation catalogue rows: %',
      v_problem;
  end if;
end;
$duplicate_guard$;

create or replace function private.ensure_management_escalation_request_type(
  p_hotel_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_type_id uuid;
begin
  if p_hotel_id is null then
    raise exception 'Hotel is required.';
  end if;

  if not exists (
    select 1
    from public.hotels h
    where h.id = p_hotel_id
  ) then
    raise exception 'Hotel does not exist.';
  end if;

  select srt.id
  into v_type_id
  from public.service_request_types srt
  where srt.hotel_id = p_hotel_id
    and (
      lower(trim(srt.name)) = 'management escalation'
      or lower(trim(srt.code)) in (
        'management_escalation',
        'management-escalation',
        'management escalation'
      )
    )
  order by
    case when lower(trim(srt.name)) = 'management escalation' then 0 else 1 end,
    srt.created_at nulls last,
    srt.id
  limit 1;

  if v_type_id is null then
    insert into public.service_request_types (
      hotel_id,
      name,
      code,
      description,
      department,
      default_priority,
      default_estimated_minutes,
      guest_visible,
      is_active,
      sort_order,
      sla_minutes,
      escalation_minutes,
      charge_enabled,
      default_charge_amount,
      created_at,
      updated_at
    ) values (
      p_hotel_id,
      'Management Escalation',
      'management_escalation',
      'Escalate a service or staff concern directly to hotel management.',
      'management',
      'urgent',
      10,
      true,
      true,
      5,
      10,
      5,
      false,
      null,
      now(),
      now()
    )
    returning id into v_type_id;
  else
    update public.service_request_types
    set
      name = 'Management Escalation',
      code = 'management_escalation',
      description =
        'Escalate a service or staff concern directly to hotel management.',
      department = 'management',
      default_priority = 'urgent',
      default_estimated_minutes = 10,
      guest_visible = true,
      is_active = true,
      sort_order = 5,
      sla_minutes = 10,
      escalation_minutes = 5,
      charge_enabled = false,
      default_charge_amount = null,
      updated_at = now()
    where id = v_type_id
      and hotel_id = p_hotel_id;
  end if;

  return v_type_id;
end;
$function$;

revoke all on function
  private.ensure_management_escalation_request_type(uuid)
from public, anon, authenticated;

do $backfill$
declare
  v_hotel record;
begin
  for v_hotel in
    select h.id
    from public.hotels h
    order by h.created_at, h.id
  loop
    perform private.ensure_management_escalation_request_type(v_hotel.id);
  end loop;
end;
$backfill$;

create or replace function private.seed_management_escalation_after_hotel_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $trigger$
begin
  perform private.ensure_management_escalation_request_type(new.id);
  return new;
end;
$trigger$;

revoke all on function
  private.seed_management_escalation_after_hotel_insert()
from public, anon, authenticated;

drop trigger if exists
  trg_seed_management_escalation_after_hotel_insert
on public.hotels;

create trigger trg_seed_management_escalation_after_hotel_insert
after insert on public.hotels
for each row
execute function private.seed_management_escalation_after_hotel_insert();

do $final_guard$
declare
  v_bad_count integer;
begin
  select count(*)::int
  into v_bad_count
  from public.hotels h
  where (
    select count(*)
    from public.service_request_types srt
    where srt.hotel_id = h.id
      and lower(trim(srt.name)) = 'management escalation'
      and lower(trim(srt.code)) = 'management_escalation'
      and srt.department = 'management'
      and srt.default_priority = 'urgent'
      and srt.guest_visible
      and srt.is_active
      and not srt.charge_enabled
      and srt.default_charge_amount is null
  ) <> 1;

  if v_bad_count <> 0 then
    raise exception
      'Migration 093 REV2: % hotel(s) failed final Management Escalation invariant.',
      v_bad_count;
  end if;
end;
$final_guard$;

commit;
