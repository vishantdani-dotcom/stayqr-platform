-- ============================================================================
-- StayQR v1.0
-- Audit 038 REV5 — exception-isolated source/security contract gate
--
-- Run with role: postgres
-- Expected: exactly 24 rows.
-- Every passed value must be true.
--
-- This version avoids pg_get_functiondef() and avoids executing guest-token
-- production functions. Each assertion is planned and executed independently.
-- Any PostgreSQL error is captured in that exact row instead of aborting the
-- entire audit. TEMP objects only; no production data is modified.
-- ============================================================================

set statement_timeout = '180s';

drop table if exists pg_temp.stayqr_audit_038_results;

create temporary table stayqr_audit_038_results (
  test_name text primary key,
  passed boolean not null,
  details text not null
) on commit preserve rows;

do $audit$
declare
  check_row record;
  assertion_result boolean;
begin
  for check_row in
    select *
    from (
      values
      ('01_stage2_migration_installed'::text,
       $assert$obj_description(
  to_regprocedure('public.get_guest_access_links(uuid)'),
  'pg_proc'
) = 'Returns hotel-scoped signed guest links. Manual revocation persists until explicit token rotation.'$assert$::text,
       $detail$Migration 014 marker is installed.$detail$::text),
      ('02_guest_session_trigger_installed'::text,
       $assert$exists (
  select 1
  from pg_trigger
  where tgrelid = to_regclass('public.guest_sessions')
    and tgname = 'guest_sessions_sync_guest_access'
    and not tgisinternal
)$assert$::text,
       $detail$Guest-token lifecycle trigger is attached to public.guest_sessions.$detail$::text),
      ('03_trigger_issues_on_insert'::text,
       $assert$position(
  'if tg_op = ''insert'' then'
  in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('private.sync_guest_access_from_session()')))
) > 0
and position(
  'perform private.issue_guest_access_token(new.id, false, null)'
  in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('private.sync_guest_access_from_session()')))
) > 0$assert$::text,
       $detail$A new active stay receives its first signed token.$detail$::text),
      ('04_trigger_rotates_access_defining_changes'::text,
       $assert$position('old.hotel_id is distinct from new.hotel_id' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('private.sync_guest_access_from_session()')))) > 0
and position('old.room_id is distinct from new.room_id' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('private.sync_guest_access_from_session()')))) > 0
and position('old.guest_id is distinct from new.guest_id' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('private.sync_guest_access_from_session()')))) > 0
and position('old.checkout_time is distinct from new.checkout_time' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('private.sync_guest_access_from_session()')))) > 0
and position('old.extended_until is distinct from new.extended_until' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('private.sync_guest_access_from_session()')))) > 0$assert$::text,
       $detail$Hotel, room, guest and expiry changes explicitly rotate access.$detail$::text),
      ('05_unrelated_update_does_not_reissue'::text,
       $assert$lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('private.sync_guest_access_from_session()')))
!~ 'else[[:space:]]+perform private\.issue_guest_access_token\(new\.id, false, null\)'$assert$::text,
       $detail$An unrelated guest-session update cannot silently reactivate revoked access.$detail$::text),
      ('06_inactive_or_expired_stay_revoked'::text,
       $assert$position('guest stay is no longer active' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('private.sync_guest_access_from_session()')))) > 0
and position('guest stay expired' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('private.sync_guest_access_from_session()')))) > 0$assert$::text,
       $detail$Inactive, checked-out and expired stays invalidate active tokens.$detail$::text),
      ('07_link_status_contract'::text,
       $assert$position('''stay_active''' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('public.get_guest_access_links(uuid)')))) > 0
and position('''access_active''' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('public.get_guest_access_links(uuid)')))) > 0
and position('''access_status''' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('public.get_guest_access_links(uuid)')))) > 0
and position('''revocation_reason''' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('public.get_guest_access_links(uuid)')))) > 0$assert$::text,
       $detail$The staff QR response separates stay status from access status.$detail$::text),
      ('08_recovery_only_without_token_history'::text,
       $assert$position('token_history_exists := latest_token_id is not null' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('public.get_guest_access_links(uuid)')))) > 0
and position('if not token_history_exists then' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('public.get_guest_access_links(uuid)')))) > 0$assert$::text,
       $detail$Automatic recovery is limited to active legacy stays with no token history.$detail$::text),
      ('09_revoked_token_not_silently_reissued'::text,
       $assert$position('when latest_token_status = ''revoked'' then ''revoked''' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('public.get_guest_access_links(uuid)')))) > 0
and lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('public.get_guest_access_links(uuid)')))
!~ 'if latest_token_status = ''revoked'' then[[:space:]]+latest_token_id := private\.issue_guest_access_token'$assert$::text,
       $detail$Refreshing link administration preserves manual revocation.$detail$::text),
      ('10_only_active_unexpired_token_rendered'::text,
       $assert$position('if latest_token_status = ''active''' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('public.get_guest_access_links(uuid)')))) > 0
and position('latest_token_expires_at > now()' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('public.get_guest_access_links(uuid)')))) > 0$assert$::text,
       $detail$Only an active and unexpired token is rendered into guest URLs.$detail$::text),
      ('11_rotation_revokes_previous_token'::text,
       $assert$position('where guest_session_id = session_row.id' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('private.issue_guest_access_token(uuid,boolean,text)')))) > 0
and position('and status = ''active''' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('private.issue_guest_access_token(uuid,boolean,text)')))) > 0
and position('superseded by a new signed guest access token' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('private.issue_guest_access_token(uuid,boolean,text)')))) > 0$assert$::text,
       $detail$Explicit rotation revokes the previous active token before issuance.$detail$::text),
      ('12_one_active_token_per_stay'::text,
       $assert$exists (
  select 1 from pg_indexes
  where schemaname = 'public'
    and tablename = 'guest_access_tokens'
    and indexname = 'uq_guest_access_one_active_session_token'
)
and not exists (
  select 1
  from public.guest_access_tokens
  where status = 'active'
  group by guest_session_id
  having count(*) > 1
)$assert$::text,
       $detail$The database permits at most one active token per guest stay.$detail$::text),
      ('13_resolver_requires_active_token'::text,
       $assert$position('t.status = ''active''' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('private.resolve_guest_access_token(text,text,boolean)')))) > 0
and position('t.expires_at > now()' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('private.resolve_guest_access_token(text,text,boolean)')))) > 0$assert$::text,
       $detail$Revoked and expired token records cannot resolve.$detail$::text),
      ('14_resolver_requires_active_stay'::text,
       $assert$position('gs.status = ''active''' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('private.resolve_guest_access_token(text,text,boolean)')))) > 0
and position('coalesce(gs.extended_until, gs.checkout_time) > now()' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('private.resolve_guest_access_token(text,text,boolean)')))) > 0$assert$::text,
       $detail$Checkout and stay expiry invalidate previously signed URLs.$detail$::text),
      ('15_signed_token_format_contract'::text,
       $assert$position('extensions.hmac' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('private.render_guest_access_token(uuid)')))) > 0
and position('''sha256''' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('private.render_guest_access_token(uuid)')))) > 0
and position('token_row.token_nonce::text || ''.'' || signature' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('private.render_guest_access_token(uuid)')))) > 0$assert$::text,
       $detail$Rendered access uses UUID nonce plus SHA-256 HMAC signature.$detail$::text),
      ('16_tampered_signature_rejection_contract'::text,
       $assert$position('supplied_signature !~ ''^[0-9a-f]{64}$''' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('private.resolve_guest_access_token(text,text,boolean)')))) > 0
and position('expected_signature := encode' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('private.resolve_guest_access_token(text,text,boolean)')))) > 0
and position('extensions.digest' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('private.resolve_guest_access_token(text,text,boolean)')))) > 0$assert$::text,
       $detail$Malformed or altered signatures are rejected by the resolver.$detail$::text),
      ('17_hotel_slug_binding_contract'::text,
       $assert$position('lower(h.slug) = lower(trim(p_hotel_slug))' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('private.resolve_guest_access_token(text,text,boolean)')))) > 0$assert$::text,
       $detail$A signed token is bound to its hotel slug.$detail$::text),
      ('18_room_number_is_not_credential_contract'::text,
       $assert$position('token_parts := string_to_array(coalesce(trim(p_access_token), ''''), ''.'')' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('private.resolve_guest_access_token(text,text,boolean)')))) > 0
and position('supplied_nonce := token_parts[1]::uuid' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('private.resolve_guest_access_token(text,text,boolean)')))) > 0
and position('room_number' in lower((select p.prosrc from pg_proc p where p.oid = to_regprocedure('private.resolve_guest_access_token(text,text,boolean)')))) = 0$assert$::text,
       $detail$The resolver accepts signed UUID-plus-HMAC tokens, never room numbers.$detail$::text),
      ('19_no_raw_token_or_signing_secret'::text,
       $assert$not exists (
  select 1
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'guest_access_tokens'
    and column_name in ('token', 'access_token', 'secret', 'signing_secret')
)
and not exists (
  select 1
  from information_schema.role_table_grants
  where table_schema = 'private'
    and table_name = 'guest_access_signing_keys'
    and grantee in ('anon', 'authenticated', 'PUBLIC')
)$assert$::text,
       $detail$Raw tokens and signing secrets are not exposed to browser roles.$detail$::text),
      ('20_link_administration_not_anonymous'::text,
       $assert$has_function_privilege('authenticated', 'public.get_guest_access_links(uuid)', 'EXECUTE')
and has_function_privilege('authenticated', 'public.rotate_guest_access_token(uuid,uuid,text)', 'EXECUTE')
and has_function_privilege('authenticated', 'public.revoke_guest_access_token(uuid,uuid,text)', 'EXECUTE')
and not has_function_privilege('anon', 'public.get_guest_access_links(uuid)', 'EXECUTE')
and not has_function_privilege('anon', 'public.rotate_guest_access_token(uuid,uuid,text)', 'EXECUTE')
and not has_function_privilege('anon', 'public.revoke_guest_access_token(uuid,uuid,text)', 'EXECUTE')$assert$::text,
       $detail$Only authenticated hotel staff can administer secure guest links.$detail$::text),
      ('21_no_anonymous_table_access'::text,
       $assert$not exists (
  select 1
  from information_schema.role_table_grants
  where table_schema = 'public'
    and grantee = 'anon'
)
and not exists (
  select 1
  from pg_policies
  where schemaname = 'public'
    and roles && array['anon'::name, 'public'::name]
)$assert$::text,
       $detail$Anonymous access remains restricted to approved RPCs.$detail$::text),
      ('22_all_hotel_tables_have_rls'::text,
       $assert$not exists (
  select 1
  from information_schema.columns col
  join pg_class c on c.relname = col.table_name
  join pg_namespace n on n.oid = c.relnamespace and n.nspname = col.table_schema
  where col.table_schema = 'public'
    and col.column_name = 'hotel_id'
    and c.relkind in ('r', 'p')
    and not c.relrowsecurity
)$assert$::text,
       $detail$Every public table carrying hotel_id has RLS enabled.$detail$::text),
      ('23_guest_token_tenant_consistency'::text,
       $assert$not exists (
  select 1
  from public.guest_access_tokens t
  join public.guest_sessions gs on gs.id = t.guest_session_id
  join public.rooms r on r.id = t.room_id
  where t.hotel_id <> gs.hotel_id
     or t.room_id <> gs.room_id
     or t.hotel_id <> r.hotel_id
)$assert$::text,
       $detail$Every token remains bound to one hotel, room and authoritative stay.$detail$::text),
      ('24_private_storage_policy_contract'::text,
       $assert$(
  select count(*) = 2
  from storage.buckets
  where id in ('hotel-assets', 'guest-documents')
    and public = false
)
and (
  select count(*) = 8
  from pg_policies
  where schemaname = 'storage'
    and tablename = 'objects'
    and policyname in (
      'stayqr_hotel_assets_select',
      'stayqr_hotel_assets_insert',
      'stayqr_hotel_assets_update',
      'stayqr_hotel_assets_delete',
      'stayqr_guest_documents_select',
      'stayqr_guest_documents_insert',
      'stayqr_guest_documents_update',
      'stayqr_guest_documents_delete'
    )
)$assert$::text,
       $detail$Both StayQR Storage buckets are private and have all eight policies.$detail$::text)
    ) as checks(test_name, assertion_sql, success_details)
  loop
    begin
      execute 'select coalesce((' || check_row.assertion_sql || '), false)'
        into assertion_result;

      insert into pg_temp.stayqr_audit_038_results(test_name, passed, details)
      values (
        check_row.test_name,
        coalesce(assertion_result, false),
        case
          when coalesce(assertion_result, false)
            then check_row.success_details
          else 'FAILED: assertion returned false. ' || check_row.success_details
        end
      );
    exception when others then
      insert into pg_temp.stayqr_audit_038_results(test_name, passed, details)
      values (
        check_row.test_name,
        false,
        format('FAILED with SQLSTATE %s: %s', sqlstate, sqlerrm)
      );
    end;
  end loop;
end;
$audit$;

select test_name, passed, details
from pg_temp.stayqr_audit_038_results
order by test_name;
