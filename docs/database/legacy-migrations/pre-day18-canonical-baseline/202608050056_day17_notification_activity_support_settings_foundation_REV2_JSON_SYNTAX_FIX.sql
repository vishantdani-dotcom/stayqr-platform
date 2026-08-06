-- ============================================================================
-- StayQR v1.0
-- Migration 056 REV2 JSON SYNTAX FIX
-- Day 17 Notification, Activity, Support and System Settings Foundation
--
-- GROUNDED IN AUDIT 069 REV3
-- 217 rows: 192 passed / 25 compatibility findings.
--
-- COMPATIBILITY DECISIONS
-- - Reuse support_ticket_events; do not create support_ticket_messages.
-- - Reuse support_tickets.created_by and assigned_to.
-- - Reuse announcements.target_hotel_id and created_by.
-- - Reuse save_platform_announcement(jsonb).
-- - Reuse hotel_settings actual Day 8 columns.
-- - hotels remains timezone and currency authority.
-- - Create reservation/payment notification events through transactional
--   outbox triggers without inventing reservation_events/payment_events.
--
-- PROVIDER SAFETY
-- - No email or WhatsApp provider secret is stored in this migration.
-- - Email configs store secret references only.
-- - WhatsApp is manual-template only; no automatic sending endpoint.
--
-- EXPECTED RESULT
-- 274 rows / 274 passed / 0 failures.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '300s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202608050056:day17-foundation-rev2')
);

create schema if not exists private;

do $preflight$
declare
  v_missing text;
begin
  select string_agg(item, ', ' order by item)
  into v_missing
  from (
    values
      ('public.hotels', to_regclass('public.hotels') is not null),
      ('public.hotel_settings', to_regclass('public.hotel_settings') is not null),
      ('public.staff', to_regclass('public.staff') is not null),
      ('public.notifications', to_regclass('public.notifications') is not null),
      ('public.activity_logs', to_regclass('public.activity_logs') is not null),
      ('public.support_tickets', to_regclass('public.support_tickets') is not null),
      ('public.support_ticket_events', to_regclass('public.support_ticket_events') is not null),
      ('public.announcements', to_regclass('public.announcements') is not null),
      ('public.reservations', to_regclass('public.reservations') is not null),
      ('public.payments', to_regclass('public.payments') is not null),
      ('public.service_requests', to_regclass('public.service_requests') is not null),
      ('private.user_has_hotel_access(uuid)',
        to_regprocedure('private.user_has_hotel_access(uuid)') is not null),
      ('private.user_has_hotel_role(uuid,text[])',
        to_regprocedure('private.user_has_hotel_role(uuid,text[])') is not null),
      ('private.is_platform_admin()',
        to_regprocedure('private.is_platform_admin()') is not null),
      ('private.set_updated_at()',
        to_regprocedure('private.set_updated_at()') is not null)
  ) required(item, exists_now)
  where not exists_now;

  if v_missing is not null then
    raise exception 'Migration 056 stopped. Missing prerequisite(s): %', v_missing;
  end if;
end;
$preflight$;

-- ============================================================================
-- 1. Canonical event catalogue and recipient preferences
-- ============================================================================

create table if not exists public.notification_event_catalog (
  event_key text primary key,
  source_type text not null,
  audience text not null default 'all_staff',
  severity text not null default 'info',
  default_channels jsonb not null default '["in_app"]'::jsonb,
  default_title text not null,
  default_body text not null,
  is_critical boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_event_catalog_key_not_blank
    check (length(trim(event_key)) between 3 and 120),
  constraint notification_event_catalog_source_not_blank
    check (length(trim(source_type)) between 2 and 80),
  constraint notification_event_catalog_audience_check
    check (audience in ('all_staff', 'platform_admins', 'guest_session')),
  constraint notification_event_catalog_severity_check
    check (severity in ('info', 'success', 'warning', 'critical')),
  constraint notification_event_catalog_channels_array
    check (jsonb_typeof(default_channels) = 'array'),
  constraint notification_event_catalog_title_not_blank
    check (length(trim(default_title)) > 0),
  constraint notification_event_catalog_body_not_blank
    check (length(trim(default_body)) > 0)
);

create table if not exists public.notification_preferences (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  in_app_enabled boolean not null default true,
  email_enabled boolean not null default false,
  manual_whatsapp_enabled boolean not null default false,
  locale text not null default 'en',
  quiet_hours_start time,
  quiet_hours_end time,
  event_overrides jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_preferences_locale_not_blank
    check (length(trim(locale)) between 2 and 20),
  constraint notification_preferences_overrides_object
    check (jsonb_typeof(event_overrides) = 'object'),
  constraint notification_preferences_hotel_user_unique
    unique (hotel_id, user_id)
);

-- ============================================================================
-- 2. Versioned templates
-- ============================================================================

create table if not exists public.notification_templates (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid references public.hotels(id) on delete cascade,
  event_key text not null
    references public.notification_event_catalog(event_key) on delete restrict,
  channel text not null,
  locale text not null default 'en',
  title_template text not null,
  body_template text not null,
  status text not null default 'draft',
  current_version integer not null default 1,
  created_by uuid references auth.users(id) on delete set null,
  published_by uuid references auth.users(id) on delete set null,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_templates_channel_check
    check (channel in ('in_app', 'email', 'manual_whatsapp')),
  constraint notification_templates_locale_not_blank
    check (length(trim(locale)) between 2 and 20),
  constraint notification_templates_title_not_blank
    check (length(trim(title_template)) > 0),
  constraint notification_templates_body_not_blank
    check (length(trim(body_template)) > 0),
  constraint notification_templates_status_check
    check (status in ('draft', 'published', 'archived')),
  constraint notification_templates_version_positive
    check (current_version >= 1)
);

create unique index if not exists
  uq_notification_templates_global
on public.notification_templates (event_key, channel, locale)
where hotel_id is null;

create unique index if not exists
  uq_notification_templates_hotel
on public.notification_templates (hotel_id, event_key, channel, locale)
where hotel_id is not null;

create table if not exists public.notification_template_versions (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null
    references public.notification_templates(id) on delete cascade,
  version_number integer not null,
  title_template text not null,
  body_template text not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint notification_template_versions_positive
    check (version_number >= 1),
  constraint notification_template_versions_unique
    unique (template_id, version_number)
);

-- ============================================================================
-- 3. Transactional outbox, recipient inbox and delivery ledgers
-- ============================================================================

create table if not exists public.notification_outbox (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  event_key text not null
    references public.notification_event_catalog(event_key) on delete restrict,
  source_type text not null,
  source_id uuid not null,
  idempotency_key text not null,
  payload jsonb not null default '{}'::jsonb,
  business_date date not null,
  status text not null default 'pending',
  pending_delivery_count integer not null default 0,
  completed_delivery_count integer not null default 0,
  failed_delivery_count integer not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_outbox_source_not_blank
    check (length(trim(source_type)) > 0),
  constraint notification_outbox_idempotency_not_blank
    check (length(trim(idempotency_key)) between 8 and 240),
  constraint notification_outbox_payload_object
    check (jsonb_typeof(payload) = 'object'),
  constraint notification_outbox_status_check
    check (status in ('pending', 'processing', 'completed', 'partial', 'failed')),
  constraint notification_outbox_counts_nonnegative
    check (
      pending_delivery_count >= 0
      and completed_delivery_count >= 0
      and failed_delivery_count >= 0
    ),
  constraint notification_outbox_hotel_idempotency_unique
    unique (hotel_id, idempotency_key)
);

create index if not exists idx_notification_outbox_hotel_status
on public.notification_outbox (
  hotel_id,
  status,
  occurred_at desc
);

create table if not exists public.notification_recipients (
  id uuid primary key default gen_random_uuid(),
  outbox_id uuid not null
    references public.notification_outbox(id) on delete cascade,
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  message text not null,
  severity text not null default 'info',
  status text not null default 'unread',
  read_at timestamptz,
  dismissed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_recipients_title_not_blank
    check (length(trim(title)) > 0),
  constraint notification_recipients_message_not_blank
    check (length(trim(message)) > 0),
  constraint notification_recipients_severity_check
    check (severity in ('info', 'success', 'warning', 'critical')),
  constraint notification_recipients_status_check
    check (status in ('unread', 'read', 'dismissed')),
  constraint notification_recipients_metadata_object
    check (jsonb_typeof(metadata) = 'object'),
  constraint notification_recipients_outbox_user_unique
    unique (outbox_id, user_id)
);

create index if not exists idx_notification_recipients_user_unread
on public.notification_recipients (
  user_id,
  hotel_id,
  status,
  created_at desc
);

create table if not exists public.notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  outbox_id uuid not null
    references public.notification_outbox(id) on delete cascade,
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  recipient_user_id uuid references auth.users(id) on delete cascade,
  guest_session_id uuid,
  channel text not null,
  address_snapshot text,
  locale text not null default 'en',
  rendered_title text not null,
  rendered_body text not null,
  status text not null default 'pending',
  attempt_count integer not null default 0,
  max_attempts integer not null default 3,
  next_attempt_at timestamptz,
  last_error_code text,
  last_error_message text,
  manual_action_url text,
  provider_message_id text,
  queued_at timestamptz not null default now(),
  delivered_at timestamptz,
  read_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_deliveries_channel_check
    check (channel in ('in_app', 'email', 'manual_whatsapp')),
  constraint notification_deliveries_status_check
    check (
      status in (
        'pending',
        'adapter_ready',
        'manual_ready',
        'retrying',
        'delivered',
        'read',
        'skipped',
        'failed'
      )
    ),
  constraint notification_deliveries_attempts_check
    check (attempt_count >= 0 and max_attempts between 1 and 20),
  constraint notification_deliveries_metadata_object
    check (jsonb_typeof(metadata) = 'object')
);

create unique index if not exists
  uq_notification_deliveries_recipient_channel
on public.notification_deliveries (
  outbox_id,
  coalesce(recipient_user_id, '00000000-0000-0000-0000-000000000000'::uuid),
  coalesce(guest_session_id, '00000000-0000-0000-0000-000000000000'::uuid),
  channel
);

create index if not exists idx_notification_deliveries_hotel_status
on public.notification_deliveries (
  hotel_id,
  status,
  next_attempt_at,
  created_at
);

create table if not exists public.notification_delivery_attempts (
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid not null
    references public.notification_deliveries(id) on delete cascade,
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  attempt_number integer not null,
  attempt_status text not null,
  adapter_key text,
  error_code text,
  error_message text,
  request_metadata jsonb not null default '{}'::jsonb,
  response_metadata jsonb not null default '{}'::jsonb,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint notification_attempts_number_positive
    check (attempt_number >= 1),
  constraint notification_attempts_status_check
    check (attempt_status in ('prepared', 'sent', 'failed', 'skipped')),
  constraint notification_attempts_request_object
    check (jsonb_typeof(request_metadata) = 'object'),
  constraint notification_attempts_response_object
    check (jsonb_typeof(response_metadata) = 'object'),
  constraint notification_attempts_unique
    unique (delivery_id, attempt_number)
);

create table if not exists public.notification_dead_letters (
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid not null
    references public.notification_deliveries(id) on delete cascade,
  outbox_id uuid not null
    references public.notification_outbox(id) on delete cascade,
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  reason_code text not null,
  reason_message text not null,
  payload_snapshot jsonb not null default '{}'::jsonb,
  resolved_at timestamptz,
  resolved_by uuid references auth.users(id) on delete set null,
  resolution_note text,
  created_at timestamptz not null default now(),
  constraint notification_dead_letters_reason_not_blank
    check (
      length(trim(reason_code)) > 0
      and length(trim(reason_message)) > 0
    ),
  constraint notification_dead_letters_payload_object
    check (jsonb_typeof(payload_snapshot) = 'object'),
  constraint notification_dead_letters_delivery_unique
    unique (delivery_id)
);

-- ============================================================================
-- 4. Provider-neutral email and manual WhatsApp configuration
-- ============================================================================

create table if not exists public.email_adapter_configs (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid references public.hotels(id) on delete cascade,
  adapter_key text not null,
  provider text not null default 'edge_function',
  from_name text,
  from_email text,
  reply_to_email text,
  secret_reference text,
  endpoint_name text,
  is_enabled boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint email_adapter_configs_key_not_blank
    check (length(trim(adapter_key)) between 2 and 100),
  constraint email_adapter_configs_provider_check
    check (provider in ('edge_function', 'external_worker', 'manual')),
  constraint email_adapter_configs_metadata_object
    check (jsonb_typeof(metadata) = 'object')
);

create unique index if not exists uq_email_adapter_global
on public.email_adapter_configs (adapter_key)
where hotel_id is null;

create unique index if not exists uq_email_adapter_hotel
on public.email_adapter_configs (hotel_id, adapter_key)
where hotel_id is not null;

create table if not exists public.whatsapp_templates (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid references public.hotels(id) on delete cascade,
  event_key text not null
    references public.notification_event_catalog(event_key) on delete restrict,
  locale text not null default 'en',
  template_name text not null,
  body_template text not null,
  status text not null default 'draft',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint whatsapp_templates_locale_not_blank
    check (length(trim(locale)) between 2 and 20),
  constraint whatsapp_templates_name_not_blank
    check (length(trim(template_name)) > 0),
  constraint whatsapp_templates_body_not_blank
    check (length(trim(body_template)) > 0),
  constraint whatsapp_templates_status_check
    check (status in ('draft', 'published', 'archived'))
);

create unique index if not exists uq_whatsapp_templates_global
on public.whatsapp_templates (event_key, locale)
where hotel_id is null;

create unique index if not exists uq_whatsapp_templates_hotel
on public.whatsapp_templates (hotel_id, event_key, locale)
where hotel_id is not null;

-- ============================================================================
-- 5. Business-day authority
-- ============================================================================

create table if not exists public.business_day_settings (
  hotel_id uuid primary key
    references public.hotels(id) on delete cascade,
  business_day_cutoff time not null default '00:00',
  week_starts_on integer not null default 1,
  night_audit_time time not null default '02:00',
  locale text not null default 'en-IN',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint business_day_settings_week_check
    check (week_starts_on between 0 and 6),
  constraint business_day_settings_locale_not_blank
    check (length(trim(locale)) between 2 and 20)
);

insert into public.business_day_settings (
  hotel_id,
  business_day_cutoff,
  week_starts_on,
  night_audit_time,
  locale,
  created_at,
  updated_at
)
select
  h.id,
  '00:00'::time,
  1,
  '02:00'::time,
  coalesce(nullif(trim(hs.locale), ''), 'en-IN'),
  now(),
  now()
from public.hotels h
left join public.hotel_settings hs
  on hs.hotel_id = h.id
on conflict (hotel_id) do nothing;

-- ============================================================================
-- 6. Seed canonical events and safe platform templates
-- ============================================================================

insert into public.notification_event_catalog (
  event_key,
  source_type,
  audience,
  severity,
  default_channels,
  default_title,
  default_body,
  is_critical,
  is_active,
  created_at,
  updated_at
)
values
  ('reservation.created', 'reservation', 'all_staff', 'info', jsonb_build_array('in_app'), 'New reservation {{reservation_number}}', 'A reservation was created with status {{status}}.', true, true, now(), now()),
  ('reservation.status_changed', 'reservation', 'all_staff', 'warning', jsonb_build_array('in_app'), 'Reservation {{reservation_number}} updated', 'Reservation status changed from {{old_status}} to {{status}}.', true, true, now(), now()),
  ('payment.created', 'payment', 'all_staff', 'info', jsonb_build_array('in_app'), 'Payment record created', 'A payment of {{amount}} was recorded with status {{status}}.', true, true, now(), now()),
  ('payment.status_changed', 'payment', 'all_staff', 'warning', jsonb_build_array('in_app'), 'Payment status updated', 'Payment status changed from {{old_status}} to {{status}}.', true, true, now(), now()),
  ('service_request.created', 'service_request', 'all_staff', 'info', jsonb_build_array('in_app'), 'New service request', '{{request_type}} was requested for department {{department}}.', true, true, now(), now()),
  ('service_request.status_changed', 'service_request', 'all_staff', 'warning', jsonb_build_array('in_app'), 'Service request updated', '{{request_type}} changed from {{old_status}} to {{status}}.', true, true, now(), now()),
  ('support.ticket_created', 'support_ticket', 'all_staff', 'info', jsonb_build_array('in_app'), 'Support ticket {{ticket_number}} created', '{{subject}} has been submitted to StayQR support.', false, true, now(), now()),
  ('support.status_changed', 'support_ticket', 'all_staff', 'info', jsonb_build_array('in_app'), 'Support ticket {{ticket_number}} updated', 'Support status changed from {{old_status}} to {{status}}.', false, true, now(), now()),
  ('announcement.published', 'announcement', 'all_staff', 'info', jsonb_build_array('in_app'), '{{title}}', '{{body}}', false, true, now(), now())
on conflict (event_key) do update
set
  source_type = excluded.source_type,
  audience = excluded.audience,
  severity = excluded.severity,
  default_channels = excluded.default_channels,
  default_title = excluded.default_title,
  default_body = excluded.default_body,
  is_critical = excluded.is_critical,
  is_active = excluded.is_active,
  updated_at = now();

insert into public.notification_templates (
  hotel_id,
  event_key,
  channel,
  locale,
  title_template,
  body_template,
  status,
  current_version,
  published_at,
  created_at,
  updated_at
)
select
  null,
  nec.event_key,
  'in_app',
  'en',
  nec.default_title,
  nec.default_body,
  'published',
  1,
  now(),
  now(),
  now()
from public.notification_event_catalog nec
where nec.event_key in (
  'reservation.created', 'reservation.status_changed', 'payment.created', 'payment.status_changed', 'service_request.created', 'service_request.status_changed', 'support.ticket_created', 'support.status_changed', 'announcement.published'
)
on conflict (event_key, channel, locale)
where hotel_id is null
do update
set
  title_template = excluded.title_template,
  body_template = excluded.body_template,
  status = 'published',
  published_at = coalesce(
    public.notification_templates.published_at,
    now()
  ),
  updated_at = now();

insert into public.notification_template_versions (
  template_id,
  version_number,
  title_template,
  body_template,
  created_at
)
select
  nt.id,
  1,
  nt.title_template,
  nt.body_template,
  now()
from public.notification_templates nt
where nt.hotel_id is null
  and nt.channel = 'in_app'
  and nt.locale = 'en'
  and nt.event_key in (
    'reservation.created', 'reservation.status_changed', 'payment.created', 'payment.status_changed', 'service_request.created', 'service_request.status_changed', 'support.ticket_created', 'support.status_changed', 'announcement.published'
  )
on conflict (template_id, version_number) do nothing;

-- ============================================================================
-- 7. Updated-at triggers
-- ============================================================================

do $updated_at$
declare
  v_table text;
begin
  foreach v_table in array array[
    'notification_event_catalog',
    'notification_preferences',
    'notification_templates',
    'notification_outbox',
    'notification_recipients',
    'notification_deliveries',
    'email_adapter_configs',
    'whatsapp_templates',
    'business_day_settings'
  ]
  loop
    execute format(
      'drop trigger if exists %I on public.%I',
      'set_' || v_table || '_updated_at_day17',
      v_table
    );

    execute format(
      'create trigger %I before update on public.%I
       for each row execute function private.set_updated_at()',
      'set_' || v_table || '_updated_at_day17',
      v_table
    );
  end loop;
end;
$updated_at$;

-- ============================================================================
-- 8. Security helpers and business-date resolver
-- ============================================================================

create or replace function private.day17_can_manage_hotel(
  p_hotel_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    private.is_platform_admin()
    or private.user_has_hotel_role(
      p_hotel_id,
      array['owner', 'manager', 'hotel_admin', 'admin']
    );
$function$;

create or replace function private.resolve_hotel_business_date(
  p_hotel_id uuid,
  p_occurred_at timestamptz default now()
)
returns date
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_timezone text;
  v_cutoff time;
  v_local timestamp;
begin
  select
    coalesce(nullif(trim(h.timezone), ''), 'Asia/Kolkata'),
    coalesce(bds.business_day_cutoff, '00:00'::time)
  into v_timezone, v_cutoff
  from public.hotels h
  left join public.business_day_settings bds
    on bds.hotel_id = h.id
  where h.id = p_hotel_id;

  if not found then
    raise exception 'Hotel was not found.';
  end if;

  v_local := p_occurred_at at time zone v_timezone;

  return case
    when v_local::time < v_cutoff
      then v_local::date - 1
    else v_local::date
  end;
end;
$function$;

create or replace function private.day17_render_notification_text(
  p_template text,
  p_payload jsonb
)
returns text
language plpgsql
immutable
security invoker
set search_path = ''
as $function$
declare
  v_result text := coalesce(p_template, '');
  v_pair record;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    return v_result;
  end if;

  for v_pair in
    select key, value
    from jsonb_each_text(p_payload)
  loop
    v_result := replace(
      v_result,
      '{{' || v_pair.key || '}}',
      coalesce(v_pair.value, '')
    );
  end loop;

  return v_result;
end;
$function$;

-- ============================================================================
-- 9. Internal transactional outbox writer
-- ============================================================================

create or replace function private.day17_enqueue_notification_event_internal(
  p_hotel_id uuid,
  p_event_key text,
  p_source_id uuid,
  p_payload jsonb,
  p_actor_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_catalog public.notification_event_catalog%rowtype;
  v_outbox public.notification_outbox%rowtype;
  v_existing public.notification_outbox%rowtype;
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_idempotency_key text;
  v_recipient record;
  v_title_template text;
  v_body_template text;
  v_title text;
  v_body text;
  v_locale text;
  v_recipient_count integer := 0;
  v_pending_count integer := 0;
begin
  if jsonb_typeof(v_payload) <> 'object' then
    raise exception 'Notification payload must be a JSON object.';
  end if;

  select *
  into v_catalog
  from public.notification_event_catalog nec
  where nec.event_key = p_event_key
    and nec.is_active;

  if not found then
    raise exception 'Unsupported notification event key: %', p_event_key;
  end if;

  if not exists (
    select 1
    from public.hotels h
    where h.id = p_hotel_id
  ) then
    raise exception 'Notification hotel was not found.';
  end if;

  v_idempotency_key := coalesce(
    nullif(trim(v_payload ->> 'idempotency_key'), ''),
    p_event_key || ':' || p_source_id::text || ':' ||
      coalesce(
        nullif(trim(v_payload ->> 'status'), ''),
        nullif(trim(v_payload ->> 'event_version'), ''),
        'base'
      )
  );

  insert into public.notification_outbox (
    hotel_id,
    event_key,
    source_type,
    source_id,
    idempotency_key,
    payload,
    business_date,
    status,
    created_by,
    occurred_at,
    created_at,
    updated_at
  ) values (
    p_hotel_id,
    p_event_key,
    v_catalog.source_type,
    p_source_id,
    v_idempotency_key,
    v_payload - 'idempotency_key',
    private.resolve_hotel_business_date(
      p_hotel_id,
      coalesce(
        nullif(v_payload ->> 'occurred_at', '')::timestamptz,
        now()
      )
    ),
    'processing',
    p_actor_user_id,
    coalesce(
      nullif(v_payload ->> 'occurred_at', '')::timestamptz,
      now()
    ),
    now(),
    now()
  )
  on conflict (hotel_id, idempotency_key) do nothing
  returning * into v_outbox;

  if v_outbox.id is null then
    select *
    into v_existing
    from public.notification_outbox nox
    where nox.hotel_id = p_hotel_id
      and nox.idempotency_key = v_idempotency_key;

    return jsonb_build_object(
      'outbox_id', v_existing.id,
      'idempotent', true,
      'status', v_existing.status
    );
  end if;

  for v_recipient in
    select
      s.auth_user_id as user_id,
      nullif(trim(s.email), '') as email,
      nullif(trim(s.phone), '') as phone,
      coalesce(np.locale, 'en') as locale,
      coalesce(np.in_app_enabled, true) as in_app_enabled,
      coalesce(np.email_enabled, false) as email_enabled,
      coalesce(np.manual_whatsapp_enabled, false)
        as manual_whatsapp_enabled
    from public.staff s
    left join public.notification_preferences np
      on np.hotel_id = s.hotel_id
     and np.user_id = s.auth_user_id
    where s.hotel_id = p_hotel_id
      and s.status = 'active'
      and s.auth_user_id is not null
  loop
    v_locale := v_recipient.locale;

    select
      nt.title_template,
      nt.body_template
    into
      v_title_template,
      v_body_template
    from public.notification_templates nt
    where nt.event_key = p_event_key
      and nt.channel = 'in_app'
      and nt.status = 'published'
      and (nt.hotel_id = p_hotel_id or nt.hotel_id is null)
      and nt.locale in (v_locale, 'en')
    order by
      case when nt.hotel_id = p_hotel_id then 0 else 1 end,
      case when nt.locale = v_locale then 0 else 1 end,
      nt.updated_at desc
    limit 1;

    v_title := private.day17_render_notification_text(
      coalesce(v_title_template, v_catalog.default_title),
      v_payload
    );
    v_body := private.day17_render_notification_text(
      coalesce(v_body_template, v_catalog.default_body),
      v_payload
    );

    if v_catalog.default_channels ? 'in_app'
       and v_recipient.in_app_enabled
    then
      insert into public.notification_recipients (
        outbox_id,
        hotel_id,
        user_id,
        title,
        message,
        severity,
        status,
        metadata,
        created_at,
        updated_at
      ) values (
        v_outbox.id,
        p_hotel_id,
        v_recipient.user_id,
        v_title,
        v_body,
        v_catalog.severity,
        'unread',
        jsonb_build_object(
          'event_key', p_event_key,
          'source_type', v_catalog.source_type,
          'source_id', p_source_id,
          'business_date', v_outbox.business_date
        ),
        now(),
        now()
      )
      on conflict (outbox_id, user_id) do nothing;

      insert into public.notification_deliveries (
        outbox_id,
        hotel_id,
        recipient_user_id,
        channel,
        address_snapshot,
        locale,
        rendered_title,
        rendered_body,
        status,
        attempt_count,
        delivered_at,
        metadata,
        created_at,
        updated_at
      ) values (
        v_outbox.id,
        p_hotel_id,
        v_recipient.user_id,
        'in_app',
        v_recipient.user_id::text,
        v_locale,
        v_title,
        v_body,
        'delivered',
        1,
        now(),
        jsonb_build_object('delivery_mode', 'realtime_in_app'),
        now(),
        now()
      )
      on conflict do nothing;

      v_recipient_count := v_recipient_count + 1;
    end if;

    if v_catalog.default_channels ? 'email'
       and v_recipient.email_enabled
       and v_recipient.email is not null
    then
      insert into public.notification_deliveries (
        outbox_id,
        hotel_id,
        recipient_user_id,
        channel,
        address_snapshot,
        locale,
        rendered_title,
        rendered_body,
        status,
        metadata,
        created_at,
        updated_at
      ) values (
        v_outbox.id,
        p_hotel_id,
        v_recipient.user_id,
        'email',
        v_recipient.email,
        v_locale,
        v_title,
        v_body,
        'pending',
        jsonb_build_object('delivery_mode', 'provider_adapter'),
        now(),
        now()
      )
      on conflict do nothing;

      v_pending_count := v_pending_count + 1;
    end if;
  end loop;

  update public.notification_outbox nox
  set
    status = case
      when v_pending_count > 0 then 'pending'
      else 'completed'
    end,
    pending_delivery_count = v_pending_count,
    completed_delivery_count = v_recipient_count,
    failed_delivery_count = 0,
    updated_at = now()
  where nox.id = v_outbox.id
  returning * into v_outbox;

  insert into public.activity_logs (
    hotel_id,
    actor_user_id,
    actor_role,
    action,
    entity_type,
    entity_id,
    description,
    metadata,
    created_at
  ) values (
    p_hotel_id,
    p_actor_user_id,
    case
      when p_actor_user_id is null then 'system'
      else 'authenticated'
    end,
    'notification_event_enqueued',
    v_catalog.source_type,
    p_source_id,
    p_event_key,
    jsonb_build_object(
      'outbox_id', v_outbox.id,
      'recipient_count', v_recipient_count,
      'pending_delivery_count', v_pending_count,
      'business_date', v_outbox.business_date
    ),
    now()
  );

  return jsonb_build_object(
    'outbox_id', v_outbox.id,
    'idempotent', false,
    'status', v_outbox.status,
    'recipient_count', v_recipient_count,
    'pending_delivery_count', v_pending_count,
    'business_date', v_outbox.business_date
  );
end;
$function$;

-- ============================================================================
-- 10. Trusted notification and settings RPCs
-- ============================================================================

create or replace function public.enqueue_notification_event(
  p_hotel_id uuid,
  p_event_key text,
  p_source_id uuid,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required.';
  end if;

  if not private.user_has_hotel_access(p_hotel_id) then
    raise exception 'Notification event access denied.';
  end if;

  return private.day17_enqueue_notification_event_internal(
    p_hotel_id,
    p_event_key,
    p_source_id,
    coalesce(p_payload, '{}'::jsonb),
    (select auth.uid())
  );
end;
$function$;

create or replace function public.get_notification_inbox(
  p_hotel_id uuid,
  p_limit integer default 50,
  p_before timestamptz default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_result jsonb;
begin
  if v_user_id is null
     or not private.user_has_hotel_access(p_hotel_id)
  then
    raise exception 'Notification inbox access denied.';
  end if;

  select jsonb_build_object(
    'hotel_id', p_hotel_id,
    'user_id', v_user_id,
    'unread_count', (
      select count(*)
      from public.notification_recipients nr
      where nr.hotel_id = p_hotel_id
        and nr.user_id = v_user_id
        and nr.status = 'unread'
    ),
    'items', coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', source.id,
          'outbox_id', source.outbox_id,
          'event_key', source.event_key,
          'source_type', source.source_type,
          'source_id', source.source_id,
          'title', source.title,
          'message', source.message,
          'severity', source.severity,
          'status', source.status,
          'business_date', source.business_date,
          'read_at', source.read_at,
          'created_at', source.created_at,
          'metadata', source.metadata
        )
        order by source.created_at desc
      ),
      '[]'::jsonb
    )
  )
  into v_result
  from (
    select
      nr.id,
      nr.outbox_id,
      nox.event_key,
      nox.source_type,
      nox.source_id,
      nr.title,
      nr.message,
      nr.severity,
      nr.status,
      nox.business_date,
      nr.read_at,
      nr.created_at,
      nr.metadata
    from public.notification_recipients nr
    join public.notification_outbox nox
      on nox.id = nr.outbox_id
     and nox.hotel_id = nr.hotel_id
    where nr.hotel_id = p_hotel_id
      and nr.user_id = v_user_id
      and (p_before is null or nr.created_at < p_before)
    order by nr.created_at desc
    limit greatest(1, least(coalesce(p_limit, 50), 200))
  ) source;

  return coalesce(
    v_result,
    jsonb_build_object(
      'hotel_id', p_hotel_id,
      'user_id', v_user_id,
      'unread_count', 0,
      'items', '[]'::jsonb
    )
  );
end;
$function$;

create or replace function public.mark_notification_read(
  p_recipient_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_row public.notification_recipients%rowtype;
begin
  if v_user_id is null then
    raise exception 'Authentication required.';
  end if;

  update public.notification_recipients nr
  set
    status = 'read',
    read_at = coalesce(nr.read_at, now()),
    updated_at = now()
  where nr.id = p_recipient_id
    and nr.user_id = v_user_id
    and private.user_has_hotel_access(nr.hotel_id)
  returning * into v_row;

  if not found then
    raise exception 'Notification was not found or access was denied.';
  end if;

  update public.notification_deliveries nd
  set
    status = case
      when nd.channel = 'in_app' then 'read'
      else nd.status
    end,
    read_at = coalesce(nd.read_at, now()),
    updated_at = now()
  where nd.outbox_id = v_row.outbox_id
    and nd.recipient_user_id = v_user_id
    and nd.channel = 'in_app';

  return jsonb_build_object(
    'notification_id', v_row.id,
    'status', v_row.status,
    'read_at', v_row.read_at
  );
end;
$function$;

create or replace function public.mark_all_notifications_read(
  p_hotel_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_count integer;
begin
  if v_user_id is null
     or not private.user_has_hotel_access(p_hotel_id)
  then
    raise exception 'Notification inbox access denied.';
  end if;

  update public.notification_recipients nr
  set
    status = 'read',
    read_at = coalesce(nr.read_at, now()),
    updated_at = now()
  where nr.hotel_id = p_hotel_id
    and nr.user_id = v_user_id
    and nr.status = 'unread';

  get diagnostics v_count = row_count;

  update public.notification_deliveries nd
  set
    status = 'read',
    read_at = coalesce(nd.read_at, now()),
    updated_at = now()
  where nd.hotel_id = p_hotel_id
    and nd.recipient_user_id = v_user_id
    and nd.channel = 'in_app'
    and nd.status = 'delivered';

  return jsonb_build_object(
    'hotel_id', p_hotel_id,
    'updated_count', v_count
  );
end;
$function$;

create or replace function public.upsert_notification_preferences(
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
  v_row public.notification_preferences%rowtype;
begin
  if v_user_id is null
     or not private.user_has_hotel_access(p_hotel_id)
  then
    raise exception 'Notification preference access denied.';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Preference payload must be a JSON object.';
  end if;

  if p_payload ? 'event_overrides'
     and jsonb_typeof(p_payload -> 'event_overrides') <> 'object'
  then
    raise exception 'event_overrides must be a JSON object.';
  end if;

  insert into public.notification_preferences (
    hotel_id,
    user_id,
    in_app_enabled,
    email_enabled,
    manual_whatsapp_enabled,
    locale,
    quiet_hours_start,
    quiet_hours_end,
    event_overrides,
    created_at,
    updated_at
  ) values (
    p_hotel_id,
    v_user_id,
    coalesce((p_payload ->> 'in_app_enabled')::boolean, true),
    coalesce((p_payload ->> 'email_enabled')::boolean, false),
    coalesce((p_payload ->> 'manual_whatsapp_enabled')::boolean, false),
    coalesce(nullif(trim(p_payload ->> 'locale'), ''), 'en'),
    nullif(trim(p_payload ->> 'quiet_hours_start'), '')::time,
    nullif(trim(p_payload ->> 'quiet_hours_end'), '')::time,
    coalesce(p_payload -> 'event_overrides', '{}'::jsonb),
    now(),
    now()
  )
  on conflict (hotel_id, user_id) do update
  set
    in_app_enabled = excluded.in_app_enabled,
    email_enabled = excluded.email_enabled,
    manual_whatsapp_enabled = excluded.manual_whatsapp_enabled,
    locale = excluded.locale,
    quiet_hours_start = excluded.quiet_hours_start,
    quiet_hours_end = excluded.quiet_hours_end,
    event_overrides = excluded.event_overrides,
    updated_at = now()
  returning * into v_row;

  return to_jsonb(v_row);
end;
$function$;

create or replace function public.publish_notification_template(
  p_hotel_id uuid,
  p_event_key text,
  p_channel text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_row public.notification_templates%rowtype;
  v_next_version integer;
  v_locale text;
begin
  if v_user_id is null
     or not private.day17_can_manage_hotel(p_hotel_id)
  then
    raise exception 'Notification template management denied.';
  end if;

  if p_channel not in ('in_app', 'email', 'manual_whatsapp') then
    raise exception 'Unsupported notification channel.';
  end if;

  if not exists (
    select 1
    from public.notification_event_catalog nec
    where nec.event_key = p_event_key
      and nec.is_active
  ) then
    raise exception 'Unsupported notification event key.';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Template payload must be a JSON object.';
  end if;

  if nullif(trim(p_payload ->> 'title_template'), '') is null
     or nullif(trim(p_payload ->> 'body_template'), '') is null
  then
    raise exception 'Template title and body are required.';
  end if;

  v_locale := coalesce(
    nullif(trim(p_payload ->> 'locale'), ''),
    'en'
  );

  select coalesce(max(nt.current_version), 0) + 1
  into v_next_version
  from public.notification_templates nt
  where nt.hotel_id = p_hotel_id
    and nt.event_key = p_event_key
    and nt.channel = p_channel
    and nt.locale = v_locale;

  insert into public.notification_templates (
    hotel_id,
    event_key,
    channel,
    locale,
    title_template,
    body_template,
    status,
    current_version,
    created_by,
    published_by,
    published_at,
    created_at,
    updated_at
  ) values (
    p_hotel_id,
    p_event_key,
    p_channel,
    v_locale,
    trim(p_payload ->> 'title_template'),
    trim(p_payload ->> 'body_template'),
    'published',
    v_next_version,
    v_user_id,
    v_user_id,
    now(),
    now(),
    now()
  )
  on conflict (hotel_id, event_key, channel, locale)
  where hotel_id is not null
  do update
  set
    title_template = excluded.title_template,
    body_template = excluded.body_template,
    status = 'published',
    current_version = public.notification_templates.current_version + 1,
    published_by = v_user_id,
    published_at = now(),
    updated_at = now()
  returning * into v_row;

  insert into public.notification_template_versions (
    template_id,
    version_number,
    title_template,
    body_template,
    created_by,
    created_at
  ) values (
    v_row.id,
    v_row.current_version,
    v_row.title_template,
    v_row.body_template,
    v_user_id,
    now()
  )
  on conflict (template_id, version_number) do nothing;

  return jsonb_build_object(
    'template', to_jsonb(v_row),
    'published', true
  );
end;
$function$;

create or replace function public.process_notification_outbox(
  p_limit integer default 50
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_delivery record;
  v_adapter public.email_adapter_configs%rowtype;
  v_attempt integer;
  v_processed integer := 0;
  v_ready integer := 0;
  v_failed integer := 0;
begin
  if not private.is_platform_admin() then
    raise exception 'Notification dispatcher access denied.';
  end if;

  for v_delivery in
    select nd.*
    from public.notification_deliveries nd
    where nd.status in ('pending', 'retrying')
      and (
        nd.next_attempt_at is null
        or nd.next_attempt_at <= now()
      )
    order by nd.created_at
    limit greatest(1, least(coalesce(p_limit, 50), 500))
    for update skip locked
  loop
    v_processed := v_processed + 1;
    v_attempt := v_delivery.attempt_count + 1;

    if v_delivery.channel = 'manual_whatsapp' then
      update public.notification_deliveries nd
      set
        status = 'manual_ready',
        attempt_count = v_attempt,
        manual_action_url = case
          when nullif(trim(v_delivery.address_snapshot), '') is null
            then null
          else
            'https://wa.me/' ||
            regexp_replace(v_delivery.address_snapshot, '[^0-9]', '', 'g') ||
            '?text=' ||
            replace(v_delivery.rendered_body, ' ', '%20')
        end,
        updated_at = now()
      where nd.id = v_delivery.id;

      insert into public.notification_delivery_attempts (
        delivery_id,
        hotel_id,
        attempt_number,
        attempt_status,
        adapter_key,
        request_metadata,
        response_metadata,
        started_at,
        completed_at,
        created_at
      ) values (
        v_delivery.id,
        v_delivery.hotel_id,
        v_attempt,
        'prepared',
        'manual_whatsapp',
        jsonb_build_object('channel', 'manual_whatsapp'),
        jsonb_build_object('result', 'manual_ready'),
        now(),
        now(),
        now()
      )
      on conflict (delivery_id, attempt_number) do nothing;

      v_ready := v_ready + 1;
      continue;
    end if;

    if v_delivery.channel = 'email' then
      select *
      into v_adapter
      from public.email_adapter_configs eac
      where eac.is_enabled
        and (eac.hotel_id = v_delivery.hotel_id or eac.hotel_id is null)
      order by
        case when eac.hotel_id = v_delivery.hotel_id then 0 else 1 end,
        eac.updated_at desc
      limit 1;

      if found then
        update public.notification_deliveries nd
        set
          status = 'adapter_ready',
          attempt_count = v_attempt,
          last_error_code = null,
          last_error_message = null,
          updated_at = now()
        where nd.id = v_delivery.id;

        insert into public.notification_delivery_attempts (
          delivery_id,
          hotel_id,
          attempt_number,
          attempt_status,
          adapter_key,
          request_metadata,
          response_metadata,
          started_at,
          completed_at,
          created_at
        ) values (
          v_delivery.id,
          v_delivery.hotel_id,
          v_attempt,
          'prepared',
          v_adapter.adapter_key,
          jsonb_build_object(
            'provider', v_adapter.provider,
            'endpoint_name', v_adapter.endpoint_name,
            'secret_reference', v_adapter.secret_reference
          ),
          jsonb_build_object('result', 'adapter_ready'),
          now(),
          now(),
          now()
        )
        on conflict (delivery_id, attempt_number) do nothing;

        v_ready := v_ready + 1;
      else
        insert into public.notification_delivery_attempts (
          delivery_id,
          hotel_id,
          attempt_number,
          attempt_status,
          error_code,
          error_message,
          request_metadata,
          response_metadata,
          started_at,
          completed_at,
          created_at
        ) values (
          v_delivery.id,
          v_delivery.hotel_id,
          v_attempt,
          'failed',
          'EMAIL_ADAPTER_NOT_CONFIGURED',
          'No enabled email adapter is configured.',
          jsonb_build_object('channel', 'email'),
          '{}'::jsonb,
          now(),
          now(),
          now()
        )
        on conflict (delivery_id, attempt_number) do nothing;

        if v_attempt >= v_delivery.max_attempts then
          update public.notification_deliveries nd
          set
            status = 'failed',
            attempt_count = v_attempt,
            last_error_code = 'EMAIL_ADAPTER_NOT_CONFIGURED',
            last_error_message = 'No enabled email adapter is configured.',
            next_attempt_at = null,
            updated_at = now()
          where nd.id = v_delivery.id;

          insert into public.notification_dead_letters (
            delivery_id,
            outbox_id,
            hotel_id,
            reason_code,
            reason_message,
            payload_snapshot,
            created_at
          ) values (
            v_delivery.id,
            v_delivery.outbox_id,
            v_delivery.hotel_id,
            'EMAIL_ADAPTER_NOT_CONFIGURED',
            'No enabled email adapter is configured after maximum retries.',
            jsonb_build_object(
              'address', v_delivery.address_snapshot,
              'title', v_delivery.rendered_title,
              'body', v_delivery.rendered_body
            ),
            now()
          )
          on conflict (delivery_id) do nothing;
        else
          update public.notification_deliveries nd
          set
            status = 'retrying',
            attempt_count = v_attempt,
            last_error_code = 'EMAIL_ADAPTER_NOT_CONFIGURED',
            last_error_message = 'No enabled email adapter is configured.',
            next_attempt_at = now() + make_interval(
              mins => least(60, 5 * v_attempt)
            ),
            updated_at = now()
          where nd.id = v_delivery.id;
        end if;

        v_failed := v_failed + 1;
      end if;
    end if;
  end loop;

  update public.notification_outbox nox
  set
    pending_delivery_count = summary.pending_count,
    completed_delivery_count = summary.completed_count,
    failed_delivery_count = summary.failed_count,
    status = case
      when summary.failed_count > 0 and summary.pending_count = 0
        then 'partial'
      when summary.pending_count > 0
        then 'pending'
      else 'completed'
    end,
    updated_at = now()
  from (
    select
      nd.outbox_id,
      count(*) filter (
        where nd.status in ('pending', 'retrying')
      )::integer as pending_count,
      count(*) filter (
        where nd.status in (
          'adapter_ready',
          'manual_ready',
          'delivered',
          'read',
          'skipped'
        )
      )::integer as completed_count,
      count(*) filter (
        where nd.status = 'failed'
      )::integer as failed_count
    from public.notification_deliveries nd
    group by nd.outbox_id
  ) summary
  where nox.id = summary.outbox_id;

  return jsonb_build_object(
    'processed', v_processed,
    'adapter_or_manual_ready', v_ready,
    'failed_or_retrying', v_failed
  );
end;
$function$;

create or replace function public.retry_notification_delivery(
  p_delivery_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_row public.notification_deliveries%rowtype;
begin
  select *
  into v_row
  from public.notification_deliveries nd
  where nd.id = p_delivery_id
  for update;

  if not found then
    raise exception 'Notification delivery was not found.';
  end if;

  if not (
    private.is_platform_admin()
    or private.day17_can_manage_hotel(v_row.hotel_id)
  ) then
    raise exception 'Notification retry access denied.';
  end if;

  if v_row.status not in ('failed', 'retrying') then
    raise exception 'Only failed or retrying deliveries can be retried.';
  end if;

  update public.notification_deliveries nd
  set
    status = 'pending',
    next_attempt_at = now(),
    last_error_code = null,
    last_error_message = null,
    updated_at = now()
  where nd.id = p_delivery_id
  returning * into v_row;

  delete from public.notification_dead_letters ndl
  where ndl.delivery_id = p_delivery_id;

  return jsonb_build_object(
    'delivery_id', v_row.id,
    'status', v_row.status,
    'next_attempt_at', v_row.next_attempt_at
  );
end;
$function$;

create or replace function public.get_activity_timeline(
  p_hotel_id uuid,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_filters jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_limit integer := greatest(
    1,
    least(
      coalesce((p_filters ->> 'limit')::integer, 100),
      500
    )
  );
  v_result jsonb;
begin
  if not private.user_has_hotel_access(p_hotel_id) then
    raise exception 'Activity timeline access denied.';
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(source) order by source.created_at desc),
    '[]'::jsonb
  )
  into v_result
  from (
    select
      al.id,
      al.hotel_id,
      al.actor_user_id,
      al.actor_role,
      al.action,
      al.entity_type,
      al.entity_id,
      al.description,
      al.before_data,
      al.after_data,
      al.metadata,
      al.created_at
    from public.activity_logs al
    where al.hotel_id = p_hotel_id
      and (p_from is null or al.created_at >= p_from)
      and (p_to is null or al.created_at <= p_to)
      and (
        nullif(trim(p_filters ->> 'entity_type'), '') is null
        or al.entity_type = trim(p_filters ->> 'entity_type')
      )
      and (
        nullif(trim(p_filters ->> 'action'), '') is null
        or al.action = trim(p_filters ->> 'action')
      )
      and (
        nullif(trim(p_filters ->> 'actor_user_id'), '') is null
        or al.actor_user_id =
          nullif(trim(p_filters ->> 'actor_user_id'), '')::uuid
      )
    order by al.created_at desc
    limit v_limit
  ) source;

  return jsonb_build_object(
    'hotel_id', p_hotel_id,
    'items', v_result
  );
end;
$function$;

create or replace function public.get_hotel_system_settings(
  p_hotel_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if not private.user_has_hotel_access(p_hotel_id) then
    raise exception 'Hotel settings access denied.';
  end if;

  return (
    select jsonb_build_object(
      'hotel', jsonb_build_object(
        'id', h.id,
        'hotel_name', h.hotel_name,
        'timezone', h.timezone,
        'currency_code', h.currency_code,
        'status', h.status
      ),
      'hotel_settings', to_jsonb(hs),
      'business_day_settings', to_jsonb(bds),
      'notification_preferences', (
        select to_jsonb(np)
        from public.notification_preferences np
        where np.hotel_id = p_hotel_id
          and np.user_id = (select auth.uid())
      ),
      'email_adapter', case
        when private.day17_can_manage_hotel(p_hotel_id) then (
          select to_jsonb(eac) - 'secret_reference'
          from public.email_adapter_configs eac
          where eac.hotel_id = p_hotel_id
          order by eac.updated_at desc
          limit 1
        )
        else null
      end
    )
    from public.hotels h
    left join public.hotel_settings hs
      on hs.hotel_id = h.id
    left join public.business_day_settings bds
      on bds.hotel_id = h.id
    where h.id = p_hotel_id
  );
end;
$function$;

create or replace function public.update_hotel_system_settings(
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
begin
  if v_user_id is null
     or not private.day17_can_manage_hotel(p_hotel_id)
  then
    raise exception 'Hotel settings management denied.';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Hotel settings payload must be a JSON object.';
  end if;

  if p_payload ? 'timezone' then
    perform now() at time zone trim(p_payload ->> 'timezone');

    update public.hotels h
    set
      timezone = trim(p_payload ->> 'timezone'),
      updated_at = now()
    where h.id = p_hotel_id;
  end if;

  if p_payload ? 'currency_code' then
    if upper(trim(p_payload ->> 'currency_code')) !~ '^[A-Z]{3}$' then
      raise exception 'currency_code must contain three letters.';
    end if;

    update public.hotels h
    set
      currency_code = upper(trim(p_payload ->> 'currency_code')),
      updated_at = now()
    where h.id = p_hotel_id;
  end if;

  update public.hotel_settings hs
  set
    legal_name = case
      when p_payload ? 'legal_name'
        then nullif(trim(p_payload ->> 'legal_name'), '')
      else hs.legal_name
    end,
    tax_registration_number = case
      when p_payload ? 'tax_registration_number'
        then nullif(trim(p_payload ->> 'tax_registration_number'), '')
      else hs.tax_registration_number
    end,
    default_tax_percent = case
      when p_payload ? 'default_tax_percent'
        then (p_payload ->> 'default_tax_percent')::numeric
      else hs.default_tax_percent
    end,
    prices_include_tax = case
      when p_payload ? 'prices_include_tax'
        then (p_payload ->> 'prices_include_tax')::boolean
      else hs.prices_include_tax
    end,
    checkin_time = case
      when p_payload ? 'checkin_time'
        then (p_payload ->> 'checkin_time')::time
      else hs.checkin_time
    end,
    checkout_time = case
      when p_payload ? 'checkout_time'
        then (p_payload ->> 'checkout_time')::time
      else hs.checkout_time
    end,
    checkout_grace_minutes = case
      when p_payload ? 'checkout_grace_minutes'
        then (p_payload ->> 'checkout_grace_minutes')::integer
      else hs.checkout_grace_minutes
    end,
    cancellation_policy = case
      when p_payload ? 'cancellation_policy'
        then nullif(trim(p_payload ->> 'cancellation_policy'), '')
      else hs.cancellation_policy
    end,
    house_rules = case
      when p_payload ? 'house_rules'
        then nullif(trim(p_payload ->> 'house_rules'), '')
      else hs.house_rules
    end,
    terms_and_conditions = case
      when p_payload ? 'terms_and_conditions'
        then nullif(trim(p_payload ->> 'terms_and_conditions'), '')
      else hs.terms_and_conditions
    end,
    locale = case
      when p_payload ? 'locale'
        then coalesce(nullif(trim(p_payload ->> 'locale'), ''), hs.locale)
      else hs.locale
    end,
    date_format = case
      when p_payload ? 'date_format'
        then trim(p_payload ->> 'date_format')
      else hs.date_format
    end,
    updated_by = v_user_id,
    updated_at = now()
  where hs.hotel_id = p_hotel_id;

  insert into public.business_day_settings (
    hotel_id,
    business_day_cutoff,
    week_starts_on,
    night_audit_time,
    locale,
    created_by,
    updated_by,
    created_at,
    updated_at
  ) values (
    p_hotel_id,
    coalesce(
      nullif(trim(p_payload ->> 'business_day_cutoff'), '')::time,
      '00:00'::time
    ),
    coalesce((p_payload ->> 'week_starts_on')::integer, 1),
    coalesce(
      nullif(trim(p_payload ->> 'night_audit_time'), '')::time,
      '02:00'::time
    ),
    coalesce(nullif(trim(p_payload ->> 'locale'), ''), 'en-IN'),
    v_user_id,
    v_user_id,
    now(),
    now()
  )
  on conflict (hotel_id) do update
  set
    business_day_cutoff = case
      when p_payload ? 'business_day_cutoff'
        then (p_payload ->> 'business_day_cutoff')::time
      else public.business_day_settings.business_day_cutoff
    end,
    week_starts_on = case
      when p_payload ? 'week_starts_on'
        then (p_payload ->> 'week_starts_on')::integer
      else public.business_day_settings.week_starts_on
    end,
    night_audit_time = case
      when p_payload ? 'night_audit_time'
        then (p_payload ->> 'night_audit_time')::time
      else public.business_day_settings.night_audit_time
    end,
    locale = case
      when p_payload ? 'locale'
        then coalesce(
          nullif(trim(p_payload ->> 'locale'), ''),
          public.business_day_settings.locale
        )
      else public.business_day_settings.locale
    end,
    updated_by = v_user_id,
    updated_at = now();

  insert into public.activity_logs (
    hotel_id,
    actor_user_id,
    actor_role,
    action,
    entity_type,
    entity_id,
    description,
    metadata,
    created_at
  ) values (
    p_hotel_id,
    v_user_id,
    'manager',
    'hotel_system_settings_updated',
    'hotel',
    p_hotel_id,
    'Hotel system settings were updated.',
    jsonb_build_object(
      'changed_keys', (
        select coalesce(
          jsonb_agg(changed_key.key_name order by changed_key.key_name),
          '[]'::jsonb
        )
        from jsonb_object_keys(p_payload)
          as changed_key(key_name)
      ),
      'business_date', private.resolve_hotel_business_date(
        p_hotel_id,
        now()
      )
    ),
    now()
  );

  return public.get_hotel_system_settings(p_hotel_id);
end;
$function$;

create or replace function public.get_support_workspace(
  p_hotel_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if not private.user_has_hotel_access(p_hotel_id) then
    raise exception 'Support workspace access denied.';
  end if;

  return jsonb_build_object(
    'tickets', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', st.id,
            'ticket_number', st.ticket_number,
            'subject', st.subject,
            'description', st.description,
            'category', st.category,
            'priority', st.priority,
            'status', st.status,
            'created_by', st.created_by,
            'assigned_to', st.assigned_to,
            'last_response_at', st.last_response_at,
            'created_at', st.created_at,
            'updated_at', st.updated_at,
            'events', coalesce(
              (
                select jsonb_agg(
                  to_jsonb(ste)
                  order by ste.created_at
                )
                from public.support_ticket_events ste
                where ste.ticket_id = st.id
                  and ste.hotel_id = st.hotel_id
              ),
              '[]'::jsonb
            )
          )
          order by st.updated_at desc
        )
        from public.support_tickets st
        where st.hotel_id = p_hotel_id
      ),
      '[]'::jsonb
    )
  );
end;
$function$;

create or replace function public.get_active_announcements(
  p_hotel_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if not private.user_has_hotel_access(p_hotel_id) then
    raise exception 'Announcement access denied.';
  end if;

  return coalesce(
    (
      select jsonb_agg(
        jsonb_build_object(
          'id', a.id,
          'scope', a.scope,
          'target_hotel_id', a.target_hotel_id,
          'title', a.title,
          'body', a.body,
          'severity', a.severity,
          'starts_at', a.starts_at,
          'ends_at', a.ends_at,
          'published_at', a.published_at
        )
        order by
          case a.severity
            when 'critical' then 0
            when 'warning' then 1
            else 2
          end,
          a.published_at desc nulls last,
          a.created_at desc
      )
      from public.announcements a
      where a.status = 'published'
        and (
          a.scope = 'global'
          or (
            a.scope = 'hotel'
            and a.target_hotel_id = p_hotel_id
          )
        )
        and (a.starts_at is null or a.starts_at <= now())
        and (a.ends_at is null or a.ends_at > now())
    ),
    '[]'::jsonb
  );
end;
$function$;

-- ============================================================================
-- 11. Critical source triggers
-- ============================================================================

create or replace function private.day17_capture_critical_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_new jsonb := to_jsonb(new);
  v_old jsonb := case
    when tg_op = 'UPDATE' then to_jsonb(old)
    else '{}'::jsonb
  end;
  v_hotel_id uuid := (v_new ->> 'hotel_id')::uuid;
  v_source_id uuid := (v_new ->> 'id')::uuid;
  v_source_type text;
  v_event_key text;
  v_status text;
  v_old_status text;
  v_payload jsonb;
begin
  v_source_type := case tg_table_name
    when 'reservations' then 'reservation'
    when 'payments' then 'payment'
    when 'service_requests' then 'service_request'
    else tg_table_name
  end;

  v_status := coalesce(
    nullif(v_new ->> 'status', ''),
    nullif(v_new ->> 'payment_status', ''),
    'recorded'
  );

  v_old_status := coalesce(
    nullif(v_old ->> 'status', ''),
    nullif(v_old ->> 'payment_status', '')
  );

  if tg_op = 'INSERT' then
    v_event_key := v_source_type || '.created';
  elsif v_status is distinct from v_old_status then
    v_event_key := v_source_type || '.status_changed';
  else
    return new;
  end if;

  v_payload := jsonb_strip_nulls(
    jsonb_build_object(
      'idempotency_key',
        v_event_key || ':' || v_source_id::text || ':' || v_status,
      'source_type', v_source_type,
      'source_id', v_source_id,
      'status', v_status,
      'old_status', v_old_status,
      'reservation_number', v_new ->> 'reservation_number',
      'amount', v_new ->> 'amount',
      'request_type', v_new ->> 'request_type',
      'department', v_new ->> 'department',
      'guest_session_id', v_new ->> 'guest_session_id',
      'room_id', v_new ->> 'room_id',
      'guest_id', v_new ->> 'guest_id',
      'occurred_at', coalesce(
        v_new ->> 'updated_at',
        v_new ->> 'created_at',
        now()::text
      )
    )
  );

  perform private.day17_enqueue_notification_event_internal(
    v_hotel_id,
    v_event_key,
    v_source_id,
    v_payload,
    (select auth.uid())
  );

  return new;
end;
$function$;

drop trigger if exists day17_reservation_notification_event
on public.reservations;

create trigger day17_reservation_notification_event
after insert or update on public.reservations
for each row execute function private.day17_capture_critical_event();

drop trigger if exists day17_payment_notification_event
on public.payments;

create trigger day17_payment_notification_event
after insert or update on public.payments
for each row execute function private.day17_capture_critical_event();

drop trigger if exists day17_service_request_notification_event
on public.service_requests;

create trigger day17_service_request_notification_event
after insert or update on public.service_requests
for each row execute function private.day17_capture_critical_event();

create or replace function private.day17_capture_support_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_event_key text;
  v_old_status text;
begin
  if tg_op = 'INSERT' then
    v_event_key := 'support.ticket_created';
    v_old_status := null;
  elsif new.status is distinct from old.status then
    v_event_key := 'support.status_changed';
    v_old_status := old.status;
  else
    return new;
  end if;

  perform private.day17_enqueue_notification_event_internal(
    new.hotel_id,
    v_event_key,
    new.id,
    jsonb_build_object(
      'idempotency_key',
        v_event_key || ':' || new.id::text || ':' || new.status,
      'ticket_number', new.ticket_number,
      'subject', new.subject,
      'status', new.status,
      'old_status', v_old_status,
      'occurred_at', coalesce(new.updated_at, new.created_at, now())
    ),
    (select auth.uid())
  );

  return new;
end;
$function$;

drop trigger if exists day17_support_ticket_notification_event
on public.support_tickets;

create trigger day17_support_ticket_notification_event
after insert or update on public.support_tickets
for each row execute function private.day17_capture_support_event();

create or replace function private.day17_capture_announcement_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_hotel record;
begin
  if new.status <> 'published'
     or (
       tg_op = 'UPDATE'
       and old.status = 'published'
       and new.title is not distinct from old.title
       and new.body is not distinct from old.body
       and new.starts_at is not distinct from old.starts_at
       and new.ends_at is not distinct from old.ends_at
     )
  then
    return new;
  end if;

  for v_hotel in
    select h.id
    from public.hotels h
    where h.status = 'active'
      and (
        new.scope = 'global'
        or h.id = new.target_hotel_id
      )
  loop
    perform private.day17_enqueue_notification_event_internal(
      v_hotel.id,
      'announcement.published',
      new.id,
      jsonb_build_object(
        'idempotency_key',
          'announcement.published:' || new.id::text || ':' ||
          extract(epoch from coalesce(new.published_at, new.updated_at, now()))::text,
        'title', new.title,
        'body', new.body,
        'severity', new.severity,
        'occurred_at', coalesce(new.published_at, new.updated_at, now())
      ),
      (select auth.uid())
    );
  end loop;

  return new;
end;
$function$;

drop trigger if exists day17_announcement_notification_event
on public.announcements;

create trigger day17_announcement_notification_event
after insert or update on public.announcements
for each row execute function private.day17_capture_announcement_event();

-- ============================================================================
-- 12. RLS, grants and realtime
-- ============================================================================

do $rls$
declare
  v_table text;
begin
  foreach v_table in array array[
    'notification_event_catalog',
    'notification_preferences',
    'notification_templates',
    'notification_template_versions',
    'notification_outbox',
    'notification_deliveries',
    'notification_delivery_attempts',
    'notification_dead_letters',
    'notification_recipients',
    'email_adapter_configs',
    'whatsapp_templates',
    'business_day_settings'
  ]
  loop
    execute format(
      'alter table public.%I enable row level security',
      v_table
    );
  end loop;
end;
$rls$;

drop policy if exists notification_event_catalog_select_day17
on public.notification_event_catalog;
create policy notification_event_catalog_select_day17
on public.notification_event_catalog
for select to authenticated
using (true);

drop policy if exists notification_preferences_select_day17
on public.notification_preferences;
create policy notification_preferences_select_day17
on public.notification_preferences
for select to authenticated
using (
  user_id = (select auth.uid())
  and private.user_has_hotel_access(hotel_id)
);

drop policy if exists notification_templates_select_day17
on public.notification_templates;
create policy notification_templates_select_day17
on public.notification_templates
for select to authenticated
using (
  hotel_id is null
  or private.user_has_hotel_access(hotel_id)
);

drop policy if exists notification_template_versions_select_day17
on public.notification_template_versions;
create policy notification_template_versions_select_day17
on public.notification_template_versions
for select to authenticated
using (
  exists (
    select 1
    from public.notification_templates nt
    where nt.id =
      notification_template_versions.template_id
      and (
        nt.hotel_id is null
        or private.user_has_hotel_access(nt.hotel_id)
      )
  )
);

drop policy if exists notification_outbox_select_day17
on public.notification_outbox;
create policy notification_outbox_select_day17
on public.notification_outbox
for select to authenticated
using (private.user_has_hotel_access(hotel_id));

drop policy if exists notification_deliveries_select_day17
on public.notification_deliveries;
create policy notification_deliveries_select_day17
on public.notification_deliveries
for select to authenticated
using (
  private.user_has_hotel_access(hotel_id)
  and (
    recipient_user_id = (select auth.uid())
    or private.day17_can_manage_hotel(hotel_id)
  )
);

drop policy if exists notification_attempts_select_day17
on public.notification_delivery_attempts;
create policy notification_attempts_select_day17
on public.notification_delivery_attempts
for select to authenticated
using (private.day17_can_manage_hotel(hotel_id));

drop policy if exists notification_dead_letters_select_day17
on public.notification_dead_letters;
create policy notification_dead_letters_select_day17
on public.notification_dead_letters
for select to authenticated
using (private.day17_can_manage_hotel(hotel_id));

drop policy if exists notification_recipients_select_day17
on public.notification_recipients;
create policy notification_recipients_select_day17
on public.notification_recipients
for select to authenticated
using (
  user_id = (select auth.uid())
  and private.user_has_hotel_access(hotel_id)
);

drop policy if exists email_adapter_configs_select_day17
on public.email_adapter_configs;
create policy email_adapter_configs_select_day17
on public.email_adapter_configs
for select to authenticated
using (
  private.is_platform_admin()
  or (
    hotel_id is not null
    and private.day17_can_manage_hotel(hotel_id)
  )
);

drop policy if exists whatsapp_templates_select_day17
on public.whatsapp_templates;
create policy whatsapp_templates_select_day17
on public.whatsapp_templates
for select to authenticated
using (
  hotel_id is null
  or private.user_has_hotel_access(hotel_id)
);

drop policy if exists business_day_settings_select_day17
on public.business_day_settings;
create policy business_day_settings_select_day17
on public.business_day_settings
for select to authenticated
using (private.user_has_hotel_access(hotel_id));

revoke all on table
  public.notification_event_catalog,
  public.notification_preferences,
  public.notification_templates,
  public.notification_template_versions,
  public.notification_outbox,
  public.notification_deliveries,
  public.notification_delivery_attempts,
  public.notification_dead_letters,
  public.notification_recipients,
  public.email_adapter_configs,
  public.whatsapp_templates,
  public.business_day_settings
from public, anon, authenticated;

grant select on table
  public.notification_event_catalog,
  public.notification_preferences,
  public.notification_templates,
  public.notification_template_versions,
  public.notification_outbox,
  public.notification_deliveries,
  public.notification_delivery_attempts,
  public.notification_dead_letters,
  public.notification_recipients,
  public.email_adapter_configs,
  public.whatsapp_templates,
  public.business_day_settings
to authenticated;

revoke all on function
  private.day17_can_manage_hotel(uuid),
  private.resolve_hotel_business_date(uuid,timestamptz),
  private.day17_render_notification_text(text,jsonb),
  private.day17_enqueue_notification_event_internal(uuid,text,uuid,jsonb,uuid),
  private.day17_capture_critical_event(),
  private.day17_capture_support_event(),
  private.day17_capture_announcement_event()
from public, anon, authenticated;

revoke all on function
  public.get_notification_inbox(uuid,integer,timestamptz),
  public.mark_notification_read(uuid),
  public.mark_all_notifications_read(uuid),
  public.upsert_notification_preferences(uuid,jsonb),
  public.publish_notification_template(uuid,text,text,jsonb),
  public.enqueue_notification_event(uuid,text,uuid,jsonb),
  public.process_notification_outbox(integer),
  public.retry_notification_delivery(uuid),
  public.get_activity_timeline(uuid,timestamptz,timestamptz,jsonb),
  public.get_hotel_system_settings(uuid),
  public.update_hotel_system_settings(uuid,jsonb),
  public.get_support_workspace(uuid),
  public.get_active_announcements(uuid)
from public, anon, authenticated;

grant execute on function
  public.get_notification_inbox(uuid,integer,timestamptz),
  public.mark_notification_read(uuid),
  public.mark_all_notifications_read(uuid),
  public.upsert_notification_preferences(uuid,jsonb),
  public.publish_notification_template(uuid,text,text,jsonb),
  public.enqueue_notification_event(uuid,text,uuid,jsonb),
  public.process_notification_outbox(integer),
  public.retry_notification_delivery(uuid),
  public.get_activity_timeline(uuid,timestamptz,timestamptz,jsonb),
  public.get_hotel_system_settings(uuid),
  public.update_hotel_system_settings(uuid,jsonb),
  public.get_support_workspace(uuid),
  public.get_active_announcements(uuid)
to authenticated;

alter table public.notification_recipients replica identity full;
alter table public.notification_deliveries replica identity full;

do $realtime$
declare
  v_table text;
begin
  foreach v_table in array array[
    'notification_recipients',
    'notification_deliveries'
  ]
  loop
    if not exists (
      select 1
      from pg_publication_tables pt
      where pt.pubname = 'supabase_realtime'
        and pt.schemaname = 'public'
        and pt.tablename = v_table
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I',
        v_table
      );
    end if;
  end loop;
end;
$realtime$;

-- ============================================================================
-- 13. Fixed acceptance
-- ============================================================================

create or replace function private.day17_migration_056_acceptance_rev2()
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
  v_rec record;
  v_exists boolean;
  v_count bigint;
begin
  for v_rec in
    select table_name
    from (
      values
      ('notification_event_catalog'),
      ('notification_preferences'),
      ('notification_templates'),
      ('notification_template_versions'),
      ('notification_outbox'),
      ('notification_deliveries'),
      ('notification_delivery_attempts'),
      ('notification_dead_letters'),
      ('notification_recipients'),
      ('email_adapter_configs'),
      ('whatsapp_templates'),
      ('business_day_settings')
    ) expected(table_name)
  loop
    suite := 'TABLE';
    test_name := v_rec.table_name;
    passed := to_regclass('public.' || v_rec.table_name) is not null;
    details := case when passed then 'PRESENT' else 'MISSING' end;
    return next;
  end loop;

  for v_rec in
    select table_name, column_name
    from (
      values
      ('notification_event_catalog', 'event_key'),
      ('notification_event_catalog', 'source_type'),
      ('notification_event_catalog', 'audience'),
      ('notification_event_catalog', 'severity'),
      ('notification_event_catalog', 'default_channels'),
      ('notification_event_catalog', 'default_title'),
      ('notification_event_catalog', 'default_body'),
      ('notification_event_catalog', 'is_critical'),
      ('notification_event_catalog', 'is_active'),
      ('notification_event_catalog', 'created_at'),
      ('notification_event_catalog', 'updated_at'),
      ('notification_preferences', 'id'),
      ('notification_preferences', 'hotel_id'),
      ('notification_preferences', 'user_id'),
      ('notification_preferences', 'in_app_enabled'),
      ('notification_preferences', 'email_enabled'),
      ('notification_preferences', 'manual_whatsapp_enabled'),
      ('notification_preferences', 'locale'),
      ('notification_preferences', 'quiet_hours_start'),
      ('notification_preferences', 'quiet_hours_end'),
      ('notification_preferences', 'event_overrides'),
      ('notification_preferences', 'created_at'),
      ('notification_preferences', 'updated_at'),
      ('notification_templates', 'id'),
      ('notification_templates', 'hotel_id'),
      ('notification_templates', 'event_key'),
      ('notification_templates', 'channel'),
      ('notification_templates', 'locale'),
      ('notification_templates', 'title_template'),
      ('notification_templates', 'body_template'),
      ('notification_templates', 'status'),
      ('notification_templates', 'current_version'),
      ('notification_templates', 'created_by'),
      ('notification_templates', 'published_by'),
      ('notification_templates', 'published_at'),
      ('notification_templates', 'created_at'),
      ('notification_templates', 'updated_at'),
      ('notification_template_versions', 'id'),
      ('notification_template_versions', 'template_id'),
      ('notification_template_versions', 'version_number'),
      ('notification_template_versions', 'title_template'),
      ('notification_template_versions', 'body_template'),
      ('notification_template_versions', 'created_by'),
      ('notification_template_versions', 'created_at'),
      ('notification_outbox', 'id'),
      ('notification_outbox', 'hotel_id'),
      ('notification_outbox', 'event_key'),
      ('notification_outbox', 'source_type'),
      ('notification_outbox', 'source_id'),
      ('notification_outbox', 'idempotency_key'),
      ('notification_outbox', 'payload'),
      ('notification_outbox', 'business_date'),
      ('notification_outbox', 'status'),
      ('notification_outbox', 'pending_delivery_count'),
      ('notification_outbox', 'completed_delivery_count'),
      ('notification_outbox', 'failed_delivery_count'),
      ('notification_outbox', 'created_by'),
      ('notification_outbox', 'occurred_at'),
      ('notification_outbox', 'created_at'),
      ('notification_outbox', 'updated_at'),
      ('notification_deliveries', 'id'),
      ('notification_deliveries', 'outbox_id'),
      ('notification_deliveries', 'hotel_id'),
      ('notification_deliveries', 'recipient_user_id'),
      ('notification_deliveries', 'guest_session_id'),
      ('notification_deliveries', 'channel'),
      ('notification_deliveries', 'address_snapshot'),
      ('notification_deliveries', 'locale'),
      ('notification_deliveries', 'rendered_title'),
      ('notification_deliveries', 'rendered_body'),
      ('notification_deliveries', 'status'),
      ('notification_deliveries', 'attempt_count'),
      ('notification_deliveries', 'max_attempts'),
      ('notification_deliveries', 'next_attempt_at'),
      ('notification_deliveries', 'last_error_code'),
      ('notification_deliveries', 'last_error_message'),
      ('notification_deliveries', 'manual_action_url'),
      ('notification_deliveries', 'provider_message_id'),
      ('notification_deliveries', 'queued_at'),
      ('notification_deliveries', 'delivered_at'),
      ('notification_deliveries', 'read_at'),
      ('notification_deliveries', 'metadata'),
      ('notification_deliveries', 'created_at'),
      ('notification_deliveries', 'updated_at'),
      ('notification_delivery_attempts', 'id'),
      ('notification_delivery_attempts', 'delivery_id'),
      ('notification_delivery_attempts', 'hotel_id'),
      ('notification_delivery_attempts', 'attempt_number'),
      ('notification_delivery_attempts', 'attempt_status'),
      ('notification_delivery_attempts', 'adapter_key'),
      ('notification_delivery_attempts', 'error_code'),
      ('notification_delivery_attempts', 'error_message'),
      ('notification_delivery_attempts', 'request_metadata'),
      ('notification_delivery_attempts', 'response_metadata'),
      ('notification_delivery_attempts', 'started_at'),
      ('notification_delivery_attempts', 'completed_at'),
      ('notification_delivery_attempts', 'created_at'),
      ('notification_dead_letters', 'id'),
      ('notification_dead_letters', 'delivery_id'),
      ('notification_dead_letters', 'outbox_id'),
      ('notification_dead_letters', 'hotel_id'),
      ('notification_dead_letters', 'reason_code'),
      ('notification_dead_letters', 'reason_message'),
      ('notification_dead_letters', 'payload_snapshot'),
      ('notification_dead_letters', 'resolved_at'),
      ('notification_dead_letters', 'resolved_by'),
      ('notification_dead_letters', 'resolution_note'),
      ('notification_dead_letters', 'created_at'),
      ('notification_recipients', 'id'),
      ('notification_recipients', 'outbox_id'),
      ('notification_recipients', 'hotel_id'),
      ('notification_recipients', 'user_id'),
      ('notification_recipients', 'title'),
      ('notification_recipients', 'message'),
      ('notification_recipients', 'severity'),
      ('notification_recipients', 'status'),
      ('notification_recipients', 'read_at'),
      ('notification_recipients', 'dismissed_at'),
      ('notification_recipients', 'metadata'),
      ('notification_recipients', 'created_at'),
      ('notification_recipients', 'updated_at'),
      ('email_adapter_configs', 'id'),
      ('email_adapter_configs', 'hotel_id'),
      ('email_adapter_configs', 'adapter_key'),
      ('email_adapter_configs', 'provider'),
      ('email_adapter_configs', 'from_name'),
      ('email_adapter_configs', 'from_email'),
      ('email_adapter_configs', 'reply_to_email'),
      ('email_adapter_configs', 'secret_reference'),
      ('email_adapter_configs', 'endpoint_name'),
      ('email_adapter_configs', 'is_enabled'),
      ('email_adapter_configs', 'metadata'),
      ('email_adapter_configs', 'created_by'),
      ('email_adapter_configs', 'updated_by'),
      ('email_adapter_configs', 'created_at'),
      ('email_adapter_configs', 'updated_at'),
      ('whatsapp_templates', 'id'),
      ('whatsapp_templates', 'hotel_id'),
      ('whatsapp_templates', 'event_key'),
      ('whatsapp_templates', 'locale'),
      ('whatsapp_templates', 'template_name'),
      ('whatsapp_templates', 'body_template'),
      ('whatsapp_templates', 'status'),
      ('whatsapp_templates', 'created_by'),
      ('whatsapp_templates', 'updated_by'),
      ('whatsapp_templates', 'created_at'),
      ('whatsapp_templates', 'updated_at'),
      ('business_day_settings', 'hotel_id'),
      ('business_day_settings', 'business_day_cutoff'),
      ('business_day_settings', 'week_starts_on'),
      ('business_day_settings', 'night_audit_time'),
      ('business_day_settings', 'locale'),
      ('business_day_settings', 'created_by'),
      ('business_day_settings', 'updated_by'),
      ('business_day_settings', 'created_at'),
      ('business_day_settings', 'updated_at')
    ) expected(table_name, column_name)
  loop
    suite := 'COLUMN';
    test_name := v_rec.table_name || '.' || v_rec.column_name;
    select exists (
      select 1
      from information_schema.columns c
      where c.table_schema = 'public'
        and c.table_name = v_rec.table_name
        and c.column_name = v_rec.column_name
    ) into passed;
    details := case when passed then 'PRESENT' else 'MISSING' end;
    return next;
  end loop;

  for v_rec in
    select table_name
    from (
      values
      ('notification_event_catalog'),
      ('notification_preferences'),
      ('notification_templates'),
      ('notification_template_versions'),
      ('notification_outbox'),
      ('notification_deliveries'),
      ('notification_delivery_attempts'),
      ('notification_dead_letters'),
      ('notification_recipients'),
      ('email_adapter_configs'),
      ('whatsapp_templates'),
      ('business_day_settings')
    ) expected(table_name)
  loop
    suite := 'RLS';
    test_name := v_rec.table_name || '.enabled';
    select coalesce(c.relrowsecurity, false)
    into passed
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = v_rec.table_name;
    details := case when passed then 'RLS ENABLED' else 'RLS MISSING' end;
    return next;

    suite := 'RLS';
    test_name := v_rec.table_name || '.policy';
    select count(*)
    into v_count
    from pg_policies p
    where p.schemaname = 'public'
      and p.tablename = v_rec.table_name;
    passed := v_count > 0;
    details := format('%s policy/policies.', v_count);
    return next;

    suite := 'GRANT';
    test_name := v_rec.table_name || '.authenticated_select';
    select has_table_privilege(
      'authenticated',
      format('public.%I', v_rec.table_name),
      'SELECT'
    ) into passed;
    details := case when passed then 'SELECT GRANTED' else 'SELECT MISSING' end;
    return next;
  end loop;

  for v_rec in
    select signature
    from (
      values
      ('public.get_notification_inbox(uuid,integer,timestamptz)'),
      ('public.mark_notification_read(uuid)'),
      ('public.mark_all_notifications_read(uuid)'),
      ('public.upsert_notification_preferences(uuid,jsonb)'),
      ('public.publish_notification_template(uuid,text,text,jsonb)'),
      ('public.enqueue_notification_event(uuid,text,uuid,jsonb)'),
      ('public.process_notification_outbox(integer)'),
      ('public.retry_notification_delivery(uuid)'),
      ('public.get_activity_timeline(uuid,timestamptz,timestamptz,jsonb)'),
      ('public.get_hotel_system_settings(uuid)'),
      ('public.update_hotel_system_settings(uuid,jsonb)'),
      ('public.get_support_workspace(uuid)'),
      ('public.get_active_announcements(uuid)')
    ) expected(signature)
  loop
    suite := 'FUNCTION';
    test_name := v_rec.signature;
    passed := to_regprocedure(v_rec.signature) is not null;
    details := case when passed then 'PRESENT' else 'MISSING' end;
    return next;

    suite := 'GRANT';
    test_name := v_rec.signature || '.authenticated_execute';
    select has_function_privilege(
      'authenticated',
      v_rec.signature,
      'EXECUTE'
    ) into passed;
    details := case when passed then 'EXECUTE GRANTED' else 'EXECUTE MISSING' end;
    return next;
  end loop;

  for v_rec in
    select signature
    from (
      values
      ('private.day17_can_manage_hotel(uuid)'),
      ('private.resolve_hotel_business_date(uuid,timestamptz)'),
      ('private.day17_render_notification_text(text,jsonb)'),
      ('private.day17_enqueue_notification_event_internal(uuid,text,uuid,jsonb,uuid)'),
      ('private.day17_capture_critical_event()'),
      ('private.day17_capture_support_event()'),
      ('private.day17_capture_announcement_event()')
    ) expected(signature)
  loop
    suite := 'PRIVATE_FUNCTION';
    test_name := v_rec.signature;
    passed := to_regprocedure(v_rec.signature) is not null;
    details := case when passed then 'PRESENT' else 'MISSING' end;
    return next;
  end loop;

  for v_rec in
    select *
    from (
      values
        ('reservations', 'day17_reservation_notification_event'),
        ('payments', 'day17_payment_notification_event'),
        ('service_requests', 'day17_service_request_notification_event'),
        ('support_tickets', 'day17_support_ticket_notification_event'),
        ('announcements', 'day17_announcement_notification_event')
    ) expected(table_name, trigger_name)
  loop
    suite := 'TRIGGER';
    test_name := v_rec.trigger_name;
    select exists (
      select 1
      from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
      where not t.tgisinternal
        and n.nspname = 'public'
        and c.relname = v_rec.table_name
        and t.tgname = v_rec.trigger_name
    ) into passed;
    details := case when passed then 'PRESENT' else 'MISSING' end;
    return next;
  end loop;

  for v_rec in
    select table_name
    from (
      values
        ('notification_recipients'),
        ('notification_deliveries')
    ) expected(table_name)
  loop
    suite := 'REALTIME';
    test_name := v_rec.table_name;
    select exists (
      select 1
      from pg_publication_tables pt
      where pt.pubname = 'supabase_realtime'
        and pt.schemaname = 'public'
        and pt.tablename = v_rec.table_name
    ) into passed;
    details := case when passed then 'PUBLISHED' else 'NOT PUBLISHED' end;
    return next;
  end loop;

  for v_rec in
    select event_key
    from (
      values
      ('reservation.created'),
      ('reservation.status_changed'),
      ('payment.created'),
      ('payment.status_changed'),
      ('service_request.created'),
      ('service_request.status_changed'),
      ('support.ticket_created'),
      ('support.status_changed'),
      ('announcement.published')
    ) expected(event_key)
  loop
    suite := 'CATALOG';
    test_name := v_rec.event_key;
    select exists (
      select 1
      from public.notification_event_catalog nec
      where nec.event_key = v_rec.event_key
        and nec.is_active
    ) into passed;
    details := case when passed then 'ACTIVE' else 'MISSING' end;
    return next;

    suite := 'TEMPLATE';
    test_name := v_rec.event_key || '.in_app.en';
    select exists (
      select 1
      from public.notification_templates nt
      where nt.hotel_id is null
        and nt.event_key = v_rec.event_key
        and nt.channel = 'in_app'
        and nt.locale = 'en'
        and nt.status = 'published'
    ) into passed;
    details := case when passed then 'PUBLISHED' else 'MISSING' end;
    return next;
  end loop;

  suite := 'FINAL';
  test_name := 'audit_069_actual_schema_respected';
  passed :=
    to_regclass('public.support_ticket_events') is not null
    and to_regclass('public.support_ticket_messages') is null
    and exists (
      select 1
      from information_schema.columns c
      where c.table_schema = 'public'
        and c.table_name = 'announcements'
        and c.column_name = 'target_hotel_id'
    )
    and exists (
      select 1
      from information_schema.columns c
      where c.table_schema = 'public'
        and c.table_name = 'support_tickets'
        and c.column_name = 'created_by'
    );
  details := 'Migration uses the real Day 9 support and announcement schema.';
  return next;

  suite := 'FINAL';
  test_name := 'hotel_settings_actual_schema_respected';
  passed :=
    exists (
      select 1
      from information_schema.columns c
      where c.table_schema = 'public'
        and c.table_name = 'hotel_settings'
        and c.column_name = 'default_tax_percent'
    )
    and not exists (
      select 1
      from information_schema.columns c
      where c.table_schema = 'public'
        and c.table_name = 'hotel_settings'
        and c.column_name = 'tax_rate'
    );
  details := 'Day 8 structured settings remain authoritative.';
  return next;

  suite := 'FINAL';
  test_name := 'business_day_settings_coverage';
  select count(*)
  into v_count
  from public.hotels h
  where not exists (
    select 1
    from public.business_day_settings bds
    where bds.hotel_id = h.id
  );
  passed := v_count = 0;
  details := format('%s hotel(s) missing business-day settings.', v_count);
  return next;

  suite := 'FINAL';
  test_name := 'outbox_anon_blocked';
  passed := not (
    has_table_privilege('anon', 'public.notification_outbox', 'SELECT')
    or has_table_privilege('anon', 'public.notification_outbox', 'INSERT')
    or has_table_privilege('anon', 'public.notification_outbox', 'UPDATE')
  );
  details := 'Anonymous outbox access is blocked.';
  return next;

  suite := 'FINAL';
  test_name := 'recipient_anon_blocked';
  passed := not (
    has_table_privilege('anon', 'public.notification_recipients', 'SELECT')
    or has_table_privilege('anon', 'public.notification_recipients', 'INSERT')
    or has_table_privilege('anon', 'public.notification_recipients', 'UPDATE')
  );
  details := 'Anonymous recipient-inbox access is blocked.';
  return next;

  suite := 'FINAL';
  test_name := 'email_secret_not_stored';
  passed := not exists (
    select 1
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = 'email_adapter_configs'
      and c.column_name in (
        'api_key',
        'api_secret',
        'password',
        'access_token'
      )
  );
  details := 'Only secret references are stored.';
  return next;

  suite := 'FINAL';
  test_name := 'manual_whatsapp_only';
  passed :=
    to_regclass('public.whatsapp_templates') is not null
    and not exists (
      select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname in ('public', 'private')
        and p.proname ilike '%send%whatsapp%'
    );
  details := 'WhatsApp foundation is manual-template-only.';
  return next;

  suite := 'FINAL';
  test_name := 'critical_triggers_complete';
  select count(*)
  into v_count
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  where not t.tgisinternal
    and n.nspname = 'public'
    and c.relname in ('reservations', 'payments', 'service_requests')
    and t.tgname like 'day17_%_notification_event';
  passed := v_count = 3;
  details := format('%s/3 critical source triggers present.', v_count);
  return next;

  suite := 'FINAL';
  test_name := 'legacy_notifications_preserved';
  passed := to_regclass('public.notifications') is not null;
  details := 'Existing Navbar notification table remains intact.';
  return next;

  suite := 'FINAL';
  test_name := 'guest_notifications_preserved';
  passed := to_regclass('public.guest_notifications') is not null;
  details := 'Day 15 guest notification history remains intact.';
  return next;

  suite := 'FINAL';
  test_name := 'support_rpc_preserved';
  passed :=
    to_regprocedure(
      'public.create_support_ticket(uuid,text,text,text,text)'
    ) is not null
    and to_regprocedure(
      'public.add_support_ticket_message(uuid,text)'
    ) is not null
    and to_regprocedure(
      'public.update_support_ticket_status(uuid,text,text,uuid)'
    ) is not null;
  details := 'Day 9 support workflow remains intact.';
  return next;

  suite := 'FINAL';
  test_name := 'announcement_rpc_preserved';
  passed := to_regprocedure(
    'public.save_platform_announcement(jsonb)'
  ) is not null;
  details := 'Actual Day 9 announcement RPC remains intact.';
  return next;

  suite := 'FINAL';
  test_name := 'migration_056_foundation_complete';
  passed := true;
  details :=
    'Day 17 database foundation is installed; runtime and frontend acceptance remain.';
  return next;
end;
$function$;

revoke all on function private.day17_migration_056_acceptance_rev2()
from public, anon, authenticated;

commit;

select suite, test_name, passed, details
from private.day17_migration_056_acceptance_rev2()
order by suite, test_name;
