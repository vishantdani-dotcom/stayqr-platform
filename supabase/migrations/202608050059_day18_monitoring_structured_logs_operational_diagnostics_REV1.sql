-- ============================================================================
-- StayQR v1.0 — Day 18 Migration 059
-- Production monitoring, structured error logging and operational diagnostics
-- REV1
--
-- PURPOSE
-- 1. Create a tenant-aware operational error ledger.
-- 2. Persist sanitized frontend/backend failures with request and release context.
-- 3. Deduplicate repeated incidents without losing occurrence counts.
-- 4. Expose manager-only diagnostics and health snapshots.
-- 5. Keep direct table access closed; all writes/reads use trusted RPCs.
--
-- SAFETY
-- - No existing hotel business data is modified.
-- - Anonymous execution is denied.
-- - Authenticated users can only report against an authorized hotel.
-- - Diagnostic reads and status changes require hotel-management authority.
-- - Raw tokens, guest URLs, email addresses and phone numbers are sanitized.
-- - Arbitrary client context is not persisted; only a fixed allowlist is stored.
-- - No service-role secret is stored in the database or frontend.
--
-- EXPECTED RESULT
-- 100 rows / 100 passed / 0 failures
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '10min';

select pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtext('stayqr:202608050059:day18-monitoring-rev1')
);

do $preflight$
declare
  v_missing text;
begin
  select string_agg(required.object_name, ', ' order by required.object_name)
  into v_missing
  from (
    values
      ('public.hotels', to_regclass('public.hotels') is not null),
      ('public.platform_admins', to_regclass('public.platform_admins') is not null),
      ('auth.users', to_regclass('auth.users') is not null),
      (
        'private.user_has_hotel_access(uuid)',
        to_regprocedure('private.user_has_hotel_access(uuid)') is not null
      ),
      (
        'private.day17_can_manage_hotel(uuid)',
        to_regprocedure('private.day17_can_manage_hotel(uuid)') is not null
      ),
      (
        'public.get_day18_query_health(uuid)',
        to_regprocedure('public.get_day18_query_health(uuid)') is not null
      ),
      (
        'public.notification_deliveries',
        to_regclass('public.notification_deliveries') is not null
      )
  ) required(object_name, present)
  where not required.present;

  if v_missing is not null then
    raise exception
      'Migration 059 prerequisite(s) missing: %',
      v_missing
      using errcode = '55000';
  end if;
end;
$preflight$;

-- ============================================================================
-- 1. Operational error ledger
-- ============================================================================

create table if not exists public.operational_error_events (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid null references public.hotels(id) on delete set null,
  actor_user_id uuid null references auth.users(id) on delete set null,
  incident_id text not null,
  fingerprint text not null,
  source text not null default 'client',
  environment text not null default 'production',
  severity text not null default 'error',
  status text not null default 'open',
  event_name text not null default 'client.error',
  error_name text null,
  error_code text null,
  message text not null,
  route text null,
  scope text null,
  component text null,
  request_id text null,
  release text null,
  context jsonb not null default '{}'::jsonb,
  occurrence_count integer not null default 1,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  acknowledged_at timestamptz null,
  acknowledged_by uuid null references auth.users(id) on delete set null,
  resolved_at timestamptz null,
  resolved_by uuid null references auth.users(id) on delete set null,
  resolution_note text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint operational_error_events_incident_id_length
    check (char_length(incident_id) between 8 and 96),
  constraint operational_error_events_fingerprint_format
    check (fingerprint ~ '^[a-f0-9]{32}$'),
  constraint operational_error_events_source_check
    check (
      source in (
        'client',
        'edge_function',
        'webhook',
        'database',
        'deployment',
        'manual'
      )
    ),
  constraint operational_error_events_environment_check
    check (
      environment in (
        'development',
        'staging',
        'production',
        'test'
      )
    ),
  constraint operational_error_events_severity_check
    check (severity in ('info', 'warning', 'error', 'critical')),
  constraint operational_error_events_status_check
    check (status in ('open', 'acknowledged', 'resolved', 'ignored')),
  constraint operational_error_events_occurrence_count_check
    check (occurrence_count > 0),
  constraint operational_error_events_context_object_check
    check (jsonb_typeof(context) = 'object'),
  constraint operational_error_events_seen_order_check
    check (last_seen_at >= first_seen_at)
);

create unique index if not exists
  idx_d18_operational_error_incident_unique
on public.operational_error_events (incident_id);

create index if not exists
  idx_d18_operational_error_hotel_status
on public.operational_error_events (
  hotel_id,
  status,
  last_seen_at desc,
  id desc
);

create index if not exists
  idx_d18_operational_error_hotel_severity
on public.operational_error_events (
  hotel_id,
  severity,
  last_seen_at desc,
  id desc
);

create index if not exists
  idx_d18_operational_error_fingerprint
on public.operational_error_events (
  hotel_id,
  environment,
  fingerprint,
  last_seen_at desc
);

create index if not exists
  idx_d18_operational_error_request
on public.operational_error_events (request_id)
where request_id is not null;

create index if not exists
  idx_d18_operational_error_unresolved
on public.operational_error_events (
  hotel_id,
  last_seen_at desc,
  id desc
)
where status in ('open', 'acknowledged');

alter table public.operational_error_events enable row level security;
alter table public.operational_error_events force row level security;

revoke all on table public.operational_error_events
from public, anon, authenticated;

-- ============================================================================
-- 2. Sanitization helpers
-- ============================================================================

create or replace function private.day18_safe_log_text(
  p_value text,
  p_max_length integer default 500
)
returns text
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_text text := coalesce(p_value, '');
  v_limit integer := greatest(
    1,
    least(coalesce(p_max_length, 500), 4000)
  );
begin
  v_text := pg_catalog.regexp_replace(
    v_text,
    '(?i)bearer[[:space:]]+[a-z0-9._~+/-]+',
    'Bearer [REDACTED]',
    'g'
  );

  v_text := pg_catalog.regexp_replace(
    v_text,
    '(?i)[a-z0-9_-]{20,}\.[a-z0-9_-]{20,}\.[a-z0-9_-]{10,}',
    '[REDACTED_JWT]',
    'g'
  );

  v_text := pg_catalog.regexp_replace(
    v_text,
    '(?i)/(guest|food)/[a-z0-9_-]{8,}',
    '/\1/:token',
    'g'
  );

  v_text := pg_catalog.regexp_replace(
    v_text,
    '(?i)/invoice/verify/[a-z0-9_-]{8,}',
    '/invoice/verify/:token',
    'g'
  );

  v_text := pg_catalog.regexp_replace(
    v_text,
    '(?i)[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9.-]+\.[a-z]{2,}',
    '[REDACTED_EMAIL]',
    'g'
  );

  v_text := pg_catalog.regexp_replace(
    v_text,
    '(\+?[0-9][[:space:]().-]*){10,15}',
    '[REDACTED_PHONE]',
    'g'
  );

  v_text := pg_catalog.regexp_replace(
    v_text,
    '(?i)(anon[_-]?key|service[_-]?role|api[_-]?key|password|secret)[[:space:]]*[:=][[:space:]]*[^,[:space:];]+',
    '\1=[REDACTED]',
    'g'
  );

  return pg_catalog.left(v_text, v_limit);
end;
$function$;

create or replace function private.day18_safe_log_context(
  p_context jsonb
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_context jsonb := coalesce(p_context, '{}'::jsonb);
  v_stack_frames integer;
begin
  if jsonb_typeof(v_context) <> 'object' then
    return '{}'::jsonb;
  end if;

  if coalesce(v_context ->> 'stack_frames', '') ~ '^[0-9]+$' then
    v_stack_frames := least(
      greatest((v_context ->> 'stack_frames')::integer, 0),
      200
    );
  end if;

  return jsonb_strip_nulls(
    jsonb_build_object(
      'online',
        case
          when lower(v_context ->> 'online') in ('true', 'false')
          then (v_context ->> 'online')::boolean
          else null
        end,
      'visibility_state',
        nullif(
          private.day18_safe_log_text(
            v_context ->> 'visibility_state',
            32
          ),
          ''
        ),
      'viewport',
        nullif(
          private.day18_safe_log_text(
            v_context ->> 'viewport',
            64
          ),
          ''
        ),
      'stack_frames',
        v_stack_frames,
      'network_type',
        nullif(
          private.day18_safe_log_text(
            v_context ->> 'network_type',
            32
          ),
          ''
        ),
      'retryable',
        case
          when lower(v_context ->> 'retryable') in ('true', 'false')
          then (v_context ->> 'retryable')::boolean
          else null
        end
    )
  );
end;
$function$;

revoke all on function private.day18_safe_log_text(text, integer)
from public, anon, authenticated;

revoke all on function private.day18_safe_log_context(jsonb)
from public, anon, authenticated;

-- ============================================================================
-- 3. Trusted structured error writer
-- ============================================================================

create or replace function public.report_operational_error(
  p_hotel_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_is_service boolean := coalesce(auth.role(), '') = 'service_role';
  v_actor_user_id uuid := auth.uid();
  v_source text;
  v_environment text;
  v_severity text;
  v_event_name text;
  v_error_name text;
  v_error_code text;
  v_message text;
  v_route text;
  v_scope text;
  v_component text;
  v_request_id text;
  v_release text;
  v_context jsonb;
  v_incident_id text;
  v_fingerprint text;
  v_event_id uuid;
  v_occurrence_count integer;
  v_existing_id uuid;
  v_existing_incident text;
  v_deduplicated boolean := false;
begin
  if pg_column_size(v_payload) > 16384 then
    raise exception 'Operational payload exceeds 16 KiB.'
      using errcode = '22023';
  end if;

  if not v_is_service then
    if v_actor_user_id is null
       or p_hotel_id is null
       or not private.user_has_hotel_access(p_hotel_id)
    then
      raise exception 'Hotel access denied.'
        using errcode = '42501';
    end if;
  elsif p_hotel_id is not null
    and not exists (
      select 1
      from public.hotels h
      where h.id = p_hotel_id
    )
  then
    raise exception 'Unknown hotel context.'
      using errcode = '23503';
  end if;

  v_source := lower(coalesce(v_payload ->> 'source', 'client'));

  if not v_is_service then
    v_source := 'client';
  elsif v_source not in (
    'client',
    'edge_function',
    'webhook',
    'database',
    'deployment',
    'manual'
  ) then
    v_source := 'edge_function';
  end if;

  v_environment := lower(
    coalesce(v_payload ->> 'environment', 'production')
  );

  if v_environment not in (
    'development',
    'staging',
    'production',
    'test'
  ) then
    v_environment := 'production';
  end if;

  v_severity := lower(coalesce(v_payload ->> 'severity', 'error'));

  if v_severity not in ('info', 'warning', 'error', 'critical') then
    v_severity := 'error';
  end if;

  v_event_name := coalesce(
    nullif(
      private.day18_safe_log_text(
        v_payload ->> 'event_name',
        100
      ),
      ''
    ),
    'client.error'
  );

  v_error_name := nullif(
    private.day18_safe_log_text(
      v_payload ->> 'error_name',
      100
    ),
    ''
  );

  v_error_code := nullif(
    private.day18_safe_log_text(
      v_payload ->> 'error_code',
      100
    ),
    ''
  );

  v_message := coalesce(
    nullif(
      private.day18_safe_log_text(
        v_payload ->> 'message',
        1000
      ),
      ''
    ),
    'Unknown operational error'
  );

  v_route := nullif(
    private.day18_safe_log_text(
      v_payload ->> 'route',
      200
    ),
    ''
  );

  v_scope := nullif(
    private.day18_safe_log_text(
      v_payload ->> 'scope',
      100
    ),
    ''
  );

  v_component := nullif(
    private.day18_safe_log_text(
      v_payload ->> 'component',
      120
    ),
    ''
  );

  v_request_id := nullif(
    private.day18_safe_log_text(
      v_payload ->> 'request_id',
      96
    ),
    ''
  );

  v_release := nullif(
    private.day18_safe_log_text(
      v_payload ->> 'release',
      96
    ),
    ''
  );

  v_context := private.day18_safe_log_context(
    v_payload -> 'context'
  );

  v_incident_id := nullif(
    private.day18_safe_log_text(
      v_payload ->> 'incident_id',
      96
    ),
    ''
  );

  if v_incident_id is null
     or char_length(v_incident_id) < 8
  then
    v_incident_id :=
      'd18-' || replace(gen_random_uuid()::text, '-', '');
  end if;

  v_fingerprint := md5(
    concat_ws(
      '|',
      coalesce(p_hotel_id::text, 'platform'),
      v_environment,
      v_source,
      v_event_name,
      coalesce(v_error_name, ''),
      coalesce(v_error_code, ''),
      coalesce(v_route, ''),
      coalesce(v_scope, ''),
      coalesce(v_component, ''),
      left(v_message, 240)
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(
      coalesce(p_hotel_id::text, 'platform')
      || '|'
      || v_environment
      || '|'
      || v_fingerprint
    )
  );

  select
    event.id,
    event.incident_id
  into
    v_existing_id,
    v_existing_incident
  from public.operational_error_events event
  where event.hotel_id is not distinct from p_hotel_id
    and event.environment = v_environment
    and event.fingerprint = v_fingerprint
    and event.status in ('open', 'acknowledged')
    and event.last_seen_at >= now() - interval '30 minutes'
  order by event.last_seen_at desc, event.id desc
  limit 1
  for update;

  if v_existing_id is not null then
    update public.operational_error_events
    set
      severity = case
        when array_position(
          array['info', 'warning', 'error', 'critical'],
          v_severity
        ) > array_position(
          array['info', 'warning', 'error', 'critical'],
          severity
        )
        then v_severity
        else severity
      end,
      error_name = coalesce(v_error_name, error_name),
      error_code = coalesce(v_error_code, error_code),
      message = v_message,
      route = coalesce(v_route, route),
      scope = coalesce(v_scope, scope),
      component = coalesce(v_component, component),
      request_id = coalesce(v_request_id, request_id),
      release = coalesce(v_release, release),
      context = context || v_context,
      occurrence_count = occurrence_count + 1,
      last_seen_at = now(),
      updated_at = now()
    where id = v_existing_id
    returning
      id,
      incident_id,
      occurrence_count
    into
      v_event_id,
      v_incident_id,
      v_occurrence_count;

    v_deduplicated := true;
  else
    if exists (
      select 1
      from public.operational_error_events event
      where event.incident_id = v_incident_id
    ) then
      v_incident_id :=
        'd18-' || replace(gen_random_uuid()::text, '-', '');
    end if;

    insert into public.operational_error_events (
      hotel_id,
      actor_user_id,
      incident_id,
      fingerprint,
      source,
      environment,
      severity,
      status,
      event_name,
      error_name,
      error_code,
      message,
      route,
      scope,
      component,
      request_id,
      release,
      context
    )
    values (
      p_hotel_id,
      v_actor_user_id,
      v_incident_id,
      v_fingerprint,
      v_source,
      v_environment,
      v_severity,
      'open',
      v_event_name,
      v_error_name,
      v_error_code,
      v_message,
      v_route,
      v_scope,
      v_component,
      v_request_id,
      v_release,
      v_context
    )
    returning
      id,
      occurrence_count
    into
      v_event_id,
      v_occurrence_count;
  end if;

  return jsonb_build_object(
    'event_id', v_event_id,
    'incident_id', v_incident_id,
    'fingerprint', v_fingerprint,
    'occurrence_count', v_occurrence_count,
    'deduplicated', v_deduplicated,
    'recorded_at', now()
  );
end;
$function$;

-- ============================================================================
-- 4. Manager-only health snapshot
-- ============================================================================

create or replace function public.get_operational_health_snapshot(
  p_hotel_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_query_health jsonb;
  v_unresolved_24h bigint;
  v_critical_24h bigint;
  v_failed_deliveries bigint;
  v_retrying_deliveries bigint;
  v_last_event_at timestamptz;
  v_status text;
begin
  if p_hotel_id is null
     or not private.day17_can_manage_hotel(p_hotel_id)
  then
    raise exception 'Hotel management access required.'
      using errcode = '42501';
  end if;

  v_query_health := public.get_day18_query_health(p_hotel_id);

  select
    count(*) filter (
      where status in ('open', 'acknowledged')
    ),
    count(*) filter (
      where severity = 'critical'
        and status in ('open', 'acknowledged')
    ),
    max(last_seen_at)
  into
    v_unresolved_24h,
    v_critical_24h,
    v_last_event_at
  from public.operational_error_events
  where hotel_id = p_hotel_id
    and last_seen_at >= now() - interval '24 hours';

  select
    count(*) filter (where status = 'failed'),
    count(*) filter (where status = 'retrying')
  into
    v_failed_deliveries,
    v_retrying_deliveries
  from public.notification_deliveries
  where hotel_id = p_hotel_id
    and created_at >= now() - interval '24 hours';

  v_status := case
    when coalesce((v_query_health ->> 'invalid_index_count')::integer, 0) > 0
      or v_critical_24h > 0
    then 'critical'
    when v_unresolved_24h > 0
      or v_failed_deliveries > 0
      or v_retrying_deliveries > 0
    then 'degraded'
    else 'healthy'
  end;

  return jsonb_build_object(
    'captured_at', now(),
    'hotel_id', p_hotel_id,
    'status', v_status,
    'unresolved_24h', v_unresolved_24h,
    'critical_24h', v_critical_24h,
    'last_event_at', v_last_event_at,
    'query_health', v_query_health,
    'delivery_health', jsonb_build_object(
      'failed_24h', v_failed_deliveries,
      'retrying_24h', v_retrying_deliveries
    )
  );
end;
$function$;

-- ============================================================================
-- 5. Manager-only searchable diagnostics
-- ============================================================================

create or replace function public.get_operational_diagnostics(
  p_hotel_id uuid,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_limit integer default 50,
  p_status text default null,
  p_severity text default null,
  p_source text default null,
  p_search text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_to timestamptz := coalesce(p_to, now());
  v_from timestamptz := coalesce(
    p_from,
    coalesce(p_to, now()) - interval '7 days'
  );
  v_limit integer := greatest(1, least(coalesce(p_limit, 50), 100));
  v_status text := nullif(lower(trim(p_status)), '');
  v_severity text := nullif(lower(trim(p_severity)), '');
  v_source text := nullif(lower(trim(p_source)), '');
  v_search text := nullif(lower(trim(p_search)), '');
  v_items jsonb;
  v_summary jsonb;
  v_health jsonb;
begin
  if p_hotel_id is null
     or not private.day17_can_manage_hotel(p_hotel_id)
  then
    raise exception 'Hotel management access required.'
      using errcode = '42501';
  end if;

  if v_from > v_to then
    raise exception 'Diagnostic start must be before end.'
      using errcode = '22007';
  end if;

  if v_to - v_from > interval '31 days' then
    v_from := v_to - interval '31 days';
  end if;

  with visible as (
    select
      event.id,
      event.incident_id,
      event.source,
      event.environment,
      event.severity,
      event.status,
      event.event_name,
      event.error_name,
      event.error_code,
      event.message,
      event.route,
      event.scope,
      event.component,
      event.request_id,
      event.release,
      event.context,
      event.occurrence_count,
      event.first_seen_at,
      event.last_seen_at,
      event.acknowledged_at,
      event.resolved_at,
      event.resolution_note
    from public.operational_error_events event
    where event.hotel_id = p_hotel_id
      and event.last_seen_at between v_from and v_to
      and (v_status is null or event.status = v_status)
      and (v_severity is null or event.severity = v_severity)
      and (v_source is null or event.source = v_source)
      and (
        v_search is null
        or lower(event.incident_id) like '%' || v_search || '%'
        or lower(coalesce(event.request_id, '')) like '%' || v_search || '%'
        or lower(coalesce(event.error_code, '')) like '%' || v_search || '%'
        or lower(event.message) like '%' || v_search || '%'
      )
    order by event.last_seen_at desc, event.id desc
    limit v_limit
  )
  select coalesce(
    jsonb_agg(to_jsonb(visible) order by last_seen_at desc, id desc),
    '[]'::jsonb
  )
  into v_items
  from visible;

  select jsonb_build_object(
    'total_in_window', count(*),
    'open_count', count(*) filter (where status = 'open'),
    'acknowledged_count', count(*) filter (where status = 'acknowledged'),
    'resolved_count', count(*) filter (where status = 'resolved'),
    'ignored_count', count(*) filter (where status = 'ignored'),
    'critical_count', count(*) filter (where severity = 'critical'),
    'error_count', count(*) filter (where severity = 'error'),
    'warning_count', count(*) filter (where severity = 'warning')
  )
  into v_summary
  from public.operational_error_events event
  where event.hotel_id = p_hotel_id
    and event.last_seen_at between v_from and v_to
    and (v_status is null or event.status = v_status)
    and (v_severity is null or event.severity = v_severity)
    and (v_source is null or event.source = v_source)
    and (
      v_search is null
      or lower(event.incident_id) like '%' || v_search || '%'
      or lower(coalesce(event.request_id, '')) like '%' || v_search || '%'
      or lower(coalesce(event.error_code, '')) like '%' || v_search || '%'
      or lower(event.message) like '%' || v_search || '%'
    );

  v_health := public.get_operational_health_snapshot(p_hotel_id);

  return jsonb_build_object(
    'captured_at', now(),
    'hotel_id', p_hotel_id,
    'health_status', v_health ->> 'status',
    'window', jsonb_build_object(
      'from', v_from,
      'to', v_to,
      'limit', v_limit
    ),
    'summary', v_summary,
    'items', v_items,
    'query_health', v_health -> 'query_health',
    'delivery_health', v_health -> 'delivery_health'
  );
end;
$function$;

-- ============================================================================
-- 6. Manager-only incident status transitions
-- ============================================================================

create or replace function public.set_operational_incident_status(
  p_hotel_id uuid,
  p_event_id uuid,
  p_status text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_status text := lower(trim(coalesce(p_status, '')));
  v_actor uuid := auth.uid();
  v_result jsonb;
begin
  if p_hotel_id is null
     or not private.day17_can_manage_hotel(p_hotel_id)
  then
    raise exception 'Hotel management access required.'
      using errcode = '42501';
  end if;

  if v_status not in ('open', 'acknowledged', 'resolved', 'ignored') then
    raise exception 'Invalid operational incident status.'
      using errcode = '22023';
  end if;

  update public.operational_error_events event
  set
    status = v_status,
    acknowledged_at = case
      when v_status = 'acknowledged'
      then coalesce(event.acknowledged_at, now())
      when v_status = 'open'
      then null
      else event.acknowledged_at
    end,
    acknowledged_by = case
      when v_status = 'acknowledged'
      then v_actor
      when v_status = 'open'
      then null
      else event.acknowledged_by
    end,
    resolved_at = case
      when v_status in ('resolved', 'ignored')
      then now()
      when v_status = 'open'
      then null
      else event.resolved_at
    end,
    resolved_by = case
      when v_status in ('resolved', 'ignored')
      then v_actor
      when v_status = 'open'
      then null
      else event.resolved_by
    end,
    resolution_note = case
      when p_note is not null
      then nullif(private.day18_safe_log_text(p_note, 500), '')
      when v_status = 'open'
      then null
      else event.resolution_note
    end,
    updated_at = now()
  where event.id = p_event_id
    and event.hotel_id = p_hotel_id
  returning jsonb_build_object(
    'event_id', event.id,
    'incident_id', event.incident_id,
    'status', event.status,
    'acknowledged_at', event.acknowledged_at,
    'resolved_at', event.resolved_at,
    'resolution_note', event.resolution_note,
    'updated_at', event.updated_at
  )
  into v_result;

  if v_result is null then
    raise exception 'Operational incident was not found.'
      using errcode = 'P0002';
  end if;

  return v_result;
end;
$function$;

-- ============================================================================
-- 7. Execution closure
-- ============================================================================

revoke all on function public.report_operational_error(uuid, jsonb)
from public, anon;

revoke all on function public.get_operational_health_snapshot(uuid)
from public, anon;

revoke all on function public.get_operational_diagnostics(
  uuid,
  timestamptz,
  timestamptz,
  integer,
  text,
  text,
  text,
  text
)
from public, anon;

revoke all on function public.set_operational_incident_status(
  uuid,
  uuid,
  text,
  text
)
from public, anon;

grant execute on function public.report_operational_error(uuid, jsonb)
to authenticated, service_role;

grant execute on function public.get_operational_health_snapshot(uuid)
to authenticated;

grant execute on function public.get_operational_diagnostics(
  uuid,
  timestamptz,
  timestamptz,
  integer,
  text,
  text,
  text,
  text
)
to authenticated;

grant execute on function public.set_operational_incident_status(
  uuid,
  uuid,
  text,
  text
)
to authenticated;

-- ============================================================================
-- 8. Fixed 100-row acceptance
-- ============================================================================

create or replace function private.day18_migration_059_acceptance_rev1()
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
      and v_event_record.message like '%[REDACTED_JWT]%'
      and v_event_record.route = '/guest/:token'
      and v_event_record.message not like '%guest@example.com%'
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
      ) = 20,
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

revoke all on function private.day18_migration_059_acceptance_rev1()
from public, anon, authenticated;

commit;

select suite, test_name, passed, details
from private.day18_migration_059_acceptance_rev1()
order by suite, test_name;
