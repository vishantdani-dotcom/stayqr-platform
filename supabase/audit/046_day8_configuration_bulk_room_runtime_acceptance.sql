-- ============================================================================
-- StayQR v1.0
-- Day 8 Audit 046 — Configuration and Bulk Room Runtime Acceptance
--
-- PURPOSE
-- Runs Migration 019 through the real authenticated RPC boundary and proves:
--   - fresh hotels automatically receive amenity/request/menu defaults;
--   - configuration defaults are idempotent;
--   - room types, floors and rate plans configure atomically;
--   - repeated configuration creates no duplicate inventory;
--   - room bulk import inserts, updates and detects unchanged rows;
--   - duplicate payload rows are rejected;
--   - unknown room types and floors are rejected;
--   - occupied-room reconfiguration is blocked;
--   - onboarding readiness updates as inventory becomes operational;
--   - anonymous configuration calls remain blocked;
--   - all synthetic records are rolled back.
--
-- SAFETY
-- - Run once in Supabase SQL Editor with role: postgres.
-- - Synthetic records are created inside a reversible subtransaction.
-- - Existing production hotels, rooms, rates and configuration are not edited.
--
-- EXPECTED RESULT
-- 28 rows, and every passed value must be true.
-- ============================================================================

create or replace function
  private.run_day8_configuration_runtime_acceptance_20260727()
returns table (
  test_name text,
  passed boolean,
  details text
)
language plpgsql
security invoker
set search_path = ''
as $audit$
declare
  actor_user_id uuid;
  actor_email text;
  plan_id_value uuid;
  plan_name_value text;

  request_id_value uuid := gen_random_uuid();
  audit_suffix text :=
    left(replace(gen_random_uuid()::text, '-', ''), 12);
  requested_slug text;
  contact_email_value text;

  bootstrap_payload jsonb;
  bootstrap_result jsonb;
  seed_result_one jsonb;
  seed_result_two jsonb;
  configure_result_one jsonb;
  configure_result_two jsonb;
  import_result_one jsonb;
  import_result_two jsonb;
  import_result_three jsonb;
  readiness_before_rooms jsonb;
  readiness_after_rooms jsonb;

  hotel_id_value uuid;
  floor_id_value uuid;
  standard_room_type_id uuid;
  deluxe_room_type_id uuid;

  actor_resolved boolean := false;
  bootstrap_ok boolean := false;
  automatic_amenities_ok boolean := false;
  automatic_request_types_ok boolean := false;
  automatic_menu_categories_ok boolean := false;
  defaults_idempotent_ok boolean := false;
  inventory_configuration_ok boolean := false;
  inventory_no_duplicates_ok boolean := false;
  room_type_rate_linkage_ok boolean := false;
  readiness_before_rooms_ok boolean := false;
  first_import_ok boolean := false;
  imported_room_linkage_ok boolean := false;
  repeated_import_idempotent_ok boolean := false;
  available_room_update_ok boolean := false;
  duplicate_payload_rejected boolean := false;
  unknown_room_type_rejected boolean := false;
  unknown_floor_rejected boolean := false;
  occupied_room_marked boolean := false;
  occupied_reconfiguration_blocked boolean := false;
  readiness_after_rooms_ok boolean := false;
  normalized_defaults_counts_ok boolean := false;
  new_tables_rls_ok boolean := false;
  authenticated_execute_ok boolean := false;
  anon_configure_blocked boolean := false;
  anon_import_blocked boolean := false;
  production_counts_unchanged boolean := false;
  rollback_verified boolean := false;

  before_hotel_count bigint := 0;
  before_room_count bigint := 0;
  before_room_type_count bigint := 0;
  before_rate_count bigint := 0;
  before_amenity_count bigint := 0;
  before_request_type_count bigint := 0;
  before_menu_category_count bigint := 0;

  after_hotel_count bigint := 0;
  after_room_count bigint := 0;
  after_room_type_count bigint := 0;
  after_rate_count bigint := 0;
  after_amenity_count bigint := 0;
  after_request_type_count bigint := 0;
  after_menu_category_count bigint := 0;

  amenity_count_after_bootstrap bigint := 0;
  request_type_count_after_bootstrap bigint := 0;
  menu_category_count_after_bootstrap bigint := 0;

  role_switched boolean := false;
  failure_details text;
  results jsonb := '[]'::jsonb;
begin
  -- ------------------------------------------------------------------------
  -- Resolve prerequisites and production baseline.
  -- ------------------------------------------------------------------------
  select pa.user_id, lower(au.email)
  into actor_user_id, actor_email
  from public.platform_admins pa
  join auth.users au on au.id = pa.user_id
  where pa.status = 'active'
    and au.email is not null
    and coalesce(
      au.banned_until,
      '-infinity'::timestamptz
    ) <= now()
  order by pa.created_at
  limit 1;

  select sp.id, sp.plan_name
  into plan_id_value, plan_name_value
  from public.subscription_plans sp
  where sp.status = 'active'
  order by sp.created_at
  limit 1;

  actor_resolved :=
    actor_user_id is not null
    and actor_email is not null
    and plan_id_value is not null;

  select count(*) into before_hotel_count
  from public.hotels;
  select count(*) into before_room_count
  from public.rooms;
  select count(*) into before_room_type_count
  from public.room_types;
  select count(*) into before_rate_count
  from public.rate_plans;
  select count(*) into before_amenity_count
  from public.amenities;
  select count(*) into before_request_type_count
  from public.service_request_types;
  select count(*) into before_menu_category_count
  from public.menu_categories;

  requested_slug :=
    'stayqr-day8-config-audit-' || audit_suffix;
  contact_email_value :=
    'day8-config-audit-' || audit_suffix || '@stayqr.test';

  bootstrap_payload := jsonb_build_object(
    'request_id', request_id_value,
    'hotel_name',
      'StayQR Day 8 Configuration Audit ' || audit_suffix,
    'owner_name', 'Day 8 Configuration Audit Owner',
    'contact_email', contact_email_value,
    'phone', '9999999997',
    'address', 'Temporary configuration audit address',
    'city', 'Nagpur',
    'state', 'Maharashtra',
    'location', 'Nagpur, Maharashtra',
    'timezone', 'Asia/Kolkata',
    'currency_code', 'INR',
    'hotel_slug', requested_slug,
    'plan_id', plan_id_value,
    'trial_days', 14,
    'default_tax_percent', 12,
    'prices_include_tax', false,
    'checkin_time', '14:00',
    'checkout_time', '11:00'
  );

  -- ------------------------------------------------------------------------
  -- Reversible authenticated runtime test.
  -- ------------------------------------------------------------------------
  begin
    if not actor_resolved then
      raise exception
        'An active Platform Admin and active subscription plan are required.';
    end if;

    perform set_config(
      'request.jwt.claim.sub',
      actor_user_id::text,
      true
    );
    perform set_config(
      'request.jwt.claim.role',
      'authenticated',
      true
    );

    execute 'set local role authenticated';
    role_switched := true;

    bootstrap_result :=
      public.bootstrap_hotel_onboarding(
        bootstrap_payload
      );

    hotel_id_value :=
      (bootstrap_result ->> 'hotel_id')::uuid;

    bootstrap_ok :=
      hotel_id_value is not null
      and bootstrap_result ->> 'hotel_slug' = requested_slug
      and coalesce(
        (bootstrap_result ->> 'idempotent')::boolean,
        true
      ) = false;

    select count(*)
    into amenity_count_after_bootstrap
    from public.amenities a
    where a.hotel_id = hotel_id_value
      and a.is_active;

    select count(*)
    into request_type_count_after_bootstrap
    from public.service_request_types srt
    where srt.hotel_id = hotel_id_value
      and srt.is_active;

    select count(*)
    into menu_category_count_after_bootstrap
    from public.menu_categories mc
    where mc.hotel_id = hotel_id_value
      and mc.is_active;

    automatic_amenities_ok :=
      amenity_count_after_bootstrap >= 5;

    automatic_request_types_ok :=
      request_type_count_after_bootstrap >= 4;

    automatic_menu_categories_ok :=
      menu_category_count_after_bootstrap >= 3;

    seed_result_one :=
      public.seed_hotel_configuration_defaults(
        hotel_id_value
      );

    seed_result_two :=
      public.seed_hotel_configuration_defaults(
        hotel_id_value
      );

    defaults_idempotent_ok :=
      coalesce(
        (seed_result_one ->> 'amenities_inserted')::integer,
        -1
      ) = 0
      and coalesce(
        (seed_result_one ->> 'request_types_inserted')::integer,
        -1
      ) = 0
      and coalesce(
        (
          seed_result_one
          -> 'menu'
          ->> 'menu_categories_inserted'
        )::integer,
        -1
      ) = 0
      and coalesce(
        (seed_result_two ->> 'amenities_inserted')::integer,
        -1
      ) = 0
      and coalesce(
        (seed_result_two ->> 'request_types_inserted')::integer,
        -1
      ) = 0
      and coalesce(
        (
          seed_result_two
          -> 'menu'
          ->> 'menu_categories_inserted'
        )::integer,
        -1
      ) = 0;

    configure_result_one :=
      public.configure_hotel_inventory(
        hotel_id_value,
        jsonb_build_object(
          'floors',
          jsonb_build_array(
            jsonb_build_object(
              'name', 'First Floor',
              'code', 'F1',
              'floor_number', 1,
              'sort_order', 10,
              'is_active', true
            )
          ),
          'room_types',
          jsonb_build_array(
            jsonb_build_object(
              'name', 'Standard Room',
              'code', 'STD',
              'description',
                'Standard Day 8 audit room.',
              'base_occupancy', 1,
              'max_adults', 2,
              'max_children', 1,
              'max_occupancy', 3,
              'base_rate', 2500,
              'extra_adult_rate', 500,
              'extra_child_rate', 250,
              'sort_order', 10,
              'is_active', true
            ),
            jsonb_build_object(
              'name', 'Deluxe Room',
              'code', 'DLX',
              'description',
                'Deluxe Day 8 audit room.',
              'base_occupancy', 2,
              'max_adults', 3,
              'max_children', 2,
              'max_occupancy', 4,
              'base_rate', 3500,
              'extra_adult_rate', 700,
              'extra_child_rate', 350,
              'sort_order', 20,
              'is_active', true
            )
          ),
          'rate_plans',
          jsonb_build_array(
            jsonb_build_object(
              'name', 'Standard Best Available Rate',
              'code', 'STD-BAR',
              'room_type_code', 'STD',
              'meal_plan', 'room_only',
              'currency_code', 'INR',
              'base_rate', 2500,
              'minimum_stay', 1,
              'is_refundable', true,
              'priority', 10,
              'is_active', true
            ),
            jsonb_build_object(
              'name', 'Deluxe Best Available Rate',
              'code', 'DLX-BAR',
              'room_type_code', 'DLX',
              'meal_plan', 'room_only',
              'currency_code', 'INR',
              'base_rate', 3500,
              'minimum_stay', 1,
              'is_refundable', true,
              'priority', 20,
              'is_active', true
            )
          )
        )
      );

    inventory_configuration_ok :=
      coalesce(
        (
          configure_result_one
          -> 'floors'
          ->> 'inserted'
        )::integer,
        0
      ) = 1
      and coalesce(
        (
          configure_result_one
          -> 'room_types'
          ->> 'inserted'
        )::integer,
        0
      ) = 2
      and coalesce(
        (
          configure_result_one
          -> 'rate_plans'
          ->> 'inserted'
        )::integer,
        0
      ) = 2;

    select f.id
    into floor_id_value
    from public.floors f
    where f.hotel_id = hotel_id_value
      and upper(trim(f.code)) = 'F1';

    select rt.id
    into standard_room_type_id
    from public.room_types rt
    where rt.hotel_id = hotel_id_value
      and upper(trim(rt.code)) = 'STD';

    select rt.id
    into deluxe_room_type_id
    from public.room_types rt
    where rt.hotel_id = hotel_id_value
      and upper(trim(rt.code)) = 'DLX';

    configure_result_two :=
      public.configure_hotel_inventory(
        hotel_id_value,
        jsonb_build_object(
          'floors',
          jsonb_build_array(
            jsonb_build_object(
              'name', 'First Floor',
              'code', 'F1',
              'floor_number', 1,
              'sort_order', 10,
              'is_active', true
            )
          ),
          'room_types',
          jsonb_build_array(
            jsonb_build_object(
              'name', 'Standard Room',
              'code', 'STD',
              'base_rate', 2500,
              'is_active', true
            ),
            jsonb_build_object(
              'name', 'Deluxe Room',
              'code', 'DLX',
              'base_rate', 3500,
              'is_active', true
            )
          ),
          'rate_plans',
          jsonb_build_array(
            jsonb_build_object(
              'name', 'Standard Best Available Rate',
              'code', 'STD-BAR',
              'room_type_code', 'STD',
              'base_rate', 2500,
              'is_active', true
            ),
            jsonb_build_object(
              'name', 'Deluxe Best Available Rate',
              'code', 'DLX-BAR',
              'room_type_code', 'DLX',
              'base_rate', 3500,
              'is_active', true
            )
          )
        )
      );

    select
      (
        select count(*)
        from public.floors f
        where f.hotel_id = hotel_id_value
          and upper(trim(f.code)) = 'F1'
      ) = 1
      and (
        select count(*)
        from public.room_types rt
        where rt.hotel_id = hotel_id_value
          and upper(trim(rt.code)) in ('STD', 'DLX')
      ) = 2
      and (
        select count(*)
        from public.rate_plans rp
        where rp.hotel_id = hotel_id_value
          and upper(trim(rp.code))
            in ('STD-BAR', 'DLX-BAR')
      ) = 2
    into inventory_no_duplicates_ok;

    select
      (
        select count(*)
        from public.rate_plans rp
        join public.room_types rt
          on rt.hotel_id = rp.hotel_id
         and rt.id = rp.room_type_id
        where rp.hotel_id = hotel_id_value
          and (
            (
              upper(trim(rp.code)) = 'STD-BAR'
              and upper(trim(rt.code)) = 'STD'
            )
            or
            (
              upper(trim(rp.code)) = 'DLX-BAR'
              and upper(trim(rt.code)) = 'DLX'
            )
          )
      ) = 2
    into room_type_rate_linkage_ok;

    readiness_before_rooms :=
      configure_result_one -> 'readiness';

    readiness_before_rooms_ok :=
      coalesce(
        (
          readiness_before_rooms
          -> 'checklist'
          ->> 'room_types'
        )::boolean,
        false
      )
      and coalesce(
        (
          readiness_before_rooms
          -> 'checklist'
          ->> 'rates'
        )::boolean,
        false
      )
      and coalesce(
        (
          readiness_before_rooms
          -> 'checklist'
          ->> 'floors'
        )::boolean,
        false
      )
      and not coalesce(
        (
          readiness_before_rooms
          -> 'checklist'
          ->> 'rooms'
        )::boolean,
        true
      );

    import_result_one :=
      public.import_hotel_rooms(
        hotel_id_value,
        jsonb_build_object(
          'rooms',
          jsonb_build_array(
            jsonb_build_object(
              'room_number', '801',
              'room_type_code', 'STD',
              'floor_code', 'F1',
              'status', 'available'
            ),
            jsonb_build_object(
              'room_number', '802',
              'room_type_code', 'DLX',
              'floor_code', 'F1',
              'status', 'available'
            )
          )
        )
      );

    first_import_ok :=
      coalesce(
        (import_result_one ->> 'total_rows')::integer,
        0
      ) = 2
      and coalesce(
        (import_result_one ->> 'inserted')::integer,
        0
      ) = 2
      and coalesce(
        (import_result_one ->> 'updated')::integer,
        -1
      ) = 0
      and coalesce(
        (import_result_one ->> 'unchanged')::integer,
        -1
      ) = 0;

    select
      count(*) = 2
      and count(*) filter (
        where r.floor_id = floor_id_value
      ) = 2
      and count(*) filter (
        where r.room_number = '801'
          and r.room_type_id = standard_room_type_id
          and r.room_type = 'Standard Room'
      ) = 1
      and count(*) filter (
        where r.room_number = '802'
          and r.room_type_id = deluxe_room_type_id
          and r.room_type = 'Deluxe Room'
      ) = 1
    into imported_room_linkage_ok
    from public.rooms r
    where r.hotel_id = hotel_id_value
      and r.room_number in ('801', '802');

    import_result_two :=
      public.import_hotel_rooms(
        hotel_id_value,
        jsonb_build_array(
          jsonb_build_object(
            'room_number', '801',
            'room_type_code', 'STD',
            'floor_code', 'F1',
            'status', 'available'
          ),
          jsonb_build_object(
            'room_number', '802',
            'room_type_code', 'DLX',
            'floor_code', 'F1',
            'status', 'available'
          )
        )
      );

    repeated_import_idempotent_ok :=
      coalesce(
        (import_result_two ->> 'inserted')::integer,
        -1
      ) = 0
      and coalesce(
        (import_result_two ->> 'updated')::integer,
        -1
      ) = 0
      and coalesce(
        (import_result_two ->> 'unchanged')::integer,
        0
      ) = 2
      and (
        select count(*) = 2
        from public.rooms r
        where r.hotel_id = hotel_id_value
          and r.room_number in ('801', '802')
      );

    import_result_three :=
      public.import_hotel_rooms(
        hotel_id_value,
        jsonb_build_array(
          jsonb_build_object(
            'room_number', '802',
            'room_type_code', 'DLX',
            'floor_code', 'F1',
            'status', 'maintenance'
          )
        )
      );

    available_room_update_ok :=
      coalesce(
        (import_result_three ->> 'updated')::integer,
        0
      ) = 1
      and exists (
        select 1
        from public.rooms r
        where r.hotel_id = hotel_id_value
          and r.room_number = '802'
          and r.status = 'maintenance'
      );

    begin
      perform public.import_hotel_rooms(
        hotel_id_value,
        jsonb_build_array(
          jsonb_build_object(
            'room_number', '803',
            'room_type_code', 'STD',
            'floor_code', 'F1'
          ),
          jsonb_build_object(
            'room_number', '803',
            'room_type_code', 'STD',
            'floor_code', 'F1'
          )
        )
      );
    exception when others then
      duplicate_payload_rejected :=
        lower(sqlerrm) like
          '%duplicate room numbers%';
    end;

    begin
      perform public.import_hotel_rooms(
        hotel_id_value,
        jsonb_build_array(
          jsonb_build_object(
            'room_number', '804',
            'room_type_code', 'UNKNOWN',
            'floor_code', 'F1'
          )
        )
      );
    exception when others then
      unknown_room_type_rejected :=
        lower(sqlerrm) like
          '%unknown active room_type_code%';
    end;

    begin
      perform public.import_hotel_rooms(
        hotel_id_value,
        jsonb_build_array(
          jsonb_build_object(
            'room_number', '805',
            'room_type_code', 'STD',
            'floor_code', 'UNKNOWN'
          )
        )
      );
    exception when others then
      unknown_floor_rejected :=
        lower(sqlerrm) like
          '%unknown active floor_code%';
    end;

    perform public.import_hotel_rooms(
      hotel_id_value,
      jsonb_build_array(
        jsonb_build_object(
          'room_number', '801',
          'room_type_code', 'STD',
          'floor_code', 'F1',
          'status', 'occupied'
        )
      )
    );

    occupied_room_marked := exists (
      select 1
      from public.rooms r
      where r.hotel_id = hotel_id_value
        and r.room_number = '801'
        and r.status = 'occupied'
        and r.room_type_id = standard_room_type_id
    );

    begin
      perform public.import_hotel_rooms(
        hotel_id_value,
        jsonb_build_array(
          jsonb_build_object(
            'room_number', '801',
            'room_type_code', 'DLX',
            'floor_code', 'F1',
            'status', 'occupied'
          )
        )
      );
    exception when others then
      occupied_reconfiguration_blocked :=
        lower(sqlerrm) like
          '%occupied/cleaning room%'
        and lower(sqlerrm) like
          '%cannot be reconfigured%';
    end;

    readiness_after_rooms :=
      public.get_hotel_onboarding_readiness(
        hotel_id_value
      );

    readiness_after_rooms_ok :=
      coalesce(
        (
          readiness_after_rooms
          -> 'checklist'
          ->> 'room_types'
        )::boolean,
        false
      )
      and coalesce(
        (
          readiness_after_rooms
          -> 'checklist'
          ->> 'rates'
        )::boolean,
        false
      )
      and coalesce(
        (
          readiness_after_rooms
          -> 'checklist'
          ->> 'floors'
        )::boolean,
        false
      )
      and coalesce(
        (
          readiness_after_rooms
          -> 'checklist'
          ->> 'rooms'
        )::boolean,
        false
      )
      and coalesce(
        (
          readiness_after_rooms
          -> 'checklist'
          ->> 'amenities'
        )::boolean,
        false
      )
      and coalesce(
        (
          readiness_after_rooms
          -> 'checklist'
          ->> 'request_categories'
        )::boolean,
        false
      )
      and coalesce(
        (
          readiness_after_rooms
          -> 'checklist'
          ->> 'qr_ready'
        )::boolean,
        false
      )
      and not coalesce(
        (
          readiness_after_rooms
          -> 'checklist'
          ->> 'menu'
        )::boolean,
        true
      );

    normalized_defaults_counts_ok :=
      (
        select count(*) >= 5
        from public.amenities a
        where a.hotel_id = hotel_id_value
          and a.is_active
      )
      and (
        select count(*) >= 4
        from public.service_request_types srt
        where srt.hotel_id = hotel_id_value
          and srt.is_active
      )
      and (
        select count(*) >= 3
        from public.menu_categories mc
        where mc.hotel_id = hotel_id_value
          and mc.is_active
      );

    select
      (
        select c.relrowsecurity
        from pg_class c
        where c.oid = 'public.amenities'::regclass
      )
      and (
        select c.relrowsecurity
        from pg_class c
        where c.oid =
          'public.service_request_types'::regclass
      )
    into new_tables_rls_ok;

    authenticated_execute_ok :=
      has_function_privilege(
        'authenticated',
        'public.configure_hotel_inventory(uuid,jsonb)',
        'EXECUTE'
      )
      and has_function_privilege(
        'authenticated',
        'public.import_hotel_rooms(uuid,jsonb)',
        'EXECUTE'
      )
      and has_function_privilege(
        'authenticated',
        'public.seed_hotel_configuration_defaults(uuid)',
        'EXECUTE'
      );

    execute 'reset role';
    role_switched := false;

    perform set_config(
      'request.jwt.claim.sub',
      '',
      true
    );
    perform set_config(
      'request.jwt.claim.role',
      'anon',
      true
    );

    execute 'set local role anon';
    role_switched := true;

    begin
      perform public.configure_hotel_inventory(
        hotel_id_value,
        '{}'::jsonb
      );
    exception
      when insufficient_privilege then
        anon_configure_blocked := true;
      when others then
        anon_configure_blocked :=
          lower(sqlerrm) like '%permission denied%';
    end;

    begin
      perform public.import_hotel_rooms(
        hotel_id_value,
        '[]'::jsonb
      );
    exception
      when insufficient_privilege then
        anon_import_blocked := true;
      when others then
        anon_import_blocked :=
          lower(sqlerrm) like '%permission denied%';
    end;

    execute 'reset role';
    role_switched := false;

    raise exception using
      errcode = 'P7919',
      message =
        'StayQR Day 8 configuration runtime acceptance rollback';
  exception
    when sqlstate 'P7919' then
      null;
    when others then
      if role_switched then
        begin
          execute 'reset role';
        exception when others then
          null;
        end;
        role_switched := false;
      end if;

      failure_details := format(
        'Audit harness failure [%s] %s',
        sqlstate,
        sqlerrm
      );
  end;

  -- ------------------------------------------------------------------------
  -- Confirm production counts and rollback.
  -- ------------------------------------------------------------------------
  select count(*) into after_hotel_count
  from public.hotels;
  select count(*) into after_room_count
  from public.rooms;
  select count(*) into after_room_type_count
  from public.room_types;
  select count(*) into after_rate_count
  from public.rate_plans;
  select count(*) into after_amenity_count
  from public.amenities;
  select count(*) into after_request_type_count
  from public.service_request_types;
  select count(*) into after_menu_category_count
  from public.menu_categories;

  production_counts_unchanged :=
    before_hotel_count = after_hotel_count
    and before_room_count = after_room_count
    and before_room_type_count = after_room_type_count
    and before_rate_count = after_rate_count
    and before_amenity_count = after_amenity_count
    and before_request_type_count =
      after_request_type_count
    and before_menu_category_count =
      after_menu_category_count;

  rollback_verified :=
    not exists (
      select 1
      from public.hotels h
      where h.slug = requested_slug
    )
    and not exists (
      select 1
      from public.hotel_onboarding ho
      where ho.bootstrap_request_id =
        request_id_value
    )
    and production_counts_unchanged;

  -- ------------------------------------------------------------------------
  -- Final 28-row result.
  -- ------------------------------------------------------------------------
  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '01_actor_and_plan_resolved',
    'passed', actor_resolved,
    'details', format(
      'Actor=%s; plan=%s.',
      coalesce(actor_email, 'NOT FOUND'),
      coalesce(plan_name_value, 'NOT FOUND')
    )
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '02_fresh_hotel_bootstrap_succeeded',
    'passed', bootstrap_ok,
    'details',
      'A reversible fresh hotel was created through the authenticated atomic bootstrap RPC.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '03_future_hotel_amenity_defaults',
    'passed', automatic_amenities_ok,
    'details', format(
      'Active amenities immediately after bootstrap=%s.',
      amenity_count_after_bootstrap
    )
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '04_future_hotel_request_defaults',
    'passed', automatic_request_types_ok,
    'details', format(
      'Active request categories immediately after bootstrap=%s.',
      request_type_count_after_bootstrap
    )
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '05_future_hotel_menu_category_defaults',
    'passed', automatic_menu_categories_ok,
    'details', format(
      'Active menu categories immediately after bootstrap=%s.',
      menu_category_count_after_bootstrap
    )
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '06_configuration_defaults_idempotent',
    'passed', defaults_idempotent_ok,
    'details',
      'Repeated default seeding inserted no duplicate amenities, request types or menu categories.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '07_inventory_configuration_rpc',
    'passed', inventory_configuration_ok,
    'details',
      'One call created one floor, two room types and two rate plans.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '08_inventory_reconfiguration_no_duplicates',
    'passed', inventory_no_duplicates_ok,
    'details',
      'Repeating inventory configuration retained one F1 floor, two room types and two rate plans.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '09_rate_plans_linked_to_correct_room_types',
    'passed', room_type_rate_linkage_ok,
    'details',
      'STD-BAR and DLX-BAR are linked to their hotel-owned room types.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '10_readiness_before_rooms_is_correct',
    'passed', readiness_before_rooms_ok,
    'details',
      'Room types, rates and floors were ready while rooms remained incomplete.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '11_first_bulk_room_import',
    'passed', first_import_ok,
    'details',
      'The first two-row import inserted both rooms atomically.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '12_imported_room_links_and_legacy_text',
    'passed', imported_room_linkage_ok,
    'details',
      'Imported rooms have correct floor_id, room_type_id and compatible room_type text.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '13_repeated_room_import_idempotent',
    'passed', repeated_import_idempotent_ok,
    'details',
      'Repeating the same room import produced two unchanged rows and no duplicates.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '14_available_room_update_allowed',
    'passed', available_room_update_ok,
    'details',
      'An available room could be moved to maintenance through the import RPC.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '15_duplicate_payload_rooms_rejected',
    'passed', duplicate_payload_rejected,
    'details',
      'Two rows with the same room number in one payload were rejected.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '16_unknown_room_type_rejected',
    'passed', unknown_room_type_rejected,
    'details',
      'An unknown active room_type_code could not create a room.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '17_unknown_floor_rejected',
    'passed', unknown_floor_rejected,
    'details',
      'An unknown active floor_code could not create a room.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '18_room_can_be_marked_occupied',
    'passed', occupied_room_marked,
    'details',
      'The import RPC preserved normal operational status updates.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '19_occupied_room_reconfiguration_blocked',
    'passed', occupied_reconfiguration_blocked,
    'details',
      'An occupied room could not be moved to another room type through bulk import.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '20_readiness_after_rooms_is_correct',
    'passed', readiness_after_rooms_ok,
    'details',
      'Rooms, rates, floors, amenities, request categories and QR readiness passed; menu items correctly remained incomplete.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '21_normalized_default_counts',
    'passed', normalized_defaults_counts_ok,
    'details',
      'Fresh hotel retained the minimum amenity, request-category and menu-category defaults.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '22_new_configuration_tables_have_rls',
    'passed', new_tables_rls_ok,
    'details',
      'Amenities and service_request_types both have RLS enabled.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '23_authenticated_rpc_execute',
    'passed', authenticated_execute_ok,
    'details',
      'Authenticated users retain execute grants on approved configuration RPCs.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '24_anonymous_configure_blocked',
    'passed', anon_configure_blocked,
    'details',
      'The real anon role could not execute inventory configuration.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '25_anonymous_room_import_blocked',
    'passed', anon_import_blocked,
    'details',
      'The real anon role could not execute room import.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '26_existing_production_counts_unchanged',
    'passed', production_counts_unchanged,
    'details', format(
      'Hotels %s→%s; rooms %s→%s; room types %s→%s; rates %s→%s; amenities %s→%s; request types %s→%s; menu categories %s→%s.',
      before_hotel_count,
      after_hotel_count,
      before_room_count,
      after_room_count,
      before_room_type_count,
      after_room_type_count,
      before_rate_count,
      after_rate_count,
      before_amenity_count,
      after_amenity_count,
      before_request_type_count,
      after_request_type_count,
      before_menu_category_count,
      after_menu_category_count
    )
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '27_synthetic_configuration_rolled_back',
    'passed', rollback_verified,
    'details',
      'The synthetic hotel, rooms, rates and defaults were fully rolled back.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '28_day8_configuration_runtime_ready',
    'passed',
      bootstrap_ok
      and inventory_configuration_ok
      and first_import_ok
      and repeated_import_idempotent_ok
      and occupied_reconfiguration_blocked
      and readiness_after_rooms_ok
      and rollback_verified,
    'details', coalesce(
      failure_details,
      'Migration 019 configuration and bulk-room runtime acceptance passed.'
    )
  ));

  return query
  select
    item.test_name,
    item.passed,
    item.details
  from jsonb_to_recordset(results)
    as item(
      test_name text,
      passed boolean,
      details text
    )
  order by item.test_name;
exception when others then
  if role_switched then
    begin
      execute 'reset role';
    exception when others then
      null;
    end;
  end if;

  return query
  select
    '00_audit_harness_error'::text,
    false,
    format('[%s] %s', sqlstate, sqlerrm);
end;
$audit$;

revoke all on function
  private.run_day8_configuration_runtime_acceptance_20260727()
from public, anon, authenticated;

comment on function
  private.run_day8_configuration_runtime_acceptance_20260727() is
  'Reversible authenticated runtime acceptance for Day 8 Migration 019 defaults, inventory configuration, room import, readiness and anon blocking. Remove after evidence export.';

select test_name, passed, details
from private.run_day8_configuration_runtime_acceptance_20260727()
order by test_name;
