-- ============================================================================
-- StayQR v1.0 — Day 18 Audit 072
-- Migration 059 monitoring acceptance REV2 expectation fix
--
-- PURPOSE
-- Correct two stale assertions in the original Migration 059 acceptance:
-- 1. Day 18 query health now contains 26 indexes after Migration 059 adds
--    six monitoring indexes to the 20 Migration 058 indexes.
-- 2. Bearer credentials are intentionally sanitized as
--    "Bearer [REDACTED]" before the generic JWT pass.
--
-- SAFETY
-- - Does not recreate or change the monitoring ledger/RPC implementation.
-- - Does not insert, update or delete hotel business data.
-- - Runtime fixture rows are deleted by the acceptance function itself.
-- - Executes under one transaction and a dedicated advisory lock.
--
-- EXPECTED RESULT
-- 100 rows / 100 passed / 0 failed
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '10min';

select pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtext('stayqr:202608050072:day18-m059-acceptance-rev2')
);

do $preflight$
declare
  v_missing text;
begin
  select string_agg(required.object_name, ', ' order by required.object_name)
  into v_missing
  from (
    values
      (
        'public.operational_error_events',
        to_regclass('public.operational_error_events') is not null
      ),
      (
        'public.report_operational_error(uuid,jsonb)',
        to_regprocedure('public.report_operational_error(uuid,jsonb)') is not null
      ),
      (
        'public.get_operational_diagnostics(uuid,timestamptz,timestamptz,integer,text,text,text,text)',
        to_regprocedure(
          'public.get_operational_diagnostics(uuid,timestamptz,timestamptz,integer,text,text,text,text)'
        ) is not null
      ),
      (
        'public.set_operational_incident_status(uuid,uuid,text,text)',
        to_regprocedure(
          'public.set_operational_incident_status(uuid,uuid,text,text)'
        ) is not null
      ),
      (
        'public.get_day18_query_health(uuid)',
        to_regprocedure('public.get_day18_query_health(uuid)') is not null
      ),
      (
        'private.day18_safe_log_text(text,integer)',
        to_regprocedure('private.day18_safe_log_text(text,integer)') is not null
      )
  ) required(object_name, present)
  where not required.present;

  if v_missing is not null then
    raise exception
      'Audit 072 prerequisite(s) missing: %',
      v_missing
      using errcode = '55000';
  end if;
end;
$preflight$;

create or replace function private.day18_migration_059_acceptance_rev2()
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
  v_admin_user uuid;
  v_hotel_id uuid;
  v_previous_sub text :=
    current_setting('request.jwt.claim.sub', true);
  v_previous_role text :=
    current_setting('request.jwt.claim.role', true);
  v_previous_claims text :=
    current_setting('request.jwt.claims', true);
  v_column record;
  v_constraint_name text;
  v_index_name text;
  v_signature text;
  v_function_oid oid;
  v_payload jsonb;
  v_first_result jsonb;
  v_second_result jsonb;
  v_diagnostics jsonb;
  v_status_result jsonb;
  v_event_id uuid;
  v_event_record public.operational_error_events%rowtype;
  v_error text;
  v_count bigint;
begin
  -- 7 prerequisite checks
  return query
  select *
  from (
    values
      (
        'PREREQUISITE'::text,
        'hotels_table'::text,
        to_regclass('public.hotels') is not null,
        'Hotel authority exists.'::text
      ),
      (
        'PREREQUISITE',
        'platform_admins_table',
        to_regclass('public.platform_admins') is not null,
        'Platform-admin authority exists.'
      ),
      (
        'PREREQUISITE',
        'auth_users_table',
        to_regclass('auth.users') is not null,
        'Auth users exist.'
      ),
      (
        'PREREQUISITE',
        'hotel_access_helper',
        to_regprocedure(
          'private.user_has_hotel_access(uuid)'
        ) is not null,
        'Hotel access helper exists.'
      ),
      (
        'PREREQUISITE',
        'hotel_management_helper',
        to_regprocedure(
          'private.day17_can_manage_hotel(uuid)'
        ) is not null,
        'Hotel management helper exists.'
      ),
      (
        'PREREQUISITE',
        'query_health_rpc',
        to_regprocedure(
          'public.get_day18_query_health(uuid)'
        ) is not null,
        'Migration 058 query health exists.'
      ),
      (
        'PREREQUISITE',
        'notification_deliveries_table',
        to_regclass(
          'public.notification_deliveries'
        ) is not null,
        'Delivery health source exists.'
      )
  ) checks(suite, test_name, passed, details);

  -- 29 column checks
  for v_column in
    select *
    from (
      values
        ('id', 'uuid'),
        ('hotel_id', 'uuid'),
        ('actor_user_id', 'uuid'),
        ('incident_id', 'text'),
        ('fingerprint', 'text'),
        ('source', 'text'),
        ('environment', 'text'),
        ('severity', 'text'),
        ('status', 'text'),
        ('event_name', 'text'),
        ('error_name', 'text'),
        ('error_code', 'text'),
        ('message', 'text'),
        ('route', 'text'),
        ('scope', 'text'),
        ('component', 'text'),
        ('request_id', 'text'),
        ('release', 'text'),
        ('context', 'jsonb'),
        ('occurrence_count', 'integer'),
        ('first_seen_at', 'timestamp with time zone'),
        ('last_seen_at', 'timestamp with time zone'),
        ('acknowledged_at', 'timestamp with time zone'),
        ('acknowledged_by', 'uuid'),
        ('resolved_at', 'timestamp with time zone'),
        ('resolved_by', 'uuid'),
        ('resolution_note', 'text'),
        ('created_at', 'timestamp with time zone'),
        ('updated_at', 'timestamp with time zone')
    ) expected(column_name, data_type)
  loop
    return query
    select
      'COLUMN',
      v_column.column_name,
      exists (
        select 1
        from information_schema.columns column_state
        where column_state.table_schema = 'public'
          and column_state.table_name = 'operational_error_events'
          and column_state.column_name = v_column.column_name
          and column_state.data_type = v_column.data_type
      ),
      format(
        'Expected %s %s.',
        v_column.column_name,
        v_column.data_type
      );
  end loop;

  -- 6 constraint checks
  foreach v_constraint_name in array array[
    'operational_error_events_source_check',
    'operational_error_events_environment_check',
    'operational_error_events_severity_check',
    'operational_error_events_status_check',
    'operational_error_events_occurrence_count_check',
    'operational_error_events_context_object_check'
  ]
  loop
    return query
    select
      'CONSTRAINT',
      v_constraint_name,
      exists (
        select 1
        from pg_catalog.pg_constraint constraint_state
        where constraint_state.conrelid =
          'public.operational_error_events'::regclass
          and constraint_state.conname = v_constraint_name
          and constraint_state.convalidated
      ),
      'Validated table constraint checked.';
  end loop;

  -- 6 index checks
  foreach v_index_name in array array[
    'idx_d18_operational_error_incident_unique',
    'idx_d18_operational_error_hotel_status',
    'idx_d18_operational_error_hotel_severity',
    'idx_d18_operational_error_fingerprint',
    'idx_d18_operational_error_request',
    'idx_d18_operational_error_unresolved'
  ]
  loop
    return query
    select
      'INDEX',
      v_index_name,
      index_catalog.indisvalid and index_catalog.indisready,
      pg_catalog.pg_get_indexdef(index_catalog.indexrelid)
    from pg_catalog.pg_index index_catalog
    join pg_catalog.pg_class index_relation
      on index_relation.oid = index_catalog.indexrelid
    join pg_catalog.pg_namespace index_namespace
      on index_namespace.oid = index_relation.relnamespace
    where index_namespace.nspname = 'public'
      and index_relation.relname = v_index_name;
  end loop;

  -- 6 table-security checks
  return query
  select
    'TABLE_SECURITY',
    'rls_enabled',
    relation.relrowsecurity,
    format('relrowsecurity=%s', relation.relrowsecurity)
  from pg_catalog.pg_class relation
  where relation.oid = 'public.operational_error_events'::regclass;

  return query
  select
    'TABLE_SECURITY',
    'rls_forced',
    relation.relforcerowsecurity,
    format('relforcerowsecurity=%s', relation.relforcerowsecurity)
  from pg_catalog.pg_class relation
  where relation.oid = 'public.operational_error_events'::regclass;

  return query
  select
    'TABLE_SECURITY',
    'anon_select_blocked',
    not has_table_privilege(
      'anon',
      'public.operational_error_events',
      'SELECT'
    ),
    'Anonymous direct SELECT denied.';

  return query
  select
    'TABLE_SECURITY',
    'authenticated_select_blocked',
    not has_table_privilege(
      'authenticated',
      'public.operational_error_events',
      'SELECT'
    ),
    'Authenticated direct SELECT denied.';

  return query
  select
    'TABLE_SECURITY',
    'authenticated_insert_blocked',
    not has_table_privilege(
      'authenticated',
      'public.operational_error_events',
      'INSERT'
    ),
    'Authenticated direct INSERT denied.';

  return query
  select
    'TABLE_SECURITY',
    'authenticated_mutation_blocked',
    not has_table_privilege(
      'authenticated',
      'public.operational_error_events',
      'UPDATE'
    )
      and not has_table_privilege(
        'authenticated',
        'public.operational_error_events',
        'DELETE'
      ),
    'Authenticated direct UPDATE and DELETE denied.';

  -- 2 private helpers x 3 checks = 6
  foreach v_signature in array array[
    'private.day18_safe_log_text(text,integer)',
    'private.day18_safe_log_context(jsonb)'
  ]
  loop
    v_function_oid := to_regprocedure(v_signature);

    return query
    select
      'HELPER_EXISTS',
      v_signature,
      v_function_oid is not null,
      coalesce(v_function_oid::regprocedure::text, 'missing');

    return query
    select
      'HELPER_SEARCH_PATH',
      v_signature,
      coalesce(proc.proconfig, array[]::text[])
        @> array['search_path=""']::text[],
      coalesce(array_to_string(proc.proconfig, ','), 'no proconfig')
    from pg_catalog.pg_proc proc
    where proc.oid = v_function_oid;

    return query
    select
      'HELPER_EXECUTION_CLOSED',
      v_signature,
      not has_function_privilege(
        'anon',
        v_signature,
        'EXECUTE'
      )
      and not has_function_privilege(
        'authenticated',
        v_signature,
        'EXECUTE'
      ),
      'Private helper execution denied to API roles.';
  end loop;

  -- 4 trusted RPCs x 5 checks = 20
  foreach v_signature in array array[
    'public.report_operational_error(uuid,jsonb)',
    'public.get_operational_health_snapshot(uuid)',
    'public.get_operational_diagnostics(uuid,timestamp with time zone,timestamp with time zone,integer,text,text,text,text)',
    'public.set_operational_incident_status(uuid,uuid,text,text)'
  ]
  loop
    v_function_oid := to_regprocedure(v_signature);

    return query
    select
      'RPC_EXISTS',
      v_signature,
      v_function_oid is not null,
      coalesce(v_function_oid::regprocedure::text, 'missing');

    return query
    select
      'RPC_SECURITY_DEFINER',
      v_signature,
      coalesce(proc.prosecdef, false),
      format(
        'security_definer=%s',
        coalesce(proc.prosecdef, false)
      )
    from pg_catalog.pg_proc proc
    where proc.oid = v_function_oid;

    return query
    select
      'RPC_SEARCH_PATH',
      v_signature,
      coalesce(proc.proconfig, array[]::text[])
        @> array['search_path=""']::text[],
      coalesce(array_to_string(proc.proconfig, ','), 'no proconfig')
    from pg_catalog.pg_proc proc
    where proc.oid = v_function_oid;

    return query
    select
      'RPC_AUTHENTICATED_EXECUTE',
      v_signature,
      has_function_privilege(
        'authenticated',
        v_signature,
        'EXECUTE'
      ),
      'Authenticated execute privilege checked.';

    return query
    select
      'RPC_ANON_BLOCKED',
      v_signature,
      not has_function_privilege(
        'anon',
        v_signature,
        'EXECUTE'
      ),
      'Anonymous execute privilege denied.';
  end loop;

  -- 1 service-role writer check
  return query
  select
    'SERVICE_ROLE',
    'report_writer_execute',
    has_function_privilege(
      'service_role',
      'public.report_operational_error(uuid,jsonb)',
      'EXECUTE'
    ),
    'Backend writers can use the trusted RPC.';

  select pa.user_id
  into v_admin_user
  from public.platform_admins pa
  join auth.users au
    on au.id = pa.user_id
  where pa.status = 'active'
    and coalesce(
      au.banned_until,
      '-infinity'::timestamptz
    ) <= now()
  order by pa.created_at, pa.user_id
  limit 1;

  select h.id
  into v_hotel_id
  from public.hotels h
  where h.status = 'active'
  order by h.created_at, h.id
  limit 1;

  if v_admin_user is null or v_hotel_id is null then
    raise exception
      'Migration 059 acceptance requires an active platform admin and hotel.';
  end if;

  delete from public.operational_error_events
  where request_id = 'd18-m059-acceptance';

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

  v_payload := jsonb_build_object(
    'source', 'webhook',
    'environment', 'test',
    'severity', 'critical',
    'event_name', 'day18.acceptance.test',
    'error_name', 'AcceptanceError',
    'error_code', 'D18_ACCEPTANCE',
    'message',
      'Failure for guest@example.com Bearer abcdefghijklmnopqrst.abcdefghijklmnopqrst.abcdefghijk /guest/secretToken123456',
    'route', '/guest/secretToken123456',
    'scope', 'acceptance',
    'component', 'Migration059',
    'incident_id', 'd18-acceptance-incident',
    'request_id', 'd18-m059-acceptance',
    'release', 'migration-059-rev1',
    'context', jsonb_build_object(
      'online', true,
      'visibility_state', 'visible',
      'viewport', '1440x900',
      'stack_frames', 7,
      'network_type', '4g',
      'retryable', true,
      'secret', 'must-not-persist'
    )
  );

  begin
    v_first_result := public.report_operational_error(
      v_hotel_id,
      v_payload
    );
    v_error := null;
  exception when others then
    v_error := format('%s [%s]', sqlerrm, sqlstate);
  end;

  v_event_id := nullif(v_first_result ->> 'event_id', '')::uuid;

  if v_event_id is not null then
    select *
    into v_event_record
    from public.operational_error_events
    where id = v_event_id;
  end if;

  -- 8 first-write runtime checks
  return query
  select
    'RUNTIME_REPORT',
    'writer_returns_shape',
    v_error is null
      and jsonb_typeof(v_first_result) = 'object'
      and v_first_result ?& array[
        'event_id',
        'incident_id',
        'fingerprint',
        'occurrence_count',
        'deduplicated',
        'recorded_at'
      ],
    coalesce(v_error, v_first_result::text);

  return query
  select
    'RUNTIME_REPORT',
    'row_inserted',
    v_event_record.id = v_event_id,
    coalesce(v_event_record.id::text, 'missing');

  return query
  select
    'RUNTIME_REPORT',
    'authenticated_source_forced_client',
    v_event_record.source = 'client',
    coalesce(v_event_record.source, 'missing');

  return query
  select
    'RUNTIME_REPORT',
    'actor_user_captured',
    v_event_record.actor_user_id = v_admin_user,
    coalesce(v_event_record.actor_user_id::text, 'missing');

  return query
  select
    'RUNTIME_REPORT',
    'sensitive_text_redacted',
    v_event_record.message like '%[REDACTED_EMAIL]%'
      and v_event_record.message like '%Bearer [REDACTED]%'
      and v_event_record.route = '/guest/:token'
      and v_event_record.message not like '%guest@example.com%'
      and v_event_record.message not like '%abcdefghijklmnopqrst.%'
      and v_event_record.message not like '%secretToken123456%',
    coalesce(v_event_record.message, 'missing');

  return query
  select
    'RUNTIME_REPORT',
    'context_allowlist',
    v_event_record.context ?& array[
      'online',
      'visibility_state',
      'viewport',
      'stack_frames',
      'network_type',
      'retryable'
    ]
      and not (v_event_record.context ? 'secret'),
    coalesce(v_event_record.context::text, 'missing');

  return query
  select
    'RUNTIME_REPORT',
    'release_request_environment',
    v_event_record.environment = 'test'
      and v_event_record.release = 'migration-059-rev1'
      and v_event_record.request_id = 'd18-m059-acceptance',
    format(
      'environment=%s release=%s request=%s',
      coalesce(v_event_record.environment, 'missing'),
      coalesce(v_event_record.release, 'missing'),
      coalesce(v_event_record.request_id, 'missing')
    );

  return query
  select
    'RUNTIME_REPORT',
    'first_occurrence_count',
    v_event_record.occurrence_count = 1
      and coalesce(
        (v_first_result ->> 'deduplicated')::boolean,
        true
      ) = false,
    format(
      'occurrence_count=%s deduplicated=%s',
      coalesce(v_event_record.occurrence_count::text, 'missing'),
      coalesce(v_first_result ->> 'deduplicated', 'missing')
    );

  begin
    v_second_result := public.report_operational_error(
      v_hotel_id,
      v_payload
    );
    v_error := null;
  exception when others then
    v_error := format('%s [%s]', sqlerrm, sqlstate);
  end;

  select *
  into v_event_record
  from public.operational_error_events
  where id = v_event_id;

  select count(*)
  into v_count
  from public.operational_error_events
  where hotel_id = v_hotel_id
    and request_id = 'd18-m059-acceptance';

  -- 3 deduplication runtime checks
  return query
  select
    'RUNTIME_DEDUPE',
    'same_event_reused',
    v_error is null
      and nullif(v_second_result ->> 'event_id', '')::uuid = v_event_id
      and coalesce(
        (v_second_result ->> 'deduplicated')::boolean,
        false
      ),
    coalesce(v_error, v_second_result::text);

  return query
  select
    'RUNTIME_DEDUPE',
    'occurrence_incremented',
    v_event_record.occurrence_count = 2,
    format(
      'occurrence_count=%s',
      coalesce(v_event_record.occurrence_count::text, 'missing')
    );

  return query
  select
    'RUNTIME_DEDUPE',
    'single_row_preserved',
    v_count = 1,
    format('matching_rows=%s', v_count);

  begin
    v_diagnostics := public.get_operational_diagnostics(
      v_hotel_id,
      now() - interval '1 hour',
      now() + interval '1 minute',
      1000,
      null,
      null,
      null,
      'd18-m059-acceptance'
    );
    v_error := null;
  exception when others then
    v_error := format('%s [%s]', sqlerrm, sqlstate);
  end;

  -- 4 diagnostics runtime checks
  return query
  select
    'RUNTIME_DIAGNOSTICS',
    'diagnostics_shape',
    v_error is null
      and jsonb_typeof(v_diagnostics) = 'object'
      and v_diagnostics ?& array[
        'captured_at',
        'hotel_id',
        'health_status',
        'window',
        'summary',
        'items',
        'query_health',
        'delivery_health'
      ],
    coalesce(v_error, v_diagnostics::text);

  return query
  select
    'RUNTIME_DIAGNOSTICS',
    'incident_visible',
    jsonb_array_length(v_diagnostics -> 'items') = 1
      and (
        v_diagnostics
        -> 'items'
        -> 0
        ->> 'id'
      )::uuid = v_event_id,
    coalesce(v_diagnostics -> 'items' -> 0 ->> 'incident_id', 'missing');

  return query
  select
    'RUNTIME_DIAGNOSTICS',
    'query_health_attached',
    coalesce(
      (
        v_diagnostics
        -> 'query_health'
        ->> 'invalid_index_count'
      )::integer,
      -1
    ) = 0
      and coalesce(
        (
          v_diagnostics
          -> 'query_health'
          ->> 'day18_index_count'
        )::integer,
        -1
      ) = 26,
    coalesce((v_diagnostics -> 'query_health')::text, 'missing');

  return query
  select
    'RUNTIME_DIAGNOSTICS',
    'limit_clamped_to_100',
    (
      v_diagnostics
      -> 'window'
      ->> 'limit'
    )::integer = 100,
    coalesce((v_diagnostics -> 'window')::text, 'missing');

  begin
    v_status_result := public.set_operational_incident_status(
      v_hotel_id,
      v_event_id,
      'acknowledged',
      'Reviewed by ops guest@example.com'
    );
    v_error := null;
  exception when others then
    v_error := format('%s [%s]', sqlerrm, sqlstate);
  end;

  select *
  into v_event_record
  from public.operational_error_events
  where id = v_event_id;

  -- 2 status runtime checks
  return query
  select
    'RUNTIME_STATUS',
    'acknowledge_returns_shape',
    v_error is null
      and v_status_result ->> 'status' = 'acknowledged'
      and nullif(v_status_result ->> 'event_id', '')::uuid = v_event_id,
    coalesce(v_error, v_status_result::text);

  return query
  select
    'RUNTIME_STATUS',
    'acknowledgement_audited_and_sanitized',
    v_event_record.status = 'acknowledged'
      and v_event_record.acknowledged_by = v_admin_user
      and v_event_record.acknowledged_at is not null
      and v_event_record.resolution_note like '%[REDACTED_EMAIL]%',
    coalesce(v_event_record.resolution_note, 'missing');

  -- 2 access/validation runtime checks
  begin
    perform public.set_operational_incident_status(
      v_hotel_id,
      v_event_id,
      'invalid_status',
      null
    );
    v_error := null;
  exception when others then
    v_error := sqlstate;
  end;

  return query
  select
    'RUNTIME_ACCESS',
    'invalid_status_rejected',
    v_error = '22023',
    coalesce(v_error, 'no error');

  begin
    perform public.report_operational_error(
      null,
      v_payload
    );
    v_error := null;
  exception when others then
    v_error := sqlstate;
  end;

  return query
  select
    'RUNTIME_ACCESS',
    'authenticated_null_hotel_rejected',
    v_error = '42501',
    coalesce(v_error, 'no error');

  delete from public.operational_error_events
  where request_id = 'd18-m059-acceptance';

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
end;
$function$;

revoke all on function private.day18_migration_059_acceptance_rev2()
from public, anon, authenticated;

commit;

select suite, test_name, passed, details
from private.day18_migration_059_acceptance_rev2()
order by suite, test_name;
