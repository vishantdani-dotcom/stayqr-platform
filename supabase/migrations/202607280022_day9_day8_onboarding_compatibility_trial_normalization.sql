-- ============================================================================
-- StayQR v1.0
-- Day 9 Migration 022 — Day 8 Onboarding Compatibility and Trial Normalization
--
-- WHY THIS MIGRATION EXISTS
-- Migration 021 correctly installed server-level staff and room plan-limit
-- enforcement. A compatibility review then found that the locked Day 8 atomic
-- bootstrap inserts the first active owner staff row before it creates the
-- trial subscription. The generic staff-limit trigger would therefore reject
-- a brand-new hotel with "This hotel has no current subscription."
--
-- This bounded hotfix preserves strict plan-limit enforcement while allowing
-- only the exact first owner row created by the locked atomic bootstrap:
--   - INSERT only;
--   - role=owner, status=active;
--   - auth_user_id and created_by equal auth.uid();
--   - exact Day 8 bootstrap reconciliation marker;
--   - hotel created in the current transaction;
--   - hotel cached state is trialing;
--   - no staff, onboarding row or subscription exists yet.
--
-- If later bootstrap work fails, PostgreSQL rolls the whole bootstrap
-- transaction back, so no subscriptionless active tenant is left behind.
--
-- The migration also normalizes all future trial subscription inserts to:
--   billing_mode=trial, billing_cycle=none, amount_minor=0,
--   provider_status=trial/trialing, and matching current-period timestamps.
--
-- SAFETY
-- - Run once in Supabase SQL Editor with role: postgres.
-- - Transactional and idempotent.
-- - Does not create/delete hotels, staff, rooms or subscriptions.
-- - Existing trial rows are normalized only when their commercial fields drift.
-- - Existing paid, complimentary, expired and cancelled contracts are untouched.
--
-- EXPECTED RESULT
-- 18 rows, and every passed value must be true.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202607280022:day8-onboarding-compatibility')
);

select set_config(
  'stayqr.subscription_event_source',
  'migration_022',
  true
);

-- ============================================================================
-- 0. PRE-MIGRATION ASSERTIONS
-- ============================================================================

do $preflight$
begin
  if to_regprocedure(
    'public.bootstrap_hotel_onboarding(jsonb)'
  ) is null
     or to_regprocedure(
       'public.activate_hotel_trial(uuid,uuid,integer)'
     ) is null
     or to_regprocedure(
       'private.assert_subscription_capacity_internal_20260728(uuid,uuid,integer,integer)'
     ) is null
  then
    raise exception
      'Migration 022 stopped: Day 8 bootstrap or Day 9 capacity helper is missing.';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    where t.tgrelid = 'public.staff'::regclass
      and t.tgname =
        'enforce_staff_subscription_limit_20260728'
      and not t.tgisinternal
  ) then
    raise exception
      'Migration 022 stopped: Migration 021 staff-limit trigger is missing.';
  end if;

  if position(
    'Owner identity created atomically by Day 8 hotel onboarding.'
    in pg_get_functiondef(
      'public.bootstrap_hotel_onboarding(jsonb)'::regprocedure
    )
  ) = 0 then
    raise exception
      'Migration 022 stopped: locked Day 8 bootstrap marker changed.';
  end if;
end;
$preflight$;

-- ============================================================================
-- 1. TRIAL COMMERCIAL-CONTRACT NORMALIZATION
-- ============================================================================

create or replace function
  private.normalize_subscription_lifecycle_contract_20260728()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  hotel_currency text;
begin
  if new.status in ('trial', 'trialing') then
    select h.currency_code
    into hotel_currency
    from public.hotels h
    where h.id = new.hotel_id;

    new.billing_mode := 'trial';
    new.billing_cycle := 'none';
    new.amount_minor := 0;
    new.currency_code := upper(
      coalesce(
        nullif(trim(new.currency_code), ''),
        nullif(trim(hotel_currency), ''),
        'INR'
      )
    );
    new.provider := coalesce(
      nullif(trim(new.provider), ''),
      'manual'
    );
    new.provider_status := new.status;
    new.provider_metadata := coalesce(
      new.provider_metadata,
      '{}'::jsonb
    );
    new.current_period_start := coalesce(
      new.current_period_start,
      new.trial_started_at,
      new.start_date,
      now()
    );
    new.current_period_end := coalesce(
      new.current_period_end,
      new.trial_ends_at,
      new.end_date
    );

    if new.trial_started_at is null then
      new.trial_started_at := coalesce(
        new.start_date,
        new.current_period_start,
        now()
      );
    end if;

    if new.trial_ends_at is null then
      new.trial_ends_at := coalesce(
        new.end_date,
        new.current_period_end
      );
    end if;
  end if;

  return new;
end;
$$;

revoke all on function
  private.normalize_subscription_lifecycle_contract_20260728()
from public, anon, authenticated;

drop trigger if exists
  normalize_subscription_lifecycle_contract_20260728
on public.hotel_subscriptions;

create trigger
  normalize_subscription_lifecycle_contract_20260728
before insert or update of
  status,
  billing_mode,
  billing_cycle,
  currency_code,
  amount_minor,
  provider,
  provider_status,
  trial_started_at,
  trial_ends_at,
  start_date,
  end_date,
  current_period_start,
  current_period_end
on public.hotel_subscriptions
for each row execute function
  private.normalize_subscription_lifecycle_contract_20260728();

update public.hotel_subscriptions hs
set
  billing_mode = 'trial',
  billing_cycle = 'none',
  amount_minor = 0,
  provider_status = hs.status,
  current_period_start = coalesce(
    hs.current_period_start,
    hs.trial_started_at,
    hs.start_date
  ),
  current_period_end = coalesce(
    hs.current_period_end,
    hs.trial_ends_at,
    hs.end_date
  ),
  provider_metadata = coalesce(
    hs.provider_metadata,
    '{}'::jsonb
  ),
  metadata = coalesce(hs.metadata, '{}'::jsonb)
    || jsonb_build_object(
      'migration_022_trial_contract_normalized_at',
      now()
    ),
  updated_at = now()
where hs.status in ('trial', 'trialing')
  and (
    hs.billing_mode is distinct from 'trial'
    or hs.billing_cycle is distinct from 'none'
    or hs.amount_minor is distinct from 0
    or hs.provider_status is distinct from hs.status
    or hs.current_period_start is distinct from coalesce(
      hs.current_period_start,
      hs.trial_started_at,
      hs.start_date
    )
    or hs.current_period_end is distinct from coalesce(
      hs.current_period_end,
      hs.trial_ends_at,
      hs.end_date
    )
  );

-- ============================================================================
-- 2. STRICT FIRST-OWNER BOOTSTRAP EXCEPTION
-- ============================================================================

create or replace function
  private.enforce_staff_subscription_limit_20260728()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := (select auth.uid());
  has_current_subscription boolean := false;
  is_locked_bootstrap_owner boolean := false;
begin
  if new.status <> 'active' then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and old.status = 'active'
     and new.hotel_id = old.hotel_id
  then
    return new;
  end if;

  select exists (
    select 1
    from public.hotel_subscriptions hs
    where hs.hotel_id = new.hotel_id
      and hs.status in (
        'trial',
        'trialing',
        'active',
        'past_due',
        'suspended'
      )
  )
  into has_current_subscription;

  if has_current_subscription then
    perform
      private.assert_subscription_capacity_internal_20260728(
        new.hotel_id,
        null,
        0,
        1
      );

    return new;
  end if;

  if tg_op = 'INSERT' then
    select
      actor_user_id is not null
      and new.auth_user_id = actor_user_id
      and new.created_by = actor_user_id
      and new.updated_by = actor_user_id
      and lower(replace(trim(new.role), ' ', '_')) = 'owner'
      and new.identity_reconciliation_status = 'linked'
      and new.identity_reconciliation_note =
        'Owner identity created atomically by Day 8 hotel onboarding.'
      and new.accepted_at is not null
      and new.disabled_at is null
      and exists (
        select 1
        from public.hotels h
        where h.id = new.hotel_id
          and h.status = 'active'
          and h.subscription_status = 'trialing'
          and h.created_at = transaction_timestamp()
      )
      and not exists (
        select 1
        from public.staff existing_staff
        where existing_staff.hotel_id = new.hotel_id
      )
      and not exists (
        select 1
        from public.hotel_onboarding ho
        where ho.hotel_id = new.hotel_id
      )
      and not exists (
        select 1
        from public.hotel_subscriptions hs
        where hs.hotel_id = new.hotel_id
      )
    into is_locked_bootstrap_owner;
  end if;

  if is_locked_bootstrap_owner then
    return new;
  end if;

  -- Preserve the authoritative rejection and its clear reason for every
  -- non-bootstrap active staff creation/activation.
  perform
    private.assert_subscription_capacity_internal_20260728(
      new.hotel_id,
      null,
      0,
      1
    );

  return new;
end;
$$;

revoke all on function
  private.enforce_staff_subscription_limit_20260728()
from public, anon, authenticated;

drop trigger if exists
  enforce_staff_subscription_limit_20260728
on public.staff;

create trigger enforce_staff_subscription_limit_20260728
before insert or update of hotel_id, status on public.staff
for each row execute function
  private.enforce_staff_subscription_limit_20260728();

-- ============================================================================
-- 3. POST-MIGRATION ASSERTIONS
-- ============================================================================

do $verify$
begin
  if not exists (
    select 1
    from pg_trigger t
    where t.tgrelid =
      'public.hotel_subscriptions'::regclass
      and t.tgname =
        'normalize_subscription_lifecycle_contract_20260728'
      and not t.tgisinternal
  ) then
    raise exception
      'Migration 022 failed: trial normalization trigger is missing.';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    where t.tgrelid = 'public.staff'::regclass
      and t.tgname =
        'enforce_staff_subscription_limit_20260728'
      and not t.tgisinternal
  ) then
    raise exception
      'Migration 022 failed: staff-limit trigger is missing.';
  end if;

  if exists (
    select 1
    from public.hotel_subscriptions hs
    where hs.status in ('trial', 'trialing')
      and (
        hs.billing_mode <> 'trial'
        or hs.billing_cycle <> 'none'
        or hs.amount_minor <> 0
        or hs.provider_status is distinct from hs.status
        or hs.current_period_start is null
        or hs.current_period_end is null
      )
  ) then
    raise exception
      'Migration 022 failed: an existing trial commercial contract remains inconsistent.';
  end if;

  if has_function_privilege(
    'authenticated',
    'private.enforce_staff_subscription_limit_20260728()',
    'EXECUTE'
  ) or has_function_privilege(
    'authenticated',
    'private.normalize_subscription_lifecycle_contract_20260728()',
    'EXECUTE'
  ) then
    raise exception
      'Migration 022 failed: authenticated can execute a private trigger helper directly.';
  end if;
end;
$verify$;

commit;

-- ============================================================================
-- 4. ACCEPTANCE RESULT
-- ============================================================================

with checks(test_name, passed, details) as (
  values
    (
      '01_trial_normalization_function',
      to_regprocedure(
        'private.normalize_subscription_lifecycle_contract_20260728()'
      ) is not null,
      'Trial subscription commercial fields have a dedicated normalization helper.'
    ),
    (
      '02_trial_normalization_trigger',
      exists (
        select 1
        from pg_trigger t
        where t.tgrelid =
          'public.hotel_subscriptions'::regclass
          and t.tgname =
            'normalize_subscription_lifecycle_contract_20260728'
          and not t.tgisinternal
      ),
      'Future trial insert/update operations are normalized before constraints and event logging.'
    ),
    (
      '03_existing_trial_billing_mode',
      not exists (
        select 1
        from public.hotel_subscriptions hs
        where hs.status in ('trial', 'trialing')
          and hs.billing_mode <> 'trial'
      ),
      'Every current trial uses billing_mode=trial.'
    ),
    (
      '04_existing_trial_billing_cycle',
      not exists (
        select 1
        from public.hotel_subscriptions hs
        where hs.status in ('trial', 'trialing')
          and hs.billing_cycle <> 'none'
      ),
      'Every current trial has no paid billing cycle.'
    ),
    (
      '05_existing_trial_zero_amount',
      not exists (
        select 1
        from public.hotel_subscriptions hs
        where hs.status in ('trial', 'trialing')
          and hs.amount_minor <> 0
      ),
      'Every current trial records zero billable amount.'
    ),
    (
      '06_existing_trial_provider_status',
      not exists (
        select 1
        from public.hotel_subscriptions hs
        where hs.status in ('trial', 'trialing')
          and hs.provider_status is distinct from hs.status
      ),
      'Every trial provider status matches its lifecycle status.'
    ),
    (
      '07_existing_trial_periods',
      not exists (
        select 1
        from public.hotel_subscriptions hs
        where hs.status in ('trial', 'trialing')
          and (
            hs.current_period_start is null
            or hs.current_period_end is null
            or hs.current_period_end <= hs.current_period_start
          )
      ),
      'Every current trial has a valid current-period range.'
    ),
    (
      '08_staff_limit_function_replaced',
      position(
        'is_locked_bootstrap_owner'
        in pg_get_functiondef(
          'private.enforce_staff_subscription_limit_20260728()'::regprocedure
        )
      ) > 0,
      'Staff limit enforcement contains the narrow locked-bootstrap owner exception.'
    ),
    (
      '09_staff_limit_trigger_present',
      exists (
        select 1
        from pg_trigger t
        where t.tgrelid = 'public.staff'::regclass
          and t.tgname =
            'enforce_staff_subscription_limit_20260728'
          and not t.tgisinternal
      ),
      'Active staff creation/activation remains protected by the plan-limit trigger.'
    ),
    (
      '10_bootstrap_marker_contract',
      position(
        'Owner identity created atomically by Day 8 hotel onboarding.'
        in pg_get_functiondef(
          'public.bootstrap_hotel_onboarding(jsonb)'::regprocedure
        )
      ) > 0,
      'The exception remains tied to the exact locked Day 8 bootstrap marker.'
    ),
    (
      '11_bootstrap_transaction_contract',
      position(
        'insert into public.staff'
        in lower(
          pg_get_functiondef(
            'public.bootstrap_hotel_onboarding(jsonb)'::regprocedure
          )
        )
      ) > 0
      and position(
        'trial_result := public.activate_hotel_trial'
        in lower(
          pg_get_functiondef(
            'public.bootstrap_hotel_onboarding(jsonb)'::regprocedure
          )
        )
      ) > 0,
      'Locked bootstrap still creates owner and trial in one database transaction.'
    ),
    (
      '12_non_bootstrap_capacity_helper_preserved',
      position(
        'private.assert_subscription_capacity_internal_20260728'
        in pg_get_functiondef(
          'private.enforce_staff_subscription_limit_20260728()'::regprocedure
        )
      ) > 0,
      'Every non-bootstrap active staff path still uses authoritative capacity enforcement.'
    ),
    (
      '13_room_limit_trigger_preserved',
      exists (
        select 1
        from pg_trigger t
        where t.tgrelid = 'public.rooms'::regclass
          and t.tgname =
            'enforce_room_subscription_limit_20260728'
          and not t.tgisinternal
      ),
      'Room plan-limit enforcement remains installed.'
    ),
    (
      '14_private_helpers_not_browser_executable',
      not has_function_privilege(
        'authenticated',
        'private.enforce_staff_subscription_limit_20260728()',
        'EXECUTE'
      )
      and not has_function_privilege(
        'authenticated',
        'private.normalize_subscription_lifecycle_contract_20260728()',
        'EXECUTE'
      ),
      'Browser roles cannot invoke either private compatibility helper directly.'
    ),
    (
      '15_day8_bootstrap_execute_preserved',
      has_function_privilege(
        'authenticated',
        'public.bootstrap_hotel_onboarding(jsonb)',
        'EXECUTE'
      )
      and not has_function_privilege(
        'anon',
        'public.bootstrap_hotel_onboarding(jsonb)',
        'EXECUTE'
      ),
      'Authenticated onboarding remains available while anonymous bootstrap remains blocked.'
    ),
    (
      '16_day9_lifecycle_rpcs_preserved',
      to_regprocedure(
        'public.activate_paid_subscription(uuid,jsonb)'
      ) is not null
      and to_regprocedure(
        'public.suspend_hotel_subscription(uuid,text,text)'
      ) is not null
      and to_regprocedure(
        'public.get_super_admin_dashboard()'
      ) is not null,
      'Migration 021 lifecycle and metrics RPCs remain installed.'
    ),
    (
      '17_current_subscription_uniqueness',
      not exists (
        select 1
        from (
          select hs.hotel_id
          from public.hotel_subscriptions hs
          where hs.status in (
            'trial',
            'trialing',
            'active',
            'past_due',
            'suspended'
          )
          group by hs.hotel_id
          having count(*) > 1
        ) duplicate_current
      ),
      'Compatibility hardening introduced no duplicate current subscriptions.'
    ),
    (
      '18_day8_day9_compatibility_ready',
      to_regprocedure(
        'private.normalize_subscription_lifecycle_contract_20260728()'
      ) is not null
      and position(
        'is_locked_bootstrap_owner'
        in pg_get_functiondef(
          'private.enforce_staff_subscription_limit_20260728()'::regprocedure
        )
      ) > 0,
      'Day 8 zero-to-operational onboarding is ready for a reversible post-Day-9 runtime retest.'
    )
)
select test_name, passed, details
from checks
order by test_name;
