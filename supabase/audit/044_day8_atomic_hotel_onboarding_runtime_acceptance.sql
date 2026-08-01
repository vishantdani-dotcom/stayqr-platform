-- ============================================================================
-- StayQR v1.0
-- Day 8 Audit 044 REV3 — Atomic Hotel Onboarding Runtime Acceptance
--
-- PURPOSE
-- Runs the new Migration 018 onboarding workflow as a real authenticated
-- Platform Admin and proves that:
--   - one RPC creates the complete initial hotel/owner/settings/trial stack;
--   - repeated request_id calls are idempotent;
--   - colliding hotel_slug requests receive a safe unique slug;
--   - resumable steps are server-validated;
--   - incomplete steps cannot be falsely marked complete;
--   - trial activation is idempotent;
--   - readiness is computed and persisted;
--   - anonymous execution remains blocked.
--
-- SAFETY
-- - Run once in Supabase SQL Editor with role: postgres.
-- - Every synthetic hotel, staff, subscription and configuration row is
--   created inside a reversible subtransaction and rolled back.
-- - Existing production hotel data is not edited.
-- - The audit helper remains private and is executable only by postgres.
--
-- REV3 FIXES
-- - public.subscription_plans uses `plan_name`, not `name`.
-- - public.hotels still has a legacy globally unique email constraint. REV2
--   reused the existing Platform Admin's hotel email as each synthetic hotel's
--   contact email, so bootstrap correctly rejected the duplicate before any
--   synthetic tenant could be committed.
-- - REV3 gives each reversible synthetic hotel its own unique contact email.
--   The authenticated Platform Admin remains the owner actor, which is valid
--   because staff and compatibility memberships are unique per hotel.
--
-- The REV2 failure occurred inside the audit's rollback subtransaction.
-- Production hotel, staff and subscription counts remained unchanged.
--
-- EXPECTED RESULT
-- 24 rows, and every passed value must be true.
-- ============================================================================

create or replace function private.run_day8_atomic_onboarding_acceptance_20260727()
returns table (
  test_name text,
  passed boolean,
  details text
)
language plpgsql
security invoker
set search_path = ''
as $audit$
declare
  actor_user_id uuid;
  actor_email text;
  plan_id_value uuid;
  plan_name_value text;

  request_id_one uuid := gen_random_uuid();
  request_id_two uuid := gen_random_uuid();
  audit_suffix text := left(replace(gen_random_uuid()::text, '-', ''), 12);
  requested_slug text;
  contact_email_one text;
  contact_email_two text;
  payload_one jsonb;
  payload_two jsonb;

  first_result jsonb;
  idempotent_result jsonb;
  second_result jsonb;
  trial_result jsonb;
  save_result jsonb;
  draft_result jsonb;
  readiness_result jsonb;
  refresh_result jsonb;

  hotel_one_id uuid;
  hotel_two_id uuid;
  hotel_one_slug text;
  hotel_two_slug text;
  owner_staff_id uuid;
  subscription_id uuid;

  actor_resolved boolean := false;
  first_bootstrap_returned boolean := false;
  hotel_metadata_ok boolean := false;
  owner_identity_ok boolean := false;
  compatibility_membership_ok boolean := false;
  profile_settings_ok boolean := false;
  onboarding_state_ok boolean := false;
  default_floor_ok boolean := false;
  invoice_sequence_ok boolean := false;
  trial_subscription_ok boolean := false;
  readiness_shape_ok boolean := false;
  readiness_expected_incomplete boolean := false;
  idempotent_request_ok boolean := false;
  idempotent_no_duplicate_ok boolean := false;
  slug_collision_ok boolean := false;
  second_hotel_complete_stack_ok boolean := false;
  valid_step_completion_ok boolean := false;
  incomplete_step_rejected boolean := false;
  draft_step_saved_ok boolean := false;
  readiness_get_ok boolean := false;
  readiness_refresh_ok boolean := false;
  trial_idempotent_ok boolean := false;
  anon_bootstrap_blocked boolean := false;
  anon_trial_blocked boolean := false;
  no_existing_data_mutated boolean := false;
  rollback_verified boolean := false;

  before_hotel_count bigint := 0;
  before_staff_count bigint := 0;
  before_subscription_count bigint := 0;
  after_hotel_count bigint := 0;
  after_staff_count bigint := 0;
  after_subscription_count bigint := 0;

  role_switched boolean := false;
  rejection_message text;
  results jsonb := '[]'::jsonb;
begin
  -- ------------------------------------------------------------------------
  -- Resolve production-safe test prerequisites as postgres.
  -- ------------------------------------------------------------------------
  select pa.user_id, lower(au.email)
  into actor_user_id, actor_email
  from public.platform_admins pa
  join auth.users au on au.id = pa.user_id
  where pa.status = 'active'
    and au.email is not null
    and coalesce(au.banned_until, '-infinity'::timestamptz) <= now()
  order by pa.created_at
  limit 1;

  select sp.id, sp.plan_name
  into plan_id_value, plan_name_value
  from public.subscription_plans sp
  where sp.status = 'active'
  order by sp.created_at
  limit 1;

  actor_resolved :=
    actor_user_id is not null
    and actor_email is not null
    and plan_id_value is not null;

  select count(*) into before_hotel_count from public.hotels;
  select count(*) into before_staff_count from public.staff;
  select count(*) into before_subscription_count
  from public.hotel_subscriptions;

  requested_slug := 'stayqr-day8-audit-' || audit_suffix;
  contact_email_one :=
    'day8-audit-one-' || audit_suffix || '@stayqr.test';
  contact_email_two :=
    'day8-audit-two-' || audit_suffix || '@stayqr.test';

  payload_one := jsonb_build_object(
    'request_id', request_id_one,
    'hotel_name', 'StayQR Day 8 Audit Hotel ' || audit_suffix,
    'owner_name', 'Day 8 Audit Owner',
    'contact_email', contact_email_one,
    'phone', '9999999999',
    'address', 'Temporary audit address',
    'city', 'Nagpur',
    'state', 'Maharashtra',
    'location', 'Nagpur, Maharashtra',
    'timezone', 'Asia/Kolkata',
    'currency_code', 'INR',
    'hotel_slug', requested_slug,
    'plan_id', plan_id_value,
    'trial_days', 14,
    'default_tax_percent', 12,
    'prices_include_tax', false,
    'checkin_time', '14:00',
    'checkout_time', '11:00',
    'cancellation_policy', 'Temporary Day 8 audit policy.',
    'house_rules', 'Temporary Day 8 audit rules.',
    'terms_and_conditions', 'Temporary Day 8 audit terms.',
    'invoice_notes', 'Temporary Day 8 audit invoice note.'
  );

  payload_two := jsonb_build_object(
    'request_id', request_id_two,
    'hotel_name', 'StayQR Day 8 Collision Hotel ' || audit_suffix,
    'owner_name', 'Day 8 Audit Owner',
    'contact_email', contact_email_two,
    'phone', '9999999998',
    'address', 'Temporary collision audit address',
    'city', 'Nagpur',
    'state', 'Maharashtra',
    'location', 'Nagpur, Maharashtra',
    'timezone', 'Asia/Kolkata',
    'currency_code', 'INR',
    'hotel_slug', requested_slug,
    'plan_id', plan_id_value,
    'trial_days', 14
  );

  -- ------------------------------------------------------------------------
  -- Reversible authenticated runtime acceptance.
  -- ------------------------------------------------------------------------
  begin
    if not actor_resolved then
      raise exception
        'An active Platform Admin and active subscription plan are required.';
    end if;

    perform set_config(
      'request.jwt.claim.sub',
      actor_user_id::text,
      true
    );
    perform set_config(
      'request.jwt.claim.role',
      'authenticated',
      true
    );

    execute 'set local role authenticated';
    role_switched := true;

    first_result :=
      public.bootstrap_hotel_onboarding(payload_one);

    hotel_one_id := (first_result ->> 'hotel_id')::uuid;
    hotel_one_slug := first_result ->> 'hotel_slug';
    owner_staff_id := (first_result ->> 'owner_staff_id')::uuid;
    subscription_id :=
      (first_result -> 'trial' ->> 'subscription_id')::uuid;

    first_bootstrap_returned :=
      hotel_one_id is not null
      and hotel_one_slug is not null
      and owner_staff_id is not null
      and subscription_id is not null
      and coalesce(
        (first_result ->> 'idempotent')::boolean,
        true
      ) = false;

    select exists (
      select 1
      from public.hotels h
      where h.id = hotel_one_id
        and h.hotel_name =
          'StayQR Day 8 Audit Hotel ' || audit_suffix
        and h.slug = hotel_one_slug
        and h.slug = requested_slug
        and h.email = contact_email_one
        and h.status = 'active'
        and h.subscription_status = 'trialing'
        and h.timezone = 'Asia/Kolkata'
        and h.currency_code = 'INR'
        and h.city = 'Nagpur'
        and h.state = 'Maharashtra'
    )
    into hotel_metadata_ok;

    select exists (
      select 1
      from public.staff s
      where s.id = owner_staff_id
        and s.hotel_id = hotel_one_id
        and s.auth_user_id = actor_user_id
        and s.email = actor_email
        and s.status = 'active'
        and lower(replace(trim(s.role::text), ' ', '_')) = 'owner'
    )
    into owner_identity_ok;

    select exists (
      select 1
      from public.hotel_users hu
      where hu.hotel_id = hotel_one_id
        and hu.user_id = actor_user_id
        and hu.status = 'active'
        and lower(replace(trim(hu.role::text), ' ', '_')) = 'owner'
    )
    into compatibility_membership_ok;

    select
      exists (
        select 1
        from public.hotel_info hi
        where hi.hotel_id = hotel_one_id
          and hi.hotel_name =
            'StayQR Day 8 Audit Hotel ' || audit_suffix
      )
      and exists (
        select 1
        from public.hotel_settings hs
        where hs.hotel_id = hotel_one_id
          and hs.default_tax_percent = 12
          and hs.prices_include_tax = false
          and hs.checkin_time = '14:00'::time
          and hs.checkout_time = '11:00'::time
      )
    into profile_settings_ok;

    select exists (
      select 1
      from public.hotel_onboarding ho
      where ho.hotel_id = hotel_one_id
        and ho.owner_user_id = actor_user_id
        and ho.bootstrap_request_id = request_id_one
        and ho.onboarding_source = 'platform_admin'
        and ho.status = 'in_progress'
        and ho.current_step = 'room_types'
        and ho.completed_steps @>
          array[
            'account',
            'hotel_details',
            'policies',
            'subscription'
          ]::text[]
        and ho.form_state ? 'hotel_details'
        and ho.form_state ? 'policies'
        and ho.form_state ? 'subscription'
    )
    into onboarding_state_ok;

    select exists (
      select 1
      from public.floors f
      where f.hotel_id = hotel_one_id
        and upper(f.code) = 'DEFAULT'
        and f.name = 'Default Floor'
        and f.floor_number = 0
        and f.is_active
    )
    into default_floor_ok;

    select exists (
      select 1
      from public.invoice_number_sequences ins
      where ins.hotel_id = hotel_one_id
        and ins.sequence_year =
          extract(year from now())::integer
        and ins.last_number = 0
        and ins.padding = 6
        and length(trim(ins.prefix)) > 0
    )
    into invoice_sequence_ok;

    select exists (
      select 1
      from public.hotel_subscriptions hsub
      where hsub.id = subscription_id
        and hsub.hotel_id = hotel_one_id
        and hsub.plan_id = plan_id_value
        and hsub.status = 'trialing'
        and hsub.trial_started_at is not null
        and hsub.trial_ends_at > hsub.trial_started_at
        and hsub.end_date = hsub.trial_ends_at
        and hsub.metadata ->> 'source' = 'day8_onboarding'
    )
    into trial_subscription_ok;

    readiness_result := first_result -> 'readiness';

    readiness_shape_ok :=
      jsonb_typeof(readiness_result) = 'object'
      and readiness_result ? 'ready'
      and readiness_result ? 'checklist'
      and readiness_result ? 'missing'
      and (readiness_result -> 'checklist') ? 'hotel_details'
      and (readiness_result -> 'checklist') ? 'rooms'
      and (readiness_result -> 'checklist') ? 'subscription'
      and (readiness_result -> 'checklist') ? 'qr_ready';

    readiness_expected_incomplete :=
      coalesce((readiness_result ->> 'ready')::boolean, true) = false
      and coalesce(
        (readiness_result
          -> 'checklist'
          ->> 'hotel_details')::boolean,
        false
      )
      and coalesce(
        (readiness_result
          -> 'checklist'
          ->> 'owner_identity')::boolean,
        false
      )
      and coalesce(
        (readiness_result
          -> 'checklist'
          ->> 'settings')::boolean,
        false
      )
      and coalesce(
        (readiness_result
          -> 'checklist'
          ->> 'floors')::boolean,
        false
      )
      and coalesce(
        (readiness_result
          -> 'checklist'
          ->> 'subscription')::boolean,
        false
      )
      and not coalesce(
        (readiness_result
          -> 'checklist'
          ->> 'room_types')::boolean,
        true
      )
      and not coalesce(
        (readiness_result
          -> 'checklist'
          ->> 'rooms')::boolean,
        true
      )
      and (readiness_result -> 'missing')
        @> '["room_types","rooms"]'::jsonb;

    idempotent_result :=
      public.bootstrap_hotel_onboarding(payload_one);

    idempotent_request_ok :=
      (idempotent_result ->> 'hotel_id')::uuid = hotel_one_id
      and idempotent_result ->> 'hotel_slug' = hotel_one_slug
      and coalesce(
        (idempotent_result ->> 'idempotent')::boolean,
        false
      );

    select
      (select count(*)
       from public.hotels h
       where h.id = hotel_one_id) = 1
      and
      (select count(*)
       from public.hotel_onboarding ho
       where ho.bootstrap_request_id = request_id_one) = 1
      and
      (select count(*)
       from public.hotel_subscriptions hsub
       where hsub.hotel_id = hotel_one_id
         and hsub.status in (
           'trial',
           'trialing',
           'active',
           'past_due'
         )) = 1
    into idempotent_no_duplicate_ok;

    second_result :=
      public.bootstrap_hotel_onboarding(payload_two);

    hotel_two_id := (second_result ->> 'hotel_id')::uuid;
    hotel_two_slug := second_result ->> 'hotel_slug';

    slug_collision_ok :=
      hotel_two_id is not null
      and hotel_two_id <> hotel_one_id
      and hotel_two_slug <> hotel_one_slug
      and hotel_two_slug like requested_slug || '-%';

    select
      exists (
        select 1
        from public.hotels h
        where h.id = hotel_two_id
          and h.slug = hotel_two_slug
          and h.email = contact_email_two
      )
      and exists (
        select 1
        from public.staff s
        where s.hotel_id = hotel_two_id
          and s.auth_user_id = actor_user_id
          and s.status = 'active'
          and lower(replace(trim(s.role::text), ' ', '_')) = 'owner'
      )
      and exists (
        select 1
        from public.hotel_settings hs
        where hs.hotel_id = hotel_two_id
      )
      and exists (
        select 1
        from public.hotel_subscriptions hsub
        where hsub.hotel_id = hotel_two_id
          and hsub.status = 'trialing'
      )
    into second_hotel_complete_stack_ok;

    save_result :=
      public.save_hotel_onboarding_step(
        hotel_one_id,
        'policies',
        jsonb_build_object(
          'complete',
          true,
          'verified_by_audit',
          true
        )
      );

    valid_step_completion_ok :=
      coalesce(
        (save_result ->> 'step_ready')::boolean,
        false
      )
      and coalesce(
        (save_result ->> 'complete_requested')::boolean,
        false
      )
      and save_result ->> 'next_step' = 'room_types'
      and (
        save_result
        -> 'onboarding'
        -> 'completed_steps'
      ) @> '["policies"]'::jsonb;

    rejection_message := null;
    begin
      perform public.save_hotel_onboarding_step(
        hotel_one_id,
        'room_types',
        jsonb_build_object(
          'complete',
          true,
          'attempt',
          'must fail before room types exist'
        )
      );
    exception when others then
      rejection_message := sqlerrm;
      incomplete_step_rejected :=
        lower(sqlerrm) like
          '%server readiness check is false%';
    end;

    draft_result :=
      public.save_hotel_onboarding_step(
        hotel_one_id,
        'room_types',
        jsonb_build_object(
          'complete',
          false,
          'draft_note',
          'Saved without falsely completing the step.'
        )
      );

    draft_step_saved_ok :=
      coalesce(
        (draft_result ->> 'complete_requested')::boolean,
        true
      ) = false
      and draft_result
        -> 'onboarding'
        -> 'form_state'
        -> 'room_types'
        ->> 'draft_note'
        = 'Saved without falsely completing the step.'
      and draft_result
        -> 'onboarding'
        ->> 'current_step'
        = 'room_types';

    readiness_result :=
      public.get_hotel_onboarding_readiness(hotel_one_id);

    readiness_get_ok :=
      jsonb_typeof(readiness_result) = 'object'
      and readiness_result ? 'checklist'
      and coalesce(
        (readiness_result ->> 'ready')::boolean,
        true
      ) = false;

    refresh_result :=
      public.refresh_hotel_onboarding_readiness(hotel_one_id);

    select
      jsonb_typeof(refresh_result) = 'object'
      and refresh_result ? 'checklist'
      and exists (
        select 1
        from public.hotel_onboarding ho
        where ho.hotel_id = hotel_one_id
          and ho.readiness_state = refresh_result
          and ho.status = 'in_progress'
      )
    into readiness_refresh_ok;

    trial_result :=
      public.activate_hotel_trial(
        hotel_one_id,
        plan_id_value,
        14
      );

    trial_idempotent_ok :=
      (trial_result ->> 'subscription_id')::uuid =
        subscription_id
      and coalesce(
        (trial_result ->> 'idempotent')::boolean,
        false
      )
      and (
        select count(*) = 1
        from public.hotel_subscriptions hsub
        where hsub.hotel_id = hotel_one_id
          and hsub.status in (
            'trial',
            'trialing',
            'active',
            'past_due'
          )
      );

    execute 'reset role';
    role_switched := false;

    -- Real anonymous permission probes.
    perform set_config(
      'request.jwt.claim.sub',
      '',
      true
    );
    perform set_config(
      'request.jwt.claim.role',
      'anon',
      true
    );

    execute 'set local role anon';
    role_switched := true;

    begin
      perform public.bootstrap_hotel_onboarding(payload_one);
    exception
      when insufficient_privilege then
        anon_bootstrap_blocked := true;
      when others then
        anon_bootstrap_blocked :=
          lower(sqlerrm) like '%permission denied%';
    end;

    begin
      perform public.activate_hotel_trial(
        hotel_one_id,
        plan_id_value,
        14
      );
    exception
      when insufficient_privilege then
        anon_trial_blocked := true;
      when others then
        anon_trial_blocked :=
          lower(sqlerrm) like '%permission denied%';
    end;

    execute 'reset role';
    role_switched := false;

    -- Force rollback of every synthetic record.
    raise exception using
      errcode = 'P7918',
      message =
        'StayQR Day 8 atomic onboarding acceptance rollback';
  exception
    when sqlstate 'P7918' then
      null;
    when others then
      if role_switched then
        begin
          execute 'reset role';
        exception when others then
          null;
        end;
        role_switched := false;
      end if;

      rejection_message := coalesce(
        rejection_message || E'\n',
        ''
      ) || format(
        'Audit harness failure [%s] %s',
        sqlstate,
        sqlerrm
      );
  end;

  -- ------------------------------------------------------------------------
  -- Verify the reversible audit left no production records behind.
  -- ------------------------------------------------------------------------
  select count(*) into after_hotel_count from public.hotels;
  select count(*) into after_staff_count from public.staff;
  select count(*) into after_subscription_count
  from public.hotel_subscriptions;

  no_existing_data_mutated :=
    before_hotel_count = after_hotel_count
    and before_staff_count = after_staff_count
    and before_subscription_count = after_subscription_count;

  rollback_verified :=
    not exists (
      select 1
      from public.hotel_onboarding ho
      where ho.bootstrap_request_id in (
        request_id_one,
        request_id_two
      )
    )
    and not exists (
      select 1
      from public.hotels h
      where h.slug = requested_slug
         or h.slug like requested_slug || '-%'
    )
    and no_existing_data_mutated;

  -- ------------------------------------------------------------------------
  -- Final 24-row acceptance result.
  -- ------------------------------------------------------------------------
  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '01_actor_and_plan_resolved',
    'passed', actor_resolved,
    'details', format(
      'Actor=%s; active plan=%s.',
      coalesce(actor_email, 'NOT FOUND'),
      coalesce(plan_name_value, 'NOT FOUND')
    )
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '02_atomic_bootstrap_returned_complete_identity',
    'passed', first_bootstrap_returned,
    'details',
      'Bootstrap returned hotel, slug, owner staff, subscription and non-idempotent first-call identifiers.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '03_hotel_metadata_created',
    'passed', hotel_metadata_ok,
    'details',
      'Hotel name, slug, status, trial state, timezone, currency and location were created atomically.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '04_owner_staff_identity_created',
    'passed', owner_identity_ok,
    'details',
      'Authenticated actor became the active authoritative owner of the new hotel.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '05_compatibility_membership_synced',
    'passed', compatibility_membership_ok,
    'details',
      'The locked staff-to-hotel_users compatibility mirror contains the active owner.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '06_profile_and_settings_created',
    'passed', profile_settings_ok,
    'details',
      'Neutral hotel profile and structured tax/policy settings were created.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '07_onboarding_state_created',
    'passed', onboarding_state_ok,
    'details',
      'Resumable onboarding state, request ID, owner, completed steps and saved form data were created.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '08_default_floor_created',
    'passed', default_floor_ok,
    'details',
      'A normalized Default Floor was created for the fresh hotel.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '09_invoice_sequence_created',
    'passed', invoice_sequence_ok,
    'details',
      'Current-year hotel-scoped invoice numbering was initialized.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '10_trial_subscription_created',
    'passed', trial_subscription_ok,
    'details',
      'The approved active plan received one explicit trialing subscription with valid dates and metadata.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '11_readiness_shape_valid',
    'passed', readiness_shape_ok,
    'details',
      'Bootstrap returned the server readiness object and major checklist categories.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '12_fresh_hotel_correctly_incomplete',
    'passed', readiness_expected_incomplete,
    'details',
      'Core identity/settings/floor/trial checks passed while missing room types and rooms kept readiness false.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '13_same_request_is_idempotent',
    'passed', idempotent_request_ok,
    'details',
      'Repeating the identical request ID returned the same hotel instead of creating another tenant.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '14_idempotency_created_no_duplicates',
    'passed', idempotent_no_duplicate_ok,
    'details',
      'One request ID produced one hotel, one onboarding row and one current subscription.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '15_slug_collision_resolved',
    'passed', slug_collision_ok,
    'details', format(
      'Requested slug=%s; collision-safe second slug=%s.',
      requested_slug,
      coalesce(hotel_two_slug, 'NOT CREATED')
    )
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '16_second_hotel_stack_complete',
    'passed', second_hotel_complete_stack_ok,
    'details',
      'A separate request created a separate hotel with owner, settings and trial stack.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '17_valid_step_completion',
    'passed', valid_step_completion_ok,
    'details',
      'A server-ready policies step completed and advanced to room_types.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '18_incomplete_step_rejected',
    'passed', incomplete_step_rejected,
    'details', coalesce(
      rejection_message,
      'Room types completion was rejected because no room type existed.'
    )
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '19_draft_step_saved_without_completion',
    'passed', draft_step_saved_ok,
    'details',
      'Room-type draft data was saved without falsely completing or advancing the step.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '20_readiness_get_and_refresh',
    'passed', readiness_get_ok and readiness_refresh_ok,
    'details',
      'Authorized readiness retrieval and persisted refresh both succeeded.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '21_trial_activation_idempotent',
    'passed', trial_idempotent_ok,
    'details',
      'Repeating trial activation returned the existing subscription and created no duplicate.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '22_anonymous_onboarding_and_trial_blocked',
    'passed', anon_bootstrap_blocked and anon_trial_blocked,
    'details',
      'Real anon role calls could execute neither hotel bootstrap nor trial activation.'
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '23_existing_production_counts_unchanged',
    'passed', no_existing_data_mutated,
    'details', format(
      'Hotels %s→%s; staff %s→%s; subscriptions %s→%s.',
      before_hotel_count,
      after_hotel_count,
      before_staff_count,
      after_staff_count,
      before_subscription_count,
      after_subscription_count
    )
  ));

  results := results || jsonb_build_array(jsonb_build_object(
    'test_name', '24_synthetic_acceptance_data_rolled_back',
    'passed', rollback_verified,
    'details',
      'Both synthetic hotels and every dependent onboarding record were rolled back.'
  ));

  return query
  select item.test_name, item.passed, item.details
  from jsonb_to_recordset(results)
    as item(test_name text, passed boolean, details text)
  order by item.test_name;
exception when others then
  if role_switched then
    begin
      execute 'reset role';
    exception when others then
      null;
    end;
  end if;

  return query
  select
    '00_audit_harness_error'::text,
    false,
    format('[%s] %s', sqlstate, sqlerrm);
end;
$audit$;

revoke all on function
  private.run_day8_atomic_onboarding_acceptance_20260727()
from public, anon, authenticated;

comment on function
  private.run_day8_atomic_onboarding_acceptance_20260727() is
  'Reversible authenticated runtime acceptance REV3 for Day 8 Migration 018 atomic hotel onboarding, idempotency, trial and readiness RPCs. Remove after evidence export.';

select test_name, passed, details
from private.run_day8_atomic_onboarding_acceptance_20260727()
order by test_name;
