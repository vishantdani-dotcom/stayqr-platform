-- ============================================================================
-- StayQR v1.0
-- Day 8 Audit 045 — Configuration Schema Contract Preflight
--
-- PURPOSE
-- Read-only inspection before the next Day 8 migration package. It captures
-- the exact production contract for:
--   - room types, floors, rooms and rate plans;
--   - bulk room import prerequisites;
--   - menu items/categories;
--   - service request categories;
--   - amenities;
--   - onboarding readiness integration;
--   - RLS and write-policy coverage.
--
-- SAFETY
-- - Run once in Supabase SQL Editor with role: postgres.
-- - Reads metadata and aggregate counts only.
-- - Does not create a helper function.
-- - Does not insert, update or delete business data.
--
-- EXPECTED RESULT
-- 30 diagnostic rows.
-- READY = usable as-is.
-- GAP   = next Day 8 migration must create/complete it.
-- RISK  = existing production data requires guarded handling.
-- INFO  = exact schema/data inventory.
-- ============================================================================

with
target_tables(table_name) as (
  values
    ('rooms'),
    ('room_types'),
    ('rate_plans'),
    ('floors'),
    ('menu_items'),
    ('menu_categories'),
    ('service_requests'),
    ('service_request_types'),
    ('amenities'),
    ('hotel_settings'),
    ('hotel_onboarding'),
    ('invoice_number_sequences')
),
table_inventory as (
  select
    tt.table_name,
    to_regclass('public.' || tt.table_name) is not null as table_exists,
    coalesce(c.relrowsecurity, false) as rls_enabled
  from target_tables tt
  left join pg_class c
    on c.oid = to_regclass('public.' || tt.table_name)
),
column_inventory as (
  select
    c.table_name,
    jsonb_agg(
      jsonb_build_object(
        'name', c.column_name,
        'type', c.data_type,
        'udt', c.udt_name,
        'nullable', c.is_nullable,
        'default', c.column_default
      )
      order by c.ordinal_position
    ) as columns
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name in (
      select table_name from target_tables
    )
  group by c.table_name
),
required_without_default as (
  select
    c.table_name,
    array_agg(c.column_name order by c.ordinal_position) as column_names
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name in (
      'rooms',
      'room_types',
      'rate_plans',
      'menu_items',
      'service_requests'
    )
    and c.is_nullable = 'NO'
    and c.column_default is null
    and c.is_identity = 'NO'
    and c.is_generated = 'NEVER'
  group by c.table_name
),
policy_counts as (
  select
    p.tablename as table_name,
    count(*) as total_policies,
    count(*) filter (where p.cmd in ('SELECT', 'ALL')) as select_policies,
    count(*) filter (where p.cmd in ('INSERT', 'ALL')) as insert_policies,
    count(*) filter (where p.cmd in ('UPDATE', 'ALL')) as update_policies,
    count(*) filter (where p.cmd in ('DELETE', 'ALL')) as delete_policies
  from pg_policies p
  where p.schemaname = 'public'
    and p.tablename in (
      select table_name from target_tables
    )
  group by p.tablename
),
constraint_inventory as (
  select
    rel.relname as table_name,
    jsonb_agg(
      jsonb_build_object(
        'name', con.conname,
        'type', con.contype,
        'definition', pg_get_constraintdef(con.oid, true),
        'validated', con.convalidated
      )
      order by con.conname
    ) as constraints
  from pg_constraint con
  join pg_class rel on rel.oid = con.conrelid
  join pg_namespace n on n.oid = rel.relnamespace
  where n.nspname = 'public'
    and rel.relname in (
      'rooms',
      'room_types',
      'rate_plans',
      'floors',
      'menu_items',
      'service_requests'
    )
  group by rel.relname
),
room_stats as (
  select
    count(*) as room_count,
    count(*) filter (where room_type_id is null) as without_room_type,
    count(*) filter (where floor_id is null) as without_floor,
    count(*) filter (
      where nullif(trim(room_number), '') is null
    ) as blank_room_number,
    count(*) filter (
      where nullif(trim(room_type), '') is null
    ) as blank_legacy_room_type
  from public.rooms
),
room_duplicate_stats as (
  select count(*) as duplicate_groups
  from (
    select r.hotel_id, lower(trim(r.room_number))
    from public.rooms r
    group by r.hotel_id, lower(trim(r.room_number))
    having count(*) > 1
  ) duplicate_room
),
room_type_stats as (
  select
    count(*) as total,
    count(*) filter (where is_active) as active,
    count(*) filter (where base_rate < 0) as negative_rates
  from public.room_types
),
room_type_duplicate_stats as (
  select
    (
      select count(*)
      from (
        select rt.hotel_id, lower(trim(rt.name))
        from public.room_types rt
        group by rt.hotel_id, lower(trim(rt.name))
        having count(*) > 1
      ) d
    ) as duplicate_name_groups,
    (
      select count(*)
      from (
        select rt.hotel_id, upper(trim(rt.code))
        from public.room_types rt
        group by rt.hotel_id, upper(trim(rt.code))
        having count(*) > 1
      ) d
    ) as duplicate_code_groups
),
rate_stats as (
  select
    count(*) as total,
    count(*) filter (where is_active) as active,
    count(*) filter (
      where base_rate < 0
         or extra_adult_rate < 0
         or extra_child_rate < 0
    ) as negative_rates,
    count(*) filter (
      where currency_code !~ '^[A-Z]{3}$'
    ) as invalid_currency
  from public.rate_plans
),
room_types_without_rate as (
  select count(*) as total
  from public.room_types rt
  where rt.is_active
    and not exists (
      select 1
      from public.rate_plans rp
      where rp.hotel_id = rt.hotel_id
        and rp.room_type_id = rt.id
        and rp.is_active
    )
),
floor_stats as (
  select
    count(*) as total,
    count(*) filter (where is_active) as active,
    count(*) filter (
      where upper(code) = 'DEFAULT'
    ) as default_floors
  from public.floors
),
menu_item_stats as (
  select
    count(*) as total,
    count(*) filter (
      where coalesce(is_available, true)
    ) as available,
    count(*) filter (
      where nullif(trim(item_name), '') is null
    ) as blank_names,
    count(*) filter (where price < 0) as negative_prices,
    count(distinct nullif(trim(category), '')) as distinct_categories
  from public.menu_items
),
service_request_stats as (
  select
    count(*) as total,
    count(distinct nullif(trim(request_type), '')) as distinct_request_types,
    count(*) filter (
      where nullif(trim(request_type), '') is null
    ) as blank_request_types
  from public.service_requests
),
status_values as (
  select
    'rooms'::text as table_name,
    jsonb_agg(distinct r.status order by r.status) as values
  from public.rooms r
  union all
  select
    'service_requests',
    jsonb_agg(distinct sr.status order by sr.status)
  from public.service_requests sr
),
category_values as (
  select
    jsonb_agg(category order by category) as menu_categories
  from (
    select distinct nullif(trim(mi.category), '') as category
    from public.menu_items mi
    where nullif(trim(mi.category), '') is not null
    order by 1
  ) categories
),
request_type_values as (
  select
    jsonb_agg(request_type order by request_type) as request_types
  from (
    select distinct nullif(trim(sr.request_type), '') as request_type
    from public.service_requests sr
    where nullif(trim(sr.request_type), '') is not null
    order by 1
  ) request_types
),
checks(check_name, status, details) as (
  values
    (
      '01_rooms_schema_contract',
      'INFO',
      coalesce(
        (select columns::text
         from column_inventory
         where table_name = 'rooms'),
        'rooms table missing'
      )
    ),
    (
      '02_room_types_schema_contract',
      'INFO',
      coalesce(
        (select columns::text
         from column_inventory
         where table_name = 'room_types'),
        'room_types table missing'
      )
    ),
    (
      '03_rate_plans_schema_contract',
      'INFO',
      coalesce(
        (select columns::text
         from column_inventory
         where table_name = 'rate_plans'),
        'rate_plans table missing'
      )
    ),
    (
      '04_menu_items_schema_contract',
      'INFO',
      coalesce(
        (select columns::text
         from column_inventory
         where table_name = 'menu_items'),
        'menu_items table missing'
      )
    ),
    (
      '05_service_requests_schema_contract',
      'INFO',
      coalesce(
        (select columns::text
         from column_inventory
         where table_name = 'service_requests'),
        'service_requests table missing'
      )
    ),
    (
      '06_room_required_insert_columns',
      'INFO',
      coalesce(
        (select array_to_string(column_names, ', ')
         from required_without_default
         where table_name = 'rooms'),
        'No required no-default columns detected.'
      )
    ),
    (
      '07_room_type_required_insert_columns',
      'INFO',
      coalesce(
        (select array_to_string(column_names, ', ')
         from required_without_default
         where table_name = 'room_types'),
        'No required no-default columns detected.'
      )
    ),
    (
      '08_rate_plan_required_insert_columns',
      'INFO',
      coalesce(
        (select array_to_string(column_names, ', ')
         from required_without_default
         where table_name = 'rate_plans'),
        'No required no-default columns detected.'
      )
    ),
    (
      '09_menu_item_required_insert_columns',
      'INFO',
      coalesce(
        (select array_to_string(column_names, ', ')
         from required_without_default
         where table_name = 'menu_items'),
        'No required no-default columns detected.'
      )
    ),
    (
      '10_room_constraints',
      'INFO',
      coalesce(
        (select constraints::text
         from constraint_inventory
         where table_name = 'rooms'),
        'No constraints found.'
      )
    ),
    (
      '11_room_type_constraints',
      'INFO',
      coalesce(
        (select constraints::text
         from constraint_inventory
         where table_name = 'room_types'),
        'No constraints found.'
      )
    ),
    (
      '12_rate_plan_constraints',
      'INFO',
      coalesce(
        (select constraints::text
         from constraint_inventory
         where table_name = 'rate_plans'),
        'No constraints found.'
      )
    ),
    (
      '13_room_inventory_integrity',
      case
        when (select without_room_type + without_floor
              + blank_room_number + blank_legacy_room_type
              from room_stats) = 0
          then 'READY'
        else 'RISK'
      end,
      format(
        'Rooms=%s; without room_type_id=%s; without floor_id=%s; blank room number=%s; blank legacy room_type=%s.',
        (select room_count from room_stats),
        (select without_room_type from room_stats),
        (select without_floor from room_stats),
        (select blank_room_number from room_stats),
        (select blank_legacy_room_type from room_stats)
      )
    ),
    (
      '14_room_number_uniqueness',
      case when (select duplicate_groups from room_duplicate_stats) = 0
        then 'READY' else 'RISK' end,
      format(
        'Duplicate hotel+room-number groups=%s.',
        (select duplicate_groups from room_duplicate_stats)
      )
    ),
    (
      '15_room_type_integrity',
      case
        when (select negative_rates from room_type_stats) = 0
         and (select duplicate_name_groups + duplicate_code_groups
              from room_type_duplicate_stats) = 0
          then 'READY'
        else 'RISK'
      end,
      format(
        'Total=%s; active=%s; negative rates=%s; duplicate name groups=%s; duplicate code groups=%s.',
        (select total from room_type_stats),
        (select active from room_type_stats),
        (select negative_rates from room_type_stats),
        (select duplicate_name_groups from room_type_duplicate_stats),
        (select duplicate_code_groups from room_type_duplicate_stats)
      )
    ),
    (
      '16_rate_plan_integrity',
      case
        when (select negative_rates + invalid_currency from rate_stats) = 0
          then 'READY'
        else 'RISK'
      end,
      format(
        'Total=%s; active=%s; negative rates=%s; invalid currency=%s; active room types without active rate=%s.',
        (select total from rate_stats),
        (select active from rate_stats),
        (select negative_rates from rate_stats),
        (select invalid_currency from rate_stats),
        (select total from room_types_without_rate)
      )
    ),
    (
      '17_floor_inventory',
      case when (select active from floor_stats) > 0
        then 'READY' else 'GAP' end,
      format(
        'Floors=%s; active=%s; Default Floor rows=%s.',
        (select total from floor_stats),
        (select active from floor_stats),
        (select default_floors from floor_stats)
      )
    ),
    (
      '18_bulk_room_import_rpc',
      case when to_regprocedure(
        'public.import_hotel_rooms(uuid,jsonb)'
      ) is not null then 'READY' else 'GAP' end,
      'Expected contract: hotel UUID plus JSON array with room number, room type and floor identifiers/codes.'
    ),
    (
      '19_room_configuration_rpc',
      case when to_regprocedure(
        'public.configure_hotel_inventory(uuid,jsonb)'
      ) is not null then 'READY' else 'GAP' end,
      'Expected atomic room type, floor, rate and room configuration RPC.'
    ),
    (
      '20_amenities_table',
      case when to_regclass('public.amenities') is not null
        then 'READY' else 'GAP' end,
      coalesce(
        (select columns::text
         from column_inventory
         where table_name = 'amenities'),
        'No normalized amenities table exists.'
      )
    ),
    (
      '21_service_request_types_table',
      case when to_regclass(
        'public.service_request_types'
      ) is not null then 'READY' else 'GAP' end,
      coalesce(
        (select columns::text
         from column_inventory
         where table_name = 'service_request_types'),
        'No normalized service request category table exists.'
      )
    ),
    (
      '22_menu_categories_table',
      case when to_regclass('public.menu_categories') is not null
        then 'READY' else 'GAP' end,
      coalesce(
        (select columns::text
         from column_inventory
         where table_name = 'menu_categories'),
        'Menu categories currently exist only as menu_items.category text.'
      )
    ),
    (
      '23_menu_item_integrity',
      case
        when (select blank_names + negative_prices
              from menu_item_stats) = 0
          then 'READY'
        else 'RISK'
      end,
      format(
        'Items=%s; available=%s; blank names=%s; negative prices=%s; distinct text categories=%s.',
        (select total from menu_item_stats),
        (select available from menu_item_stats),
        (select blank_names from menu_item_stats),
        (select negative_prices from menu_item_stats),
        (select distinct_categories from menu_item_stats)
      )
    ),
    (
      '24_existing_menu_category_values',
      'INFO',
      coalesce(
        (select menu_categories::text from category_values),
        '[]'
      )
    ),
    (
      '25_existing_request_type_values',
      'INFO',
      coalesce(
        (select request_types::text from request_type_values),
        '[]'
      )
    ),
    (
      '26_service_request_integrity',
      case when (select blank_request_types
                 from service_request_stats) = 0
        then 'READY' else 'RISK' end,
      format(
        'Requests=%s; distinct request types=%s; blank request types=%s.',
        (select total from service_request_stats),
        (select distinct_request_types from service_request_stats),
        (select blank_request_types from service_request_stats)
      )
    ),
    (
      '27_status_values',
      'INFO',
      (
        select jsonb_object_agg(table_name, values)::text
        from status_values
      )
    ),
    (
      '28_target_table_rls_inventory',
      case
        when not exists (
          select 1
          from table_inventory ti
          where ti.table_exists
            and ti.table_name in (
              'rooms',
              'room_types',
              'rate_plans',
              'floors',
              'menu_items',
              'service_requests',
              'hotel_settings',
              'hotel_onboarding',
              'invoice_number_sequences'
            )
            and not ti.rls_enabled
        ) then 'READY'
        else 'RISK'
      end,
      (
        select jsonb_agg(
          jsonb_build_object(
            'table', ti.table_name,
            'exists', ti.table_exists,
            'rls', ti.rls_enabled
          )
          order by ti.table_name
        )::text
        from table_inventory ti
      )
    ),
    (
      '29_target_policy_inventory',
      'INFO',
      (
        select jsonb_agg(
          jsonb_build_object(
            'table', ti.table_name,
            'policies', coalesce(pc.total_policies, 0),
            'select', coalesce(pc.select_policies, 0),
            'insert', coalesce(pc.insert_policies, 0),
            'update', coalesce(pc.update_policies, 0),
            'delete', coalesce(pc.delete_policies, 0)
          )
          order by ti.table_name
        )::text
        from table_inventory ti
        left join policy_counts pc
          on pc.table_name = ti.table_name
      )
    ),
    (
      '30_configuration_package_summary',
      'INFO',
      'Use this exact contract to build Migration 019: inventory configuration, bulk import, normalized amenities/request categories/menu categories, defaults and readiness integration.'
    )
)
select check_name, status, details
from checks
order by check_name;
