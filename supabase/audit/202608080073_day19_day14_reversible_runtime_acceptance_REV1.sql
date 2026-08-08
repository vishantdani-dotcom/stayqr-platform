-- ============================================================================
-- StayQR v1.0
-- Day 19 / Gate 19B
-- Day 14 Reversible Runtime Acceptance REV1
-- Date: 2026-08-08
--
-- PURPOSE
-- Recreate the Day 14 controlled runtime evidence on StayQR Staging without
-- leaving synthetic hotel/guest/content/feedback/token data behind.
--
-- TARGET
-- Hotel : Day 19 QA Hotel
-- Slug  : day-19-qa-hotel
-- Room  : 101
--
-- SAFETY MODEL
-- - All business-data mutations happen inside one PL/pgSQL exception block.
-- - The block deliberately raises SQLSTATE P7914 after assertions are captured.
-- - PostgreSQL rolls back every mutation made inside that block.
-- - Local PL/pgSQL variables retain the captured assertion results.
-- - Final result rows are written only to a TEMP table after rollback.
-- - No persistent helper function, policy, trigger, schema, grant, or migration.
--
-- EXPECTED RESULT
-- - 30 rows
-- - every passed value = true
-- - final CLEANUP row = true
-- ============================================================================

set statement_timeout = '240s';

drop table if exists pg_temp.stayqr_day19_day14_runtime_results;

create temporary table stayqr_day19_day14_runtime_results (
  suite text not null,
  test_name text not null,
  passed boolean not null,
  details text not null,
  primary key (suite, test_name)
) on commit preserve rows;

do $audit$
declare
  v_hotel_id constant uuid :=
    '798915b5-b1f1-4b3e-bd7b-56a8b187dae5'::uuid;
  v_hotel_slug constant text := 'day-19-qa-hotel';
  v_room_id constant uuid :=
    'e7f372bb-2213-4883-bf6a-d92827bf73c0'::uuid;
  v_room_number constant text := '101';

  v_suffix text := substr(gen_random_uuid()::text, 1, 8);
  v_guest_name text;
  v_fixture_review_url constant text :=
    'https://www.google.com/maps/search/?api=1&query=Day+19+QA+Hotel';

  v_actor_user uuid;
  v_actor_email text;
  v_guest_id uuid;
  v_session_id uuid;
  v_initial_token_id uuid;
  v_new_token_id uuid;
  v_initial_token text;
  v_new_token text;

  v_en_result jsonb;
  v_hi_result jsonb;
  v_portal_before jsonb;
  v_portal_after jsonb;
  v_feedback_result jsonb;
  v_reward_result jsonb;
  v_rotation_result jsonb;

  v_hotel_ok boolean := false;
  v_room_ok boolean := false;
  v_room_clean boolean := false;
  v_actor_ok boolean := false;
  v_signing_key_ok boolean := false;
  v_rpcs_ok boolean := false;
  v_hotel_info_ok boolean := false;

  v_actor_permission_ok boolean := false;
  v_guest_created boolean := false;
  v_session_created boolean := false;
  v_initial_token_created boolean := false;
  v_content_rpc_ok boolean := false;
  v_portal_before_ok boolean := false;
  v_portal_identity_ok boolean := false;
  v_portal_locales_ok boolean := false;
  v_feedback_ok boolean := false;
  v_reward_ok boolean := false;
  v_rotation_ok boolean := false;
  v_revoked_old_token_ok boolean := false;
  v_one_active_replacement_ok boolean := false;
  v_old_token_rejected boolean := false;
  v_new_token_resolves boolean := false;
  v_review_config_visible boolean := false;

  v_legacy_01 boolean := false;
  v_legacy_02 boolean := false;
  v_legacy_03 boolean := false;
  v_legacy_07 boolean := false;
  v_legacy_08 boolean := false;
  v_legacy_09 boolean := false;
  v_legacy_17 boolean := false;
  v_legacy_18 boolean := false;
  v_legacy_20 boolean := false;

  v_fixture_completed boolean := false;
  v_fixture_rolled_back boolean := false;
  v_role_switched boolean := false;
  v_failure_details text;

  v_before_guest_count bigint;
  v_before_session_count bigint;
  v_before_token_count bigint;
  v_before_feedback_count bigint;
  v_before_reward_count bigint;
  v_before_content_count bigint;
  v_before_active_english_count bigint;
  v_before_review_url text;

  v_after_guest_count bigint;
  v_after_session_count bigint;
  v_after_token_count bigint;
  v_after_feedback_count bigint;
  v_after_reward_count bigint;
  v_after_content_count bigint;
  v_after_active_english_count bigint;
  v_after_review_url text;

  v_cleanup_ok boolean := false;
begin
  v_guest_name := 'D19 Day14 Runtime Guest ' || v_suffix;

  -- --------------------------------------------------------------------------
  -- PRECHECKS
  -- --------------------------------------------------------------------------

  select exists (
    select 1
    from public.hotels h
    where h.id = v_hotel_id
      and h.slug = v_hotel_slug
      and h.status = 'active'
  )
  into v_hotel_ok;

  select exists (
    select 1
    from public.rooms r
    where r.id = v_room_id
      and r.hotel_id = v_hotel_id
      and r.room_number = v_room_number
      and r.status = 'available'
      and r.is_active
  )
  into v_room_ok;

  select not exists (
    select 1
    from public.guest_sessions gs
    where gs.hotel_id = v_hotel_id
      and gs.room_id = v_room_id
      and gs.status = 'active'
      and coalesce(gs.extended_until, gs.checkout_time) > now()
  )
  into v_room_clean;

  select
    s.auth_user_id,
    au.email
  into
    v_actor_user,
    v_actor_email
  from public.staff s
  join auth.users au
    on au.id = s.auth_user_id
  where s.hotel_id = v_hotel_id
    and s.status = 'active'
    and s.auth_user_id is not null
    and coalesce(au.banned_until, '-infinity'::timestamptz) <= now()
  order by
    case lower(replace(trim(s.role), ' ', '_'))
      when 'owner' then 1
      when 'manager' then 2
      else 3
    end,
    s.created_at,
    s.id
  limit 1;

  v_actor_ok := v_actor_user is not null;

  select exists (
    select 1
    from private.guest_access_signing_keys k
    where k.status = 'active'
  )
  into v_signing_key_ok;

  v_rpcs_ok :=
       to_regprocedure('public.resolve_guest_portal(text,text)') is not null
   and to_regprocedure(
         'public.submit_guest_feedback(text,text,integer,text,boolean)'
       ) is not null
   and to_regprocedure(
         'public.record_guest_review_reward_action(text,text,text)'
       ) is not null
   and to_regprocedure(
         'public.rotate_guest_access_token(uuid,uuid,text)'
       ) is not null
   and to_regprocedure(
         'public.get_hotel_guest_content(uuid,text)'
       ) is not null
   and to_regprocedure(
         'public.upsert_hotel_guest_content(uuid,text,jsonb)'
       ) is not null
   and to_regprocedure(
         'private.render_guest_access_token(uuid)'
       ) is not null;

  select exists (
    select 1
    from public.hotel_info hi
    where hi.hotel_id = v_hotel_id
  )
  into v_hotel_info_ok;

  -- Baseline values used to prove cleanup after the forced rollback.
  select count(*) into v_before_guest_count
  from public.guests
  where hotel_id = v_hotel_id;

  select count(*) into v_before_session_count
  from public.guest_sessions
  where hotel_id = v_hotel_id;

  select count(*) into v_before_token_count
  from public.guest_access_tokens
  where hotel_id = v_hotel_id;

  select count(*) into v_before_feedback_count
  from public.guest_feedback
  where hotel_id = v_hotel_id;

  select count(*) into v_before_reward_count
  from public.guest_review_rewards
  where hotel_id = v_hotel_id;

  select count(*) into v_before_content_count
  from public.hotel_guest_content;

  select count(*) into v_before_active_english_count
  from public.hotels h
  where exists (
    select 1
    from public.hotel_guest_content c
    where c.hotel_id = h.id
      and c.locale = 'en'
      and c.is_active
  );

  select hi.google_review_url
  into v_before_review_url
  from public.hotel_info hi
  where hi.hotel_id = v_hotel_id;

  if v_hotel_ok
     and v_room_ok
     and v_room_clean
     and v_actor_ok
     and v_signing_key_ok
     and v_rpcs_ok
     and v_hotel_info_ok
  then

    -- ========================================================================
    -- REVERSIBLE FIXTURE SUBTRANSACTION
    -- Everything below is rolled back by the intentional P7914 exception.
    -- ========================================================================
    begin
      -- ----------------------------------------------------------------------
      -- A. Real authenticated hotel-management context
      -- ----------------------------------------------------------------------

      perform set_config(
        'request.jwt.claim.sub',
        v_actor_user::text,
        true
      );
      perform set_config(
        'request.jwt.claim.role',
        'authenticated',
        true
      );

      execute 'set local role authenticated';
      v_role_switched := true;

      v_actor_permission_ok :=
        private.user_has_permission(v_hotel_id, 'hotel.manage');

      if not v_actor_permission_ok then
        raise exception
          'Resolved actor does not have hotel.manage on Day 19 QA Hotel.';
      end if;

      v_en_result := public.upsert_hotel_guest_content(
        v_hotel_id,
        'en',
        jsonb_build_object(
          'welcome_title', 'Welcome to Day 19 QA Hotel',
          'welcome_message',
            'Temporary Gate 19B English guest-content fixture.',
          'fixture', 'day19-gate19b-day14-runtime'
        )
      );

      v_hi_result := public.upsert_hotel_guest_content(
        v_hotel_id,
        'hi',
        jsonb_build_object(
          'welcome_title', 'Day 19 QA Hotel में आपका स्वागत है',
          'welcome_message',
            'अस्थायी Gate 19B Hindi guest-content fixture.',
          'fixture', 'day19-gate19b-day14-runtime'
        )
      );

      v_content_rpc_ok :=
           v_en_result ->> 'result' = 'GUEST CONTENT SAVED'
       and v_hi_result ->> 'result' = 'GUEST CONTENT SAVED';

      update public.hotel_info
      set google_review_url = v_fixture_review_url
      where hotel_id = v_hotel_id;

      execute 'reset role';
      v_role_switched := false;

      -- Audit 062's first legacy runtime condition is global: every hotel needs
      -- an active English row. Temporarily supply/activate only missing rows.
      -- This is fixture-only setup and is rolled back in this same block.
      insert into public.hotel_guest_content (
        hotel_id,
        locale,
        content,
        is_active,
        updated_by
      )
      select
        h.id,
        'en',
        jsonb_build_object(
          'welcome_title', coalesce(h.hotel_name, 'StayQR Hotel'),
          'fixture', 'day19-gate19b-global-english-baseline'
        ),
        true,
        v_actor_user
      from public.hotels h
      where not exists (
        select 1
        from public.hotel_guest_content c
        where c.hotel_id = h.id
          and c.locale = 'en'
          and c.is_active
      )
      on conflict (hotel_id, locale)
      do update set
        is_active = true,
        updated_at = now();

      -- ----------------------------------------------------------------------
      -- B. Temporary guest + stay.
      -- Inserting an active guest_session invokes the existing Day 7 lifecycle
      -- trigger, which must create the first signed token automatically.
      -- ----------------------------------------------------------------------

      insert into public.guests (
        hotel_id,
        full_name,
        preferred_language,
        room_number,
        purpose_of_visit
      )
      values (
        v_hotel_id,
        v_guest_name,
        'hindi',
        v_room_number,
        'Day 19 reversible runtime acceptance'
      )
      returning id into v_guest_id;

      v_guest_created := v_guest_id is not null;

      insert into public.guest_sessions (
        hotel_id,
        room_id,
        guest_id,
        checkin_time,
        checkout_time,
        status
      )
      values (
        v_hotel_id,
        v_room_id,
        v_guest_id,
        now() - interval '1 hour',
        now() + interval '1 day',
        'active'
      )
      returning id into v_session_id;

      v_session_created := v_session_id is not null;

      select t.id
      into v_initial_token_id
      from public.guest_access_tokens t
      where t.hotel_id = v_hotel_id
        and t.room_id = v_room_id
        and t.guest_session_id = v_session_id
        and t.status = 'active'
        and t.expires_at > now()
      order by t.issued_at desc
      limit 1;

      v_initial_token_created := v_initial_token_id is not null;

      if not v_initial_token_created then
        raise exception
          'Active guest-session insert did not auto-issue a signed guest token.';
      end if;

      v_initial_token :=
        private.render_guest_access_token(v_initial_token_id);

      -- ----------------------------------------------------------------------
      -- C. Real anonymous signed guest RPCs
      -- ----------------------------------------------------------------------

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
      v_role_switched := true;

      v_portal_before := public.resolve_guest_portal(
        v_hotel_slug,
        v_initial_token
      );

      v_feedback_result := public.submit_guest_feedback(
        v_hotel_slug,
        v_initial_token,
        5,
        'Day 19 reversible five-star private feedback.',
        true
      );

      v_reward_result := public.record_guest_review_reward_action(
        v_hotel_slug,
        v_initial_token,
        'review_opened'
      );

      execute 'reset role';
      v_role_switched := false;

      v_portal_before_ok :=
        coalesce(v_portal_before -> 'hotel' ->> 'slug', '') = v_hotel_slug;

      v_portal_identity_ok :=
           coalesce(
             v_portal_before #>> '{session,guests,full_name}',
             ''
           ) = v_guest_name
       and coalesce(
             v_portal_before #>> '{session,rooms,room_number}',
             ''
           ) = v_room_number;

      v_portal_locales_ok :=
           coalesce(
             v_portal_before #> '{guest_content,translations}',
             '{}'::jsonb
           ) ? 'en'
       and coalesce(
             v_portal_before #> '{guest_content,translations}',
             '{}'::jsonb
           ) ? 'hi';

      v_review_config_visible :=
        coalesce(
          v_portal_before #>> '{hotel_info,google_review_url}',
          ''
        ) = v_fixture_review_url;

      select exists (
        select 1
        from public.guest_feedback f
        where f.hotel_id = v_hotel_id
          and f.guest_session_id = v_session_id
          and f.guest_access_token_id = v_initial_token_id
          and f.rating = 5
          and f.consent_to_follow_up
          and f.status = 'new'
      )
      into v_feedback_ok;

      v_feedback_ok :=
        v_feedback_ok
        and coalesce(
              v_feedback_result ->> 'result',
              ''
            ) = 'FEEDBACK RECEIVED';

      select exists (
        select 1
        from public.guest_review_rewards rr
        where rr.hotel_id = v_hotel_id
          and rr.guest_session_id = v_session_id
          and rr.guest_access_token_id = v_initial_token_id
          and rr.action = 'review_opened'
          and rr.status = 'recorded'
      )
      into v_reward_ok;

      v_reward_ok :=
        v_reward_ok
        and coalesce(
              v_reward_result ->> 'result',
              ''
            ) = 'ACTION RECORDED';

      -- ----------------------------------------------------------------------
      -- D. Real authenticated rotation RPC
      -- ----------------------------------------------------------------------

      perform set_config(
        'request.jwt.claim.sub',
        v_actor_user::text,
        true
      );
      perform set_config(
        'request.jwt.claim.role',
        'authenticated',
        true
      );

      execute 'set local role authenticated';
      v_role_switched := true;

      v_rotation_result := public.rotate_guest_access_token(
        v_hotel_id,
        v_session_id,
        'Day 19 reversible runtime token rotation'
      );

      execute 'reset role';
      v_role_switched := false;

      select t.id
      into v_new_token_id
      from public.guest_access_tokens t
      where t.hotel_id = v_hotel_id
        and t.guest_session_id = v_session_id
        and t.status = 'active'
        and t.expires_at > now()
      order by t.issued_at desc
      limit 1;

      v_rotation_ok :=
           coalesce(
             v_rotation_result ->> 'result',
             ''
           ) = 'GUEST ACCESS ROTATED'
       and v_new_token_id is not null
       and v_new_token_id <> v_initial_token_id;

      select exists (
        select 1
        from public.guest_access_tokens t
        where t.id = v_initial_token_id
          and t.guest_session_id = v_session_id
          and t.status = 'revoked'
          and t.revoked_at is not null
      )
      into v_revoked_old_token_ok;

      select count(*) = 1
      into v_one_active_replacement_ok
      from public.guest_access_tokens t
      where t.guest_session_id = v_session_id
        and t.status = 'active'
        and t.expires_at > now();

      if v_new_token_id is not null then
        v_new_token :=
          private.render_guest_access_token(v_new_token_id);
      end if;

      -- ----------------------------------------------------------------------
      -- E. Prove the new token works and the revoked token does not.
      -- ----------------------------------------------------------------------

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
      v_role_switched := true;

      begin
        v_portal_after := public.resolve_guest_portal(
          v_hotel_slug,
          v_new_token
        );

        v_new_token_resolves :=
          coalesce(
            v_portal_after #>> '{session,rooms,room_number}',
            ''
          ) = v_room_number;
      exception
        when others then
          v_new_token_resolves := false;
      end;

      begin
        perform public.resolve_guest_portal(
          v_hotel_slug,
          v_initial_token
        );

        v_old_token_rejected := false;
      exception
        when others then
          v_old_token_rejected :=
            lower(sqlerrm) like '%invalid or expired%';
      end;

      execute 'reset role';
      v_role_switched := false;

      -- ----------------------------------------------------------------------
      -- F. Recreate the exact 9 legacy runtime assertions that were failing.
      -- ----------------------------------------------------------------------

      v_legacy_01 := not exists (
        select 1
        from public.hotels h
        where not exists (
          select 1
          from public.hotel_guest_content c
          where c.hotel_id = h.id
            and c.locale = 'en'
            and c.is_active
        )
      );

      v_legacy_02 := exists (
        select 1
        from public.hotel_guest_content c
        where c.is_active
        group by c.hotel_id
        having count(distinct c.locale) >= 2
      );

      v_legacy_03 := exists (
        select 1
        from public.hotel_guest_content c
        where c.locale = 'hi'
          and c.is_active
      );

      v_legacy_07 := exists (
        select 1
        from public.guest_feedback
      );

      v_legacy_08 := exists (
        select 1
        from public.guest_feedback
        where rating = 5
      );

      v_legacy_09 := exists (
        select 1
        from public.guest_feedback
        where consent_to_follow_up
      );

      v_legacy_17 := exists (
        select 1
        from public.guest_access_tokens
        where status = 'revoked'
      );

      v_legacy_18 := exists (
        select 1
        from public.guest_access_tokens
        where status = 'active'
          and expires_at > now()
      );

      v_legacy_20 := exists (
        select 1
        from public.hotel_info
        where nullif(trim(google_review_url), '') is not null
      );

      v_fixture_completed :=
           v_actor_permission_ok
       and v_guest_created
       and v_session_created
       and v_initial_token_created
       and v_content_rpc_ok
       and v_portal_before_ok
       and v_portal_identity_ok
       and v_portal_locales_ok
       and v_feedback_ok
       and v_reward_ok
       and v_rotation_ok
       and v_revoked_old_token_ok
       and v_one_active_replacement_ok
       and v_old_token_rejected
       and v_new_token_resolves
       and v_review_config_visible
       and v_legacy_01
       and v_legacy_02
       and v_legacy_03
       and v_legacy_07
       and v_legacy_08
       and v_legacy_09
       and v_legacy_17
       and v_legacy_18
       and v_legacy_20;

      -- Deliberately roll back every fixture mutation above.
      raise exception using
        errcode = 'P7914',
        message =
          'StayQR Day 19 Day 14 reversible runtime acceptance rollback';

    exception
      when sqlstate 'P7914' then
        v_fixture_rolled_back := true;

      when others then
        if v_role_switched then
          begin
            execute 'reset role';
          exception
            when others then
              null;
          end;
          v_role_switched := false;
        end if;

        v_fixture_completed := false;
        v_fixture_rolled_back := true;
        v_failure_details := format(
          'Runtime harness failure [%s] %s',
          sqlstate,
          sqlerrm
        );
    end;
  else
    v_failure_details := concat_ws(
      '; ',
      case when not v_hotel_ok then 'target hotel missing/inactive' end,
      case when not v_room_ok then 'Room 101 missing/unavailable' end,
      case when not v_room_clean then 'Room 101 already has an active stay' end,
      case when not v_actor_ok then 'active hotel actor missing' end,
      case when not v_signing_key_ok then 'active signing key missing' end,
      case when not v_rpcs_ok then 'required Day 14/guest RPC missing' end,
      case when not v_hotel_info_ok then 'hotel_info row missing' end
    );
  end if;

  -- --------------------------------------------------------------------------
  -- POST-ROLLBACK CLEANUP PROOF
  -- --------------------------------------------------------------------------

  select count(*) into v_after_guest_count
  from public.guests
  where hotel_id = v_hotel_id;

  select count(*) into v_after_session_count
  from public.guest_sessions
  where hotel_id = v_hotel_id;

  select count(*) into v_after_token_count
  from public.guest_access_tokens
  where hotel_id = v_hotel_id;

  select count(*) into v_after_feedback_count
  from public.guest_feedback
  where hotel_id = v_hotel_id;

  select count(*) into v_after_reward_count
  from public.guest_review_rewards
  where hotel_id = v_hotel_id;

  select count(*) into v_after_content_count
  from public.hotel_guest_content;

  select count(*) into v_after_active_english_count
  from public.hotels h
  where exists (
    select 1
    from public.hotel_guest_content c
    where c.hotel_id = h.id
      and c.locale = 'en'
      and c.is_active
  );

  select hi.google_review_url
  into v_after_review_url
  from public.hotel_info hi
  where hi.hotel_id = v_hotel_id;

  v_cleanup_ok :=
       v_before_guest_count = v_after_guest_count
   and v_before_session_count = v_after_session_count
   and v_before_token_count = v_after_token_count
   and v_before_feedback_count = v_after_feedback_count
   and v_before_reward_count = v_after_reward_count
   and v_before_content_count = v_after_content_count
   and v_before_active_english_count = v_after_active_english_count
   and v_before_review_url is not distinct from v_after_review_url
   and not exists (
     select 1
     from public.guests g
     where g.hotel_id = v_hotel_id
       and g.full_name = v_guest_name
   )
   and not exists (
     select 1
     from public.hotel_guest_content c
     where c.content ->> 'fixture' in (
       'day19-gate19b-day14-runtime',
       'day19-gate19b-global-english-baseline'
     )
   );

  -- --------------------------------------------------------------------------
  -- FINAL RESULTS — 29 rows
  -- --------------------------------------------------------------------------

  insert into pg_temp.stayqr_day19_day14_runtime_results
    (suite, test_name, passed, details)
  values
    (
      'PRECHECK',
      '01_target_hotel',
      v_hotel_ok,
      'Day 19 QA Hotel exists, slug matches, and hotel is active.'
    ),
    (
      'PRECHECK',
      '02_room_101_available',
      v_room_ok,
      'Room 101 exists for the QA hotel and is active/available.'
    ),
    (
      'PRECHECK',
      '03_room_101_clean',
      v_room_clean,
      'Room 101 had no pre-existing active stay.'
    ),
    (
      'PRECHECK',
      '04_authenticated_actor',
      v_actor_ok,
      coalesce(
        'Resolved actor ' || v_actor_email || ' (' ||
          v_actor_user::text || ').',
        'No active authenticated hotel actor resolved.'
      )
    ),
    (
      'PRECHECK',
      '05_active_signing_key',
      v_signing_key_ok,
      'At least one active guest-access signing key exists.'
    ),
    (
      'PRECHECK',
      '06_required_rpcs',
      v_rpcs_ok,
      'Required Day 14 content/portal/feedback/reward and token RPCs exist.'
    ),
    (
      'PRECHECK',
      '07_hotel_info_row',
      v_hotel_info_ok,
      'Day 19 QA Hotel has an editable hotel_info row.'
    ),

    (
      'RUNTIME',
      '08_actor_hotel_manage_permission',
      v_actor_permission_ok,
      'Resolved authenticated actor passed hotel.manage authorization.'
    ),
    (
      'RUNTIME',
      '09_guest_and_session_created',
      v_guest_created and v_session_created,
      'Temporary guest and active Room 101 guest_session were created.'
    ),
    (
      'RUNTIME',
      '10_token_auto_issued',
      v_initial_token_created,
      'Existing guest-session trigger automatically issued the first signed token.'
    ),
    (
      'RUNTIME',
      '11_multilingual_content_rpc',
      v_content_rpc_ok,
      'English and Hindi content were saved through the authenticated content RPC.'
    ),
    (
      'RUNTIME',
      '12_anon_portal_resolves',
      v_portal_before_ok,
      'The initial signed token resolved through the real anon portal RPC.'
    ),
    (
      'RUNTIME',
      '13_portal_guest_room_identity',
      v_portal_identity_ok,
      'Portal returned the controlled guest identity and Room 101.'
    ),
    (
      'RUNTIME',
      '14_portal_multilingual_payload',
      v_portal_locales_ok,
      'Portal translations contained both en and hi locales.'
    ),
    (
      'RUNTIME',
      '15_private_five_star_feedback',
      v_feedback_ok,
      'Anon signed RPC stored 5-star private feedback with follow-up consent.'
    ),
    (
      'RUNTIME',
      '16_review_action_recorded',
      v_reward_ok,
      'Anon signed RPC recorded review_opened through the reward-action ledger.'
    ),
    (
      'RUNTIME',
      '17_authenticated_token_rotation',
      v_rotation_ok,
      'Authenticated rotation created a different active replacement token.'
    ),
    (
      'RUNTIME',
      '18_old_token_revoked',
      v_revoked_old_token_ok and v_old_token_rejected,
      'Original token became revoked and could no longer resolve the guest portal.'
    ),
    (
      'RUNTIME',
      '19_replacement_token_valid',
      v_one_active_replacement_ok and v_new_token_resolves,
      'Exactly one active replacement token remained and resolved successfully.'
    ),
    (
      'RUNTIME',
      '20_review_configuration_visible',
      v_review_config_visible,
      'Temporary Google review configuration appeared in the signed portal payload.'
    ),

    (
      'LEGACY_A062',
      '21_01_every_hotel_has_english_content',
      v_legacy_01,
      'Recreated Audit 062 runtime check 01.'
    ),
    (
      'LEGACY_A062',
      '22_02_multilingual_content_present',
      v_legacy_02,
      'Recreated Audit 062 runtime check 02.'
    ),
    (
      'LEGACY_A062',
      '23_03_hindi_content_present',
      v_legacy_03,
      'Recreated Audit 062 runtime check 03.'
    ),
    (
      'LEGACY_A062',
      '24_07_private_feedback_recorded',
      v_legacy_07,
      'Recreated Audit 062 runtime check 07.'
    ),
    (
      'LEGACY_A062',
      '25_08_five_star_feedback_recorded',
      v_legacy_08,
      'Recreated Audit 062 runtime check 08.'
    ),
    (
      'LEGACY_A062',
      '26_09_follow_up_consent_recorded',
      v_legacy_09,
      'Recreated Audit 062 runtime check 09.'
    ),
    (
      'LEGACY_A062',
      '27_17_rotation_created_revoked_token',
      v_legacy_17,
      'Recreated Audit 062 runtime check 17.'
    ),
    (
      'LEGACY_A062',
      '28_18_active_token_remains_after_rotation',
      v_legacy_18,
      'Recreated Audit 062 runtime check 18.'
    ),
    (
      'LEGACY_A062',
      '29_20_hotel_review_configuration_present',
      v_legacy_20,
      'Recreated Audit 062 runtime check 20.'
    );

  -- Add cleanup as a separate, clearly labeled row. This makes 30 rows total.
  insert into pg_temp.stayqr_day19_day14_runtime_results
    (suite, test_name, passed, details)
  values (
    'CLEANUP',
    '30_reversible_fixture_rolled_back',
    v_fixture_rolled_back
      and v_cleanup_ok
      and (v_fixture_completed or v_failure_details is null),
    case
      when v_failure_details is not null then
        'Fixture rolled back after error: ' || v_failure_details
      when not v_fixture_completed then
        'Fixture rollback completed, but one or more runtime assertions failed.'
      when not v_cleanup_ok then
        'Fixture execution passed, but post-rollback baseline comparison failed.'
      else
        format(
          'All fixture mutations rolled back. QA counts restored: guests=%s, sessions=%s, tokens=%s, feedback=%s, rewards=%s; total content rows=%s.',
          v_after_guest_count,
          v_after_session_count,
          v_after_token_count,
          v_after_feedback_count,
          v_after_reward_count,
          v_after_content_count
        )
    end
  );
end;
$audit$;

select
  suite,
  test_name,
  passed,
  details
from pg_temp.stayqr_day19_day14_runtime_results
order by
  case suite
    when 'PRECHECK' then 1
    when 'RUNTIME' then 2
    when 'LEGACY_A062' then 3
    when 'CLEANUP' then 4
    else 9
  end,
  test_name;

-- Compact summary.
select
  count(*) as total_checks,
  count(*) filter (where passed) as passed_checks,
  count(*) filter (where not passed) as failed_checks
from pg_temp.stayqr_day19_day14_runtime_results;

drop table if exists pg_temp.stayqr_day19_day14_runtime_results;
