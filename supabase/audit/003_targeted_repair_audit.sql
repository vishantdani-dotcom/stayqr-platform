-- StayQR Day 1 - Step 3
-- Targeted repair-detail audit
--
-- READ-ONLY.
-- This script only selects the exact records involved in the remaining
-- pre-migration decisions. It does not insert, update, delete, create,
-- enable RLS, or change any policy.
--
-- Run in Supabase Dashboard > SQL Editor using the postgres role.
-- Export the one JSON row as CSV and upload it to the Master Development Chat.

with
hotel_inventory as (
  select
    h.id as hotel_id,
    h.hotel_name,
    h.status as hotel_status,
    h.subscription_status as hotel_subscription_status,
    h.created_at,
    (select count(*) from public.rooms r where r.hotel_id = h.id) as room_count,
    (select count(*) from public.staff s where s.hotel_id = h.id) as staff_count,
    (select count(*) from public.hotel_users hu where hu.hotel_id = h.id) as membership_count,
    (select count(*) from public.hotel_info hi where hi.hotel_id = h.id) as hotel_info_count,
    (
      select count(*)
      from public.hotel_subscriptions hs
      where hs.hotel_id = h.id
        and hs.status in ('trial', 'trialing', 'active', 'past_due')
    ) as current_subscription_count
  from public.hotels h
),
hotel_info_rows as (
  select
    hi.id as hotel_info_id,
    hi.hotel_id,
    hi.hotel_name as profile_hotel_name,
    h.hotel_name as linked_hotel_name,
    hi.address,
    hi.created_at
  from public.hotel_info hi
  left join public.hotels h on h.id = hi.hotel_id
),
subscription_rows as (
  select
    hs.id as subscription_id,
    hs.hotel_id,
    h.hotel_name,
    hs.plan_id,
    sp.plan_name,
    sp.price_monthly,
    hs.status,
    hs.start_date,
    hs.end_date,
    hs.created_at
  from public.hotel_subscriptions hs
  left join public.hotels h on h.id = hs.hotel_id
  left join public.subscription_plans sp on sp.id = hs.plan_id
),
membership_rows as (
  select
    hu.id as membership_id,
    hu.hotel_id,
    h.hotel_name,
    hu.full_name,
    hu.role,
    hu.status,
    hu.user_id,
    case
      when hu.email is null then null
      else left(split_part(hu.email, '@', 1), 2) || '***@' || split_part(hu.email, '@', 2)
    end as membership_email_masked,
    case
      when au.email is null then null
      else left(split_part(au.email, '@', 1), 2) || '***@' || split_part(au.email, '@', 2)
    end as auth_email_masked,
    au.id is not null as auth_user_exists,
    case
      when hu.user_id is null or au.id is null then null
      else lower(coalesce(hu.email, '')) = lower(coalesce(au.email, ''))
    end as email_matches_auth,
    hu.created_at
  from public.hotel_users hu
  left join public.hotels h on h.id = hu.hotel_id
  left join auth.users au on au.id = hu.user_id
),
staff_rows as (
  select
    s.id as staff_id,
    s.hotel_id,
    h.hotel_name,
    s.full_name,
    s.role,
    s.status,
    s.auth_user_id,
    case
      when s.email is null then null
      else left(split_part(s.email, '@', 1), 2) || '***@' || split_part(s.email, '@', 2)
    end as staff_email_masked,
    case
      when au.email is null then null
      else left(split_part(au.email, '@', 1), 2) || '***@' || split_part(au.email, '@', 2)
    end as auth_email_masked,
    au.id is not null as auth_user_exists,
    case
      when s.auth_user_id is null or au.id is null then null
      else lower(coalesce(s.email, '')) = lower(coalesce(au.email, ''))
    end as email_matches_auth,
    s.created_at
  from public.staff s
  left join public.hotels h on h.id = s.hotel_id
  left join auth.users au on au.id = s.auth_user_id
),
active_room_session_conflicts as (
  select
    r.id as room_id,
    r.hotel_id,
    h.hotel_name,
    r.room_number,
    r.status as room_status,
    gs.id as guest_session_id,
    gs.guest_id,
    gs.status as guest_session_status,
    gs.checkin_time,
    gs.checkout_time,
    gs.extended_until,
    gs.expired_at,
    case
      when coalesce(gs.extended_until, gs.checkout_time) < now()
      then true else false
    end as session_time_has_expired,
    g.created_at as guest_created_at
  from public.rooms r
  join public.guest_sessions gs
    on gs.room_id = r.id
   and gs.hotel_id = r.hotel_id
   and gs.status = 'active'
  left join public.hotels h on h.id = r.hotel_id
  left join public.guests g on g.id = gs.guest_id
  where r.status = 'available'
),
invoice_balance_mismatches as (
  select
    i.id as invoice_id,
    i.hotel_id,
    h.hotel_name,
    i.invoice_number,
    i.invoice_status,
    i.payment_status,
    i.total_amount,
    i.paid_amount,
    i.pending_amount,
    greatest(coalesce(i.total_amount, 0) - coalesce(i.paid_amount, 0), 0)
      as expected_pending_amount,
    coalesce(i.pending_amount, 0)
      - greatest(coalesce(i.total_amount, 0) - coalesce(i.paid_amount, 0), 0)
      as pending_difference,
    i.previous_paid_amount,
    i.amount_to_collect,
    i.settled_at,
    i.created_at,
    exists (
      select 1 from public.invoice_items ii
      where ii.invoice_id = i.id
    ) as has_invoice_items,
    exists (
      select 1 from public.payment_collections pc
      where pc.invoice_id = i.id
    ) as has_linked_collections
  from public.invoices i
  left join public.hotels h on h.id = i.hotel_id
  where coalesce(i.pending_amount, 0)
    <> greatest(coalesce(i.total_amount, 0) - coalesce(i.paid_amount, 0), 0)
),
auth_user_membership_counts as (
  select
    hu.user_id,
    count(*) as membership_count,
    jsonb_agg(
      jsonb_build_object(
        'membership_id', hu.id,
        'hotel_id', hu.hotel_id,
        'hotel_name', h.hotel_name,
        'role', hu.role,
        'status', hu.status
      )
      order by h.hotel_name
    ) as memberships
  from public.hotel_users hu
  left join public.hotels h on h.id = hu.hotel_id
  where hu.user_id is not null
  group by hu.user_id
  having count(*) > 1
)
select jsonb_pretty(
  jsonb_build_object(
    'generated_at', now(),
    'purpose', 'StayQR exact production repair decision audit',
    'hotel_inventory', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.hotel_name), '[]'::jsonb)
      from hotel_inventory x
    ),
    'hotel_info_rows', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at), '[]'::jsonb)
      from hotel_info_rows x
    ),
    'subscription_rows', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at), '[]'::jsonb)
      from subscription_rows x
    ),
    'hotel_memberships', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at), '[]'::jsonb)
      from membership_rows x
    ),
    'staff_rows', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at), '[]'::jsonb)
      from staff_rows x
    ),
    'users_with_multiple_hotel_memberships', (
      select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb)
      from auth_user_membership_counts x
    ),
    'active_room_session_conflicts', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.checkin_time), '[]'::jsonb)
      from active_room_session_conflicts x
    ),
    'invoice_balance_mismatches', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at), '[]'::jsonb)
      from invoice_balance_mismatches x
    )
  )
) as stayqr_targeted_repair_audit;
