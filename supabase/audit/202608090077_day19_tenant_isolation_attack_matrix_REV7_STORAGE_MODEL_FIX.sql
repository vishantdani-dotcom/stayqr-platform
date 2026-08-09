-- ============================================================================
-- StayQR v1.0
-- Day 19 Audit 077 REV7 — Final Tenant Isolation Attack Matrix
-- Gate 19C
-- Date: 2026-08-09
--
-- REV4 CORRECTION
-- The rollback-only Hotel B now gets an active rollback-only plan and current
-- trial subscription before its room is inserted. This satisfies the real
-- room subscription-capacity trigger without disabling or bypassing it.
--
-- REV3 CORRECTIONS
-- - Creates a SECOND HOTEL + ROOM only inside an outer transaction so the test
--   no longer depends on permanent Staging business data.
-- - Treats RLS-enabled policy-free RPC-owned tables as secure deny-by-default.
-- - Validates effective anonymous TABLE access rather than rejecting harmless
--   policy metadata.
-- - Validates the exact 15 current anonymous RPC signatures.
-- - Validates the current 3-bucket / 11-policy Storage contract.
-- - ROLLBACK removes the complete Hotel B fixture and all audit DDL.
--
-- Expected: 18/18 PASS.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '240s';

-- Self-contained Hotel B fixture. It is visible to the audit but is never
-- committed. Existing hotel onboarding/default triggers may populate related
-- rows; those rows are also removed by the final ROLLBACK.

-- REV4: create a rollback-only plan before the rollback-only Hotel B.
insert into public.subscription_plans (
  id,
  plan_name,
  plan_code,
  price_monthly,
  max_rooms,
  max_staff,
  max_properties,
  trial_days,
  status,
  currency_code,
  is_public,
  features
)
values (
  gen_random_uuid(),
  'Day 19 Isolation Fixture Plan',
  'D19ISO-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 16)),
  0,
  10,
  10,
  1,
  1,
  'active',
  'INR',
  false,
  '[]'::jsonb
);

insert into public.hotels (
  id,
  hotel_name,
  slug,
  status,
  subscription_status,
  timezone,
  currency_code
)
values (
  gen_random_uuid(),
  'Day 19 Isolation Fixture Hotel B',
  'day19-isolation-b-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 16),
  'active',
  'trial',
  'Asia/Kolkata',
  'INR'
);


-- REV4: rooms are protected by the real subscription-capacity trigger, so the
-- fixture hotel gets a real rollback-only current trial subscription first.
insert into public.hotel_subscriptions (
  id,
  hotel_id,
  plan_id,
  status,
  start_date,
  end_date,
  trial_started_at,
  trial_ends_at,
  billing_mode,
  billing_cycle,
  currency_code,
  amount_minor,
  provider,
  provider_status,
  current_period_start,
  current_period_end,
  metadata,
  provider_metadata
)
select
  gen_random_uuid(),
  h.id,
  sp.id,
  'trial',
  now(),
  now() + interval '1 day',
  now(),
  now() + interval '1 day',
  'trial',
  'none',
  'INR',
  0,
  'manual',
  'trial',
  now(),
  now() + interval '1 day',
  jsonb_build_object('day19_gate', '19c', 'fixture', true),
  '{}'::jsonb
from public.hotels h
cross join lateral (
  select id
  from public.subscription_plans
  where plan_name = 'Day 19 Isolation Fixture Plan'
    and plan_code like 'D19ISO-%'
  order by created_at desc, id desc
  limit 1
) sp
where h.hotel_name = 'Day 19 Isolation Fixture Hotel B'
  and h.slug like 'day19-isolation-b-%'
order by h.created_at desc, h.id desc
limit 1;



-- REV5: the current Day 13 room-reference trigger requires an ACTIVE floor
-- belonging to the same hotel before a room may be inserted.
insert into public.floors (
  id,
  hotel_id,
  name,
  code,
  floor_number,
  description,
  sort_order,
  is_active,
  metadata
)
select
  gen_random_uuid(),
  h.id,
  'Day 19 Isolation Floor',
  'D19ISO',
  19,
  'Rollback-only Gate 19C tenant-isolation floor fixture.',
  0,
  true,
  jsonb_build_object('day19_gate', '19c', 'fixture', true)
from public.hotels h
where h.hotel_name = 'Day 19 Isolation Fixture Hotel B'
  and h.slug like 'day19-isolation-b-%'
order by h.created_at desc, h.id desc
limit 1;


insert into public.room_types (
  id,
  hotel_id,
  name,
  code,
  base_occupancy,
  max_adults,
  max_children,
  max_occupancy,
  base_rate,
  is_active,
  metadata
)
select
  gen_random_uuid(),
  h.id,
  'Isolation Standard',
  'D19ISO',
  1,
  2,
  1,
  3,
  1000,
  true,
  '{}'::jsonb
from public.hotels h
where h.hotel_name = 'Day 19 Isolation Fixture Hotel B'
order by h.created_at desc
limit 1;

insert into public.rooms (
  id,
  hotel_id,
  room_number,
  room_type,
  room_type_id,
  floor_id,
  status,
  is_active,
  metadata
)
select
  gen_random_uuid(),
  h.id,
  'D19-B-101',
  rt.name,
  rt.id,
  f.id,
  'available',
  true,
  '{}'::jsonb
from public.hotels h
join public.room_types rt
  on rt.hotel_id = h.id
 and rt.code = 'D19ISO'
 and rt.is_active
join public.floors f
  on f.hotel_id = h.id
 and f.code = 'D19ISO'
 and f.is_active
where h.hotel_name = 'Day 19 Isolation Fixture Hotel B'
order by h.created_at desc
limit 1;

create or replace function private.run_day19_tenant_isolation_attack_matrix_rev5_20260809()
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
  actor_user uuid;
  actor_email text;
  actor_name text := 'Day 7 Isolation Test Actor';
  fixture_email text;
  fixture_staff_id uuid;

  hotel_a uuid;
  hotel_a_name text;
  hotel_a_slug text;
  hotel_a_room_number text;

  hotel_b uuid;
  hotel_b_name text;
  hotel_b_slug text;
  hotel_b_room uuid;
  hotel_b_room_number text;

  table_row record;
  table_names text[] := array[]::text[];
  tenant_table_count integer := 0;
  rls_all boolean := true;
  policy_all boolean := true;
  missing_rls text := '';
  missing_policy text := '';

  actor_helper_pass boolean := false;
  hotel_row_pass boolean := false;
  room_read_pass boolean := false;
  room_update_pass boolean := false;
  anon_table_pass boolean := false;
  room_guess_pass boolean := false;

  hotel_a_visible bigint := 0;
  hotel_b_visible bigint := 0;
  room_b_visible bigint := 0;
  visible_count bigint := 0;
  affected_count bigint := 0;

  read_total integer := 0;
  read_pass integer := 0;
  read_all boolean := true;
  read_failures text := '';

  update_total integer := 0;
  update_pass integer := 0;
  update_all boolean := true;
  update_failures text := '';

  portal_result jsonb;

  results jsonb := '[]'::jsonb;
  role_is_authenticated boolean := false;
  role_is_anon boolean := false;
  all_detail_probes_pass boolean := true;
  detail_probe_count integer := 0;
  fixture_completed boolean := false;
begin
  -- ------------------------------------------------------------------------
  -- Resolve one active Platform Admin Auth identity.
  -- ------------------------------------------------------------------------
  select
    pa.user_id,
    au.email
  into
    actor_user,
    actor_email
  from public.platform_admins pa
  join auth.users au on au.id = pa.user_id
  where pa.status = 'active'
    and coalesce(au.banned_until, '-infinity'::timestamptz) <= now()
  order by pa.created_at
  limit 1;

  fixture_email := format(
    'day7-isolation-%s@stayqr.invalid',
    replace(coalesce(actor_user::text, gen_random_uuid()::text), '-', '')
  );

  -- Resolve two active hotels. Prefer hotels that have rooms.
  select h.id, h.hotel_name, h.slug
  into hotel_a, hotel_a_name, hotel_a_slug
  from public.hotels h
  where h.status = 'active'
    and exists (
      select 1
      from public.rooms r
      where r.hotel_id = h.id
    )
  order by h.created_at
  limit 1;

  select h.id, h.hotel_name, h.slug
  into hotel_b, hotel_b_name, hotel_b_slug
  from public.hotels h
  where h.status = 'active'
    and h.id <> hotel_a
    and exists (
      select 1
      from public.rooms r
      where r.hotel_id = h.id
    )
  order by h.created_at
  limit 1;

  if hotel_a is not null then
    select r.room_number
    into hotel_a_room_number
    from public.rooms r
    where r.hotel_id = hotel_a
    order by r.created_at nulls last, r.room_number
    limit 1;
  end if;

  if hotel_b is not null then
    select r.id, r.room_number
    into hotel_b_room, hotel_b_room_number
    from public.rooms r
    where r.hotel_id = hotel_b
    order by r.created_at nulls last, r.room_number
    limit 1;
  end if;

  -- Inventory every current tenant-owned public table.
  for table_row in
    select
      c.relname as table_name,
      c.relrowsecurity as rls_enabled,
      (
        select count(*)::integer
        from pg_policies p
        where p.schemaname = 'public'
          and p.tablename = c.relname
      ) as policy_count
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
      and exists (
        select 1
        from pg_attribute a
        where a.attrelid = c.oid
          and a.attname = 'hotel_id'
          and a.attnum > 0
          and not a.attisdropped
      )
    order by c.relname
  loop
    tenant_table_count := tenant_table_count + 1;
    table_names := array_append(table_names, table_row.table_name);

    if not table_row.rls_enabled then
      rls_all := false;
      missing_rls := missing_rls ||
        case when missing_rls = '' then '' else ', ' end ||
        table_row.table_name;
    end if;

    if table_row.policy_count = 0 then
      -- CURRENT DAY 19 RULE:
      -- RLS-enabled RPC-owned tables may intentionally have zero browser
      -- policies; PostgreSQL then denies browser access by default.
      missing_policy := missing_policy ||
        case when missing_policy = '' then '' else ', ' end ||
        table_row.table_name;
    end if;
  end loop;

  -- ------------------------------------------------------------------------
  -- Reversible authenticated fixture and runtime probes.
  -- Every database change inside this block is rolled back by P7799.
  -- PL/pgSQL variables retain the collected audit results.
  -- ------------------------------------------------------------------------
  begin
    if actor_user is null then
      raise exception 'No active Platform Admin Auth identity is available.';
    end if;

    if hotel_a is null or hotel_b is null or hotel_a = hotel_b then
      raise exception 'Two different active hotels with rooms are required.';
    end if;

    -- Temporarily remove all Platform Admin and hotel-staff authority for the
    -- selected Auth user, then give it Hotel A Reception access only.
    update public.platform_admins
    set status = 'inactive',
        updated_at = now()
    where user_id = actor_user;

    update public.staff
    set status = 'inactive',
        disabled_at = coalesce(disabled_at, now()),
        updated_at = now()
    where auth_user_id = actor_user
      and status <> 'inactive';

    -- The selected Platform Admin may already have a staff row for Hotel A.
    -- uq_staff_hotel_auth_user applies even to inactive rows, so inserting a
    -- second row would fail. Reuse that row when present; otherwise insert a
    -- temporary one. The complete subtransaction is rolled back later.
    select s.id
    into fixture_staff_id
    from public.staff s
    where s.hotel_id = hotel_a
      and s.auth_user_id = actor_user
    order by s.created_at
    limit 1;

    if fixture_staff_id is not null then
      update public.staff
      set full_name = coalesce(nullif(trim(full_name), ''), actor_name),
          role = 'reception',
          status = 'active',
          disabled_at = null,
          accepted_at = coalesce(accepted_at, now()),
          updated_at = now(),
          updated_by = actor_user,
          identity_reconciliation_status = 'linked',
          identity_reconciliation_note =
            'Temporary Day 7 Hotel A/Hotel B isolation audit fixture.',
          identity_reconciled_at = now()
      where id = fixture_staff_id;
    else
      insert into public.staff (
        hotel_id,
        full_name,
        email,
        phone,
        role,
        status,
        auth_user_id,
        created_at,
        updated_at,
        invited_at,
        accepted_at,
        disabled_at,
        created_by,
        updated_by,
        identity_reconciliation_status,
        identity_reconciliation_note,
        identity_reconciled_at
      ) values (
        hotel_a,
        actor_name,
        fixture_email,
        null,
        'reception',
        'active',
        actor_user,
        now(),
        now(),
        now(),
        now(),
        null,
        actor_user,
        actor_user,
        'linked',
        'Temporary Day 7 Hotel A/Hotel B isolation audit fixture.',
        now()
      )
      returning id into fixture_staff_id;
    end if;

    perform set_config('request.jwt.claim.sub', actor_user::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);

    execute 'set local role authenticated';
    role_is_authenticated := true;

    begin
      actor_helper_pass :=
        private.user_has_hotel_access(hotel_a)
        and not private.user_has_hotel_access(hotel_b);
    exception when others then
      actor_helper_pass := false;
      read_failures := format(
        'Authorization helper failed [%s] %s',
        sqlstate,
        sqlerrm
      );
    end;

    begin
      select count(*) into hotel_a_visible
      from public.hotels h
      where h.id = hotel_a;

      select count(*) into hotel_b_visible
      from public.hotels h
      where h.id = hotel_b;

      hotel_row_pass := hotel_a_visible = 1 and hotel_b_visible = 0;
    exception when others then
      hotel_row_pass := false;
    end;

    if hotel_b_room is not null then
      begin
        select count(*) into room_b_visible
        from public.rooms r
        where r.id = hotel_b_room;

        room_read_pass := room_b_visible = 0;
      exception
        when insufficient_privilege then
          room_read_pass := true;
        when others then
          room_read_pass := false;
      end;

      begin
        update public.rooms
        set status = status
        where id = hotel_b_room;

        get diagnostics affected_count = row_count;

        if affected_count > 0 then
          raise exception using
            errcode = 'P7701',
            message = format(
              'RLS breach: Hotel A actor updated %s Hotel B room row(s).',
              affected_count
            );
        end if;

        room_update_pass := true;
      exception
        when sqlstate 'P7701' then
          room_update_pass := false;
        when others then
          -- Any database rejection means Hotel B could not be updated.
          room_update_pass := true;
      end;
    end if;

    foreach table_row.table_name in array table_names
    loop
      read_total := read_total + 1;
      detail_probe_count := detail_probe_count + 1;

      begin
        execute format(
          'select count(*) from public.%I where hotel_id = $1',
          table_row.table_name
        )
        into visible_count
        using hotel_b;

        if visible_count = 0 then
          read_pass := read_pass + 1;
        else
          read_all := false;
          all_detail_probes_pass := false;
          read_failures := read_failures ||
            case when read_failures = '' then '' else E'\n' end ||
            format(
              '%s exposed %s Hotel B row(s).',
              table_row.table_name,
              visible_count
            );
        end if;
      exception
        when insufficient_privilege then
          read_pass := read_pass + 1;
        when others then
          read_all := false;
          all_detail_probes_pass := false;
          read_failures := read_failures ||
            case when read_failures = '' then '' else E'\n' end ||
            format(
              '%s [%s] %s',
              table_row.table_name,
              sqlstate,
              sqlerrm
            );
      end;

      update_total := update_total + 1;
      detail_probe_count := detail_probe_count + 1;

      begin
        execute format(
          'update public.%I set hotel_id = hotel_id where hotel_id = $1',
          table_row.table_name
        )
        using hotel_b;

        get diagnostics affected_count = row_count;

        if affected_count > 0 then
          raise exception using
            errcode = 'P7702',
            message = format(
              'RLS breach: Hotel A actor updated %s Hotel B row(s) in public.%I.',
              affected_count,
              table_row.table_name
            );
        end if;

        update_pass := update_pass + 1;
      exception
        when sqlstate 'P7702' then
          update_all := false;
          all_detail_probes_pass := false;
          update_failures := update_failures ||
            case when update_failures = '' then '' else E'\n' end ||
            sqlerrm;
        when others then
          -- Permission, immutable-record and validation errors all prove that
          -- the Hotel B update did not succeed.
          update_pass := update_pass + 1;
      end;
    end loop;

    execute 'reset role';
    role_is_authenticated := false;

    fixture_completed := true;

    -- Roll back the temporary Platform Admin status and staff fixture.
    raise exception using
      errcode = 'P7799',
      message = 'StayQR Day 7 isolation fixture rollback';
  exception
    when sqlstate 'P7799' then
      null;
    when others then
      if role_is_authenticated then
        begin
          execute 'reset role';
        exception when others then
          null;
        end;
        role_is_authenticated := false;
      end if;

      fixture_completed := false;
      actor_helper_pass := false;
      hotel_row_pass := false;
      room_read_pass := false;
      room_update_pass := false;
      read_all := false;
      update_all := false;
      all_detail_probes_pass := false;

      read_failures := read_failures ||
        case when read_failures = '' then '' else E'\n' end ||
        format('Reversible fixture failed [%s] %s', sqlstate, sqlerrm);
  end;

  -- Confirm the fixture was rolled back and Platform Admin access restored.
  if actor_user is not null and not exists (
    select 1
    from public.platform_admins pa
    where pa.user_id = actor_user
      and pa.status = 'active'
  ) then
    fixture_completed := false;
    all_detail_probes_pass := false;
    read_failures := read_failures ||
      case when read_failures = '' then '' else E'\n' end ||
      'Platform Admin status was not restored after fixture rollback.';
  end if;

  -- ------------------------------------------------------------------------
  -- Anonymous runtime probes.
  -- ------------------------------------------------------------------------
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', 'anon', true);

  begin
    execute 'set local role anon';
    role_is_anon := true;

    begin
      select count(*) into visible_count
      from public.rooms;

      anon_table_pass := visible_count = 0;
    exception
      when insufficient_privilege then
        anon_table_pass := true;
      when others then
        anon_table_pass := false;
    end;

    if hotel_a_slug is not null and hotel_a_room_number is not null then
      begin
        portal_result := public.resolve_guest_portal(
          hotel_a_slug,
          hotel_a_room_number
        );

        room_guess_pass := portal_result is null;
      exception when others then
        room_guess_pass := true;
      end;
    else
      room_guess_pass := false;
    end if;

    execute 'reset role';
    role_is_anon := false;
  exception when others then
    if role_is_anon then
      begin
        execute 'reset role';
      exception when others then
        null;
      end;
      role_is_anon := false;
    end if;

    anon_table_pass := false;
    room_guess_pass := false;
    all_detail_probes_pass := false;
  end;

  detail_probe_count := detail_probe_count + 6;

  if not fixture_completed
     or not actor_helper_pass
     or not hotel_row_pass
     or not room_read_pass
     or not room_update_pass
     or not anon_table_pass
     or not room_guess_pass
  then
    all_detail_probes_pass := false;
  end if;

  -- ------------------------------------------------------------------------
  -- Build exactly 18 final result rows.
  -- ------------------------------------------------------------------------
  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '01_two_active_hotels_resolved',
    'passed', hotel_a is not null and hotel_b is not null and hotel_a <> hotel_b,
    'details', format(
      'Hotel A: %s; Hotel B: %s.',
      coalesce(hotel_a_name, 'NOT FOUND'),
      coalesce(hotel_b_name, 'NOT FOUND')
    )
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '02_reversible_hotel_a_actor_fixture',
    'passed', fixture_completed and actor_user is not null,
    'details', format(
      'Temporarily tested Auth identity %s as Hotel A Reception; all fixture changes were rolled back.',
      coalesce(actor_email, actor_user::text, 'NOT FOUND')
    )
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '03_authorization_helper_isolation',
    'passed', actor_helper_pass,
    'details', 'Hotel A actor had Hotel A access and no Hotel B access.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '04_hotel_row_isolation',
    'passed', hotel_row_pass,
    'details', format(
      'Hotel A visible rows=%s; Hotel B visible rows=%s.',
      hotel_a_visible,
      hotel_b_visible
    )
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '05_tenant_table_inventory',
    'passed', tenant_table_count >= 21,
    'details', format(
      '%s public tenant table(s) carrying hotel_id were inventoried.',
      tenant_table_count
    )
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '06_all_tenant_tables_have_rls',
    'passed', rls_all,
    'details', case
      when rls_all then format('RLS is enabled on all %s tenant tables.', tenant_table_count)
      else 'RLS missing on: ' || missing_rls
    end
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '07_all_tenant_tables_policy_or_deny_by_default',
    'passed', rls_all,
    'details',
      case
        when missing_policy = '' then
          'Every tenant table has explicit RLS policy coverage.'
        else
          'All tenant tables have RLS; policy-free RPC-owned tables deny browser access by default: ' ||
          missing_policy
      end
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '08_hotel_a_cannot_read_hotel_b_tables',
    'passed', read_all and read_total = tenant_table_count,
    'details', format(
      '%s/%s tenant-table read probes passed.%s',
      read_pass,
      read_total,
      case when read_failures = '' then '' else E'\n' || read_failures end
    )
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '09_hotel_a_cannot_update_hotel_b_tables',
    'passed', update_all and update_total = tenant_table_count,
    'details', format(
      '%s/%s tenant-table update probes passed.%s',
      update_pass,
      update_total,
      case when update_failures = '' then '' else E'\n' || update_failures end
    )
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '10_hotel_b_room_hidden',
    'passed', room_read_pass,
    'details', format(
      'Selected Hotel B room visible to Hotel A actor=%s.',
      room_b_visible
    )
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '11_hotel_b_room_update_blocked',
    'passed', room_update_pass,
    'details', 'Hotel A actor could not update the selected Hotel B room.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '12_anonymous_direct_table_access_blocked',
    'passed', anon_table_pass,
    'details', 'Anonymous direct access to public.rooms is denied or returns zero rows.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '13_room_number_guessing_rejected',
    'passed', room_guess_pass,
    'details', format(
      'Correct hotel slug plus room number %s was rejected as a guest credential.',
      coalesce(hotel_a_room_number, 'NOT FOUND')
    )
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '14_no_anonymous_effective_public_table_access',
    'passed',
      not exists (
        select 1
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public'
          and c.relkind in ('r','p','v','m')
          and (
            has_table_privilege('anon', c.oid, 'SELECT')
            or has_table_privilege('anon', c.oid, 'INSERT')
            or has_table_privilege('anon', c.oid, 'UPDATE')
            or has_table_privilege('anon', c.oid, 'DELETE')
          )
      ),
    'details',
      'Anonymous has no effective SELECT/INSERT/UPDATE/DELETE privilege on any public relation; guest access is RPC-only.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '15_exact_approved_anonymous_rpc_surface',
    'passed',
      not exists (
        select 1
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and has_function_privilege('anon', p.oid, 'EXECUTE')
          and not (
            p.oid = any(array[
          'public.cancel_guest_food_order(text,text,uuid,text)'::regprocedure::oid,
          'public.cancel_guest_service_request(text,text,uuid,text)'::regprocedure::oid,
          'public.create_guest_service_request(text,text,text)'::regprocedure::oid,
          'public.get_guest_food_menu(text,text)'::regprocedure::oid,
          'public.get_guest_food_orders(text,text)'::regprocedure::oid,
          'public.get_guest_notifications(text,text)'::regprocedure::oid,
          'public.get_guest_service_catalog(text,text)'::regprocedure::oid,
          'public.get_guest_service_requests(text,text)'::regprocedure::oid,
          'public.place_guest_food_order(text,text,jsonb)'::regprocedure::oid,
          'public.record_guest_guide_event(text,text,text,text,uuid,text,jsonb)'::regprocedure::oid,
          'public.record_guest_review_reward_action(text,text,text)'::regprocedure::oid,
          'public.resolve_guest_portal(text,text)'::regprocedure::oid,
          'public.resolve_premium_guest_guide(text,text)'::regprocedure::oid,
          'public.submit_guest_feedback(text,text,integer,text,boolean)'::regprocedure::oid,
          'public.verify_invoice(uuid)'::regprocedure::oid
            ]::oid[])
          )
      )
      and not exists (
        select allowed_oid
        from unnest(array[
          'public.cancel_guest_food_order(text,text,uuid,text)'::regprocedure::oid,
          'public.cancel_guest_service_request(text,text,uuid,text)'::regprocedure::oid,
          'public.create_guest_service_request(text,text,text)'::regprocedure::oid,
          'public.get_guest_food_menu(text,text)'::regprocedure::oid,
          'public.get_guest_food_orders(text,text)'::regprocedure::oid,
          'public.get_guest_notifications(text,text)'::regprocedure::oid,
          'public.get_guest_service_catalog(text,text)'::regprocedure::oid,
          'public.get_guest_service_requests(text,text)'::regprocedure::oid,
          'public.place_guest_food_order(text,text,jsonb)'::regprocedure::oid,
          'public.record_guest_guide_event(text,text,text,text,uuid,text,jsonb)'::regprocedure::oid,
          'public.record_guest_review_reward_action(text,text,text)'::regprocedure::oid,
          'public.resolve_guest_portal(text,text)'::regprocedure::oid,
          'public.resolve_premium_guest_guide(text,text)'::regprocedure::oid,
          'public.submit_guest_feedback(text,text,integer,text,boolean)'::regprocedure::oid,
          'public.verify_invoice(uuid)'::regprocedure::oid
        ]::oid[]) as x(allowed_oid)
        where not has_function_privilege('anon', x.allowed_oid, 'EXECUTE')
      ),
    'details',
      'Anonymous EXECUTE is exactly the 15 accepted signed-guest/invoice RPC signatures.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '16_guest_token_tenant_binding_consistent',
    'passed',
      not exists (
        select 1
        from public.guest_access_tokens t
        join public.guest_sessions gs on gs.id = t.guest_session_id
        join public.rooms r on r.id = t.room_id
        where t.hotel_id <> gs.hotel_id
           or t.room_id <> gs.room_id
           or t.hotel_id <> r.hotel_id
      ),
    'details', 'Every token remains bound to one hotel, room and authoritative stay.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '17_current_storage_rls_and_policy_matrix',
    'passed',
      exists (
        select 1
        from storage.buckets
        where id = 'hotel-assets'
          and public = false
      )
      and exists (
        select 1
        from storage.buckets
        where id = 'guest-documents'
          and public = false
      )
      and exists (
        select 1
        from storage.buckets
        where id = 'guest-guide-media'
          and public = true
      )
      and coalesce((
        select c.relrowsecurity
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'storage'
          and c.relname = 'objects'
      ), false)
      and (
        select count(*) = 11
        from pg_policies
        where schemaname = 'storage'
          and tablename = 'objects'
          and policyname = any(array[
            'stayqr_hotel_assets_select',
            'stayqr_hotel_assets_insert',
            'stayqr_hotel_assets_update',
            'stayqr_hotel_assets_delete',
            'stayqr_guest_documents_select',
            'stayqr_guest_documents_insert',
            'stayqr_guest_documents_update',
            'stayqr_guest_documents_delete',
            'stayqr_guest_guide_media_insert',
            'stayqr_guest_guide_media_update',
            'stayqr_guest_guide_media_delete'
          ]::text[])
      )
      and has_function_privilege(
        'authenticated',
        'private.storage_object_hotel_id(text)',
        'EXECUTE'
      )
      and not has_function_privilege(
        'anon',
        'private.storage_object_hotel_id(text)',
        'EXECUTE'
      ),
    'details',
      'Storage access model is canonical: bucket visibility, storage.objects RLS, all 11 StayQR policies, and authenticated-only path helper are present.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '18_no_cross_tenant_runtime_failures',
    'passed', all_detail_probes_pass,
    'details', format(
      '%s detailed authenticated/anonymous runtime probes were evaluated.',
      detail_probe_count
    )
  ));

  return query
  select
    item.test_name,
    item.passed,
    item.details
  from jsonb_to_recordset(results)
    as item(test_name text, passed boolean, details text)
  order by item.test_name;
exception when others then
  if role_is_authenticated or role_is_anon then
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

revoke all on function private.run_day19_tenant_isolation_attack_matrix_rev5_20260809()
from public, anon, authenticated;

comment on function private.run_day19_tenant_isolation_attack_matrix_rev5_20260809() is
  'Day 7 reversible Hotel A/Hotel B runtime isolation exit-gate audit. REV5 reuses an existing Hotel A staff identity when present and rolls back all fixture changes.';


drop table if exists pg_temp.day19_a077_results;

create temporary table day19_a077_results
on commit preserve rows
as
select test_name, passed, details
from private.run_day19_tenant_isolation_attack_matrix_rev5_20260809()
order by test_name;

select test_name, passed, details
from day19_a077_results
order by test_name;

select
  count(*) as total_checks,
  count(*) filter (where passed) as passed_checks,
  count(*) filter (where not passed) as failed_checks
from day19_a077_results;

do $$
declare
  failed_count integer;
begin
  select count(*) into failed_count
  from day19_a077_results
  where not passed;

  if failed_count <> 0 then
    raise exception
      'Audit 077 REV7 failed: % tenant-isolation attack check(s) failed.',
      failed_count;
  end if;
end
$$;

select '=== AUDIT 077 REV7 PASS - GATE 19C TENANT ISOLATION ATTACK MATRIX 18/18 ==='::text as gate_result;

rollback;
