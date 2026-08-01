-- ============================================================================
-- StayQR v1.0
-- Day 7 Diagnostic 039 REV2
-- Purpose: locate the exact database object behind:
--   ERROR 42P01: relation "guest" does not exist
--
-- Safe to run in Supabase SQL Editor with role postgres.
-- Creates TEMP tables only. It does not modify production data or functions.
--
-- Expected: 10 result rows. Any failed row will contain the exact matching
-- object or SQLSTATE/error text needed for the repair.
-- ============================================================================

set statement_timeout = '180s';

drop table if exists pg_temp.stayqr_diag_039_results;
drop table if exists pg_temp.stayqr_diag_039_matches;

create temporary table stayqr_diag_039_results (
  step_no integer primary key,
  check_name text not null,
  passed boolean not null,
  details text not null
) on commit preserve rows;

create temporary table stayqr_diag_039_matches (
  object_type text not null,
  object_name text not null,
  finding text not null
) on commit preserve rows;

do $diag$
declare
  obj record;
  object_def text;
  match_list text;
  relation_count integer;
  active_token_count integer;
  sample_token_id uuid;
  sample_slug text;
begin
  -- 1. Confirm canonical guest relations.
  begin
    select count(*)
      into relation_count
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname in ('guests', 'guest_sessions', 'guest_access_tokens')
      and c.relkind in ('r', 'p');

    insert into pg_temp.stayqr_diag_039_results
    values (
      1,
      'canonical_guest_relations',
      relation_count = 3,
      format(
        'Found %s/3 canonical relations: public.guests, public.guest_sessions, public.guest_access_tokens.',
        relation_count
      )
    );
  exception when others then
    insert into pg_temp.stayqr_diag_039_results
    values (1, 'canonical_guest_relations', false, format('[%s] %s', sqlstate, sqlerrm));
  end;

  -- 2. Search only ordinary functions/procedures.
  -- REV1 incorrectly called pg_get_functiondef() for aggregates such as
  -- array_agg. prokind filtering prevents that catalog error.
  for obj in
    select
      p.oid,
      n.nspname,
      p.proname,
      pg_get_function_identity_arguments(p.oid) as identity_args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private', 'storage')
      and p.prokind in ('f', 'p')
  loop
    begin
      object_def := pg_get_functiondef(obj.oid);

      if object_def ~* '(^|[^a-z0-9_.])(from|join|update|into|delete[[:space:]]+from)[[:space:]]+"?guest"?([^a-z0-9_]|$)' then
        insert into pg_temp.stayqr_diag_039_matches
        values (
          'routine',
          format('%I.%I(%s)', obj.nspname, obj.proname, obj.identity_args),
          'Definition references an unqualified relation named guest.'
        );
      end if;
    exception when others then
      insert into pg_temp.stayqr_diag_039_matches
      values (
        'routine_scan_error',
        format('%I.%I(%s)', obj.nspname, obj.proname, obj.identity_args),
        format('[%s] %s', sqlstate, sqlerrm)
      );
    end;
  end loop;

  select string_agg(
           format('%s: %s — %s', object_type, object_name, finding),
           E'\n'
           order by object_type, object_name
         )
    into match_list
  from pg_temp.stayqr_diag_039_matches
  where object_type in ('routine', 'routine_scan_error');

  insert into pg_temp.stayqr_diag_039_results
  values (
    2,
    'routine_definition_scan',
    match_list is null,
    coalesce(match_list, 'No ordinary function/procedure references an unqualified relation named guest.')
  );

  -- 3. Views and materialized views.
  begin
    insert into pg_temp.stayqr_diag_039_matches
    select
      object_type,
      object_name,
      'Definition references an unqualified relation named guest.'
    from (
      select
        'view'::text as object_type,
        format('%I.%I', schemaname, viewname) as object_name,
        definition
      from pg_views
      where schemaname in ('public', 'private', 'storage')

      union all

      select
        'materialized_view'::text,
        format('%I.%I', schemaname, matviewname),
        definition
      from pg_matviews
      where schemaname in ('public', 'private', 'storage')
    ) definitions
    where definition ~* '(^|[^a-z0-9_.])(from|join)[[:space:]]+"?guest"?([^a-z0-9_]|$)';

    select string_agg(
             format('%s: %s — %s', object_type, object_name, finding),
             E'\n'
             order by object_type, object_name
           )
      into match_list
    from pg_temp.stayqr_diag_039_matches
    where object_type in ('view', 'materialized_view');

    insert into pg_temp.stayqr_diag_039_results
    values (
      3,
      'view_definition_scan',
      match_list is null,
      coalesce(match_list, 'No view/materialized view references an unqualified relation named guest.')
    );
  exception when others then
    insert into pg_temp.stayqr_diag_039_results
    values (3, 'view_definition_scan', false, format('[%s] %s', sqlstate, sqlerrm));
  end;

  -- 4. RLS policies.
  begin
    insert into pg_temp.stayqr_diag_039_matches
    select
      'policy',
      format('%I.%I / %I', schemaname, tablename, policyname),
      'Policy expression references an unqualified relation named guest.'
    from pg_policies
    where schemaname in ('public', 'private', 'storage')
      and (
        coalesce(qual, '') || ' ' || coalesce(with_check, '')
      ) ~* '(^|[^a-z0-9_.])(from|join|update|into|delete[[:space:]]+from)[[:space:]]+"?guest"?([^a-z0-9_]|$)';

    select string_agg(
             format('%s: %s — %s', object_type, object_name, finding),
             E'\n'
             order by object_type, object_name
           )
      into match_list
    from pg_temp.stayqr_diag_039_matches
    where object_type = 'policy';

    insert into pg_temp.stayqr_diag_039_results
    values (
      4,
      'policy_definition_scan',
      match_list is null,
      coalesce(match_list, 'No RLS policy references an unqualified relation named guest.')
    );
  exception when others then
    insert into pg_temp.stayqr_diag_039_results
    values (4, 'policy_definition_scan', false, format('[%s] %s', sqlstate, sqlerrm));
  end;

  -- 5. Trigger definitions.
  for obj in
    select
      t.oid,
      format('%I.%I / %I', n.nspname, c.relname, t.tgname) as object_name
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where not t.tgisinternal
      and n.nspname in ('public', 'private', 'storage')
  loop
    begin
      object_def := pg_get_triggerdef(obj.oid, true);

      if object_def ~* '(^|[^a-z0-9_.])(from|join|update|into|delete[[:space:]]+from)[[:space:]]+"?guest"?([^a-z0-9_]|$)' then
        insert into pg_temp.stayqr_diag_039_matches
        values (
          'trigger',
          obj.object_name,
          'Trigger definition references an unqualified relation named guest.'
        );
      end if;
    exception when others then
      insert into pg_temp.stayqr_diag_039_matches
      values ('trigger_scan_error', obj.object_name, format('[%s] %s', sqlstate, sqlerrm));
    end;
  end loop;

  select string_agg(
           format('%s: %s — %s', object_type, object_name, finding),
           E'\n'
           order by object_type, object_name
         )
    into match_list
  from pg_temp.stayqr_diag_039_matches
  where object_type in ('trigger', 'trigger_scan_error');

  insert into pg_temp.stayqr_diag_039_results
  values (
    5,
    'trigger_definition_scan',
    match_list is null,
    coalesce(match_list, 'No trigger definition references an unqualified relation named guest.')
  );

  -- 6. Constraints.
  for obj in
    select
      con.oid,
      format('%I.%I / %I', n.nspname, c.relname, con.conname) as object_name
    from pg_constraint con
    join pg_class c on c.oid = con.conrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('public', 'private', 'storage')
  loop
    begin
      object_def := pg_get_constraintdef(obj.oid, true);

      if object_def ~* '(^|[^a-z0-9_.])(from|join|update|into|delete[[:space:]]+from)[[:space:]]+"?guest"?([^a-z0-9_]|$)' then
        insert into pg_temp.stayqr_diag_039_matches
        values (
          'constraint',
          obj.object_name,
          'Constraint definition references an unqualified relation named guest.'
        );
      end if;
    exception when others then
      insert into pg_temp.stayqr_diag_039_matches
      values ('constraint_scan_error', obj.object_name, format('[%s] %s', sqlstate, sqlerrm));
    end;
  end loop;

  select string_agg(
           format('%s: %s — %s', object_type, object_name, finding),
           E'\n'
           order by object_type, object_name
         )
    into match_list
  from pg_temp.stayqr_diag_039_matches
  where object_type in ('constraint', 'constraint_scan_error');

  insert into pg_temp.stayqr_diag_039_results
  values (
    6,
    'constraint_definition_scan',
    match_list is null,
    coalesce(match_list, 'No constraint definition references an unqualified relation named guest.')
  );

  -- 7. Column defaults and generated expressions.
  begin
    insert into pg_temp.stayqr_diag_039_matches
    select
      'column_expression',
      format('%I.%I.%I', n.nspname, c.relname, a.attname),
      'Column default/generated expression references an unqualified relation named guest.'
    from pg_attrdef d
    join pg_class c on c.oid = d.adrelid
    join pg_namespace n on n.oid = c.relnamespace
    join pg_attribute a
      on a.attrelid = d.adrelid
     and a.attnum = d.adnum
    where n.nspname in ('public', 'private', 'storage')
      and pg_get_expr(d.adbin, d.adrelid, true)
          ~* '(^|[^a-z0-9_.])(from|join|update|into|delete[[:space:]]+from)[[:space:]]+"?guest"?([^a-z0-9_]|$)';

    select string_agg(
             format('%s: %s — %s', object_type, object_name, finding),
             E'\n'
             order by object_type, object_name
           )
      into match_list
    from pg_temp.stayqr_diag_039_matches
    where object_type = 'column_expression';

    insert into pg_temp.stayqr_diag_039_results
    values (
      7,
      'column_expression_scan',
      match_list is null,
      coalesce(match_list, 'No column expression references an unqualified relation named guest.')
    );
  exception when others then
    insert into pg_temp.stayqr_diag_039_results
    values (7, 'column_expression_scan', false, format('[%s] %s', sqlstate, sqlerrm));
  end;

  -- 8. Probe the token table directly without invoking any token function.
  begin
    execute $sql$
      select count(*)
      from public.guest_access_tokens
    $sql$
    into relation_count;

    insert into pg_temp.stayqr_diag_039_results
    values (
      8,
      'guest_access_tokens_direct_probe',
      true,
      format('Direct token-table query succeeded; %s token row(s) currently exist.', relation_count)
    );
  exception when others then
    insert into pg_temp.stayqr_diag_039_results
    values (8, 'guest_access_tokens_direct_probe', false, format('[%s] %s', sqlstate, sqlerrm));
  end;

  -- 9. Locate an active sample without rendering or resolving it.
  begin
    execute $sql$
      select count(*)
      from public.guest_access_tokens t
      join public.hotels h on h.id = t.hotel_id
      join public.rooms r
        on r.id = t.room_id
       and r.hotel_id = t.hotel_id
      join public.guest_sessions gs
        on gs.id = t.guest_session_id
       and gs.hotel_id = t.hotel_id
       and gs.room_id = t.room_id
      where t.status = 'active'
        and t.expires_at > now()
        and h.status = 'active'
        and gs.status = 'active'
        and coalesce(gs.extended_until, gs.checkout_time) > now()
    $sql$
    into active_token_count;

    insert into pg_temp.stayqr_diag_039_results
    values (
      9,
      'active_token_join_probe',
      true,
      format('Active-token join query succeeded; %s valid active sample(s) exist.', active_token_count)
    );
  exception when others then
    insert into pg_temp.stayqr_diag_039_results
    values (9, 'active_token_join_probe', false, format('[%s] %s', sqlstate, sqlerrm));
  end;

  -- 10. Report migration 014 marker.
  begin
    insert into pg_temp.stayqr_diag_039_results
    values (
      10,
      'migration_014_marker',
      obj_description('public.get_guest_access_links(uuid)'::regprocedure, 'pg_proc') =
        'Returns hotel-scoped signed guest links. Manual revocation persists until explicit token rotation.',
      coalesce(
        obj_description('public.get_guest_access_links(uuid)'::regprocedure, 'pg_proc'),
        'Migration 014 marker is missing.'
      )
    );
  exception when others then
    insert into pg_temp.stayqr_diag_039_results
    values (10, 'migration_014_marker', false, format('[%s] %s', sqlstate, sqlerrm));
  end;
end;
$diag$;

select step_no, check_name, passed, details
from pg_temp.stayqr_diag_039_results
order by step_no;
