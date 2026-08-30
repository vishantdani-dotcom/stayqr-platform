-- ============================================================================
-- StayQR v1.1 — Batch B Acceptance 099
-- READ ONLY / structural + security acceptance
-- Expected: 44 / 44 TRUE after Migration 098
-- ============================================================================

begin transaction read only;

with tests(seq,check_name,passed,details) as (
  values
  (1,'laundry_orders_table',to_regclass('public.laundry_orders') is not null,'Dedicated laundry workflow table'),
  (2,'lost_found_items_table',to_regclass('public.lost_found_items') is not null,'Lost and found custody table'),
  (3,'inventory_items_table',to_regclass('public.inventory_items') is not null,'Consumable inventory master'),
  (4,'inventory_movements_table',to_regclass('public.inventory_movements') is not null,'Atomic stock movement ledger'),
  (5,'kitchen_printer_profiles_table',to_regclass('public.kitchen_printer_profiles') is not null,'KOT printer profiles'),
  (6,'kitchen_print_events_table',to_regclass('public.kitchen_print_events') is not null,'KOT print audit events'),
  (7,'scheduled_report_jobs_table',to_regclass('public.scheduled_report_jobs') is not null,'Scheduled report jobs'),
  (8,'scheduled_report_runs_table',to_regclass('public.scheduled_report_runs') is not null,'Scheduled report snapshots'),

  (9,'laundry_rls',coalesce((select relrowsecurity from pg_class where oid='public.laundry_orders'::regclass),false),'Laundry RLS enabled'),
  (10,'lost_found_rls',coalesce((select relrowsecurity from pg_class where oid='public.lost_found_items'::regclass),false),'Lost-found RLS enabled'),
  (11,'inventory_items_rls',coalesce((select relrowsecurity from pg_class where oid='public.inventory_items'::regclass),false),'Inventory item RLS enabled'),
  (12,'inventory_movements_rls',coalesce((select relrowsecurity from pg_class where oid='public.inventory_movements'::regclass),false),'Inventory movement RLS enabled'),
  (13,'printer_profiles_rls',coalesce((select relrowsecurity from pg_class where oid='public.kitchen_printer_profiles'::regclass),false),'Printer profile RLS enabled'),
  (14,'print_events_rls',coalesce((select relrowsecurity from pg_class where oid='public.kitchen_print_events'::regclass),false),'Print event RLS enabled'),
  (15,'report_jobs_rls',coalesce((select relrowsecurity from pg_class where oid='public.scheduled_report_jobs'::regclass),false),'Scheduled job RLS enabled'),
  (16,'report_runs_rls',coalesce((select relrowsecurity from pg_class where oid='public.scheduled_report_runs'::regclass),false),'Scheduled run RLS enabled'),

  (17,'workspace_rpc',to_regprocedure('public.get_v11_operations_workspace(uuid)') is not null,'Operations workspace RPC'),
  (18,'laundry_create_rpc',to_regprocedure('public.create_v11_laundry_order(uuid,jsonb)') is not null,'Laundry create RPC'),
  (19,'laundry_status_rpc',to_regprocedure('public.update_v11_laundry_status(uuid,uuid,text,text)') is not null,'Laundry lifecycle RPC'),
  (20,'lost_found_create_rpc',to_regprocedure('public.create_v11_lost_found_item(uuid,jsonb)') is not null,'Lost-found create RPC'),
  (21,'lost_found_transition_rpc',to_regprocedure('public.transition_v11_lost_found_item(uuid,uuid,text,jsonb)') is not null,'Lost-found transition RPC'),
  (22,'inventory_upsert_rpc',to_regprocedure('public.upsert_v11_inventory_item(uuid,jsonb)') is not null,'Inventory master RPC'),
  (23,'inventory_movement_rpc',to_regprocedure('public.post_v11_inventory_movement(uuid,uuid,text,numeric,text,text)') is not null,'Atomic inventory movement RPC'),
  (24,'printer_profile_rpc',to_regprocedure('public.upsert_v11_kitchen_printer_profile(uuid,jsonb)') is not null,'Printer profile RPC'),
  (25,'kot_prepare_rpc',to_regprocedure('public.prepare_v11_kot_print(uuid,uuid,uuid)') is not null,'KOT wrapper/audit RPC'),
  (26,'report_job_rpc',to_regprocedure('public.upsert_v11_scheduled_report_job(uuid,jsonb)') is not null,'Scheduled report job RPC'),
  (27,'report_runner_rpc',to_regprocedure('public.run_due_v11_scheduled_reports(uuid,boolean)') is not null,'Idempotent due-report runner'),

  (28,'inventory_request_key_unique',exists(
    select 1 from pg_indexes where schemaname='public' and tablename='inventory_movements' and indexdef ilike '%request_key%' and indexdef ilike '%unique%'
  ),'Inventory retries cannot create duplicate movement keys'),
  (29,'scheduled_run_unique',exists(
    select 1 from pg_constraint where conrelid='public.scheduled_report_runs'::regclass and contype='u'
  ),'A scheduled timestamp is generated at most once per job'),
  (30,'single_default_printer_index',exists(
    select 1 from pg_indexes where schemaname='public' and indexname='uq_kitchen_printer_default'
  ),'At most one active default KOT profile per hotel'),
  (31,'laundry_number_unique',exists(
    select 1 from pg_constraint where conrelid='public.laundry_orders'::regclass and contype='u'
  ),'Laundry order number is tenant-unique'),
  (32,'lost_found_number_unique',exists(
    select 1 from pg_constraint where conrelid='public.lost_found_items'::regclass and contype='u'
  ),'Lost-found item number is tenant-unique'),

  (33,'anon_no_laundry_table',not has_table_privilege('anon','public.laundry_orders','SELECT'),'Anonymous users cannot read laundry data'),
  (34,'anon_no_lost_found_table',not has_table_privilege('anon','public.lost_found_items','SELECT'),'Anonymous users cannot read lost-found data'),
  (35,'anon_no_inventory_table',not has_table_privilege('anon','public.inventory_items','SELECT'),'Anonymous users cannot read inventory'),
  (36,'anon_no_report_jobs_table',not has_table_privilege('anon','public.scheduled_report_jobs','SELECT'),'Anonymous users cannot read schedules'),
  (37,'authenticated_no_inventory_direct_insert',not has_table_privilege('authenticated','public.inventory_movements','INSERT'),'Stock writes are RPC-only'),
  (38,'authenticated_no_laundry_direct_insert',not has_table_privilege('authenticated','public.laundry_orders','INSERT'),'Laundry writes are RPC-only'),
  (39,'authenticated_no_report_direct_insert',not has_table_privilege('authenticated','public.scheduled_report_runs','INSERT'),'Report run writes are RPC-only'),

  (40,'existing_kot_authority_preserved',to_regprocedure('public.get_food_order_kot(uuid,uuid)') is not null,'Day 15 KOT authority remains present'),
  (41,'existing_report_authority_preserved',to_regprocedure('public.get_report_export_rows(uuid,date,date,text,jsonb)') is not null,'Day 16 report authority remains present'),
  (42,'future_hotel_seed_trigger',exists(
    select 1 from pg_trigger where tgrelid='public.hotels'::regclass and tgname='trg_v11b_seed_ops_foundations_after_hotel_insert' and not tgisinternal
  ),'Future hotels receive a default KOT profile'),
  (43,'existing_hotels_have_printer_profile',not exists(
    select 1 from public.hotels h where not exists(select 1 from public.kitchen_printer_profiles p where p.hotel_id=h.id and p.is_active)
  ),'Every existing hotel has at least one active KOT profile'),
  (44,'no_anon_rpc_execution',
    not has_function_privilege('anon','public.get_v11_operations_workspace(uuid)','EXECUTE')
    and not has_function_privilege('anon','public.post_v11_inventory_movement(uuid,uuid,text,numeric,text,text)','EXECUTE')
    and not has_function_privilege('anon','public.run_due_v11_scheduled_reports(uuid,boolean)','EXECUTE'),
    'No anonymous execution on operations RPC surface')
)
select * from tests order by seq;

rollback;
