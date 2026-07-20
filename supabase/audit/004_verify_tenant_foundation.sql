-- StayQR Day 1 - Step 4 verification
-- READ-ONLY.
-- Run only after the tenant foundation migration reports success.
-- Export the one JSON result as CSV and upload it to the Master Development Chat.

with
tenant_tables as (
  select unnest(array[
    'analytics_events',
    'feedback',
    'food_orders',
    'guest_sessions',
    'guests',
    'hotel_info',
    'hotel_subscriptions',
    'hotel_users',
    'housekeeping_requests',
    'housekeeping_tasks',
    'invoice_items',
    'invoices',
    'manual_charges',
    'menu_categories',
    'menu_items',
    'notifications',
    'payment_collections',
    'payments',
    'room_sessions',
    'rooms',
    'service_requests',
    'staff'
  ])::text as table_name
),
not_null_state as (
  select
    tt.table_name,
    c.is_nullable
  from tenant_tables tt
  join information_schema.columns c
    on c.table_schema = 'public'
   and c.table_name = tt.table_name
   and c.column_name = 'hotel_id'
),
protected_internal_tables as (
  select unnest(array[
    'analytics_events',
    'hotel_subscriptions',
    'hotel_users',
    'hotels',
    'housekeeping_requests',
    'housekeeping_tasks',
    'invoice_items',
    'invoices',
    'manual_charges',
    'payment_collections',
    'payments',
    'platform_admins',
    'role_permissions',
    'room_sessions',
    'staff',
    'staff_roles',
    'subscription_plans'
  ])::text as table_name
),
rls_state as (
  select
    pit.table_name,
    c.relrowsecurity as rls_enabled,
    (
      select count(*)
      from pg_policies p
      where p.schemaname = 'public'
        and p.tablename = pit.table_name
    ) as policy_count
  from protected_internal_tables pit
  join pg_class c
    on c.oid = format('public.%I', pit.table_name)::regclass
),
remaining_public_policies as (
  select
    tablename,
    policyname,
    cmd,
    roles,
    qual,
    with_check
  from pg_policies
  where schemaname = 'public'
    and (
      'public' = any(roles)
      or 'anon' = any(roles)
    )
  order by tablename, policyname
),
known_invoice_mismatches as (
  select count(*)::bigint as mismatch_count
  from public.invoices i
  where coalesce(i.pending_amount, 0)
    <> greatest(
      coalesce(i.total_amount, 0) - coalesce(i.paid_amount, 0),
      0
    )
),
known_staff_without_auth as (
  select count(*)::bigint as active_staff_without_auth
  from public.staff s
  where lower(s.status) = 'active'
    and s.auth_user_id is null
)
select jsonb_pretty(
  jsonb_build_object(
    'generated_at', now(),
    'migration', '202607200001_tenant_foundation_and_guarded_repairs',
    'hotels', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'hotel_id', h.id,
            'hotel_name', h.hotel_name,
            'slug', h.slug,
            'timezone', h.timezone,
            'currency_code', h.currency_code,
            'status', h.status,
            'subscription_status', h.subscription_status
          )
          order by h.hotel_name
        ),
        '[]'::jsonb
      )
      from public.hotels h
    ),
    'hotel_info_orphan_count', (
      select count(*) from public.hotel_info where hotel_id is null
    ),
    'hotel_info_rows', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', hi.id,
            'hotel_id', hi.hotel_id,
            'hotel_name', hi.hotel_name
          )
          order by hi.created_at
        ),
        '[]'::jsonb
      )
      from public.hotel_info hi
    ),
    'room_102_state', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'room_id', r.id,
            'hotel_id', r.hotel_id,
            'room_number', r.room_number,
            'room_status', r.status,
            'active_session_count', (
              select count(*)
              from public.guest_sessions gs
              where gs.hotel_id = r.hotel_id
                and gs.room_id = r.id
                and gs.status = 'active'
            )
          )
        ),
        '[]'::jsonb
      )
      from public.rooms r
      where r.id = '9137c934-1cae-4e99-ae71-8e99d145244e'::uuid
    ),
    'platform_admin', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'user_id', pa.user_id,
            'display_name', pa.display_name,
            'status', pa.status
          )
        ),
        '[]'::jsonb
      )
      from public.platform_admins pa
      where pa.user_id = 'a3d5f5a6-6fff-40fe-8fe0-b0b6c436effd'::uuid
    ),
    'same_hotel_membership_count', (
      select count(*)
      from public.hotel_users hu
      where hu.hotel_id = '77d850d0-016d-4155-bc44-a6207d30e7b9'::uuid
        and hu.user_id = 'a3d5f5a6-6fff-40fe-8fe0-b0b6c436effd'::uuid
    ),
    'tenant_columns_not_null', (
      select coalesce(
        jsonb_agg(to_jsonb(x) order by x.table_name),
        '[]'::jsonb
      )
      from not_null_state x
    ),
    'internal_rls_state', (
      select coalesce(
        jsonb_agg(to_jsonb(x) order by x.table_name),
        '[]'::jsonb
      )
      from rls_state x
    ),
    'remaining_anon_or_public_policies', (
      select coalesce(
        jsonb_agg(to_jsonb(x)),
        '[]'::jsonb
      )
      from remaining_public_policies x
    ),
    'helper_functions', jsonb_build_object(
      'is_platform_admin', to_regprocedure(
        'private.is_platform_admin()'
      ) is not null,
      'user_has_hotel_access', to_regprocedure(
        'private.user_has_hotel_access(uuid)'
      ) is not null,
      'user_has_hotel_role', to_regprocedure(
        'private.user_has_hotel_role(uuid,text[])'
      ) is not null
    ),
    'required_indexes', jsonb_build_object(
      'hotel_slug', to_regclass(
        'public.uq_hotels_slug_lower'
      ) is not null,
      'room_number_per_hotel', to_regclass(
        'public.uq_rooms_hotel_room_number'
      ) is not null,
      'hotel_info_per_hotel', to_regclass(
        'public.uq_hotel_info_hotel'
      ) is not null,
      'membership_per_hotel_user', to_regclass(
        'public.uq_hotel_users_hotel_user'
      ) is not null,
      'staff_per_hotel_auth_user', to_regclass(
        'public.uq_staff_hotel_auth_user'
      ) is not null,
      'current_subscription_per_hotel', to_regclass(
        'public.uq_hotel_current_subscription'
      ) is not null,
      'invoice_number_per_hotel', to_regclass(
        'public.uq_invoices_hotel_invoice_number'
      ) is not null
    ),
    'known_deferred_issues', jsonb_build_object(
      'invoice_balance_mismatches', (
        select mismatch_count from known_invoice_mismatches
      ),
      'active_staff_without_auth', (
        select active_staff_without_auth
        from known_staff_without_auth
      ),
      'guest_facing_rls_hardening',
        'Deferred until secure QR access tokens replace public room-number URLs',
      'vd_stay_inn_subscription',
        'Legacy active entitlement remains without hotel_subscriptions row; subscription lifecycle is Day 9'
    )
  )
) as stayqr_tenant_foundation_verification;
