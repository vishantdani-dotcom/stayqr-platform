-- StayQR Day 3 — Step 1 Verification
-- READ-ONLY. Run after Migration 202607220003 succeeds.
-- Export the one JSON row as CSV.

with
required_tables as (
  select unnest(array[
    'activity_logs',
    'reservation_payments'
  ])::text as table_name
),
table_state as (
  select
    rt.table_name,
    to_regclass('public.' || rt.table_name) is not null as table_exists,
    coalesce(c.relrowsecurity, false) as rls_enabled,
    (
      select count(*)
      from pg_policies p
      where p.schemaname = 'public'
        and p.tablename = rt.table_name
    ) as policy_count
  from required_tables rt
  left join pg_class c
    on c.oid = to_regclass('public.' || rt.table_name)
),
function_state as (
  select *
  from (
    values
      (
        'get_reservation_available_rooms',
        to_regprocedure(
          'public.get_reservation_available_rooms(uuid,date,date,uuid,uuid)'
        ) is not null
      ),
      (
        'get_reservation_rate_quote',
        to_regprocedure(
          'public.get_reservation_rate_quote(uuid,uuid,date,date,integer,integer)'
        ) is not null
      ),
      (
        'search_reservation_guests',
        to_regprocedure(
          'public.search_reservation_guests(uuid,text,integer)'
        ) is not null
      ),
      (
        'create_reservation',
        to_regprocedure(
          'public.create_reservation(uuid,jsonb)'
        ) is not null
      ),
      (
        'update_reservation',
        to_regprocedure(
          'public.update_reservation(uuid,uuid,jsonb,timestamptz)'
        ) is not null
      ),
      (
        'change_reservation_status',
        to_regprocedure(
          'public.change_reservation_status(uuid,uuid,text,text)'
        ) is not null
      ),
      (
        'get_reservations',
        to_regprocedure(
          'public.get_reservations(uuid,text,text,date,date,integer,integer)'
        ) is not null
      ),
      (
        'get_reservation_details',
        to_regprocedure(
          'public.get_reservation_details(uuid,uuid)'
        ) is not null
      )
  ) f(function_name, function_exists)
),
index_state as (
  select *
  from (
    values
      (
        'activity_hotel_created',
        to_regclass(
          'public.idx_activity_logs_hotel_created'
        ) is not null
      ),
      (
        'reservation_payment_reservation',
        to_regclass(
          'public.idx_reservation_payments_reservation'
        ) is not null
      ),
      (
        'guest_phone',
        to_regclass(
          'public.idx_guests_hotel_phone'
        ) is not null
      ),
      (
        'reservation_status_arrival',
        to_regclass(
          'public.idx_reservations_hotel_status_arrival'
        ) is not null
      )
  ) i(index_name, index_exists)
)
select jsonb_pretty(
  jsonb_build_object(
    'generated_at', now(),
    'migration',
      '202607220003_reservation_crud_rate_quote_activity',
    'table_state', (
      select coalesce(
        jsonb_agg(to_jsonb(x) order by x.table_name),
        '[]'::jsonb
      )
      from table_state x
    ),
    'function_state', (
      select coalesce(
        jsonb_agg(to_jsonb(x) order by x.function_name),
        '[]'::jsonb
      )
      from function_state x
    ),
    'index_state', (
      select coalesce(
        jsonb_agg(to_jsonb(x) order by x.index_name),
        '[]'::jsonb
      )
      from index_state x
    ),
    'deposit_trigger_exists', exists (
      select 1
      from information_schema.triggers
      where trigger_schema = 'public'
        and event_object_table = 'reservation_payments'
        and trigger_name =
          'reservation_payments_sync_deposit'
    ),
    'current_counts', jsonb_build_object(
      'reservations', (
        select count(*) from public.reservations
      ),
      'reservation_payments', (
        select count(*) from public.reservation_payments
      ),
      'activity_logs', (
        select count(*) from public.activity_logs
      )
    )
  )
) as stayqr_day3_crud_foundation_verification;
