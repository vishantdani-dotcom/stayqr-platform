-- ============================================================================
-- StayQR v1.0
-- Day 19 P0 Repair — Housekeeping Template Onboarding / Checkout Safety
--
-- PURPOSE
--   Close the Day 19F P0 defect where a newly onboarded hotel can reach
--   operational readiness without an active room-cleaning checklist template,
--   causing checkout_guest_session() to fail when it creates the mandatory
--   room-cleaning task.
--
-- SAFETY / BEHAVIOUR
--   - Transactional and idempotent.
--   - Does NOT replace or overwrite an existing active hotel-customized
--     room_cleaning template.
--   - Backfills a launch-safe eight-item default only for hotels missing an
--     active room_cleaning template.
--   - Installs a database-level AFTER INSERT hotels trigger so every future
--     tenant gets the mandatory baseline regardless of which hotel-creation
--     path is used.
--   - Private helper remains unavailable to browser roles.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202608101020:day19-housekeeping-template-onboarding-repair')
);

do $preflight$
begin
  if to_regclass('public.hotels') is null then
    raise exception 'Day19 repair stopped: public.hotels is missing.';
  end if;

  if to_regclass('public.housekeeping_checklist_templates') is null then
    raise exception
      'Day19 repair stopped: public.housekeeping_checklist_templates is missing.';
  end if;

  if to_regprocedure('private.day13_seed_housekeeping_items()') is null then
    raise exception
      'Day19 repair stopped: private.day13_seed_housekeeping_items() is missing.';
  end if;

  if not exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and tablename = 'housekeeping_checklist_templates'
      and indexname = 'uq_housekeeping_active_template_type'
  ) then
    raise exception
      'Day19 repair stopped: active housekeeping-template uniqueness index is missing.';
  end if;
end;
$preflight$;

create or replace function private.ensure_default_housekeeping_template(
  target_hotel_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  existing_template_id uuid;
  inserted_template_id uuid;
  next_version integer;
  default_items constant jsonb := jsonb_build_array(
    jsonb_build_object(
      'code', 'entry-security',
      'label', 'Door, lock and room entry checked',
      'sort_order', 10,
      'required', true
    ),
    jsonb_build_object(
      'code', 'bed-linen',
      'label', 'Bed made and linen refreshed',
      'sort_order', 20,
      'required', true
    ),
    jsonb_build_object(
      'code', 'bathroom',
      'label', 'Bathroom and fixtures cleaned',
      'sort_order', 30,
      'required', true
    ),
    jsonb_build_object(
      'code', 'surfaces-floor',
      'label', 'Surfaces dusted and floor cleaned',
      'sort_order', 40,
      'required', true
    ),
    jsonb_build_object(
      'code', 'towels-toiletries',
      'label', 'Towels and toiletries replenished',
      'sort_order', 50,
      'required', true
    ),
    jsonb_build_object(
      'code', 'water-amenities',
      'label', 'Drinking water and room amenities replenished',
      'sort_order', 60,
      'required', true
    ),
    jsonb_build_object(
      'code', 'waste-bins',
      'label', 'Waste removed and bins reset',
      'sort_order', 70,
      'required', true
    ),
    jsonb_build_object(
      'code', 'final-condition',
      'label', 'Final room condition checked',
      'sort_order', 80,
      'required', true
    )
  );
begin
  if target_hotel_id is null then
    raise exception 'Hotel id is required.';
  end if;

  perform 1
  from public.hotels h
  where h.id = target_hotel_id;

  if not found then
    raise exception 'Hotel % does not exist.', target_hotel_id;
  end if;

  select t.id
  into existing_template_id
  from public.housekeeping_checklist_templates t
  where t.hotel_id = target_hotel_id
    and t.task_type = 'room_cleaning'
    and t.is_active
  order by t.version desc, t.created_at desc, t.id
  limit 1;

  if existing_template_id is not null then
    return existing_template_id;
  end if;

  select coalesce(max(t.version), 0) + 1
  into next_version
  from public.housekeeping_checklist_templates t
  where t.hotel_id = target_hotel_id
    and t.code = 'standard-room-cleaning';

  begin
    insert into public.housekeeping_checklist_templates (
      hotel_id,
      code,
      name,
      task_type,
      version,
      items,
      is_active,
      created_by,
      updated_by
    )
    values (
      target_hotel_id,
      'standard-room-cleaning',
      'Standard Room Cleaning',
      'room_cleaning',
      next_version,
      default_items,
      true,
      null,
      null
    )
    returning id into inserted_template_id;

    return inserted_template_id;
  exception
    when unique_violation then
      select t.id
      into existing_template_id
      from public.housekeeping_checklist_templates t
      where t.hotel_id = target_hotel_id
        and t.task_type = 'room_cleaning'
        and t.is_active
      order by t.version desc, t.created_at desc, t.id
      limit 1;

      if existing_template_id is null then
        raise;
      end if;

      return existing_template_id;
  end;
end;
$function$;

revoke all on function
  private.ensure_default_housekeeping_template(uuid)
from public, anon, authenticated;

create or replace function private.seed_default_housekeeping_template_after_hotel_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform private.ensure_default_housekeeping_template(new.id);
  return new;
end;
$function$;

revoke all on function
  private.seed_default_housekeeping_template_after_hotel_insert()
from public, anon, authenticated;

drop trigger if exists
  hotels_day19_default_housekeeping_template
on public.hotels;

create trigger hotels_day19_default_housekeeping_template
after insert on public.hotels
for each row
execute function private.seed_default_housekeeping_template_after_hotel_insert();

do $backfill$
declare
  hotel_row record;
begin
  for hotel_row in
    select h.id
    from public.hotels h
    order by h.created_at, h.id
  loop
    perform private.ensure_default_housekeeping_template(hotel_row.id);
  end loop;
end;
$backfill$;

do $acceptance$
begin
  if exists (
    select 1
    from public.hotels h
    where not exists (
      select 1
      from public.housekeeping_checklist_templates t
      where t.hotel_id = h.id
        and t.task_type = 'room_cleaning'
        and t.is_active
    )
  ) then
    raise exception
      'Day19 repair acceptance failed: one or more hotels still lack an active room-cleaning template.';
  end if;

  if exists (
    select 1
    from public.hotels h
    where (
      select count(*)
      from public.housekeeping_checklist_templates t
      where t.hotel_id = h.id
        and t.task_type = 'room_cleaning'
        and t.is_active
    ) <> 1
  ) then
    raise exception
      'Day19 repair acceptance failed: active room-cleaning template uniqueness is not one per hotel.';
  end if;

  if exists (
    select 1
    from public.housekeeping_checklist_templates t
    where t.code = 'standard-room-cleaning'
      and t.is_active
      and jsonb_array_length(t.items) <> 8
  ) then
    raise exception
      'Day19 repair acceptance failed: a default room-cleaning template does not contain eight items.';
  end if;

  if not exists (
    select 1
    from pg_trigger
    where tgname = 'hotels_day19_default_housekeeping_template'
      and not tgisinternal
  ) then
    raise exception
      'Day19 repair acceptance failed: future-hotel template trigger is missing.';
  end if;
end;
$acceptance$;

commit;
