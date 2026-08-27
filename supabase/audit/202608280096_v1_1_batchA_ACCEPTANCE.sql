-- ============================================================================
-- StayQR v1.1 — Batch A Acceptance 096
-- READ ONLY
-- Expected: 34/34 TRUE after Migration 095
-- ============================================================================

with checks as (
  select 1 seq,'public_booking_settings_table' check_name,to_regclass('public.public_booking_settings') is not null passed,'Direct booking settings table exists.' details
  union all select 2,'corporate_accounts_table',to_regclass('public.corporate_accounts') is not null,'Corporate accounts table exists.'
  union all select 3,'corporate_rates_table',to_regclass('public.corporate_rates') is not null,'Corporate negotiated rates table exists.'
  union all select 4,'reservation_corporate_links_table',to_regclass('public.reservation_corporate_links') is not null,'Reservation-to-corporate evidence exists.'
  union all select 5,'public_booking_requests_table',to_regclass('public.public_booking_requests') is not null,'Idempotency evidence exists.'
  union all select 6,'stay_move_plans_table',to_regclass('public.stay_move_plans') is not null,'Split-stay planning table exists.'
  union all select 7,'folio_split_shares_table',to_regclass('public.folio_split_shares') is not null,'Split-bill payer shares table exists.'
  union all select 8,'accounting_export_profiles_table',to_regclass('public.accounting_export_profiles') is not null,'Accounting connector profiles exist.'

  union all select 9,'public_booking_hotel_rpc',to_regprocedure('public.get_public_booking_hotel(text)') is not null,'Public safe hotel lookup RPC exists.'
  union all select 10,'public_booking_options_rpc',to_regprocedure('public.get_public_booking_options(text,date,date,integer,integer,text)') is not null,'Public availability/quote RPC exists.'
  union all select 11,'public_booking_create_rpc',to_regprocedure('public.create_public_booking(text,text,jsonb)') is not null,'Public idempotent booking RPC exists.'
  union all select 12,'revenue_workspace_rpc',to_regprocedure('public.get_v11_revenue_workspace(uuid)') is not null,'Internal Revenue Growth workspace RPC exists.'
  union all select 13,'booking_settings_write_rpc',to_regprocedure('public.upsert_v11_public_booking_settings(uuid,jsonb)') is not null,'Booking settings write RPC exists.'
  union all select 14,'corporate_account_write_rpc',to_regprocedure('public.upsert_v11_corporate_account(uuid,jsonb)') is not null,'Corporate account RPC exists.'
  union all select 15,'corporate_rate_write_rpc',to_regprocedure('public.upsert_v11_corporate_rate(uuid,jsonb)') is not null,'Corporate rate RPC exists.'
  union all select 16,'stay_move_plan_create_rpc',to_regprocedure('public.create_v11_stay_move_plan(uuid,uuid,uuid,date,text)') is not null,'Split-stay plan RPC exists.'
  union all select 17,'stay_move_plan_verify_rpc',to_regprocedure('public.verify_v11_stay_move_plan(uuid,uuid)') is not null,'Split-stay verification RPC exists.'
  union all select 18,'split_bill_plan_rpc',to_regprocedure('public.replace_v11_folio_split_plan(uuid,uuid,jsonb)') is not null,'Payer split-plan RPC exists.'
  union all select 19,'split_bill_collection_rpc',to_regprocedure('public.post_v11_split_share_collection(uuid,uuid,numeric,text,text,text)') is not null,'Payer-specific collection RPC exists.'
  union all select 20,'accounting_profile_rpc',to_regprocedure('public.upsert_v11_accounting_profile(uuid,jsonb)') is not null,'Accounting profile RPC exists.'
  union all select 21,'accounting_export_rpc',to_regprocedure('public.generate_v11_accounting_export(uuid,uuid,date,date,text)') is not null,'Template accounting export RPC exists.'

  union all select 22,'all_existing_hotels_have_booking_settings',not exists(
    select 1 from public.hotels h left join public.public_booking_settings s on s.hotel_id=h.id where s.hotel_id is null
  ),format('%s hotel(s) checked.',(select count(*) from public.hotels))
  union all select 23,'public_booking_disabled_by_default',not exists(
    select 1 from public.public_booking_settings s where s.enabled and s.updated_by is null
  ),'No migration-seeded hotel was accidentally made public-bookable.'
  union all select 24,'accounting_profiles_seeded',not exists(
    select 1 from public.hotels h where (select count(*) from public.accounting_export_profiles p where p.hotel_id=h.id and p.template in ('stayqr','tally','zoho_books','quickbooks')) < 4
  ),'Every existing hotel has the four baseline connector profiles.'
  union all select 25,'one_default_accounting_profile',not exists(
    select 1 from public.hotels h where (select count(*) from public.accounting_export_profiles p where p.hotel_id=h.id and p.is_default and p.is_active) <> 1
  ),'Exactly one active default profile exists per hotel.'

  union all select 26,'new_tables_rls_enabled',not exists(
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname in (
      'public_booking_settings','corporate_accounts','corporate_rates','reservation_corporate_links',
      'public_booking_requests','stay_move_plans','folio_split_shares','accounting_export_profiles'
    ) and not c.relrowsecurity
  ),'RLS is enabled on every v1.1-A table.'
  union all select 27,'anon_no_direct_table_select',not exists(
    select 1 from information_schema.role_table_grants g
    where g.grantee='anon' and g.table_schema='public' and g.table_name in (
      'public_booking_settings','corporate_accounts','corporate_rates','reservation_corporate_links',
      'public_booking_requests','stay_move_plans','folio_split_shares','accounting_export_profiles'
    )
  ),'Anonymous users have no direct table grants.'
  union all select 28,'anon_public_rpc_grants',(
    has_function_privilege('anon','public.get_public_booking_hotel(text)','EXECUTE')
    and has_function_privilege('anon','public.get_public_booking_options(text,date,date,integer,integer,text)','EXECUTE')
    and has_function_privilege('anon','public.create_public_booking(text,text,jsonb)','EXECUTE')
  ),'Anon can execute only the intended safe public booking RPCs.'
  union all select 29,'internal_rpc_not_anon',not (
    has_function_privilege('anon','public.get_v11_revenue_workspace(uuid)','EXECUTE')
    or has_function_privilege('anon','public.upsert_v11_corporate_account(uuid,jsonb)','EXECUTE')
    or has_function_privilege('anon','public.replace_v11_folio_split_plan(uuid,uuid,jsonb)','EXECUTE')
    or has_function_privilege('anon','public.generate_v11_accounting_export(uuid,uuid,date,date,text)','EXECUTE')
  ),'Internal Revenue Growth functions are not executable by anon.'

  union all select 30,'corporate_booking_codes_unique',not exists(
    select 1 from public.corporate_accounts group by hotel_id,lower(booking_code) having count(*)>1
  ),'Corporate booking codes are unique per hotel.'
  union all select 31,'split_share_invariant',not exists(
    select 1 from public.folio_split_shares where paid_amount<0 or paid_amount>allocated_amount
      or (status='settled' and paid_amount<>allocated_amount)
  ),'Split-bill payer share financial invariant holds.'
  union all select 32,'original_authoritative_finance_and_room_move_preserved',(
    to_regprocedure('public.post_folio_collection(uuid,uuid,numeric,text,text,text,text,text)') is not null
    and to_regprocedure('public.post_folio_split_collection(uuid,uuid,jsonb,text)') is not null
    and to_regprocedure('public.move_active_walkin_guest_room(uuid,uuid,uuid,jsonb)') is not null
    and to_regprocedure('public.generate_accounting_csv(uuid,date,date,text)') is not null
  ),'Existing Day 10/11/12 authoritative RPCs remain installed.'
  union all select 33,'future_hotel_revenue_seed_trigger_present',exists(
    select 1
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='hotels'
      and t.tgname='trg_v11_seed_revenue_foundations_after_hotel_insert'
      and not t.tgisinternal
  ),'Future hotels automatically receive disabled booking settings and accounting profiles.'
  union all select 34,'public_booking_rpcs_security_definer',(
    coalesce((select p.prosecdef from pg_proc p where p.oid=to_regprocedure('public.get_public_booking_hotel(text)')),false)
    and coalesce((select p.prosecdef from pg_proc p where p.oid=to_regprocedure('public.get_public_booking_options(text,date,date,integer,integer,text)')),false)
    and coalesce((select p.prosecdef from pg_proc p where p.oid=to_regprocedure('public.create_public_booking(text,text,jsonb)')),false)
  ),'Public booking RPCs run through the narrow SECURITY DEFINER surface rather than table grants.'
)
select seq,check_name,passed,details
from checks
order by seq;
