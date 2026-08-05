-- ============================================================================
-- StayQR v1.0
-- Day 17 Audit 070 REV2 STATE-ORDER FIX
-- Reversible Notification Runtime Acceptance
--
-- PREREQUISITE
-- Migration 056 REV2 acceptance passed 275/275.
--
-- EXPECTED
-- 75 rows / 75 passed / 0 failures.
--
-- REV2 CORRECTIONS
-- - In-app deliveries may be in delivered or read state after inbox tests.
-- - Dead-letter absence is captured immediately after retry and before the
--   deliberate second processing failure recreates the dead-letter row.
--
-- REVERSIBILITY
-- All fixture operations run inside a nested PL/pgSQL exception block.
-- The audit intentionally raises DAY17_A070_ROLLBACK_COMPLETE after runtime
-- checks. PostgreSQL rolls back every fixture mutation before results return.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '300s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202608050070:day17-runtime-rev2')
);

create schema if not exists private;

create or replace function private.day17_a070_result_rev2(
  p_seq integer,
  p_suite text,
  p_test_name text,
  p_passed boolean,
  p_details text
)
returns jsonb
language sql
immutable
security invoker
set search_path = ''
as $function$
  select jsonb_build_array(
    jsonb_build_object(
      'seq', p_seq,
      'suite', p_suite,
      'test_name', p_test_name,
      'passed', coalesce(p_passed, false),
      'details', coalesce(p_details, '')
    )
  );
$function$;

create or replace function private.day17_a070_runtime_acceptance_rev2()
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
  v_results jsonb := '[]'::jsonb;
  v_seq integer := 0;

  v_hotel_a uuid;
  v_hotel_b uuid;
  v_staff_user uuid;
  v_admin_user uuid;
  v_staff_email text;
  v_staff_phone text;

  v_reservation_id uuid := gen_random_uuid();
  v_payment_id uuid := gen_random_uuid();
  v_service_id uuid := gen_random_uuid();
  v_source_ids uuid[];

  v_res_outbox uuid;
  v_payment_outbox uuid;
  v_service_outbox uuid;
  v_recipient_id uuid;
  v_manual_delivery uuid;
  v_email_delivery uuid;

  v_template_locale text := 'en-d17rt';
  v_json jsonb;
  v_replay jsonb;
  v_inbox jsonb;
  v_mark_result jsonb;
  v_mark_all jsonb;
  v_manual_process jsonb;
  v_email_process jsonb;
  v_email_process_2 jsonb;
  v_retry_result jsonb;
  v_retry_cleared_dead_letter boolean := false;
  v_activity jsonb;
  v_support jsonb;
  v_announcements jsonb;
  v_settings jsonb;

  v_preference_before jsonb;
  v_business_day_before jsonb;
  v_enabled_adapters_before bigint := 0;

  v_timezone text;
  v_before_timestamp timestamptz;
  v_after_timestamp timestamptz;
  v_before_business_date date;
  v_after_business_date date;

  v_foreign_denied boolean := false;
  v_anon_denied boolean := false;
  v_foreign_error text;
  v_anon_error text;

  v_previous_sub text :=
    current_setting('request.jwt.claim.sub', true);
  v_previous_role text :=
    current_setting('request.jwt.claim.role', true);
  v_previous_claims text :=
    current_setting('request.jwt.claims', true);

  v_runtime_completed boolean := false;
  v_unexpected_error text;
begin
  v_source_ids := array[
    v_reservation_id,
    v_payment_id,
    v_service_id
  ];

  select
    s.hotel_id,
    s.auth_user_id,
    coalesce(nullif(trim(s.email), ''), 'day17-runtime@stayqr.test'),
    coalesce(nullif(trim(s.phone), ''), '919999999999')
  into
    v_hotel_a,
    v_staff_user,
    v_staff_email,
    v_staff_phone
  from public.staff s
  join public.hotels h
    on h.id = s.hotel_id
  where h.status = 'active'
    and s.status = 'active'
    and s.auth_user_id is not null
    and not exists (
      select 1
      from public.platform_admins pa
      where pa.user_id = s.auth_user_id
        and pa.status = 'active'
    )
  order by
    case when nullif(trim(s.email), '') is not null then 0 else 1 end,
    s.id
  limit 1;

  select pa.user_id
  into v_admin_user
  from public.platform_admins pa
  where pa.status = 'active'
  order by pa.created_at
  limit 1;


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'PRECHECK',
      'migration_056_tables',
      ((
  select count(*) = 12
  from information_schema.tables t
  where t.table_schema = 'public'
    and t.table_name in (
      'notification_event_catalog','notification_preferences',
      'notification_templates','notification_template_versions',
      'notification_outbox','notification_deliveries',
      'notification_delivery_attempts','notification_dead_letters',
      'notification_recipients','email_adapter_configs',
      'whatsapp_templates','business_day_settings'
    )
)),
      ((
  select format('%s/12 tables present.', count(*))
  from information_schema.tables t
  where t.table_schema = 'public'
    and t.table_name in (
      'notification_event_catalog','notification_preferences',
      'notification_templates','notification_template_versions',
      'notification_outbox','notification_deliveries',
      'notification_delivery_attempts','notification_dead_letters',
      'notification_recipients','email_adapter_configs',
      'whatsapp_templates','business_day_settings'
    )
))
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'PRECHECK',
      'critical_source_triggers',
      ((
  select count(*) = 3
  from pg_trigger t
  join pg_class c on c.oid=t.tgrelid
  join pg_namespace n on n.oid=c.relnamespace
  where not t.tgisinternal
    and n.nspname='public'
    and c.relname in ('reservations','payments','service_requests')
    and t.tgname in (
      'day17_reservation_notification_event',
      'day17_payment_notification_event',
      'day17_service_request_notification_event'
    )
)),
      ((
  select format('%s/3 critical triggers present.', count(*))
  from pg_trigger t
  join pg_class c on c.oid=t.tgrelid
  join pg_namespace n on n.oid=c.relnamespace
  where not t.tgisinternal
    and n.nspname='public'
    and c.relname in ('reservations','payments','service_requests')
    and t.tgname in (
      'day17_reservation_notification_event',
      'day17_payment_notification_event',
      'day17_service_request_notification_event'
    )
))
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'PRECHECK',
      'support_announcement_triggers',
      ((
  select count(*) = 2
  from pg_trigger t
  join pg_class c on c.oid=t.tgrelid
  join pg_namespace n on n.oid=c.relnamespace
  where not t.tgisinternal
    and n.nspname='public'
    and (
      (c.relname='support_tickets'
       and t.tgname='day17_support_ticket_notification_event')
      or
      (c.relname='announcements'
       and t.tgname='day17_announcement_notification_event')
    )
)),
      ('Support and announcement triggers inspected.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'PRECHECK',
      'runtime_trigger_function',
      (to_regprocedure('private.day17_capture_critical_event()') is not null),
      ('Critical-event trigger function is installed.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'PRECHECK',
      'active_hotel_staff_fixture',
      (v_hotel_a is not null and v_staff_user is not null),
      (format('Hotel %s; staff %s.',
  coalesce(v_hotel_a::text,'missing'),
  coalesce(v_staff_user::text,'missing')))
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'PRECHECK',
      'active_platform_admin',
      (v_admin_user is not null),
      (format('Platform admin %s.',coalesce(v_admin_user::text,'missing')))
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'PRECHECK',
      'event_catalog_seed',
      ((
  select count(*)=9
  from public.notification_event_catalog nec
  where nec.is_active and nec.event_key in (
    'reservation.created','reservation.status_changed',
    'payment.created','payment.status_changed',
    'service_request.created','service_request.status_changed',
    'support.ticket_created','support.status_changed',
    'announcement.published'
  )
)),
      ('Nine canonical events are active.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'PRECHECK',
      'published_default_templates',
      ((
  select count(*)=9
  from public.notification_templates nt
  where nt.hotel_id is null and nt.channel='in_app'
    and nt.locale='en' and nt.status='published'
)),
      ('Nine global English in-app templates are published.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'PRECHECK',
      'recipient_delivery_realtime',
      ((
  select count(*)=2
  from pg_publication_tables pt
  where pt.pubname='supabase_realtime'
    and pt.schemaname='public'
    and pt.tablename in ('notification_recipients','notification_deliveries')
)),
      ('Recipient and delivery ledgers are Realtime-published.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'PRECHECK',
      'migration_acceptance_helper',
      (to_regprocedure('private.day17_migration_056_acceptance_rev2()') is not null),
      ('Migration 056 REV2 acceptance helper is present.')
    );


  begin
    if v_hotel_a is null
       or v_staff_user is null
       or v_admin_user is null
    then
      raise exception
        'Required active hotel staff or platform admin was not found.';
    end if;

    perform set_config(
      'request.jwt.claim.sub',
      v_staff_user::text,
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
        'sub', v_staff_user,
        'role', 'authenticated'
      )::text,
      true
    );

    select h.id
    into v_hotel_b
    from public.hotels h
    where h.id <> v_hotel_a
      and not private.user_has_hotel_access(h.id)
    order by h.created_at
    limit 1;

    if v_hotel_b is null then
      raise exception
        'A second unauthorized hotel is required for cross-hotel acceptance.';
    end if;

    select to_jsonb(np)
    into v_preference_before
    from public.notification_preferences np
    where np.hotel_id = v_hotel_a
      and np.user_id = v_staff_user;

    select to_jsonb(bds)
    into v_business_day_before
    from public.business_day_settings bds
    where bds.hotel_id = v_hotel_a;

    select count(*)
    into v_enabled_adapters_before
    from public.email_adapter_configs eac
    where eac.is_enabled
      and (
        eac.hotel_id = v_hotel_a
        or eac.hotel_id is null
      );

    v_json := public.upsert_notification_preferences(
      v_hotel_a,
      jsonb_build_object(
        'in_app_enabled', true,
        'email_enabled', false,
        'manual_whatsapp_enabled', false,
        'locale', 'en',
        'event_overrides', '{}'::jsonb
      )
    );

    perform set_config(
      'request.jwt.claim.sub',
      v_admin_user::text,
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

    perform public.publish_notification_template(
      v_hotel_a,
      'reservation.created',
      'in_app',
      jsonb_build_object(
        'locale', v_template_locale,
        'title_template', 'Runtime reservation {{reservation_number}}',
        'body_template', 'Runtime status {{status}}'
      )
    );

    perform set_config(
      'request.jwt.claim.sub',
      v_staff_user::text,
      true
    );
    perform set_config(
      'request.jwt.claims',
      jsonb_build_object(
        'sub', v_staff_user,
        'role', 'authenticated'
      )::text,
      true
    );

    execute $ddl$
      create temporary table reservations (
        id uuid primary key,
        hotel_id uuid not null,
        reservation_number text,
        status text,
        created_at timestamptz,
        updated_at timestamptz
      ) on commit drop
    $ddl$;

    execute $ddl$
      create temporary table payments (
        id uuid primary key,
        hotel_id uuid not null,
        payment_status text,
        amount numeric,
        created_at timestamptz,
        updated_at timestamptz
      ) on commit drop
    $ddl$;

    execute $ddl$
      create temporary table service_requests (
        id uuid primary key,
        hotel_id uuid not null,
        guest_session_id uuid,
        room_id uuid,
        guest_id uuid,
        request_type text,
        department text,
        status text,
        created_at timestamptz,
        updated_at timestamptz
      ) on commit drop
    $ddl$;

    execute $ddl$
      create trigger day17_a070_temp_reservation_trigger
      after insert or update on pg_temp.reservations
      for each row execute function private.day17_capture_critical_event()
    $ddl$;

    execute $ddl$
      create trigger day17_a070_temp_payment_trigger
      after insert or update on pg_temp.payments
      for each row execute function private.day17_capture_critical_event()
    $ddl$;

    execute $ddl$
      create trigger day17_a070_temp_service_trigger
      after insert or update on pg_temp.service_requests
      for each row execute function private.day17_capture_critical_event()
    $ddl$;

    execute $dml$
      insert into pg_temp.reservations (
        id,
        hotel_id,
        reservation_number,
        status,
        created_at,
        updated_at
      ) values ($1, $2, $3, $4, now(), now())
    $dml$
    using
      v_reservation_id,
      v_hotel_a,
      'D17-RT-RES',
      'confirmed';

    execute $dml$
      insert into pg_temp.payments (
        id,
        hotel_id,
        payment_status,
        amount,
        created_at,
        updated_at
      ) values ($1, $2, $3, $4, now(), now())
    $dml$
    using
      v_payment_id,
      v_hotel_a,
      'pending',
      117.00;

    execute $dml$
      insert into pg_temp.service_requests (
        id,
        hotel_id,
        request_type,
        department,
        status,
        created_at,
        updated_at
      ) values ($1, $2, $3, $4, $5, now(), now())
    $dml$
    using
      v_service_id,
      v_hotel_a,
      'runtime_acceptance',
      'guest_services',
      'pending';

    execute $dml$
      update pg_temp.reservations
      set status = 'checked_in', updated_at = now()
      where id = $1
    $dml$
    using v_reservation_id;

    execute $dml$
      update pg_temp.payments
      set payment_status = 'paid', updated_at = now()
      where id = $1
    $dml$
    using v_payment_id;

    execute $dml$
      update pg_temp.service_requests
      set status = 'accepted', updated_at = now()
      where id = $1
    $dml$
    using v_service_id;

    execute $dml$
      update pg_temp.reservations
      set status = 'checked_in', updated_at = now()
      where id = $1
    $dml$
    using v_reservation_id;

    execute $dml$
      update pg_temp.payments
      set payment_status = 'paid', updated_at = now()
      where id = $1
    $dml$
    using v_payment_id;

    execute $dml$
      update pg_temp.service_requests
      set status = 'accepted', updated_at = now()
      where id = $1
    $dml$
    using v_service_id;

    v_replay := private.day17_enqueue_notification_event_internal(
      v_hotel_a,
      'reservation.created',
      v_reservation_id,
      jsonb_build_object(
        'idempotency_key',
          'reservation.created:' ||
          v_reservation_id::text ||
          ':confirmed',
        'reservation_number', 'D17-RT-RES',
        'status', 'confirmed',
        'occurred_at', now()
      ),
      v_staff_user
    );

    select nox.id
    into v_res_outbox
    from public.notification_outbox nox
    where nox.hotel_id = v_hotel_a
      and nox.source_id = v_reservation_id
      and nox.event_key = 'reservation.created';

    select nox.id
    into v_payment_outbox
    from public.notification_outbox nox
    where nox.hotel_id = v_hotel_a
      and nox.source_id = v_payment_id
      and nox.event_key = 'payment.created';

    select nox.id
    into v_service_outbox
    from public.notification_outbox nox
    where nox.hotel_id = v_hotel_a
      and nox.source_id = v_service_id
      and nox.event_key = 'service_request.created';

    v_inbox := public.get_notification_inbox(
      v_hotel_a,
      200,
      null
    );

    select nr.id
    into v_recipient_id
    from public.notification_recipients nr
    where nr.outbox_id = v_res_outbox
      and nr.user_id = v_staff_user;

    v_mark_result := public.mark_notification_read(v_recipient_id);
    v_mark_all := public.mark_all_notifications_read(v_hotel_a);

    begin
      perform public.get_notification_inbox(
        v_hotel_b,
        10,
        null
      );
      v_foreign_denied := false;
    exception
      when others then
        v_foreign_denied := true;
        v_foreign_error := sqlerrm;
    end;

    perform set_config(
      'request.jwt.claim.sub',
      '',
      true
    );
    perform set_config(
      'request.jwt.claims',
      '{}',
      true
    );

    begin
      perform public.get_notification_inbox(
        v_hotel_a,
        10,
        null
      );
      v_anon_denied := false;
    exception
      when others then
        v_anon_denied := true;
        v_anon_error := sqlerrm;
    end;

    perform set_config(
      'request.jwt.claim.sub',
      v_admin_user::text,
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
      max_attempts,
      queued_at,
      metadata,
      created_at,
      updated_at
    ) values (
      v_res_outbox,
      v_hotel_a,
      v_staff_user,
      'manual_whatsapp',
      v_staff_phone,
      'en',
      'Runtime manual WhatsApp',
      'StayQR Day 17 manual WhatsApp acceptance',
      'pending',
      0,
      3,
      timestamptz '1900-01-01 00:00:00+00',
      jsonb_build_object('fixture', 'day17_a070'),
      timestamptz '1900-01-01 00:00:00+00',
      timestamptz '1900-01-01 00:00:00+00'
    )
    returning id into v_manual_delivery;

    v_manual_process := public.process_notification_outbox(1);

    update public.email_adapter_configs eac
    set
      is_enabled = false,
      updated_at = now()
    where eac.is_enabled
      and (
        eac.hotel_id = v_hotel_a
        or eac.hotel_id is null
      );

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
      max_attempts,
      queued_at,
      metadata,
      created_at,
      updated_at
    ) values (
      v_res_outbox,
      v_hotel_a,
      v_staff_user,
      'email',
      v_staff_email,
      'en',
      'Runtime email failure',
      'StayQR Day 17 retry and dead-letter acceptance',
      'pending',
      0,
      1,
      timestamptz '1901-01-01 00:00:00+00',
      jsonb_build_object('fixture', 'day17_a070'),
      timestamptz '1901-01-01 00:00:00+00',
      timestamptz '1901-01-01 00:00:00+00'
    )
    returning id into v_email_delivery;

    v_email_process := public.process_notification_outbox(1);
    v_retry_result := public.retry_notification_delivery(
      v_email_delivery
    );

    select not exists (
      select 1
      from public.notification_dead_letters ndl
      where ndl.delivery_id = v_email_delivery
    )
    into v_retry_cleared_dead_letter;

    v_email_process_2 := public.process_notification_outbox(1);

    perform set_config(
      'request.jwt.claim.sub',
      v_staff_user::text,
      true
    );
    perform set_config(
      'request.jwt.claims',
      jsonb_build_object(
        'sub', v_staff_user,
        'role', 'authenticated'
      )::text,
      true
    );

    v_activity := public.get_activity_timeline(
      v_hotel_a,
      now() - interval '1 hour',
      now() + interval '1 hour',
      jsonb_build_object('limit', 500)
    );

    v_support := public.get_support_workspace(v_hotel_a);
    v_announcements := public.get_active_announcements(v_hotel_a);
    v_settings := public.get_hotel_system_settings(v_hotel_a);

    select h.timezone
    into v_timezone
    from public.hotels h
    where h.id = v_hotel_a;

    update public.business_day_settings bds
    set
      business_day_cutoff = '06:00'::time,
      updated_at = now()
    where bds.hotel_id = v_hotel_a;

    v_before_timestamp :=
      timestamp '2030-01-15 05:00:00'
      at time zone v_timezone;

    v_after_timestamp :=
      timestamp '2030-01-15 07:00:00'
      at time zone v_timezone;

    v_before_business_date :=
      private.resolve_hotel_business_date(
        v_hotel_a,
        v_before_timestamp
      );

    v_after_business_date :=
      private.resolve_hotel_business_date(
        v_hotel_a,
        v_after_timestamp
      );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'IDENTITY',
      'foreign_hotel_available',
      (v_hotel_b is not null),
      (format('Comparison hotel %s.',coalesce(v_hotel_b::text,'none')))
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'PREFERENCES',
      'preference_rpc_returned',
      (coalesce((v_json->>'in_app_enabled')::boolean,false)),
      (v_json::text)
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'PREFERENCES',
      'preference_row_saved',
      (exists(
  select 1 from public.notification_preferences np
  where np.hotel_id=v_hotel_a and np.user_id=v_staff_user
    and np.in_app_enabled and not np.email_enabled and np.locale='en'
)),
      ('Runtime user has in-app enabled and email disabled.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'TEMPLATE',
      'hotel_template_published',
      (exists(
  select 1 from public.notification_templates nt
  where nt.hotel_id=v_hotel_a
    and nt.event_key='reservation.created'
    and nt.channel='in_app'
    and nt.locale=v_template_locale
    and nt.status='published'
)),
      (format('Runtime locale %s.',v_template_locale))
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'TEMPLATE',
      'template_version_recorded',
      (exists(
  select 1
  from public.notification_template_versions ntv
  join public.notification_templates nt on nt.id=ntv.template_id
  where nt.hotel_id=v_hotel_a
    and nt.event_key='reservation.created'
    and nt.channel='in_app'
    and nt.locale=v_template_locale
    and ntv.version_number>=1
)),
      ('Published template has a version ledger row.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'TEMPLATE',
      'template_hotel_isolation',
      (not exists(
  select 1 from public.notification_templates nt
  where nt.hotel_id is distinct from v_hotel_a
    and nt.locale=v_template_locale
)),
      ('Runtime template exists only for the selected hotel.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'TRIGGER_RUNTIME',
      'reservation_created_event',
      (exists(
  select 1 from public.notification_outbox nox
  where nox.hotel_id=v_hotel_a and nox.source_id=v_reservation_id
    and nox.event_key='reservation.created'
)),
      ('Temporary reservation insert created an outbox event.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'TRIGGER_RUNTIME',
      'payment_created_event',
      (exists(
  select 1 from public.notification_outbox nox
  where nox.hotel_id=v_hotel_a and nox.source_id=v_payment_id
    and nox.event_key='payment.created'
)),
      ('Temporary payment insert created an outbox event.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'TRIGGER_RUNTIME',
      'service_created_event',
      (exists(
  select 1 from public.notification_outbox nox
  where nox.hotel_id=v_hotel_a and nox.source_id=v_service_id
    and nox.event_key='service_request.created'
)),
      ('Temporary service insert created an outbox event.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'TRIGGER_RUNTIME',
      'reservation_status_event',
      (exists(
  select 1 from public.notification_outbox nox
  where nox.hotel_id=v_hotel_a and nox.source_id=v_reservation_id
    and nox.event_key='reservation.status_changed'
)),
      ('Reservation status change created an outbox event.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'TRIGGER_RUNTIME',
      'payment_status_event',
      (exists(
  select 1 from public.notification_outbox nox
  where nox.hotel_id=v_hotel_a and nox.source_id=v_payment_id
    and nox.event_key='payment.status_changed'
)),
      ('Payment status change created an outbox event.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'TRIGGER_RUNTIME',
      'service_status_event',
      (exists(
  select 1 from public.notification_outbox nox
  where nox.hotel_id=v_hotel_a and nox.source_id=v_service_id
    and nox.event_key='service_request.status_changed'
)),
      ('Service status change created an outbox event.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'TRIGGER_RUNTIME',
      'exact_six_source_events',
      ((
  select count(*)=6
  from public.notification_outbox nox
  where nox.hotel_id=v_hotel_a and nox.source_id=any(v_source_ids)
)),
      ((
  select format('%s/6 source events.',count(*))
  from public.notification_outbox nox
  where nox.hotel_id=v_hotel_a and nox.source_id=any(v_source_ids)
))
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'TRIGGER_RUNTIME',
      'same_status_update_no_duplicate',
      ((
  select count(*)=6
  from public.notification_outbox nox
  where nox.hotel_id=v_hotel_a and nox.source_id=any(v_source_ids)
)),
      ('Repeating the same statuses produced no new events.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'TRIGGER_RUNTIME',
      'direct_idempotent_replay',
      (coalesce((v_replay->>'idempotent')::boolean,false)),
      (v_replay::text)
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'TRIGGER_RUNTIME',
      'idempotent_replay_no_duplicate',
      ((
  select count(*)=6
  from public.notification_outbox nox
  where nox.hotel_id=v_hotel_a and nox.source_id=any(v_source_ids)
)),
      ('Direct replay retained exactly six outbox rows.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'TRIGGER_RUNTIME',
      'source_type_mapping',
      ((
  select count(distinct nox.source_type)=3
  from public.notification_outbox nox
  where nox.hotel_id=v_hotel_a and nox.source_id=any(v_source_ids)
    and nox.source_type in ('reservation','payment','service_request')
)),
      ('Three canonical source types were preserved.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'TRIGGER_RUNTIME',
      'business_date_populated',
      (not exists(
  select 1 from public.notification_outbox nox
  where nox.hotel_id=v_hotel_a and nox.source_id=any(v_source_ids)
    and nox.business_date is null
)),
      ('Every runtime event has a business date.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'TRIGGER_RUNTIME',
      'activity_log_exact_once',
      ((
  select count(*)=6
  from public.activity_logs al
  where al.hotel_id=v_hotel_a
    and al.action='notification_event_enqueued'
    and al.entity_id=any(v_source_ids)
)),
      ((
  select format('%s/6 activity rows.',count(*))
  from public.activity_logs al
  where al.hotel_id=v_hotel_a
    and al.action='notification_event_enqueued'
    and al.entity_id=any(v_source_ids)
))
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'RECIPIENT_SECURITY',
      'recipient_rows_created',
      ((
  select count(*)>=6
  from public.notification_recipients nr
  join public.notification_outbox nox on nox.id=nr.outbox_id
  where nox.source_id=any(v_source_ids) and nr.hotel_id=v_hotel_a
)),
      ((
  select format('%s recipient row(s).',count(*))
  from public.notification_recipients nr
  join public.notification_outbox nox on nox.id=nr.outbox_id
  where nox.source_id=any(v_source_ids) and nr.hotel_id=v_hotel_a
))
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'RECIPIENT_SECURITY',
      'outbox_hotel_scope',
      (not exists(
  select 1 from public.notification_outbox nox
  where nox.source_id=any(v_source_ids) and nox.hotel_id<>v_hotel_a
)),
      ('No outbox row escaped the selected hotel.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'RECIPIENT_SECURITY',
      'recipient_hotel_scope',
      (not exists(
  select 1
  from public.notification_recipients nr
  join public.notification_outbox nox on nox.id=nr.outbox_id
  where nox.source_id=any(v_source_ids) and nr.hotel_id<>v_hotel_a
)),
      ('No recipient row escaped the selected hotel.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'RECIPIENT_SECURITY',
      'foreign_hotel_has_no_recipient',
      (not exists(
  select 1
  from public.notification_recipients nr
  join public.notification_outbox nox on nox.id=nr.outbox_id
  where nox.source_id=any(v_source_ids) and nr.hotel_id=v_hotel_b
)),
      ('The comparison hotel received no runtime recipient.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'RECIPIENT_SECURITY',
      'recipients_are_active_hotel_staff',
      (not exists(
  select 1
  from public.notification_recipients nr
  join public.notification_outbox nox on nox.id=nr.outbox_id
  where nox.source_id=any(v_source_ids)
    and not exists(
      select 1 from public.staff s
      where s.hotel_id=v_hotel_a and s.auth_user_id=nr.user_id
        and s.status='active'
    )
)),
      ('Every recipient maps to active staff of the selected hotel.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'RECIPIENT_SECURITY',
      'in_app_delivery_rows',
      ((
  select count(*)>=6
  from public.notification_deliveries nd
  join public.notification_outbox nox on nox.id=nd.outbox_id
  where nox.source_id=any(v_source_ids)
    and nd.hotel_id=v_hotel_a and nd.channel='in_app'
    and nd.status in ('delivered', 'read')
)),
      ('In-app deliveries remain in a valid delivered/read state after inbox actions.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'RECIPIENT_SECURITY',
      'rendered_titles_resolved',
      (not exists(
  select 1
  from public.notification_recipients nr
  join public.notification_outbox nox on nox.id=nr.outbox_id
  where nox.source_id=any(v_source_ids) and nr.title like '%{{%'
)),
      ('No unresolved title placeholder remains.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'RECIPIENT_SECURITY',
      'rendered_messages_resolved',
      (not exists(
  select 1
  from public.notification_recipients nr
  join public.notification_outbox nox on nox.id=nr.outbox_id
  where nox.source_id=any(v_source_ids) and nr.message like '%{{%'
)),
      ('No unresolved message placeholder remains.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'INBOX_RPC',
      'inbox_contains_runtime_events',
      ((
  select count(*)>=6
  from jsonb_array_elements(coalesce(v_inbox->'items','[]'::jsonb)) item
  where nullif(item->>'source_id','')::uuid=any(v_source_ids)
)),
      (format('Inbox unread count %s.',coalesce(v_inbox->>'unread_count','0')))
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'INBOX_RPC',
      'inbox_unread_count_positive',
      (coalesce((v_inbox->>'unread_count')::integer,0)>=6),
      (v_inbox::text)
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'INBOX_RPC',
      'mark_one_read',
      (exists(
  select 1 from public.notification_recipients nr
  where nr.id=v_recipient_id and nr.status='read' and nr.read_at is not null
)),
      (v_mark_result::text)
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'INBOX_RPC',
      'delivery_read_mirrored',
      (exists(
  select 1 from public.notification_deliveries nd
  where nd.outbox_id=v_res_outbox
    and nd.recipient_user_id=v_staff_user
    and nd.channel='in_app' and nd.status='read'
    and nd.read_at is not null
)),
      ('In-app delivery read state mirrors the recipient row.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'INBOX_RPC',
      'mark_all_read_returned',
      (coalesce((v_mark_all->>'updated_count')::integer,0)>=1),
      (v_mark_all::text)
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'INBOX_RPC',
      'all_fixture_recipients_read',
      (not exists(
  select 1
  from public.notification_recipients nr
  join public.notification_outbox nox on nox.id=nr.outbox_id
  where nox.source_id=any(v_source_ids)
    and nr.user_id=v_staff_user and nr.status<>'read'
)),
      ('All selected-user runtime recipients are read.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'INBOX_RPC',
      'foreign_hotel_access_denied',
      (v_foreign_denied),
      (coalesce(v_foreign_error,'No exception captured.'))
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'INBOX_RPC',
      'anonymous_inbox_denied',
      (v_anon_denied),
      (coalesce(v_anon_error,'No exception captured.'))
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'DELIVERY_RUNTIME',
      'manual_delivery_inserted',
      (v_manual_delivery is not null),
      (format('Manual delivery %s.',v_manual_delivery))
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'DELIVERY_RUNTIME',
      'manual_delivery_prepared',
      (exists(
  select 1 from public.notification_deliveries nd
  where nd.id=v_manual_delivery and nd.status='manual_ready'
)),
      (v_manual_process::text)
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'DELIVERY_RUNTIME',
      'manual_whatsapp_url',
      (exists(
  select 1 from public.notification_deliveries nd
  where nd.id=v_manual_delivery and nd.manual_action_url like 'https://wa.me/%'
)),
      ('Manual WhatsApp URL prepared; no message auto-sent.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'DELIVERY_RUNTIME',
      'manual_attempt_logged',
      (exists(
  select 1 from public.notification_delivery_attempts nda
  where nda.delivery_id=v_manual_delivery
    and nda.attempt_status='prepared'
    and nda.adapter_key='manual_whatsapp'
)),
      ('Manual preparation attempt is auditable.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'DELIVERY_RUNTIME',
      'email_delivery_failed_safely',
      (exists(
  select 1 from public.notification_deliveries nd
  where nd.id=v_email_delivery and nd.status='failed'
    and nd.last_error_code='EMAIL_ADAPTER_NOT_CONFIGURED'
)),
      (v_email_process::text)
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'DELIVERY_RUNTIME',
      'email_failure_attempt_logged',
      (exists(
  select 1 from public.notification_delivery_attempts nda
  where nda.delivery_id=v_email_delivery and nda.attempt_number=1
    and nda.attempt_status='failed'
    and nda.error_code='EMAIL_ADAPTER_NOT_CONFIGURED'
)),
      ('First email failure attempt was recorded.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'DELIVERY_RUNTIME',
      'email_dead_letter_created',
      (exists(
  select 1 from public.notification_dead_letters ndl
  where ndl.delivery_id=v_email_delivery
    and ndl.reason_code='EMAIL_ADAPTER_NOT_CONFIGURED'
)),
      ('Terminal email failure entered the dead-letter ledger.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'DELIVERY_RUNTIME',
      'retry_returned_pending',
      (coalesce(v_retry_result->>'status','')='pending'),
      (v_retry_result::text)
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'DELIVERY_RUNTIME',
      'retry_cleared_dead_letter',
      (v_retry_cleared_dead_letter),
      ('Retry removed the prior dead-letter row before the second processing attempt.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'DELIVERY_RUNTIME',
      'second_failure_attempt_logged',
      (exists(
  select 1 from public.notification_delivery_attempts nda
  where nda.delivery_id=v_email_delivery and nda.attempt_number=2
    and nda.attempt_status='failed'
)),
      (v_email_process_2::text)
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'DELIVERY_RUNTIME',
      'dead_letter_recreated_after_retry',
      (exists(
  select 1 from public.notification_dead_letters ndl
  where ndl.delivery_id=v_email_delivery
)),
      ('Second terminal failure recreated the dead-letter row.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'DELIVERY_RUNTIME',
      'provider_secret_not_required',
      (not exists(
  select 1 from information_schema.columns c
  where c.table_schema='public' and c.table_name='email_adapter_configs'
    and c.column_name in ('api_key','api_secret','password','access_token')
)),
      ('Failure handling requires no stored provider secret.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'OPERATIONS',
      'activity_timeline_contains_events',
      ((
  select count(*)>=6
  from jsonb_array_elements(coalesce(v_activity->'items','[]'::jsonb)) item
  where nullif(item->>'entity_id','')::uuid=any(v_source_ids)
)),
      ('Trusted activity timeline returned the runtime events.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'OPERATIONS',
      'support_workspace_shape',
      (jsonb_typeof(v_support)='object'
   and jsonb_typeof(v_support->'tickets')='array'),
      ('Support workspace returned a hotel-scoped ticket array.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'OPERATIONS',
      'announcements_shape',
      (jsonb_typeof(v_announcements)='array'),
      ('Active announcements returned a JSON array.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'OPERATIONS',
      'settings_hotel_scope',
      (coalesce(v_settings#>>'{hotel,id}','')=v_hotel_a::text),
      ('System settings returned only the selected hotel.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'OPERATIONS',
      'settings_timezone_present',
      (nullif(trim(v_settings#>>'{hotel,timezone}'),'') is not null),
      (coalesce(v_settings#>>'{hotel,timezone}','missing'))
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'BUSINESS_DAY',
      'before_cutoff_previous_date',
      (v_before_business_date=date '2030-01-14'),
      (format('Resolved %s before 06:00 cutoff.',v_before_business_date))
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'BUSINESS_DAY',
      'after_cutoff_same_date',
      (v_after_business_date=date '2030-01-15'),
      (format('Resolved %s after 06:00 cutoff.',v_after_business_date))
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'BUSINESS_DAY',
      'timezone_authority_used',
      (nullif(trim(v_timezone),'') is not null),
      (format('Timezone %s.',v_timezone))
    );


    v_runtime_completed := true;

    raise exception 'DAY17_A070_ROLLBACK_COMPLETE'
      using errcode = 'P0001';

  exception
    when others then
      if sqlerrm = 'DAY17_A070_ROLLBACK_COMPLETE' then
        null;
      else
        v_unexpected_error := format(
          '%s [%s]',
          sqlerrm,
          sqlstate
        );

        v_seq := v_seq + 1;
        v_results := v_results || private.day17_a070_result_rev2(
          v_seq,
          'UNEXPECTED_ERROR',
          'runtime_execution',
          false,
          v_unexpected_error
        );
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


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'ROLLBACK_CLEANUP',
      'fixture_outbox_removed',
      (not exists(
  select 1 from public.notification_outbox nox
  where nox.source_id=any(v_source_ids)
)),
      ('All runtime outbox fixtures were rolled back.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'ROLLBACK_CLEANUP',
      'fixture_recipient_delivery_removed',
      (not exists(
  select 1 from public.notification_recipients nr
  where nr.outbox_id=v_res_outbox
)
and not exists(
  select 1 from public.notification_deliveries nd
  where nd.id in (v_manual_delivery,v_email_delivery)
)),
      ('Recipient and delivery fixtures were rolled back.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'ROLLBACK_CLEANUP',
      'fixture_activity_removed',
      (not exists(
  select 1 from public.activity_logs al
  where al.entity_id=any(v_source_ids)
    and al.action='notification_event_enqueued'
)),
      ('Runtime activity rows were rolled back.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'ROLLBACK_CLEANUP',
      'template_fixture_removed',
      (not exists(
  select 1 from public.notification_templates nt
  where nt.hotel_id=v_hotel_a and nt.locale=v_template_locale
)),
      ('Runtime template and version were rolled back.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'ROLLBACK_CLEANUP',
      'preference_restored',
      ((
  select to_jsonb(np)
  from public.notification_preferences np
  where np.hotel_id=v_hotel_a and np.user_id=v_staff_user
) is not distinct from v_preference_before),
      ('Notification preference returned to its original state.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'ROLLBACK_CLEANUP',
      'business_day_settings_restored',
      ((
  select to_jsonb(bds)
  from public.business_day_settings bds
  where bds.hotel_id=v_hotel_a
) is not distinct from v_business_day_before),
      ('Business-day settings returned to their original state.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'ROLLBACK_CLEANUP',
      'email_adapters_restored',
      ((
  select count(*) from public.email_adapter_configs eac
  where eac.is_enabled
    and (eac.hotel_id=v_hotel_a or eac.hotel_id is null)
)=v_enabled_adapters_before),
      (format('%s enabled applicable adapter(s) before and after.',
  v_enabled_adapters_before))
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'ROLLBACK_CLEANUP',
      'jwt_claims_restored',
      (coalesce(current_setting('request.jwt.claim.sub',true),'')
   =coalesce(v_previous_sub,'')),
      ('SQL Editor JWT claim context was restored.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'ROLLBACK_CLEANUP',
      'no_runtime_dead_letters',
      (not exists(
  select 1 from public.notification_dead_letters ndl
  where ndl.delivery_id=v_email_delivery
)),
      ('No runtime dead-letter fixture remains.')
    );


    v_seq := v_seq + 1;
    v_results := v_results || private.day17_a070_result_rev2(
      v_seq,
      'ROLLBACK_CLEANUP',
      'reversible_runtime_complete',
      (v_runtime_completed and v_unexpected_error is null),
      (coalesce(v_unexpected_error,
  'All runtime operations completed and were rolled back.'))
    );


  return query
  select
    result.suite,
    result.test_name,
    result.passed,
    result.details
  from jsonb_to_recordset(v_results) as result(
    seq integer,
    suite text,
    test_name text,
    passed boolean,
    details text
  )
  order by result.seq;
end;
$function$;

revoke all on function private.day17_a070_result_rev2(
  integer,
  text,
  text,
  boolean,
  text
)
from public, anon, authenticated;

revoke all on function private.day17_a070_runtime_acceptance_rev2()
from public, anon, authenticated;

commit;

select suite, test_name, passed, details
from private.day17_a070_runtime_acceptance_rev2();
