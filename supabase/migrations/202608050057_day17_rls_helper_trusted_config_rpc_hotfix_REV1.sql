-- ============================================================================
-- StayQR v1.0
-- Day 17 Migration 057 REV1
-- RLS helper execute privilege + trusted configuration RPC hotfix
--
-- ROOT CAUSE
-- Migration 056 uses private.day17_can_manage_hotel(uuid) inside authenticated
-- RLS policies, but revoked EXECUTE from authenticated. PostgREST table reads
-- therefore fail with:
--   permission denied for function day17_can_manage_hotel
--
-- SECURITY DESIGN
-- - grant only authenticated EXECUTE on the boolean authorization helper
-- - keep anon and PUBLIC blocked
-- - do not grant direct INSERT/UPDATE on configuration tables
-- - expose validated SECURITY DEFINER RPCs for hotel email-adapter and manual
--   WhatsApp-template writes
-- - never accept or return provider secrets
--
-- EXPECTED ACCEPTANCE
-- 37 rows / 37 passed / 0 failures.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '300s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202608050057:day17-rls-helper-config-rpc-hotfix-rev1')
);

create schema if not exists private;

-- --------------------------------------------------------------------------
-- 1. Allow authenticated RLS evaluation of the management helper.
-- --------------------------------------------------------------------------

revoke all on function private.day17_can_manage_hotel(uuid)
from public, anon, authenticated;

grant execute on function private.day17_can_manage_hotel(uuid)
to authenticated;

-- --------------------------------------------------------------------------
-- 2. Trusted Email Adapter writer.
-- --------------------------------------------------------------------------

create or replace function public.upsert_email_adapter_config(
  p_hotel_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_row public.email_adapter_configs%rowtype;
  v_adapter_key text;
  v_provider text;
  v_metadata jsonb;
begin
  if v_user_id is null
     or not private.day17_can_manage_hotel(p_hotel_id)
  then
    raise exception 'Email adapter management denied.';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Email adapter payload must be a JSON object.';
  end if;

  v_adapter_key := nullif(trim(p_payload ->> 'adapter_key'), '');
  v_provider := coalesce(
    nullif(trim(p_payload ->> 'provider'), ''),
    'edge_function'
  );
  v_metadata := coalesce(p_payload -> 'metadata', '{}'::jsonb);

  if v_adapter_key is null
     or length(v_adapter_key) not between 2 and 100
  then
    raise exception 'adapter_key must contain 2 to 100 characters.';
  end if;

  if v_provider not in ('edge_function', 'external_worker', 'manual') then
    raise exception 'Unsupported email adapter provider.';
  end if;

  if jsonb_typeof(v_metadata) <> 'object' then
    raise exception 'Email adapter metadata must be a JSON object.';
  end if;

  insert into public.email_adapter_configs (
    hotel_id,
    adapter_key,
    provider,
    from_name,
    from_email,
    reply_to_email,
    secret_reference,
    endpoint_name,
    is_enabled,
    metadata,
    created_by,
    updated_by,
    created_at,
    updated_at
  ) values (
    p_hotel_id,
    v_adapter_key,
    v_provider,
    nullif(trim(p_payload ->> 'from_name'), ''),
    nullif(trim(p_payload ->> 'from_email'), ''),
    nullif(trim(p_payload ->> 'reply_to_email'), ''),
    null,
    nullif(trim(p_payload ->> 'endpoint_name'), ''),
    coalesce((p_payload ->> 'is_enabled')::boolean, false),
    v_metadata,
    v_user_id,
    v_user_id,
    now(),
    now()
  )
  on conflict (hotel_id, adapter_key)
  where hotel_id is not null
  do update
  set
    provider = excluded.provider,
    from_name = excluded.from_name,
    from_email = excluded.from_email,
    reply_to_email = excluded.reply_to_email,
    endpoint_name = excluded.endpoint_name,
    is_enabled = excluded.is_enabled,
    metadata = excluded.metadata,
    updated_by = v_user_id,
    updated_at = now()
  returning * into v_row;

  return jsonb_build_object(
    'saved', true,
    'adapter', to_jsonb(v_row) - 'secret_reference'
  );
end;
$function$;

-- --------------------------------------------------------------------------
-- 3. Trusted manual WhatsApp-template writer.
-- --------------------------------------------------------------------------

create or replace function public.upsert_manual_whatsapp_template(
  p_hotel_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_row public.whatsapp_templates%rowtype;
  v_event_key text;
  v_locale text;
  v_template_name text;
  v_body_template text;
  v_status text;
begin
  if v_user_id is null
     or not private.day17_can_manage_hotel(p_hotel_id)
  then
    raise exception 'Manual WhatsApp template management denied.';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'WhatsApp template payload must be a JSON object.';
  end if;

  v_event_key := nullif(trim(p_payload ->> 'event_key'), '');
  v_locale := coalesce(
    nullif(trim(p_payload ->> 'locale'), ''),
    'en'
  );
  v_template_name := nullif(trim(p_payload ->> 'template_name'), '');
  v_body_template := nullif(trim(p_payload ->> 'body_template'), '');
  v_status := coalesce(
    nullif(trim(p_payload ->> 'status'), ''),
    'draft'
  );

  if not exists (
    select 1
    from public.notification_event_catalog nec
    where nec.event_key = v_event_key
      and nec.is_active
  ) then
    raise exception 'Unsupported notification event key.';
  end if;

  if length(v_locale) not between 2 and 20 then
    raise exception 'locale must contain 2 to 20 characters.';
  end if;

  if v_template_name is null then
    raise exception 'template_name is required.';
  end if;

  if v_body_template is null then
    raise exception 'body_template is required.';
  end if;

  if v_status not in ('draft', 'published', 'archived') then
    raise exception 'Unsupported WhatsApp template status.';
  end if;

  insert into public.whatsapp_templates (
    hotel_id,
    event_key,
    locale,
    template_name,
    body_template,
    status,
    created_by,
    updated_by,
    created_at,
    updated_at
  ) values (
    p_hotel_id,
    v_event_key,
    v_locale,
    v_template_name,
    v_body_template,
    v_status,
    v_user_id,
    v_user_id,
    now(),
    now()
  )
  on conflict (hotel_id, event_key, locale)
  where hotel_id is not null
  do update
  set
    template_name = excluded.template_name,
    body_template = excluded.body_template,
    status = excluded.status,
    updated_by = v_user_id,
    updated_at = now()
  returning * into v_row;

  return jsonb_build_object(
    'saved', true,
    'template', to_jsonb(v_row)
  );
end;
$function$;

revoke all on function
  public.upsert_email_adapter_config(uuid,jsonb),
  public.upsert_manual_whatsapp_template(uuid,jsonb)
from public, anon, authenticated;

grant execute on function
  public.upsert_email_adapter_config(uuid,jsonb),
  public.upsert_manual_whatsapp_template(uuid,jsonb)
to authenticated;

-- Direct writes remain blocked. All writes use the trusted RPCs above.
revoke insert, update, delete on table
  public.email_adapter_configs,
  public.whatsapp_templates
from public, anon, authenticated;

-- --------------------------------------------------------------------------
-- 4. Fixed acceptance.
-- --------------------------------------------------------------------------

create or replace function private.day17_migration_057_acceptance_rev1()
returns table (
  suite text,
  test_name text,
  passed boolean,
  details text
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_proc oid;
  v_definition text;
  v_admin_user uuid;
  v_hotel_id uuid;
  v_event_key text;

  v_email_key text :=
    'd17_m057_' || replace(gen_random_uuid()::text, '-', '');
  v_wa_locale text :=
    'x-d17-' || substring(replace(gen_random_uuid()::text, '-', '') from 1 for 8);

  v_email_first jsonb;
  v_email_second jsonb;
  v_wa_first jsonb;
  v_wa_second jsonb;

  v_email_id uuid;
  v_email_id_second uuid;
  v_wa_id uuid;
  v_wa_id_second uuid;

  v_email_insert_seen boolean := false;
  v_email_update_seen boolean := false;
  v_email_secret_absent boolean := false;
  v_email_values_seen boolean := false;
  v_wa_insert_seen boolean := false;
  v_wa_update_seen boolean := false;
  v_wa_values_seen boolean := false;
  v_runtime_completed boolean := false;
  v_runtime_error text;

  v_previous_sub text :=
    current_setting('request.jwt.claim.sub', true);
  v_previous_role text :=
    current_setting('request.jwt.claim.role', true);
  v_previous_claims text :=
    current_setting('request.jwt.claims', true);
begin
  suite := 'HELPER';
  test_name := 'day17_can_manage_hotel.exists';
  passed := to_regprocedure(
    'private.day17_can_manage_hotel(uuid)'
  ) is not null;
  details := case when passed then 'PRESENT' else 'MISSING' end;
  return next;

  select p.oid
  into v_proc
  from pg_proc p
  where p.oid = to_regprocedure(
    'private.day17_can_manage_hotel(uuid)'
  );

  suite := 'HELPER';
  test_name := 'day17_can_manage_hotel.security_definer';
  select p.prosecdef
  into passed
  from pg_proc p
  where p.oid = v_proc;
  details := case when passed then 'SECURITY DEFINER' else 'NOT SECURITY DEFINER' end;
  return next;

  suite := 'HELPER';
  test_name := 'day17_can_manage_hotel.stable';
  select p.provolatile = 's'
  into passed
  from pg_proc p
  where p.oid = v_proc;
  details := case when passed then 'STABLE' else 'VOLATILITY MISMATCH' end;
  return next;

  suite := 'HELPER';
  test_name := 'day17_can_manage_hotel.authenticated_execute';
  select has_function_privilege(
    'authenticated',
    'private.day17_can_manage_hotel(uuid)',
    'EXECUTE'
  )
  into passed;
  details := case when passed then 'EXECUTE GRANTED' else 'EXECUTE MISSING' end;
  return next;

  suite := 'HELPER';
  test_name := 'day17_can_manage_hotel.anon_blocked';
  select not has_function_privilege(
    'anon',
    'private.day17_can_manage_hotel(uuid)',
    'EXECUTE'
  )
  into passed;
  details := case when passed then 'ANON BLOCKED' else 'ANON CAN EXECUTE' end;
  return next;

  suite := 'RPC';
  test_name := 'upsert_email_adapter_config.exists';
  passed := to_regprocedure(
    'public.upsert_email_adapter_config(uuid,jsonb)'
  ) is not null;
  details := case when passed then 'PRESENT' else 'MISSING' end;
  return next;

  suite := 'RPC';
  test_name := 'upsert_email_adapter_config.security_definer';
  select p.prosecdef
  into passed
  from pg_proc p
  where p.oid = to_regprocedure(
    'public.upsert_email_adapter_config(uuid,jsonb)'
  );
  details := case when passed then 'SECURITY DEFINER' else 'NOT SECURITY DEFINER' end;
  return next;

  suite := 'RPC';
  test_name := 'upsert_email_adapter_config.authenticated_execute';
  select has_function_privilege(
    'authenticated',
    'public.upsert_email_adapter_config(uuid,jsonb)',
    'EXECUTE'
  )
  into passed;
  details := case when passed then 'EXECUTE GRANTED' else 'EXECUTE MISSING' end;
  return next;

  suite := 'RPC';
  test_name := 'upsert_email_adapter_config.anon_blocked';
  select not has_function_privilege(
    'anon',
    'public.upsert_email_adapter_config(uuid,jsonb)',
    'EXECUTE'
  )
  into passed;
  details := case when passed then 'ANON BLOCKED' else 'ANON CAN EXECUTE' end;
  return next;

  suite := 'RPC';
  test_name := 'upsert_email_adapter_config.no_secret_input';
  select pg_get_functiondef(
    to_regprocedure(
      'public.upsert_email_adapter_config(uuid,jsonb)'
    )::oid
  ) not ilike '%p_payload ->> ''secret_reference''%'
  into passed;
  details := case when passed then 'SECRET INPUT BLOCKED' else 'SECRET INPUT FOUND' end;
  return next;

  suite := 'RPC';
  test_name := 'upsert_manual_whatsapp_template.exists';
  passed := to_regprocedure(
    'public.upsert_manual_whatsapp_template(uuid,jsonb)'
  ) is not null;
  details := case when passed then 'PRESENT' else 'MISSING' end;
  return next;

  suite := 'RPC';
  test_name := 'upsert_manual_whatsapp_template.security_definer';
  select p.prosecdef
  into passed
  from pg_proc p
  where p.oid = to_regprocedure(
    'public.upsert_manual_whatsapp_template(uuid,jsonb)'
  );
  details := case when passed then 'SECURITY DEFINER' else 'NOT SECURITY DEFINER' end;
  return next;

  suite := 'RPC';
  test_name := 'upsert_manual_whatsapp_template.authenticated_execute';
  select has_function_privilege(
    'authenticated',
    'public.upsert_manual_whatsapp_template(uuid,jsonb)',
    'EXECUTE'
  )
  into passed;
  details := case when passed then 'EXECUTE GRANTED' else 'EXECUTE MISSING' end;
  return next;

  suite := 'RPC';
  test_name := 'upsert_manual_whatsapp_template.anon_blocked';
  select not has_function_privilege(
    'anon',
    'public.upsert_manual_whatsapp_template(uuid,jsonb)',
    'EXECUTE'
  )
  into passed;
  details := case when passed then 'ANON BLOCKED' else 'ANON CAN EXECUTE' end;
  return next;

  for suite, test_name, passed, details in
    select
      'RLS_POLICY',
      expected.policy_name,
      exists (
        select 1
        from pg_policy pol
        join pg_class c on c.oid = pol.polrelid
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public'
          and c.relname = expected.table_name
          and pol.polname = expected.policy_name
          and pg_get_expr(pol.polqual, pol.polrelid)
            ilike '%day17_can_manage_hotel%'
      ),
      format(
        '%s.%s',
        expected.table_name,
        expected.policy_name
      )
    from (
      values
        ('notification_deliveries',
          'notification_deliveries_select_day17'),
        ('notification_delivery_attempts',
          'notification_attempts_select_day17'),
        ('notification_dead_letters',
          'notification_dead_letters_select_day17'),
        ('email_adapter_configs',
          'email_adapter_configs_select_day17')
    ) expected(table_name, policy_name)
  loop
    return next;
  end loop;

  suite := 'TABLE_SECURITY';
  test_name := 'email_adapter_direct_insert_blocked';
  select not has_table_privilege(
    'authenticated',
    'public.email_adapter_configs',
    'INSERT'
  )
  into passed;
  details := case when passed then 'RPC ONLY' else 'DIRECT INSERT GRANTED' end;
  return next;

  suite := 'TABLE_SECURITY';
  test_name := 'email_adapter_direct_update_blocked';
  select not has_table_privilege(
    'authenticated',
    'public.email_adapter_configs',
    'UPDATE'
  )
  into passed;
  details := case when passed then 'RPC ONLY' else 'DIRECT UPDATE GRANTED' end;
  return next;

  suite := 'TABLE_SECURITY';
  test_name := 'whatsapp_direct_insert_blocked';
  select not has_table_privilege(
    'authenticated',
    'public.whatsapp_templates',
    'INSERT'
  )
  into passed;
  details := case when passed then 'RPC ONLY' else 'DIRECT INSERT GRANTED' end;
  return next;

  suite := 'TABLE_SECURITY';
  test_name := 'whatsapp_direct_update_blocked';
  select not has_table_privilege(
    'authenticated',
    'public.whatsapp_templates',
    'UPDATE'
  )
  into passed;
  details := case when passed then 'RPC ONLY' else 'DIRECT UPDATE GRANTED' end;
  return next;

  select pa.user_id
  into v_admin_user
  from public.platform_admins pa
  where pa.status = 'active'
  order by pa.created_at
  limit 1;

  select h.id
  into v_hotel_id
  from public.hotels h
  where h.status = 'active'
  order by h.created_at
  limit 1;

  select nec.event_key
  into v_event_key
  from public.notification_event_catalog nec
  where nec.is_active
  order by nec.event_key
  limit 1;

  suite := 'RUNTIME';
  test_name := 'active_platform_admin_fixture';
  passed := v_admin_user is not null;
  details := coalesce(v_admin_user::text, 'MISSING');
  return next;

  suite := 'RUNTIME';
  test_name := 'active_hotel_fixture';
  passed := v_hotel_id is not null;
  details := coalesce(v_hotel_id::text, 'MISSING');
  return next;

  suite := 'RUNTIME';
  test_name := 'active_event_fixture';
  passed := v_event_key is not null;
  details := coalesce(v_event_key, 'MISSING');
  return next;

  begin
    if v_admin_user is null
       or v_hotel_id is null
       or v_event_key is null
    then
      raise exception 'Required runtime fixtures were not found.';
    end if;

    perform set_config(
      'request.jwt.claim.sub',
      v_admin_user::text,
      true
    );
    perform set_config(
      'request.jwt.claim.role',
      'authenticated',
      true
    );
    perform set_config(
      'request.jwt.claims',
      jsonb_build_object(
        'sub', v_admin_user,
        'role', 'authenticated'
      )::text,
      true
    );

    v_email_first := public.upsert_email_adapter_config(
      v_hotel_id,
      jsonb_build_object(
        'adapter_key', v_email_key,
        'provider', 'manual',
        'from_name', 'Day 17 Runtime One',
        'from_email', 'runtime1@stayqr.test',
        'reply_to_email', 'reply@stayqr.test',
        'endpoint_name', 'day17_runtime',
        'is_enabled', false,
        'metadata', jsonb_build_object('fixture', 'm057'),
        'secret_reference', 'must_not_be_accepted'
      )
    );

    v_email_id := nullif(
      v_email_first #>> '{adapter,id}',
      ''
    )::uuid;

    select
      eac.id = v_email_id,
      eac.secret_reference is null,
      eac.provider = 'manual'
        and eac.from_name = 'Day 17 Runtime One'
        and not eac.is_enabled
    into
      v_email_insert_seen,
      v_email_secret_absent,
      v_email_values_seen
    from public.email_adapter_configs eac
    where eac.hotel_id = v_hotel_id
      and eac.adapter_key = v_email_key;

    v_email_second := public.upsert_email_adapter_config(
      v_hotel_id,
      jsonb_build_object(
        'adapter_key', v_email_key,
        'provider', 'edge_function',
        'from_name', 'Day 17 Runtime Two',
        'from_email', 'runtime2@stayqr.test',
        'reply_to_email', 'reply2@stayqr.test',
        'endpoint_name', 'day17_runtime_v2',
        'is_enabled', false,
        'metadata', jsonb_build_object('fixture', 'm057-v2')
      )
    );

    v_email_id_second := nullif(
      v_email_second #>> '{adapter,id}',
      ''
    )::uuid;

    select
      eac.id = v_email_id
        and v_email_id_second = v_email_id
        and eac.provider = 'edge_function'
        and eac.from_name = 'Day 17 Runtime Two'
    into v_email_update_seen
    from public.email_adapter_configs eac
    where eac.hotel_id = v_hotel_id
      and eac.adapter_key = v_email_key;

    v_wa_first := public.upsert_manual_whatsapp_template(
      v_hotel_id,
      jsonb_build_object(
        'event_key', v_event_key,
        'locale', v_wa_locale,
        'template_name', 'Day 17 Runtime WhatsApp',
        'body_template', 'Runtime message {{hotel_name}}',
        'status', 'draft'
      )
    );

    v_wa_id := nullif(
      v_wa_first #>> '{template,id}',
      ''
    )::uuid;

    select
      wt.id = v_wa_id,
      wt.template_name = 'Day 17 Runtime WhatsApp'
        and wt.status = 'draft'
    into
      v_wa_insert_seen,
      v_wa_values_seen
    from public.whatsapp_templates wt
    where wt.hotel_id = v_hotel_id
      and wt.event_key = v_event_key
      and wt.locale = v_wa_locale;

    v_wa_second := public.upsert_manual_whatsapp_template(
      v_hotel_id,
      jsonb_build_object(
        'event_key', v_event_key,
        'locale', v_wa_locale,
        'template_name', 'Day 17 Runtime WhatsApp Updated',
        'body_template', 'Updated runtime message {{hotel_name}}',
        'status', 'published'
      )
    );

    v_wa_id_second := nullif(
      v_wa_second #>> '{template,id}',
      ''
    )::uuid;

    select
      wt.id = v_wa_id
        and v_wa_id_second = v_wa_id
        and wt.template_name = 'Day 17 Runtime WhatsApp Updated'
        and wt.status = 'published'
    into v_wa_update_seen
    from public.whatsapp_templates wt
    where wt.hotel_id = v_hotel_id
      and wt.event_key = v_event_key
      and wt.locale = v_wa_locale;

    v_runtime_completed := true;

    raise exception 'DAY17_M057_ROLLBACK_COMPLETE'
      using errcode = 'P0001';
  exception
    when others then
      if sqlerrm = 'DAY17_M057_ROLLBACK_COMPLETE' then
        null;
      else
        v_runtime_error := format('%s [%s]', sqlerrm, sqlstate);
      end if;
  end;

  perform set_config(
    'request.jwt.claim.sub',
    coalesce(v_previous_sub, ''),
    true
  );
  perform set_config(
    'request.jwt.claim.role',
    coalesce(v_previous_role, ''),
    true
  );
  perform set_config(
    'request.jwt.claims',
    coalesce(v_previous_claims, '{}'),
    true
  );

  suite := 'RUNTIME';
  test_name := 'email_adapter_insert';
  passed := coalesce(v_email_insert_seen, false);
  details := coalesce(v_email_first::text, v_runtime_error, 'NO RESULT');
  return next;

  suite := 'RUNTIME';
  test_name := 'email_adapter_update_same_identity';
  passed := coalesce(v_email_update_seen, false);
  details := format(
    'first=%s second=%s',
    coalesce(v_email_id::text, 'null'),
    coalesce(v_email_id_second::text, 'null')
  );
  return next;

  suite := 'RUNTIME';
  test_name := 'email_adapter_secret_ignored';
  passed := coalesce(v_email_secret_absent, false)
    and not (coalesce(v_email_first, '{}'::jsonb) #> '{adapter}')
      ? 'secret_reference';
  details := 'secret_reference absent from row and RPC result';
  return next;

  suite := 'RUNTIME';
  test_name := 'email_adapter_values';
  passed := coalesce(v_email_values_seen, false);
  details := 'Validated provider, sender name and disabled state.';
  return next;

  suite := 'RUNTIME';
  test_name := 'whatsapp_template_insert';
  passed := coalesce(v_wa_insert_seen, false);
  details := coalesce(v_wa_first::text, v_runtime_error, 'NO RESULT');
  return next;

  suite := 'RUNTIME';
  test_name := 'whatsapp_template_update_same_identity';
  passed := coalesce(v_wa_update_seen, false);
  details := format(
    'first=%s second=%s',
    coalesce(v_wa_id::text, 'null'),
    coalesce(v_wa_id_second::text, 'null')
  );
  return next;

  suite := 'RUNTIME';
  test_name := 'whatsapp_template_values';
  passed := coalesce(v_wa_values_seen, false);
  details := 'Validated draft template before update.';
  return next;

  suite := 'RUNTIME';
  test_name := 'runtime_completed';
  passed := v_runtime_completed and v_runtime_error is null;
  details := coalesce(v_runtime_error, 'Runtime completed and rolled back.');
  return next;

  suite := 'ROLLBACK';
  test_name := 'email_fixture_removed';
  select not exists (
    select 1
    from public.email_adapter_configs eac
    where eac.hotel_id = v_hotel_id
      and eac.adapter_key = v_email_key
  )
  into passed;
  details := case when passed then 'CLEAN' else 'FIXTURE REMAINS' end;
  return next;

  suite := 'ROLLBACK';
  test_name := 'whatsapp_fixture_removed';
  select not exists (
    select 1
    from public.whatsapp_templates wt
    where wt.hotel_id = v_hotel_id
      and wt.event_key = v_event_key
      and wt.locale = v_wa_locale
  )
  into passed;
  details := case when passed then 'CLEAN' else 'FIXTURE REMAINS' end;
  return next;

  suite := 'ROLLBACK';
  test_name := 'jwt_claim_sub_restored';
  passed := coalesce(
    current_setting('request.jwt.claim.sub', true),
    ''
  ) = coalesce(v_previous_sub, '');
  details := 'JWT subject restored.';
  return next;

  suite := 'ROLLBACK';
  test_name := 'jwt_claims_restored';
  passed := coalesce(
    current_setting('request.jwt.claims', true),
    '{}'
  ) = coalesce(v_previous_claims, '{}');
  details := 'JWT claims restored.';
  return next;
end;
$function$;

revoke all on function private.day17_migration_057_acceptance_rev1()
from public, anon, authenticated;

commit;

select suite, test_name, passed, details
from private.day17_migration_057_acceptance_rev1()
order by suite, test_name;
