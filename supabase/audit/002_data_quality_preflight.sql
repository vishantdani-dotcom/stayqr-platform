-- StayQR Day 1 - Step 2
-- Existing production data-quality preflight
--
-- READ-ONLY: this query performs SELECT statements only.
-- It does not create, update, delete, enable RLS, or change any policy.
--
-- Run in Supabase Dashboard > SQL Editor using the postgres role.
-- Export the single JSON result as CSV and upload it back to the Master Development Chat.
--
-- Purpose:
-- 1. Find data that would fail future NOT NULL / FK / UNIQUE constraints.
-- 2. Identify cross-hotel inconsistencies before RLS is enabled.
-- 3. Decide whether legacy tables can be migrated or retired.
-- 4. Establish a safe migration baseline before building Reservations.

with
table_counts as (
  select 'analytics_events'::text as table_name, count(*)::bigint as row_count from public.analytics_events
  union all select 'feedback', count(*) from public.feedback
  union all select 'food_order_items', count(*) from public.food_order_items
  union all select 'food_orders', count(*) from public.food_orders
  union all select 'guest_sessions', count(*) from public.guest_sessions
  union all select 'guests', count(*) from public.guests
  union all select 'hotel_info', count(*) from public.hotel_info
  union all select 'hotel_subscriptions', count(*) from public.hotel_subscriptions
  union all select 'hotel_users', count(*) from public.hotel_users
  union all select 'hotels', count(*) from public.hotels
  union all select 'housekeeping_requests', count(*) from public.housekeeping_requests
  union all select 'housekeeping_tasks', count(*) from public.housekeeping_tasks
  union all select 'invoice_items', count(*) from public.invoice_items
  union all select 'invoices', count(*) from public.invoices
  union all select 'manual_charges', count(*) from public.manual_charges
  union all select 'menu_categories', count(*) from public.menu_categories
  union all select 'menu_items', count(*) from public.menu_items
  union all select 'notifications', count(*) from public.notifications
  union all select 'payment_collections', count(*) from public.payment_collections
  union all select 'payments', count(*) from public.payments
  union all select 'role_permissions', count(*) from public.role_permissions
  union all select 'room_sessions', count(*) from public.room_sessions
  union all select 'rooms', count(*) from public.rooms
  union all select 'service_requests', count(*) from public.service_requests
  union all select 'staff', count(*) from public.staff
  union all select 'staff_roles', count(*) from public.staff_roles
  union all select 'subscription_plans', count(*) from public.subscription_plans
),
null_hotel_ids as (
  select 'analytics_events'::text as table_name, count(*) filter (where hotel_id is null)::bigint as null_count from public.analytics_events
  union all select 'feedback', count(*) filter (where hotel_id is null) from public.feedback
  union all select 'food_orders', count(*) filter (where hotel_id is null) from public.food_orders
  union all select 'guest_sessions', count(*) filter (where hotel_id is null) from public.guest_sessions
  union all select 'guests', count(*) filter (where hotel_id is null) from public.guests
  union all select 'hotel_info', count(*) filter (where hotel_id is null) from public.hotel_info
  union all select 'hotel_subscriptions', count(*) filter (where hotel_id is null) from public.hotel_subscriptions
  union all select 'hotel_users', count(*) filter (where hotel_id is null) from public.hotel_users
  union all select 'housekeeping_requests', count(*) filter (where hotel_id is null) from public.housekeeping_requests
  union all select 'housekeeping_tasks', count(*) filter (where hotel_id is null) from public.housekeeping_tasks
  union all select 'invoice_items', count(*) filter (where hotel_id is null) from public.invoice_items
  union all select 'invoices', count(*) filter (where hotel_id is null) from public.invoices
  union all select 'manual_charges', count(*) filter (where hotel_id is null) from public.manual_charges
  union all select 'menu_categories', count(*) filter (where hotel_id is null) from public.menu_categories
  union all select 'menu_items', count(*) filter (where hotel_id is null) from public.menu_items
  union all select 'notifications', count(*) filter (where hotel_id is null) from public.notifications
  union all select 'payment_collections', count(*) filter (where hotel_id is null) from public.payment_collections
  union all select 'payments', count(*) filter (where hotel_id is null) from public.payments
  union all select 'room_sessions', count(*) filter (where hotel_id is null) from public.room_sessions
  union all select 'rooms', count(*) filter (where hotel_id is null) from public.rooms
  union all select 'service_requests', count(*) filter (where hotel_id is null) from public.service_requests
  union all select 'staff', count(*) filter (where hotel_id is null) from public.staff
),
status_counts as (
  select 'rooms'::text as table_name, coalesce(status, '<NULL>')::text as status, count(*)::bigint as row_count
  from public.rooms group by coalesce(status, '<NULL>')
  union all
  select 'guest_sessions', coalesce(status, '<NULL>'), count(*) from public.guest_sessions group by coalesce(status, '<NULL>')
  union all
  select 'room_sessions', coalesce(status, '<NULL>'), count(*) from public.room_sessions group by coalesce(status, '<NULL>')
  union all
  select 'food_orders', coalesce(order_status, '<NULL>'), count(*) from public.food_orders group by coalesce(order_status, '<NULL>')
  union all
  select 'service_requests', coalesce(status, '<NULL>'), count(*) from public.service_requests group by coalesce(status, '<NULL>')
  union all
  select 'housekeeping_requests', coalesce(request_status, '<NULL>'), count(*) from public.housekeeping_requests group by coalesce(request_status, '<NULL>')
  union all
  select 'housekeeping_tasks', coalesce(status, '<NULL>'), count(*) from public.housekeeping_tasks group by coalesce(status, '<NULL>')
  union all
  select 'payments', coalesce(payment_status, '<NULL>'), count(*) from public.payments group by coalesce(payment_status, '<NULL>')
  union all
  select 'invoices', coalesce(invoice_status, '<NULL>'), count(*) from public.invoices group by coalesce(invoice_status, '<NULL>')
  union all
  select 'hotel_subscriptions', coalesce(status, '<NULL>'), count(*) from public.hotel_subscriptions group by coalesce(status, '<NULL>')
),
duplicate_rooms as (
  select hotel_id, room_number, count(*)::bigint as duplicate_count
  from public.rooms
  group by hotel_id, room_number
  having count(*) > 1
),
duplicate_hotel_info as (
  select hotel_id, count(*)::bigint as duplicate_count
  from public.hotel_info
  where hotel_id is not null
  group by hotel_id
  having count(*) > 1
),
duplicate_active_subscriptions as (
  select hotel_id, count(*)::bigint as active_subscription_count
  from public.hotel_subscriptions
  where status in ('trial', 'trialing', 'active', 'past_due')
  group by hotel_id
  having count(*) > 1
),
duplicate_staff_auth as (
  select auth_user_id, count(*)::bigint as duplicate_count
  from public.staff
  where auth_user_id is not null
  group by auth_user_id
  having count(*) > 1
),
duplicate_hotel_user_auth as (
  select user_id, count(*)::bigint as duplicate_count
  from public.hotel_users
  where user_id is not null
  group by user_id
  having count(*) > 1
),
duplicate_role_permissions as (
  select role_name, permission_key, count(*)::bigint as duplicate_count
  from public.role_permissions
  group by role_name, permission_key
  having count(*) > 1
),
multiple_active_sessions as (
  select hotel_id, room_id, count(*)::bigint as active_session_count
  from public.guest_sessions
  where status = 'active'
  group by hotel_id, room_id
  having count(*) > 1
),
active_session_conflicts as (
  select
    gs.id as guest_session_id,
    gs.hotel_id as session_hotel_id,
    gs.room_id,
    r.hotel_id as room_hotel_id,
    gs.guest_id,
    g.hotel_id as guest_hotel_id
  from public.guest_sessions gs
  left join public.rooms r on r.id = gs.room_id
  left join public.guests g on g.id = gs.guest_id
  where
    r.id is null
    or g.id is null
    or gs.hotel_id is null
    or r.hotel_id is distinct from gs.hotel_id
    or g.hotel_id is distinct from gs.hotel_id
),
room_session_status_conflicts as (
  select
    r.id as room_id,
    r.hotel_id,
    r.room_number,
    r.status as room_status,
    exists (
      select 1
      from public.guest_sessions gs
      where gs.room_id = r.id
        and gs.hotel_id = r.hotel_id
        and gs.status = 'active'
    ) as has_active_guest_session
  from public.rooms r
  where
    (
      r.status = 'available'
      and exists (
        select 1
        from public.guest_sessions gs
        where gs.room_id = r.id
          and gs.hotel_id = r.hotel_id
          and gs.status = 'active'
      )
    )
    or
    (
      r.status = 'occupied'
      and not exists (
        select 1
        from public.guest_sessions gs
        where gs.room_id = r.id
          and gs.hotel_id = r.hotel_id
          and gs.status = 'active'
      )
    )
),
food_order_tenant_conflicts as (
  select
    fo.id as order_id,
    fo.hotel_id as order_hotel_id,
    r.hotel_id as room_hotel_id,
    g.hotel_id as guest_hotel_id
  from public.food_orders fo
  left join public.rooms r on r.id = fo.room_id
  left join public.guests g on g.id = fo.guest_id
  where
    fo.hotel_id is null
    or (fo.room_id is not null and r.id is null)
    or (fo.guest_id is not null and g.id is null)
    or (r.id is not null and r.hotel_id is distinct from fo.hotel_id)
    or (g.id is not null and g.hotel_id is distinct from fo.hotel_id)
),
food_item_tenant_conflicts as (
  select
    foi.id as order_item_id,
    fo.hotel_id as order_hotel_id,
    mi.hotel_id as menu_item_hotel_id
  from public.food_order_items foi
  left join public.food_orders fo on fo.id = foi.order_id
  left join public.menu_items mi on mi.id = foi.menu_item_id
  where
    fo.id is null
    or mi.id is null
    or fo.hotel_id is null
    or mi.hotel_id is null
    or fo.hotel_id is distinct from mi.hotel_id
),
service_request_tenant_conflicts as (
  select
    sr.id as request_id,
    sr.hotel_id as request_hotel_id,
    r.hotel_id as room_hotel_id,
    g.hotel_id as guest_hotel_id,
    s.hotel_id as staff_hotel_id
  from public.service_requests sr
  left join public.rooms r on r.id = sr.room_id
  left join public.guests g on g.id = sr.guest_id
  left join public.staff s on s.id = coalesce(sr.assigned_to, sr.assigned_staff)
  where
    sr.hotel_id is null
    or (sr.room_id is not null and (r.id is null or r.hotel_id is distinct from sr.hotel_id))
    or (sr.guest_id is not null and (g.id is null or g.hotel_id is distinct from sr.hotel_id))
    or (
      coalesce(sr.assigned_to, sr.assigned_staff) is not null
      and (s.id is null or s.hotel_id is distinct from sr.hotel_id)
    )
),
housekeeping_request_conflicts as (
  select
    hr.id as request_id,
    hr.hotel_id as request_hotel_id,
    r.hotel_id as room_hotel_id,
    g.hotel_id as guest_hotel_id,
    s.hotel_id as staff_hotel_id
  from public.housekeeping_requests hr
  left join public.rooms r on r.id = hr.room_id
  left join public.guests g on g.id = hr.guest_id
  left join public.staff s on s.id = hr.assigned_staff
  where
    (hr.room_id is not null and (r.id is null or r.hotel_id is distinct from hr.hotel_id))
    or (hr.guest_id is not null and (g.id is null or g.hotel_id is distinct from hr.hotel_id))
    or (hr.assigned_staff is not null and (s.id is null or s.hotel_id is distinct from hr.hotel_id))
),
housekeeping_task_conflicts as (
  select
    ht.id as task_id,
    ht.hotel_id as task_hotel_id,
    r.hotel_id as room_hotel_id
  from public.housekeeping_tasks ht
  left join public.rooms r on r.id = ht.room_id
  where
    ht.hotel_id is null
    or (ht.room_id is not null and (r.id is null or r.hotel_id is distinct from ht.hotel_id))
),
invoice_tenant_conflicts as (
  select
    i.id as invoice_id,
    i.hotel_id as invoice_hotel_id,
    r.hotel_id as room_hotel_id,
    g.hotel_id as guest_hotel_id
  from public.invoices i
  left join public.rooms r on r.id = i.room_id
  left join public.guests g on g.id = i.guest_id
  where
    i.hotel_id is null
    or (i.room_id is not null and (r.id is null or r.hotel_id is distinct from i.hotel_id))
    or (i.guest_id is not null and (g.id is null or g.hotel_id is distinct from i.hotel_id))
),
invoice_item_tenant_conflicts as (
  select
    ii.id as invoice_item_id,
    ii.hotel_id as item_hotel_id,
    i.hotel_id as invoice_hotel_id,
    g.hotel_id as guest_hotel_id,
    r.hotel_id as room_hotel_id
  from public.invoice_items ii
  left join public.invoices i on i.id = ii.invoice_id
  left join public.guests g on g.id = ii.guest_id
  left join public.rooms r on r.id = ii.room_id
  where
    i.id is null
    or ii.hotel_id is distinct from i.hotel_id
    or (ii.guest_id is not null and (g.id is null or g.hotel_id is distinct from ii.hotel_id))
    or (ii.room_id is not null and (r.id is null or r.hotel_id is distinct from ii.hotel_id))
),
payment_tenant_conflicts as (
  select
    p.id as payment_id,
    p.hotel_id as payment_hotel_id,
    r.hotel_id as room_hotel_id,
    g.hotel_id as guest_hotel_id,
    i.hotel_id as invoice_hotel_id
  from public.payments p
  left join public.rooms r on r.id = p.room_id
  left join public.guests g on g.id = p.guest_id
  left join public.invoices i on i.id = p.invoice_id
  where
    p.hotel_id is null
    or (p.room_id is not null and (r.id is null or r.hotel_id is distinct from p.hotel_id))
    or (p.guest_id is not null and (g.id is null or g.hotel_id is distinct from p.hotel_id))
    or (p.invoice_id is not null and (i.id is null or i.hotel_id is distinct from p.hotel_id))
),
payment_collection_conflicts as (
  select
    pc.id as collection_id,
    pc.hotel_id as collection_hotel_id,
    p.hotel_id as payment_hotel_id,
    i.hotel_id as invoice_hotel_id,
    r.hotel_id as room_hotel_id,
    g.hotel_id as guest_hotel_id,
    s.hotel_id as collector_hotel_id
  from public.payment_collections pc
  left join public.payments p on p.id = pc.payment_id
  left join public.invoices i on i.id = pc.invoice_id
  left join public.rooms r on r.id = pc.room_id
  left join public.guests g on g.id = pc.guest_id
  left join public.staff s on s.id = pc.collected_by
  where
    p.id is null
    or p.hotel_id is distinct from pc.hotel_id
    or (pc.invoice_id is not null and (i.id is null or i.hotel_id is distinct from pc.hotel_id))
    or (pc.room_id is not null and (r.id is null or r.hotel_id is distinct from pc.hotel_id))
    or (pc.guest_id is not null and (g.id is null or g.hotel_id is distinct from pc.hotel_id))
    or (pc.collected_by is not null and (s.id is null or s.hotel_id is distinct from pc.hotel_id))
),
manual_charge_conflicts as (
  select
    mc.id as charge_id,
    mc.hotel_id as charge_hotel_id,
    r.hotel_id as room_hotel_id,
    g.hotel_id as guest_hotel_id
  from public.manual_charges mc
  left join public.rooms r on r.id = mc.room_id
  left join public.guests g on g.id = mc.guest_id
  where
    mc.hotel_id is null
    or (mc.room_id is not null and (r.id is null or r.hotel_id is distinct from mc.hotel_id))
    or (mc.guest_id is not null and (g.id is null or g.hotel_id is distinct from mc.hotel_id))
),
menu_item_conflicts as (
  select
    mi.id as menu_item_id,
    mi.hotel_id as item_hotel_id,
    mc.hotel_id as category_hotel_id
  from public.menu_items mi
  left join public.menu_categories mc on mc.id = mi.category_id
  where
    mi.hotel_id is null
    or (mi.category_id is not null and (mc.id is null or mc.hotel_id is distinct from mi.hotel_id))
),
staff_auth_issues as (
  select
    count(*) filter (where s.status = 'active' and s.auth_user_id is null)::bigint as active_staff_without_auth_user,
    count(*) filter (
      where s.auth_user_id is not null
        and not exists (select 1 from auth.users au where au.id = s.auth_user_id)
    )::bigint as staff_auth_user_missing,
    count(*) filter (
      where s.auth_user_id is not null
        and exists (
          select 1 from auth.users au
          where au.id = s.auth_user_id
            and lower(coalesce(au.email, '')) <> lower(coalesce(s.email, ''))
        )
    )::bigint as staff_email_mismatch
  from public.staff s
),
hotel_user_auth_issues as (
  select
    count(*) filter (where hu.status = 'active' and hu.user_id is null)::bigint as active_memberships_without_user_id,
    count(*) filter (
      where hu.user_id is not null
        and not exists (select 1 from auth.users au where au.id = hu.user_id)
    )::bigint as membership_auth_user_missing,
    count(*) filter (
      where hu.user_id is not null
        and exists (
          select 1 from auth.users au
          where au.id = hu.user_id
            and lower(coalesce(au.email, '')) <> lower(coalesce(hu.email, ''))
        )
    )::bigint as membership_email_mismatch
  from public.hotel_users hu
),
hotel_readiness as (
  select
    h.id as hotel_id,
    h.status,
    h.subscription_status,
    exists (select 1 from public.hotel_info hi where hi.hotel_id = h.id) as has_hotel_info,
    exists (select 1 from public.rooms r where r.hotel_id = h.id) as has_rooms,
    exists (
      select 1 from public.staff s
      where s.hotel_id = h.id and s.status = 'active'
    ) as has_active_staff,
    exists (
      select 1 from public.hotel_users hu
      where hu.hotel_id = h.id and hu.status = 'active'
    ) as has_active_membership,
    exists (
      select 1 from public.hotel_subscriptions hs
      where hs.hotel_id = h.id
        and hs.status in ('trial', 'trialing', 'active', 'past_due')
    ) as has_current_subscription
  from public.hotels h
)
select jsonb_pretty(
  jsonb_build_object(
    'generated_at', now(),
    'purpose', 'StayQR pre-migration production data-quality audit',
    'table_counts', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.table_name), '[]'::jsonb)
      from table_counts x
    ),
    'null_hotel_ids', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.table_name), '[]'::jsonb)
      from null_hotel_ids x
      where x.null_count > 0
    ),
    'status_counts', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.table_name, x.status), '[]'::jsonb)
      from status_counts x
    ),
    'duplicate_rooms', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.hotel_id, x.room_number), '[]'::jsonb)
      from duplicate_rooms x
    ),
    'duplicate_hotel_info', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.hotel_id), '[]'::jsonb)
      from duplicate_hotel_info x
    ),
    'duplicate_active_subscriptions', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.hotel_id), '[]'::jsonb)
      from duplicate_active_subscriptions x
    ),
    'duplicate_staff_auth', (
      select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb)
      from duplicate_staff_auth x
    ),
    'duplicate_hotel_user_auth', (
      select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb)
      from duplicate_hotel_user_auth x
    ),
    'duplicate_role_permissions', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.role_name, x.permission_key), '[]'::jsonb)
      from duplicate_role_permissions x
    ),
    'multiple_active_sessions_per_room', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.hotel_id, x.room_id), '[]'::jsonb)
      from multiple_active_sessions x
    ),
    'active_session_tenant_or_orphan_conflicts', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.guest_session_id), '[]'::jsonb)
      from active_session_conflicts x
    ),
    'room_session_status_conflicts', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.hotel_id, x.room_number), '[]'::jsonb)
      from room_session_status_conflicts x
    ),
    'food_order_tenant_conflicts', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.order_id), '[]'::jsonb)
      from food_order_tenant_conflicts x
    ),
    'food_item_tenant_conflicts', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.order_item_id), '[]'::jsonb)
      from food_item_tenant_conflicts x
    ),
    'service_request_tenant_conflicts', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.request_id), '[]'::jsonb)
      from service_request_tenant_conflicts x
    ),
    'housekeeping_request_tenant_conflicts', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.request_id), '[]'::jsonb)
      from housekeeping_request_conflicts x
    ),
    'housekeeping_task_tenant_conflicts', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.task_id), '[]'::jsonb)
      from housekeeping_task_conflicts x
    ),
    'invoice_tenant_conflicts', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.invoice_id), '[]'::jsonb)
      from invoice_tenant_conflicts x
    ),
    'invoice_item_tenant_conflicts', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.invoice_item_id), '[]'::jsonb)
      from invoice_item_tenant_conflicts x
    ),
    'payment_tenant_conflicts', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.payment_id), '[]'::jsonb)
      from payment_tenant_conflicts x
    ),
    'payment_collection_tenant_conflicts', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.collection_id), '[]'::jsonb)
      from payment_collection_conflicts x
    ),
    'manual_charge_tenant_conflicts', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.charge_id), '[]'::jsonb)
      from manual_charge_conflicts x
    ),
    'menu_item_tenant_conflicts', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.menu_item_id), '[]'::jsonb)
      from menu_item_conflicts x
    ),
    'staff_auth_issues', (
      select to_jsonb(x) from staff_auth_issues x
    ),
    'hotel_user_auth_issues', (
      select to_jsonb(x) from hotel_user_auth_issues x
    ),
    'hotel_readiness', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.hotel_id), '[]'::jsonb)
      from hotel_readiness x
    ),
    'legacy_room_sessions', jsonb_build_object(
      'row_count', (select count(*) from public.room_sessions),
      'active_count', (select count(*) from public.room_sessions where status = 'active')
    ),
    'financial_null_or_invalid_amounts', jsonb_build_object(
      'negative_payments', (select count(*) from public.payments where amount < 0),
      'negative_collections', (select count(*) from public.payment_collections where amount <= 0),
      'negative_manual_charges', (select count(*) from public.manual_charges where charge_amount < 0),
      'negative_food_totals', (select count(*) from public.food_orders where total_amount < 0),
      'negative_invoice_totals', (select count(*) from public.invoices where total_amount < 0),
      'invoice_balance_mismatch', (
        select count(*)
        from public.invoices
        where coalesce(pending_amount, 0)
          <> greatest(coalesce(total_amount, 0) - coalesce(paid_amount, 0), 0)
      )
    )
  )
) as stayqr_data_quality_preflight;
