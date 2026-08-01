-- ============================================================================
-- StayQR v1.0
-- Day 8 Audit 043 REV2 — Hotel Onboarding and Configuration Preflight
--
-- PURPOSE
-- Read-only production preflight before Day 8 schema changes.
-- It inventories the exact current state needed for:
--   hotel registration, resumable onboarding, hotel configuration,
--   room types/floors/rates, bulk room import, amenities, request categories,
--   menu defaults, invoice numbering, QR readiness and trial activation.
--
-- SAFETY
-- - Run once in Supabase SQL Editor with role: postgres.
-- - Reads metadata and aggregate counts only.
-- - Does not insert, update or delete business data.
-- - Installs one private audit helper, executable only by postgres.
--
-- REV2 FIX
-- The function returns a column named `status`. In PL/pgSQL that output column
-- is also a variable, so unqualified source-table references such as
-- `where status = 'active'` became ambiguous. REV2 qualifies every such
-- reference with its table alias.
--
-- EXPECTED
-- 32 diagnostic rows.
-- READY = existing foundation is usable.
-- GAP   = Day 8 must create or complete this capability.
-- RISK  = existing data must be repaired before onboarding can be locked.
-- INFO  = inventory only.
-- ============================================================================

create or replace function private.run_day8_onboarding_preflight_20260727()
returns table (
  check_name text,
  status text,
  details text
)
language plpgsql
security invoker
set search_path = ''
as $audit$
declare
  hotel_count bigint := 0;
  active_hotel_count bigint := 0;
  platform_admin_count bigint := 0;
  active_owner_count bigint := 0;
  invalid_hotel_metadata bigint := 0;
  duplicate_slug_groups bigint := 0;
  duplicate_room_groups bigint := 0;
  rooms_without_room_type bigint := 0;
  room_types_without_rate bigint := 0;
  hotels_without_info bigint := 0;
  hotels_with_multiple_info bigint := 0;
  hotels_without_subscription bigint := 0;
  hotels_with_multiple_current_subscriptions bigint := 0;
  invalid_subscription_dates bigint := 0;
  active_plan_count bigint := 0;
  room_count bigint := 0;
  room_type_count bigint := 0;
  rate_plan_count bigint := 0;
  menu_category_count bigint := 0;
  menu_item_count bigint := 0;
  guest_token_count bigint := 0;
  tenant_tables_without_rls bigint := 0;
  tenant_tables_without_policy bigint := 0;
  table_exists boolean;
  column_exists boolean;
  function_exists boolean;
  results jsonb := '[]'::jsonb;
begin
  select count(*), count(*) filter (where h.status = 'active')
  into hotel_count, active_hotel_count
  from public.hotels h;

  select count(*)
  into platform_admin_count
  from public.platform_admins pa
  where pa.status = 'active';

  select count(*)
  into active_owner_count
  from public.staff s
  where s.status = 'active'
    and s.auth_user_id is not null
    and lower(replace(trim(s.role::text), ' ', '_')) = 'owner';

  select count(*)
  into invalid_hotel_metadata
  from public.hotels h
  where nullif(trim(h.hotel_name), '') is null
     or nullif(trim(h.slug), '') is null
     or nullif(trim(h.timezone), '') is null
     or h.currency_code !~ '^[A-Z]{3}$'
     or h.status not in ('active', 'suspended', 'inactive', 'archived')
     or h.subscription_status not in (
       'trial', 'trialing', 'active', 'past_due',
       'suspended', 'cancelled', 'expired'
     );

  select count(*)
  into duplicate_slug_groups
  from (
    select lower(slug)
    from public.hotels
    group by lower(slug)
    having count(*) > 1
  ) duplicate_slugs;

  select count(*)
  into duplicate_room_groups
  from (
    select hotel_id, lower(trim(room_number))
    from public.rooms
    group by hotel_id, lower(trim(room_number))
    having count(*) > 1
  ) duplicate_rooms;

  select count(*)
  into rooms_without_room_type
  from public.rooms
  where room_type_id is null;

  select count(*)
  into room_types_without_rate
  from public.room_types rt
  where rt.is_active
    and not exists (
      select 1
      from public.rate_plans rp
      where rp.hotel_id = rt.hotel_id
        and rp.room_type_id = rt.id
        and rp.is_active
    );

  select count(*)
  into hotels_without_info
  from public.hotels h
  where not exists (
    select 1
    from public.hotel_info hi
    where hi.hotel_id = h.id
  );

  select count(*)
  into hotels_with_multiple_info
  from (
    select hotel_id
    from public.hotel_info
    group by hotel_id
    having count(*) > 1
  ) repeated_info;

  select count(*)
  into hotels_without_subscription
  from public.hotels h
  where not exists (
    select 1
    from public.hotel_subscriptions hs
    where hs.hotel_id = h.id
      and hs.status in ('trial', 'trialing', 'active', 'past_due', 'suspended')
  );

  select count(*)
  into hotels_with_multiple_current_subscriptions
  from (
    select hotel_id
    from public.hotel_subscriptions hs
    where hs.status in ('trial', 'trialing', 'active', 'past_due', 'suspended')
    group by hotel_id
    having count(*) > 1
  ) repeated_current_subscription;

  select count(*)
  into invalid_subscription_dates
  from public.hotel_subscriptions
  where end_date is not null
    and start_date is not null
    and end_date <= start_date;

  select count(*)
  into active_plan_count
  from public.subscription_plans sp
  where sp.status = 'active';

  select count(*) into room_count from public.rooms;
  select count(*) into room_type_count from public.room_types;
  select count(*) into rate_plan_count from public.rate_plans;
  select count(*) into menu_category_count from public.menu_categories;
  select count(*) into menu_item_count from public.menu_items;

  if to_regclass('public.guest_access_tokens') is not null then
    execute 'select count(*) from public.guest_access_tokens'
    into guest_token_count;
  end if;

  select count(*)
  into tenant_tables_without_rls
  from information_schema.columns col
  join pg_class c on c.relname = col.table_name
  join pg_namespace n
    on n.oid = c.relnamespace
   and n.nspname = col.table_schema
  where col.table_schema = 'public'
    and col.column_name = 'hotel_id'
    and c.relkind in ('r', 'p')
    and not c.relrowsecurity;

  select count(*)
  into tenant_tables_without_policy
  from (
    select distinct col.table_name
    from information_schema.columns col
    where col.table_schema = 'public'
      and col.column_name = 'hotel_id'
  ) tenant_table
  where not exists (
    select 1
    from pg_policies p
    where p.schemaname = 'public'
      and p.tablename = tenant_table.table_name
  );

  -- 01–05: baseline and identity.
  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '01_locked_day7_tenant_foundation',
    'status', case
      when tenant_tables_without_rls = 0 and tenant_tables_without_policy = 0
        then 'READY' else 'RISK' end,
    'details', format(
      'Tenant tables without RLS=%s; without any policy=%s.',
      tenant_tables_without_rls,
      tenant_tables_without_policy
    )
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '02_existing_hotels_inventory',
    'status', 'INFO',
    'details', format(
      'Hotels=%s; active=%s.',
      hotel_count,
      active_hotel_count
    )
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '03_platform_admin_identity',
    'status', case when platform_admin_count >= 1 then 'READY' else 'RISK' end,
    'details', format('Active Platform Admin identities=%s.', platform_admin_count)
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '04_active_hotel_owner_identity',
    'status', case when active_owner_count >= 1 then 'READY' else 'GAP' end,
    'details', format(
      'Active staff rows with role owner and a linked Auth user=%s.',
      active_owner_count
    )
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '05_hotel_tenant_metadata',
    'status', case when invalid_hotel_metadata = 0 then 'READY' else 'RISK' end,
    'details', format(
      'Hotels with invalid name/slug/timezone/currency/status metadata=%s.',
      invalid_hotel_metadata
    )
  ));

  -- 06–11: hotel identity and onboarding state.
  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '06_unique_hotel_slug',
    'status', case when duplicate_slug_groups = 0 then 'READY' else 'RISK' end,
    'details', format('Duplicate case-insensitive slug groups=%s.', duplicate_slug_groups)
  ));

  table_exists := to_regclass('public.hotel_onboarding') is not null;
  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '07_resumable_onboarding_state',
    'status', case when table_exists then 'READY' else 'GAP' end,
    'details', case when table_exists
      then 'public.hotel_onboarding exists.'
      else 'No authoritative resumable onboarding state table exists.'
    end
  ));

  table_exists := to_regclass('public.hotel_settings') is not null;
  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '08_structured_hotel_settings',
    'status', case when table_exists then 'READY' else 'GAP' end,
    'details', case when table_exists
      then 'public.hotel_settings exists.'
      else 'Timezone/currency exist on hotels, but no structured tax/policy/business settings table exists.'
    end
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '09_hotel_info_one_to_one',
    'status', case
      when hotels_without_info = 0 and hotels_with_multiple_info = 0
        then 'READY' else 'GAP' end,
    'details', format(
      'Hotels without hotel_info=%s; hotels with multiple hotel_info rows=%s.',
      hotels_without_info,
      hotels_with_multiple_info
    )
  ));

  function_exists :=
    to_regprocedure('public.bootstrap_hotel_onboarding(jsonb)') is not null;
  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '10_atomic_hotel_bootstrap_rpc',
    'status', case when function_exists then 'READY' else 'GAP' end,
    'details', case when function_exists
      then 'Atomic hotel bootstrap RPC exists.'
      else 'No atomic owner+hotel+settings+trial onboarding RPC exists.'
    end
  ));

  function_exists :=
    to_regprocedure('public.save_hotel_onboarding_step(uuid,text,jsonb)') is not null;
  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '11_resumable_step_rpc',
    'status', case when function_exists then 'READY' else 'GAP' end,
    'details', case when function_exists
      then 'Resumable onboarding step RPC exists.'
      else 'No server-validated onboarding step persistence RPC exists.'
    end
  ));

  -- 12–18: inventory, types, rates and bulk import.
  table_exists := to_regclass('public.floors') is not null;
  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '12_floor_configuration',
    'status', case when table_exists then 'READY' else 'GAP' end,
    'details', case when table_exists
      then 'public.floors exists.'
      else 'No normalized floors table exists.'
    end
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '13_room_type_foundation',
    'status', case when room_type_count > 0 then 'READY' else 'GAP' end,
    'details', format('Room types=%s.', room_type_count)
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '14_rate_plan_foundation',
    'status', case when rate_plan_count > 0 then 'READY' else 'GAP' end,
    'details', format(
      'Rate plans=%s; active room types without an active rate=%s.',
      rate_plan_count,
      room_types_without_rate
    )
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '15_room_inventory_foundation',
    'status', case
      when room_count > 0 and rooms_without_room_type = 0
        then 'READY' else 'GAP' end,
    'details', format(
      'Rooms=%s; rooms without normalized room_type_id=%s.',
      room_count,
      rooms_without_room_type
    )
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '16_room_number_uniqueness',
    'status', case when duplicate_room_groups = 0 then 'READY' else 'RISK' end,
    'details', format(
      'Duplicate room-number groups within a hotel=%s.',
      duplicate_room_groups
    )
  ));

  function_exists :=
    to_regprocedure('public.import_hotel_rooms(uuid,jsonb)') is not null;
  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '17_bulk_room_import_rpc',
    'status', case when function_exists then 'READY' else 'GAP' end,
    'details', case when function_exists
      then 'Server-validated bulk room import RPC exists.'
      else 'No atomic CSV/JSON room import RPC exists.'
    end
  ));

  column_exists := exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'rooms'
      and column_name = 'floor_id'
  );
  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '18_room_floor_linkage',
    'status', case when column_exists then 'READY' else 'GAP' end,
    'details', case when column_exists
      then 'rooms.floor_id exists.'
      else 'Rooms are not linked to a normalized floor.'
    end
  ));

  -- 19–24: configurable guest operations.
  table_exists := to_regclass('public.amenities') is not null;
  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '19_configurable_amenities',
    'status', case when table_exists then 'READY' else 'GAP' end,
    'details', case when table_exists
      then 'public.amenities exists.'
      else 'Amenities page is not backed by a normalized hotel-owned amenities table.'
    end
  ));

  table_exists := to_regclass('public.service_request_types') is not null;
  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '20_request_categories',
    'status', case when table_exists then 'READY' else 'GAP' end,
    'details', case when table_exists
      then 'public.service_request_types exists.'
      else 'No configurable hotel-owned service/request category table exists.'
    end
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '21_menu_configuration_inventory',
    'status', case
      when menu_category_count > 0 and menu_item_count > 0
        then 'READY' else 'GAP' end,
    'details', format(
      'Menu categories=%s; menu items=%s.',
      menu_category_count,
      menu_item_count
    )
  ));

  function_exists :=
    to_regprocedure('public.seed_hotel_menu_defaults(uuid)') is not null;
  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '22_menu_default_seed_rpc',
    'status', case when function_exists then 'READY' else 'GAP' end,
    'details', case when function_exists
      then 'Hotel menu default seed RPC exists.'
      else 'No idempotent hotel menu-default seed RPC exists.'
    end
  ));

  function_exists :=
    to_regprocedure('public.seed_hotel_configuration_defaults(uuid)') is not null;
  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '23_configuration_default_seed_rpc',
    'status', case when function_exists then 'READY' else 'GAP' end,
    'details', case when function_exists
      then 'General onboarding defaults RPC exists.'
      else 'No single idempotent default seeding RPC exists for amenities/request categories/menu.'
    end
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '24_secure_guest_qr_foundation',
    'status', case
      when to_regclass('public.guest_access_tokens') is not null
        and to_regprocedure('public.get_guest_access_links(uuid)') is not null
        then 'READY' else 'RISK' end,
    'details', format(
      'Guest access token rows=%s; signed QR access foundation expected from locked Day 7.',
      guest_token_count
    )
  ));

  -- 25–29: invoice numbering and trial/subscription readiness.
  table_exists := to_regclass('public.invoice_number_sequences') is not null;
  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '25_invoice_numbering_configuration',
    'status', case when table_exists then 'READY' else 'GAP' end,
    'details', case when table_exists
      then 'public.invoice_number_sequences exists.'
      else 'No hotel-scoped configurable invoice numbering sequence exists.'
    end
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '26_subscription_plan_inventory',
    'status', case when active_plan_count > 0 then 'READY' else 'GAP' end,
    'details', format('Active subscription plans=%s.', active_plan_count)
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '27_current_subscription_coverage',
    'status', case
      when hotels_without_subscription = 0
       and hotels_with_multiple_current_subscriptions = 0
       and invalid_subscription_dates = 0
        then 'READY' else 'RISK' end,
    'details', format(
      'Hotels without a current subscription=%s; with multiple current subscriptions=%s; invalid date ranges=%s.',
      hotels_without_subscription,
      hotels_with_multiple_current_subscriptions,
      invalid_subscription_dates
    )
  ));

  column_exists := exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'hotel_subscriptions'
      and column_name = 'trial_ends_at'
  );
  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '28_explicit_trial_lifecycle_fields',
    'status', case when column_exists then 'READY' else 'GAP' end,
    'details', case when column_exists
      then 'hotel_subscriptions.trial_ends_at exists.'
      else 'Trial lifecycle currently relies on generic start/end dates only.'
    end
  ));

  function_exists :=
    to_regprocedure('public.activate_hotel_trial(uuid,uuid,integer)') is not null;
  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '29_trial_activation_rpc',
    'status', case when function_exists then 'READY' else 'GAP' end,
    'details', case when function_exists
      then 'Server-validated trial activation RPC exists.'
      else 'No dedicated, idempotent trial activation RPC exists.'
    end
  ));

  -- 30–32: authorization, completeness and source of truth.
  function_exists :=
    to_regprocedure('private.user_has_permission(uuid,text)') is not null;
  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '30_authoritative_permission_helper',
    'status', case when function_exists then 'READY' else 'RISK' end,
    'details', case when function_exists
      then 'private.user_has_permission(uuid,text) exists.'
      else 'Authoritative permission helper is missing.'
    end
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '31_day8_operational_readiness_checklist',
    'status', case
      when to_regclass('public.hotel_onboarding') is not null
        then 'READY' else 'GAP' end,
    'details', 'Day 8 requires a server-computed readiness checklist before onboarding can be marked complete.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'check_name', '32_preflight_summary',
    'status', 'INFO',
    'details',
      'Use this result to build Migration 017 and the first bounded onboarding subsystem. Do not manually edit production tables.'
  ));

  return query
  select item.check_name, item.status, item.details
  from jsonb_to_recordset(results)
    as item(check_name text, status text, details text)
  order by item.check_name;
end;
$audit$;

revoke all on function private.run_day8_onboarding_preflight_20260727()
from public, anon, authenticated;

comment on function private.run_day8_onboarding_preflight_20260727() is
  'Read-only Day 8 hotel onboarding and configuration preflight REV2. Remove after Day 8 foundation migration acceptance.';

select check_name, status, details
from private.run_day8_onboarding_preflight_20260727()
order by check_name;
