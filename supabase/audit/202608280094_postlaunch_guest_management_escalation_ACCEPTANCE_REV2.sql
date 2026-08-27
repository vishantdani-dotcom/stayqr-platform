-- ============================================================================
-- StayQR Post-Launch Stabilization
-- Audit 094 — Guest Management Escalation Repair Acceptance REV2
-- READ ONLY
-- Expected: 10/10 TRUE
-- ============================================================================

with apex as (
  select h.id, h.slug
  from public.hotels h
  where h.slug = 'hotel-apex-stay-inn'
  limit 1
),
tests as (
  select 1 seq, 'management_escalation_rpc_path_present'::text check_name,
    to_regprocedure('public.create_guest_service_request(text,text,text)') is not null passed,
    'Existing signed guest-service RPC remains installed.'::text details

  union all
  select 2, 'every_hotel_has_exactly_one_management_type',
    not exists (
      select 1
      from public.hotels h
      where (
        select count(*)
        from public.service_request_types srt
        where srt.hotel_id = h.id
          and lower(trim(srt.name)) = 'management escalation'
      ) <> 1
    ),
    format('%s hotel(s) checked.', (select count(*) from public.hotels))

  union all
  select 3, 'management_type_active_guest_visible',
    not exists (
      select 1 from public.service_request_types srt
      where lower(trim(srt.name)) = 'management escalation'
        and (not srt.is_active or not srt.guest_visible)
    ),
    'All Management Escalation rows are active and guest-visible.'

  union all
  select 4, 'management_department_routing',
    not exists (
      select 1 from public.service_request_types srt
      where lower(trim(srt.name)) = 'management escalation'
        and srt.department <> 'management'
    ),
    'Management Escalation routes to management.'

  union all
  select 5, 'management_priority_urgent',
    not exists (
      select 1 from public.service_request_types srt
      where lower(trim(srt.name)) = 'management escalation'
        and srt.default_priority <> 'urgent'
    ),
    'Management Escalation defaults to urgent priority.'

  union all
  select 6, 'management_sla_configured',
    not exists (
      select 1 from public.service_request_types srt
      where lower(trim(srt.name)) = 'management escalation'
        and (
          srt.default_estimated_minutes is null
          or srt.sla_minutes is null
          or srt.escalation_minutes is null
          or srt.default_estimated_minutes <= 0
          or srt.sla_minutes <= 0
          or srt.escalation_minutes < 0
        )
    ),
    'ETA, SLA and escalation timing are configured.'

  union all
  select 7, 'management_escalation_non_chargeable_contract',
    not exists (
      select 1 from public.service_request_types srt
      where lower(trim(srt.name)) = 'management escalation'
        and (
          srt.charge_enabled
          or srt.default_charge_amount is not null
        )
    ),
    'Non-chargeable contract: charge_enabled=false and default_charge_amount=NULL.'

  union all
  select 8, 'apex_management_escalation_ready',
    exists (
      select 1
      from apex h
      join public.service_request_types srt on srt.hotel_id = h.id
      where lower(trim(srt.name)) = 'management escalation'
        and lower(trim(srt.code)) = 'management_escalation'
        and srt.department = 'management'
        and srt.default_priority = 'urgent'
        and srt.guest_visible
        and srt.is_active
        and not srt.charge_enabled
        and srt.default_charge_amount is null
    ),
    coalesce((select slug from apex), 'Hotel Apex Stay Inn not found')

  union all
  select 9, 'future_hotel_seed_trigger_present',
    exists (
      select 1
      from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = 'hotels'
        and t.tgname = 'trg_seed_management_escalation_after_hotel_insert'
        and not t.tgisinternal
    ),
    'Future hotels automatically receive the Management Escalation type.'

  union all
  select 10, 'no_duplicate_management_catalogue_rows',
    not exists (
      select 1
      from public.service_request_types srt
      where lower(trim(srt.name)) = 'management escalation'
         or lower(trim(srt.code)) in (
           'management_escalation',
           'management-escalation',
           'management escalation'
         )
      group by srt.hotel_id
      having count(*) <> 1
    ),
    'No hotel has an ambiguous duplicate Management Escalation catalogue row.'
)
select seq, check_name, passed, details
from tests
order by seq;
