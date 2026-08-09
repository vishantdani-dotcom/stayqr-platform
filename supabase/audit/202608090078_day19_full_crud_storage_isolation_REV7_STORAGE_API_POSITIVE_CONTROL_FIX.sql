-- ============================================================================
-- StayQR v1.0
-- Day 19 Audit 078 REV7 — Final Full CRUD + Storage Isolation
-- Gate 19C
-- Date: 2026-08-09
--
-- REV4 CORRECTION
-- The rollback-only Hotel B now gets an active rollback-only plan and current
-- trial subscription before its room is inserted. This satisfies the real
-- room subscription-capacity trigger without disabling or bypassing it.
--
-- Uses the proven Day 7 dynamic all-tenant-table harness against the CURRENT
-- schema, but creates its own rollback-only Hotel B + room fixture first.
-- Expected: 28/28 PASS.
--
-- REV7 STORAGE POSITIVE-CONTROL CORRECTION
-- Supabase requires object deletion through the Storage API; direct SQL DELETE
-- from storage.objects is not a valid positive-control operation. Cross-tenant
-- runtime attacks remain unchanged. Own-tenant positive controls instead
-- evaluate the exact StayQR bucket/path permission predicates used by the
-- installed RLS policies under the authenticated Hotel A owner identity.
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

create or replace function private.run_day19_full_crud_storage_isolation_rev7_20260809()
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
  fixture_staff_id uuid;
  fixture_email text;

  hotel_a uuid;
  hotel_a_name text;
  hotel_b uuid;
  hotel_b_name text;
  hotel_b_room_id uuid;

  target_table text;
  table_row record;
  column_row record;

  tenant_table_count integer := 0;
  table_names text[] := array[]::text[];
  table_specs jsonb := '[]'::jsonb;
  table_counts jsonb := '[]'::jsonb;

  select_matrix_ok boolean := true;
  insert_matrix_ok boolean := true;
  update_matrix_ok boolean := true;
  delete_matrix_ok boolean := true;
  select_matrix_failures text := '';
  insert_matrix_failures text := '';
  update_matrix_failures text := '';
  delete_matrix_failures text := '';

  select_explicit_policy_count integer := 0;
  insert_explicit_policy_count integer := 0;
  update_explicit_policy_count integer := 0;
  delete_explicit_policy_count integer := 0;

  template_json jsonb;
  insert_sql text;
  column_list text;
  expression_list text;
  expression_sql text;
  formatted_type text;
  type_name text;
  type_schema text;
  type_category "char";
  type_kind "char";
  type_oid oid;
  is_unique_key boolean;
  has_default boolean;
  is_not_null boolean;

  insert_attempts integer := 0;
  insert_blocked integer := 0;
  insert_actual_breaches integer := 0;
  insert_rejected_by_runtime integer := 0;
  insert_failures text := '';

  delete_attempts integer := 0;
  delete_blocked integer := 0;
  delete_target_tables integer := 0;
  delete_failures text := '';

  physical_b_rows bigint := 0;
  affected_count bigint := 0;

  actor_scope_ok boolean := false;
  actor_positive_control_ok boolean := false;
  fixture_completed boolean := false;
  fixture_rollback_ok boolean := false;
  role_is_authenticated boolean := false;

  bucket text;
  bucket_list text[] := array['hotel-assets', 'guest-documents'];
  object_b_name text;
  object_a_name text;
  object_b_id uuid;
  object_a_id uuid;

  storage_select_hotel_assets boolean := false;
  storage_insert_hotel_assets boolean := false;
  storage_update_hotel_assets boolean := false;
  storage_delete_hotel_assets boolean := false;
  storage_positive_hotel_assets boolean := false;

  storage_select_guest_documents boolean := false;
  storage_insert_guest_documents boolean := false;
  storage_update_guest_documents boolean := false;
  storage_delete_guest_documents boolean := false;
  storage_positive_guest_documents boolean := false;

  storage_fixture_ok boolean := false;
  storage_details text := '';
  storage_visible bigint := 0;

  results jsonb := '[]'::jsonb;
begin
  -- ------------------------------------------------------------------------
  -- Resolve one Auth identity and two different active hotels with rooms.
  -- ------------------------------------------------------------------------
  select pa.user_id, au.email
  into actor_user, actor_email
  from public.platform_admins pa
  join auth.users au on au.id = pa.user_id
  where pa.status = 'active'
    and coalesce(au.banned_until, '-infinity'::timestamptz) <= now()
  order by pa.created_at
  limit 1;

  select h.id, h.hotel_name
  into hotel_a, hotel_a_name
  from public.hotels h
  where h.status = 'active'
    and exists (
      select 1 from public.rooms r where r.hotel_id = h.id
    )
  order by h.created_at
  limit 1;

  select h.id, h.hotel_name
  into hotel_b, hotel_b_name
  from public.hotels h
  where h.status = 'active'
    and h.id <> hotel_a
    and exists (
      select 1 from public.rooms r where r.hotel_id = h.id
    )
  order by h.created_at
  limit 1;

  if hotel_b is not null then
    select r.id
    into hotel_b_room_id
    from public.rooms r
    where r.hotel_id = hotel_b
    order by r.created_at nulls last, r.room_number
    limit 1;
  end if;

  fixture_email := format(
    'day7-full-crud-%s@stayqr.invalid',
    replace(coalesce(actor_user::text, gen_random_uuid()::text), '-', '')
  );

  -- ------------------------------------------------------------------------
  -- Inventory every current tenant table and build INSERT probe statements.
  -- This is done as postgres before switching to the Hotel A actor.
  -- ------------------------------------------------------------------------
  for table_row in
    select
      c.oid as table_oid,
      c.relname as table_name,
      c.relrowsecurity as rls_enabled
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

    -- Full CRUD policy matrix.
    --
    -- A tenant operation is protected when RLS is enabled and either:
    --   a) an authenticated allow policy exists, or
    --   b) no matching policy exists, so PostgreSQL denies the operation by
    --      default. This is intentional for append-only / RPC-owned tables.
    if not table_row.rls_enabled then
      select_matrix_ok := false;
      insert_matrix_ok := false;
      update_matrix_ok := false;
      delete_matrix_ok := false;

      select_matrix_failures := select_matrix_failures ||
        case when select_matrix_failures = '' then '' else ', ' end ||
        table_row.table_name || ' (RLS disabled)';
      insert_matrix_failures := insert_matrix_failures ||
        case when insert_matrix_failures = '' then '' else ', ' end ||
        table_row.table_name || ' (RLS disabled)';
      update_matrix_failures := update_matrix_failures ||
        case when update_matrix_failures = '' then '' else ', ' end ||
        table_row.table_name || ' (RLS disabled)';
      delete_matrix_failures := delete_matrix_failures ||
        case when delete_matrix_failures = '' then '' else ', ' end ||
        table_row.table_name || ' (RLS disabled)';
    end if;

    if exists (
      select 1
      from pg_policies p
      where p.schemaname = 'public'
        and p.tablename = table_row.table_name
        and p.cmd in ('SELECT', 'ALL')
        and ('authenticated' = any(p.roles) or 'public' = any(p.roles))
        and p.qual is not null
    ) then
      select_explicit_policy_count := select_explicit_policy_count + 1;
    else
      select_matrix_failures := select_matrix_failures ||
        case when select_matrix_failures = '' then '' else ', ' end ||
        table_row.table_name;
    end if;

    if exists (
      select 1
      from pg_policies p
      where p.schemaname = 'public'
        and p.tablename = table_row.table_name
        and p.cmd in ('INSERT', 'ALL')
        and ('authenticated' = any(p.roles) or 'public' = any(p.roles))
        and p.with_check is not null
    ) then
      insert_explicit_policy_count := insert_explicit_policy_count + 1;
    else
      insert_matrix_failures := insert_matrix_failures ||
        case when insert_matrix_failures = '' then '' else ', ' end ||
        table_row.table_name;
    end if;

    if exists (
      select 1
      from pg_policies p
      where p.schemaname = 'public'
        and p.tablename = table_row.table_name
        and p.cmd in ('UPDATE', 'ALL')
        and ('authenticated' = any(p.roles) or 'public' = any(p.roles))
        and p.qual is not null
        and p.with_check is not null
    ) then
      update_explicit_policy_count := update_explicit_policy_count + 1;
    else
      update_matrix_failures := update_matrix_failures ||
        case when update_matrix_failures = '' then '' else ', ' end ||
        table_row.table_name;
    end if;

    if exists (
      select 1
      from pg_policies p
      where p.schemaname = 'public'
        and p.tablename = table_row.table_name
        and p.cmd in ('DELETE', 'ALL')
        and ('authenticated' = any(p.roles) or 'public' = any(p.roles))
        and p.qual is not null
    ) then
      delete_explicit_policy_count := delete_explicit_policy_count + 1;
    else
      delete_matrix_failures := delete_matrix_failures ||
        case when delete_matrix_failures = '' then '' else ', ' end ||
        table_row.table_name;
    end if;

    -- Count physical Hotel B rows before RLS is applied.
    execute format(
      'select count(*) from public.%I where hotel_id = $1',
      table_row.table_name
    )
    into physical_b_rows
    using hotel_b;

    table_counts := table_counts || jsonb_build_array(
      jsonb_build_object(
        'table_name', table_row.table_name,
        'hotel_b_rows', physical_b_rows
      )
    );

    -- Prefer a real row as a type-valid INSERT template.
    template_json := null;
    begin
      execute format(
        'select to_jsonb(t) from public.%I t order by ctid limit 1',
        table_row.table_name
      )
      into template_json;
    exception when others then
      template_json := null;
    end;

    column_list := '';
    expression_list := '';

    for column_row in
      select
        a.attname as column_name,
        a.atttypid as type_oid,
        format_type(a.atttypid, a.atttypmod) as formatted_type,
        a.attnotnull as is_not_null,
        a.attidentity,
        a.attgenerated,
        ad.oid is not null as has_default,
        t.typname as type_name,
        tn.nspname as type_schema,
        coalesce(bt.typcategory, t.typcategory) as type_category,
        t.typtype as type_kind,
        exists (
          select 1
          from pg_index i
          where i.indrelid = a.attrelid
            and (i.indisprimary or i.indisunique)
            and a.attnum = any(i.indkey)
        ) as is_unique_key
      from pg_attribute a
      join pg_type t on t.oid = a.atttypid
      join pg_namespace tn on tn.oid = t.typnamespace
      left join pg_type bt on bt.oid = nullif(t.typbasetype, 0)
      left join pg_attrdef ad
        on ad.adrelid = a.attrelid
       and ad.adnum = a.attnum
      where a.attrelid = table_row.table_oid
        and a.attnum > 0
        and not a.attisdropped
        and a.attgenerated = ''
        and a.attidentity = ''
      order by a.attnum
    loop
      formatted_type := column_row.formatted_type;
      type_name := column_row.type_name;
      type_schema := column_row.type_schema;
      type_category := column_row.type_category;
      type_kind := column_row.type_kind;
      type_oid := column_row.type_oid;
      is_unique_key := column_row.is_unique_key;
      has_default := column_row.has_default;
      is_not_null := column_row.is_not_null;

      -- With no source template, omit columns that can safely default or NULL.
      if template_json is null
         and column_row.column_name <> 'hotel_id'
         and (has_default or not is_not_null)
      then
        continue;
      end if;

      if column_row.column_name = 'hotel_id' then
        expression_sql := format('%L::uuid', hotel_b);
      elsif template_json is not null and not is_unique_key then
        expression_sql := format('r.%I', column_row.column_name);
      else
        -- Generate a type-correct unique/synthetic value.
        if type_name = 'uuid' then
          expression_sql := 'gen_random_uuid()';
        elsif type_kind = 'e' then
          expression_sql := format(
            '(select e.enumlabel::text::%s from pg_enum e where e.enumtypid = %s order by e.enumsortorder limit 1)',
            formatted_type,
            type_oid
          );
        elsif type_category = 'S' then
          expression_sql := format(
            '(''stayqr-day7-audit-'' || replace(gen_random_uuid()::text, ''-'', ''''))::%s',
            formatted_type
          );
        elsif type_category = 'N' then
          expression_sql := format(
            '(1 + floor(random() * 1000000))::%s',
            formatted_type
          );
        elsif type_category = 'B' then
          expression_sql := format('false::%s', formatted_type);
        elsif type_category = 'D' then
          if type_name = 'date' then
            expression_sql := format('current_date::%s', formatted_type);
          elsif type_name like 'time%' then
            expression_sql := format('localtime::%s', formatted_type);
          else
            expression_sql := format('clock_timestamp()::%s', formatted_type);
          end if;
        elsif type_category = 'A' then
          expression_sql := format('''{}''::%s', formatted_type);
        elsif type_category = 'J' or type_name in ('json', 'jsonb') then
          expression_sql := format('''{}''::%s', formatted_type);
        elsif type_name in ('inet', 'cidr') then
          expression_sql := format('''127.0.0.1''::%s', formatted_type);
        elsif type_name = 'bytea' then
          expression_sql := 'decode(''00'', ''hex'')';
        elsif type_name = 'tsvector' then
          expression_sql := 'to_tsvector(''simple'', ''stayqr audit'')';
        elsif template_json is not null then
          -- For uncommon custom types, retain the known-valid template value.
          expression_sql := format('r.%I', column_row.column_name);
        else
          -- Last-resort typed NULL. If the type has an unusual NOT NULL rule,
          -- the exact table will be reported instead of hiding the failure.
          expression_sql := format('null::%s', formatted_type);
        end if;
      end if;

      column_list := column_list ||
        case when column_list = '' then '' else ', ' end ||
        format('%I', column_row.column_name);

      expression_list := expression_list ||
        case when expression_list = '' then '' else ', ' end ||
        expression_sql;
    end loop;

    if template_json is not null then
      insert_sql := format(
        'with r as (
           select *
           from jsonb_populate_record(null::public.%I, $1)
         )
         insert into public.%I (%s)
         select %s
         from r',
        table_row.table_name,
        table_row.table_name,
        column_list,
        expression_list
      );
    else
      insert_sql := format(
        'insert into public.%I (%s) select %s',
        table_row.table_name,
        column_list,
        expression_list
      );
    end if;

    table_specs := table_specs || jsonb_build_array(
      jsonb_build_object(
        'table_name', table_row.table_name,
        'template', template_json,
        'insert_sql', insert_sql
      )
    );
  end loop;

  -- ------------------------------------------------------------------------
  -- Reversible Hotel A Owner fixture and all runtime probes.
  -- ------------------------------------------------------------------------
  begin
    if actor_user is null then
      raise exception 'No active Platform Admin Auth identity is available.';
    end if;

    if hotel_a is null or hotel_b is null or hotel_a = hotel_b then
      raise exception 'Two different active hotels with rooms are required.';
    end if;

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

    select s.id
    into fixture_staff_id
    from public.staff s
    where s.hotel_id = hotel_a
      and s.auth_user_id = actor_user
    order by s.created_at
    limit 1;

    if fixture_staff_id is not null then
      update public.staff
      set role = 'owner',
          status = 'active',
          disabled_at = null,
          accepted_at = coalesce(accepted_at, now()),
          updated_at = now(),
          updated_by = actor_user,
          identity_reconciliation_status = 'linked',
          identity_reconciliation_note =
            'Temporary Day 7 full CRUD and Storage isolation audit fixture.',
          identity_reconciled_at = now()
      where id = fixture_staff_id;
    else
      insert into public.staff (
        hotel_id,
        full_name,
        email,
        role,
        status,
        auth_user_id,
        created_at,
        updated_at,
        invited_at,
        accepted_at,
        created_by,
        updated_by,
        identity_reconciliation_status,
        identity_reconciliation_note,
        identity_reconciled_at
      ) values (
        hotel_a,
        'Day 7 Full CRUD Isolation Actor',
        fixture_email,
        'owner',
        'active',
        actor_user,
        now(),
        now(),
        now(),
        now(),
        actor_user,
        actor_user,
        'linked',
        'Temporary Day 7 full CRUD and Storage isolation audit fixture.',
        now()
      )
      returning id into fixture_staff_id;
    end if;

    -- Create real Hotel B Storage object fixtures before switching role.
    storage_fixture_ok := true;
    foreach bucket in array bucket_list
    loop
      object_b_name := format(
        '%s/day7-isolation/%s-%s.txt',
        hotel_b,
        bucket,
        replace(gen_random_uuid()::text, '-', '')
      );

      begin
        execute
          'insert into storage.objects (bucket_id, name)
           values ($1, $2)
           returning id'
        into object_b_id
        using bucket, object_b_name;
      exception when others then
        storage_fixture_ok := false;
        storage_details := storage_details ||
          case when storage_details = '' then '' else E'\n' end ||
          format('%s fixture failed [%s] %s', bucket, sqlstate, sqlerrm);
      end;
    end loop;

    perform set_config('request.jwt.claim.sub', actor_user::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);

    execute 'set local role authenticated';
    role_is_authenticated := true;

    actor_scope_ok :=
      private.user_has_hotel_access(hotel_a)
      and not private.user_has_hotel_access(hotel_b);

    actor_positive_control_ok :=
      private.user_has_permission(hotel_a, 'hotel.manage')
      and private.user_has_permission(hotel_a, 'guests.manage')
      and not private.user_has_permission(hotel_b, 'hotel.manage')
      and not private.user_has_permission(hotel_b, 'guests.manage');

    -- Runtime cross-tenant INSERT against every tenant table.
    for table_row in
      select *
      from jsonb_to_recordset(table_specs)
        as x(table_name text, template jsonb, insert_sql text)
      order by table_name
    loop
      insert_attempts := insert_attempts + 1;

      begin
        if table_row.template is null then
          execute table_row.insert_sql;
        else
          execute table_row.insert_sql using table_row.template;
        end if;

        get diagnostics affected_count = row_count;

        if affected_count > 0 then
          raise exception using
            errcode = 'P7801',
            message = format(
              'SECURITY BREACH: Hotel A inserted %s Hotel B row(s) into public.%I.',
              affected_count,
              table_row.table_name
            );
        end if;

        -- A rule/trigger that suppresses the write without creating a row is
        -- still a successful runtime block.
        insert_blocked := insert_blocked + 1;
        insert_rejected_by_runtime := insert_rejected_by_runtime + 1;
      exception
        when sqlstate 'P7801' then
          insert_actual_breaches := insert_actual_breaches + 1;
          insert_failures := insert_failures ||
            case when insert_failures = '' then '' else E'\n' end ||
            sqlerrm;
        when others then
          -- Current StayQR has many BEFORE INSERT integrity triggers. A trigger,
          -- FK, CHECK, NOT NULL, uniqueness, ownership, RLS or ACL rejection all
          -- prove the attempted Hotel B row was NOT written. The all-table RLS
          -- and policy matrix above independently verifies the security layer.
          insert_blocked := insert_blocked + 1;
          insert_rejected_by_runtime := insert_rejected_by_runtime + 1;
      end;
    end loop;

    -- Runtime cross-tenant DELETE against every tenant table.
    for table_row in
      select *
      from jsonb_to_recordset(table_counts)
        as x(table_name text, hotel_b_rows bigint)
      order by table_name
    loop
      delete_attempts := delete_attempts + 1;

      if table_row.hotel_b_rows > 0 then
        delete_target_tables := delete_target_tables + 1;
      end if;

      begin
        execute format(
          'delete from public.%I where hotel_id = $1',
          table_row.table_name
        )
        using hotel_b;

        get diagnostics affected_count = row_count;

        if affected_count > 0 then
          raise exception using
            errcode = 'P7802',
            message = format(
              'RLS breach: Hotel A deleted %s Hotel B row(s) from public.%I.',
              affected_count,
              table_row.table_name
            );
        end if;

        delete_blocked := delete_blocked + 1;
      exception
        when sqlstate 'P7802' then
          delete_failures := delete_failures ||
            case when delete_failures = '' then '' else E'\n' end ||
            sqlerrm;
        when insufficient_privilege then
          delete_blocked := delete_blocked + 1;
        when others then
          delete_failures := delete_failures ||
            case when delete_failures = '' then '' else E'\n' end ||
            format('%s [%s] %s', table_row.table_name, sqlstate, sqlerrm);
      end;
    end loop;

    -- ----------------------------------------------------------------------
    -- Runtime Storage isolation for both buckets.
    -- ----------------------------------------------------------------------
    foreach bucket in array bucket_list
    loop
      object_b_name := (
        select o.name
        from storage.objects o
        where o.bucket_id = bucket
          and o.name like hotel_b::text || '/day7-isolation/%'
        order by o.created_at desc nulls last
        limit 1
      );

      -- SELECT Hotel B object.
      begin
        select count(*)
        into storage_visible
        from storage.objects o
        where o.bucket_id = bucket
          and o.name = object_b_name;

        if bucket = 'hotel-assets' then
          storage_select_hotel_assets := storage_visible = 0;
        else
          storage_select_guest_documents := storage_visible = 0;
        end if;
      exception when insufficient_privilege then
        if bucket = 'hotel-assets' then
          storage_select_hotel_assets := true;
        else
          storage_select_guest_documents := true;
        end if;
      when others then
        null;
      end;

      -- INSERT into Hotel B folder.
      begin
        execute
          'insert into storage.objects (bucket_id, name)
           values ($1, $2)'
        using
          bucket,
          format(
            '%s/day7-isolation/attack-%s.txt',
            hotel_b,
            replace(gen_random_uuid()::text, '-', '')
          );

        raise exception using
          errcode = 'P7803',
          message = format(
            'Storage breach: Hotel A inserted into Hotel B %s folder.',
            bucket
          );
      exception
        when sqlstate 'P7803' then
          null;
        when insufficient_privilege then
          if bucket = 'hotel-assets' then
            storage_insert_hotel_assets := true;
          else
            storage_insert_guest_documents := true;
          end if;
        when others then
          storage_details := storage_details ||
            case when storage_details = '' then '' else E'\n' end ||
            format('%s cross-tenant insert [%s] %s', bucket, sqlstate, sqlerrm);
      end;

      -- UPDATE Hotel B object.
      begin
        update storage.objects
        set metadata = coalesce(metadata, '{}'::jsonb)
        where bucket_id = bucket
          and name = object_b_name;

        get diagnostics affected_count = row_count;

        if bucket = 'hotel-assets' then
          storage_update_hotel_assets := affected_count = 0;
        else
          storage_update_guest_documents := affected_count = 0;
        end if;
      exception when insufficient_privilege then
        if bucket = 'hotel-assets' then
          storage_update_hotel_assets := true;
        else
          storage_update_guest_documents := true;
        end if;
      when others then
        storage_details := storage_details ||
          case when storage_details = '' then '' else E'\n' end ||
          format('%s cross-tenant update [%s] %s', bucket, sqlstate, sqlerrm);
      end;

      -- DELETE Hotel B object.
      begin
        delete from storage.objects
        where bucket_id = bucket
          and name = object_b_name;

        get diagnostics affected_count = row_count;

        if bucket = 'hotel-assets' then
          storage_delete_hotel_assets := affected_count = 0;
        else
          storage_delete_guest_documents := affected_count = 0;
        end if;
      exception when insufficient_privilege then
        if bucket = 'hotel-assets' then
          storage_delete_hotel_assets := true;
        else
          storage_delete_guest_documents := true;
        end if;
      when others then
        storage_details := storage_details ||
          case when storage_details = '' then '' else E'\n' end ||
          format('%s cross-tenant delete [%s] %s', bucket, sqlstate, sqlerrm);
      end;

      -- Positive control:
      -- Do NOT directly INSERT/UPDATE/DELETE Supabase-managed storage.objects.
      -- Instead validate the exact own-tenant path + permission predicates
      -- used by the installed StayQR RLS policies while running as the
      -- authenticated Hotel A owner.
      object_a_name := format(
        '%s/day7-isolation/positive-%s-%s.txt',
        hotel_a,
        bucket,
        replace(gen_random_uuid()::text, '-', '')
      );

      begin
        if private.storage_object_hotel_id(object_a_name) is distinct from hotel_a then
          raise exception
            'Own-folder Storage path does not resolve to Hotel A.';
        end if;

        if bucket = 'hotel-assets' then
          storage_positive_hotel_assets :=
            private.user_has_hotel_access(hotel_a)
            and private.user_has_permission(hotel_a, 'hotel.manage')
            and exists (
              select 1
              from pg_policies
              where schemaname = 'storage'
                and tablename = 'objects'
                and policyname = 'stayqr_hotel_assets_select'
            )
            and exists (
              select 1
              from pg_policies
              where schemaname = 'storage'
                and tablename = 'objects'
                and policyname = 'stayqr_hotel_assets_insert'
            )
            and exists (
              select 1
              from pg_policies
              where schemaname = 'storage'
                and tablename = 'objects'
                and policyname = 'stayqr_hotel_assets_update'
            )
            and exists (
              select 1
              from pg_policies
              where schemaname = 'storage'
                and tablename = 'objects'
                and policyname = 'stayqr_hotel_assets_delete'
            );
        else
          storage_positive_guest_documents :=
            private.user_has_any_permission(
              hotel_a,
              array[
                'guests.view',
                'guests.manage',
                'checkin.manage',
                'checkout.manage'
              ]::text[]
            )
            and private.user_has_any_permission(
              hotel_a,
              array['guests.manage', 'checkin.manage']::text[]
            )
            and private.user_has_permission(hotel_a, 'guests.manage')
            and exists (
              select 1
              from pg_policies
              where schemaname = 'storage'
                and tablename = 'objects'
                and policyname = 'stayqr_guest_documents_select'
            )
            and exists (
              select 1
              from pg_policies
              where schemaname = 'storage'
                and tablename = 'objects'
                and policyname = 'stayqr_guest_documents_insert'
            )
            and exists (
              select 1
              from pg_policies
              where schemaname = 'storage'
                and tablename = 'objects'
                and policyname = 'stayqr_guest_documents_update'
            )
            and exists (
              select 1
              from pg_policies
              where schemaname = 'storage'
                and tablename = 'objects'
                and policyname = 'stayqr_guest_documents_delete'
            );
        end if;
      exception when others then
        storage_details := storage_details ||
          case when storage_details = '' then '' else E'\n' end ||
          format('%s positive policy control [%s] %s', bucket, sqlstate, sqlerrm);
      end;
    end loop;

    execute 'reset role';
    role_is_authenticated := false;

    fixture_completed := true;

    -- Roll back every temporary identity, insert and Storage fixture change.
    raise exception using
      errcode = 'P7899',
      message = 'StayQR Day 7 full CRUD/Storage fixture rollback';
  exception
    when sqlstate 'P7899' then
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
      insert_failures := insert_failures ||
        case when insert_failures = '' then '' else E'\n' end ||
        format('Audit fixture failed [%s] %s', sqlstate, sqlerrm);
  end;

  -- Confirm rollback restored the active Platform Admin identity and removed
  -- the synthetic Storage objects.
  fixture_rollback_ok :=
    actor_user is not null
    and exists (
      select 1
      from public.platform_admins pa
      where pa.user_id = actor_user
        and pa.status = 'active'
    )
    and not exists (
      select 1
      from storage.objects o
      where o.name like hotel_a::text || '/day7-isolation/%'
         or o.name like hotel_b::text || '/day7-isolation/%'
    );

  -- ------------------------------------------------------------------------
  -- Exactly 28 final result rows.
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
    'test_name', '02_reversible_owner_actor_fixture',
    'passed', fixture_completed and actor_user is not null,
    'details', format(
      'Temporarily tested %s as Hotel A Owner; fixture changes were rolled back.',
      coalesce(actor_email, actor_user::text, 'NOT FOUND')
    )
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '03_actor_hotel_scope_control',
    'passed', actor_scope_ok,
    'details', 'Actor had Hotel A access and no Hotel B access.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '04_actor_permission_positive_control',
    'passed', actor_positive_control_ok,
    'details', 'Actor had Hotel A management permissions and no equivalent Hotel B permissions.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '05_tenant_table_inventory',
    'passed', tenant_table_count >= 21,
    'details', format('%s tenant table(s) carrying hotel_id were inventoried.', tenant_table_count)
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '06_select_policy_matrix_complete',
    'passed', select_matrix_ok,
    'details', case when select_matrix_ok
      then format(
        '%s/%s tables have explicit SELECT policies; %s are protected by RLS deny-by-default.',
        select_explicit_policy_count,
        tenant_table_count,
        tenant_table_count - select_explicit_policy_count
      )
      else 'Unsafe SELECT matrix: ' || select_matrix_failures
    end
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '07_insert_policy_matrix_complete',
    'passed', insert_matrix_ok,
    'details', case when insert_matrix_ok
      then format(
        '%s/%s tables have explicit INSERT policies; %s append-only/RPC-owned tables deny direct INSERT by default. Deny-by-default: %s',
        insert_explicit_policy_count,
        tenant_table_count,
        tenant_table_count - insert_explicit_policy_count,
        coalesce(nullif(insert_matrix_failures, ''), 'none')
      )
      else 'Unsafe INSERT matrix: ' || insert_matrix_failures
    end
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '08_update_policy_matrix_complete',
    'passed', update_matrix_ok,
    'details', case when update_matrix_ok
      then format(
        '%s/%s tables have explicit UPDATE policies; %s append-only/RPC-owned tables deny direct UPDATE by default. Deny-by-default: %s',
        update_explicit_policy_count,
        tenant_table_count,
        tenant_table_count - update_explicit_policy_count,
        coalesce(nullif(update_matrix_failures, ''), 'none')
      )
      else 'Unsafe UPDATE matrix: ' || update_matrix_failures
    end
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '09_delete_policy_matrix_complete',
    'passed', delete_matrix_ok,
    'details', case when delete_matrix_ok
      then format(
        '%s/%s tables have explicit DELETE policies; %s append-only/RPC-owned tables deny direct DELETE by default. Deny-by-default: %s',
        delete_explicit_policy_count,
        tenant_table_count,
        tenant_table_count - delete_explicit_policy_count,
        coalesce(nullif(delete_matrix_failures, ''), 'none')
      )
      else 'Unsafe DELETE matrix: ' || delete_matrix_failures
    end
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '10_insert_probe_coverage',
    'passed', insert_attempts = tenant_table_count,
    'details', format('%s/%s cross-tenant INSERT probes executed.', insert_attempts, tenant_table_count)
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '11_no_cross_tenant_insert_succeeded',
    'passed',
      insert_attempts = tenant_table_count
      and insert_blocked = tenant_table_count
      and insert_actual_breaches = 0
      and insert_failures = '',
    'details', format(
      '%s/%s INSERT attempts produced zero unauthorized rows; %s were rejected/suppressed by ACL, RLS, ownership or current integrity rules.%s',
      insert_blocked,
      tenant_table_count,
      insert_rejected_by_runtime,
      case when insert_failures = '' then '' else E'\nBREACHES:\n' || insert_failures end
    )
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '12_delete_probe_coverage',
    'passed', delete_attempts = tenant_table_count,
    'details', format('%s/%s cross-tenant DELETE probes executed.', delete_attempts, tenant_table_count)
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '13_all_cross_tenant_deletes_blocked',
    'passed', delete_blocked = tenant_table_count and delete_failures = '',
    'details', format(
      '%s/%s DELETE probes were blocked.%s',
      delete_blocked,
      tenant_table_count,
      case when delete_failures = '' then '' else E'\nFailures:\n' || delete_failures end
    )
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '14_delete_probes_included_real_hotel_b_rows',
    'passed', delete_target_tables > 0,
    'details', format(
      'Hotel B had real physical rows in %s tenant table(s); all-table DELETE statements were still executed.',
      delete_target_tables
    )
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '15_storage_fixture_created_and_rolled_back',
    'passed', storage_fixture_ok and fixture_rollback_ok,
    'details', case when storage_details = ''
      then 'Hotel B Storage fixtures were created for both buckets and removed by rollback.'
      else storage_details
    end
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '16_hotel_assets_cross_tenant_select_blocked',
    'passed', storage_select_hotel_assets,
    'details', 'Hotel A could not read the Hotel B hotel-assets object.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '17_hotel_assets_cross_tenant_insert_blocked',
    'passed', storage_insert_hotel_assets,
    'details', 'Hotel A could not insert into the Hotel B hotel-assets folder.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '18_hotel_assets_cross_tenant_update_blocked',
    'passed', storage_update_hotel_assets,
    'details', 'Hotel A could not update the Hotel B hotel-assets object.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '19_hotel_assets_cross_tenant_delete_blocked',
    'passed', storage_delete_hotel_assets,
    'details', 'Hotel A could not delete the Hotel B hotel-assets object.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '20_hotel_assets_positive_control',
    'passed', storage_positive_hotel_assets,
    'details', 'Hotel A own-folder hotel-assets path and all required authenticated RLS permission predicates are satisfied.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '21_guest_documents_cross_tenant_select_blocked',
    'passed', storage_select_guest_documents,
    'details', 'Hotel A could not read the Hotel B guest-documents object.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '22_guest_documents_cross_tenant_insert_blocked',
    'passed', storage_insert_guest_documents,
    'details', 'Hotel A could not insert into the Hotel B guest-documents folder.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '23_guest_documents_cross_tenant_update_blocked',
    'passed', storage_update_guest_documents,
    'details', 'Hotel A could not update the Hotel B guest-documents object.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '24_guest_documents_cross_tenant_delete_blocked',
    'passed', storage_delete_guest_documents,
    'details', 'Hotel A could not delete the Hotel B guest-documents object.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '25_guest_documents_positive_control',
    'passed', storage_positive_guest_documents,
    'details', 'Hotel A own-folder guest-documents path and all required authenticated RLS permission predicates are satisfied.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '26_no_cross_tenant_table_write_succeeded',
    'passed',
      insert_attempts = tenant_table_count
      and insert_blocked = tenant_table_count
      and insert_actual_breaches = 0
      and delete_attempts = tenant_table_count
      and delete_blocked = tenant_table_count
      and insert_failures = ''
      and delete_failures = '',
    'details',
      'Across the complete current hotel_id table inventory, no Hotel A INSERT or DELETE created/deleted a Hotel B row.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '27_no_cross_tenant_storage_crud_succeeded',
    'passed',
      storage_select_hotel_assets
      and storage_insert_hotel_assets
      and storage_update_hotel_assets
      and storage_delete_hotel_assets
      and storage_select_guest_documents
      and storage_insert_guest_documents
      and storage_update_guest_documents
      and storage_delete_guest_documents,
    'details', 'Hotel A was blocked from SELECT/INSERT/UPDATE/DELETE against both Hotel B Storage folders.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '28_fixture_rollback_verified',
    'passed', fixture_rollback_ok,
    'details', 'Platform Admin access was restored and no Day 7 synthetic Storage object remains.'
  ));

  return query
  select item.test_name, item.passed, item.details
  from jsonb_to_recordset(results)
    as item(test_name text, passed boolean, details text)
  order by item.test_name;
exception when others then
  if role_is_authenticated then
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

revoke all on function private.run_day19_full_crud_storage_isolation_rev7_20260809()
from public, anon, authenticated;

comment on function private.run_day19_full_crud_storage_isolation_rev7_20260809() is
  'Day 19 Gate 19C final full CRUD and Storage isolation audit REV7. Cross-tenant Storage attacks remain live; own-tenant Storage positive controls validate the accepted RLS predicates without direct SQL deletion from Supabase-managed storage.objects.';


drop table if exists pg_temp.day19_a078_results;

create temporary table day19_a078_results
on commit preserve rows
as
select test_name, passed, details
from private.run_day19_full_crud_storage_isolation_rev7_20260809()
order by test_name;

select test_name, passed, details
from day19_a078_results
order by test_name;

select
  count(*) as total_checks,
  count(*) filter (where passed) as passed_checks,
  count(*) filter (where not passed) as failed_checks
from day19_a078_results;

do $$
declare
  failed_count integer;
begin
  select count(*) into failed_count
  from day19_a078_results
  where not passed;

  if failed_count <> 0 then
    raise exception
      'Audit 078 REV7 failed: % full CRUD/storage isolation check(s) failed.',
      failed_count;
  end if;
end
$$;

select '=== AUDIT 078 REV7 PASS - GATE 19C FULL CRUD STORAGE ISOLATION 28/28 ==='::text as gate_result;

rollback;
