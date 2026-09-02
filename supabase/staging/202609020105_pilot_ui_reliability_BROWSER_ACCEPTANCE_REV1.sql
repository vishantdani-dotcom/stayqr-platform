-- Read-only verification of the 3 September 2026 browser regression fixtures.
-- Run only against staging project eecinuhvkxlbdvyuazal. Creates no records.
begin read only;
with fixture as (
  select 'c6f16ea5-dcb0-40c3-a483-e628a5ea177c'::uuid as hotel_id,
         'e50ee898-1edd-44f2-b2de-bbbc78de8a95'::uuid as session_id
), invoice as (
  select i.* from public.invoices i, fixture f
  where i.hotel_id = f.hotel_id and i.guest_session_id = f.session_id
), cleaning as (
  select t.* from public.housekeeping_tasks t, fixture f
  where t.hotel_id = f.hotel_id and t.source_guest_session_id = f.session_id
), cancellation as (
  select t.* from public.housekeeping_tasks t, fixture f
  where t.hotel_id = f.hotel_id and t.id = 'f84f255e-a39a-4554-87d2-cc4b75679696'
), food as (
  select o.* from public.food_orders o, fixture f
  where o.hotel_id = f.hotel_id and o.guest_session_id = f.session_id
), checks(test_name, passed) as (values
  ('01_expected_staging_stay_completed', (select count(*) = 1 from public.guest_sessions s join fixture f on s.id = f.session_id and s.hotel_id = f.hotel_id join public.hotels h on h.id = f.hotel_id where h.slug = '20e-test-hotel' and s.status = 'completed')),
  ('02_single_zero_total_invoice', (select count(*) = 1 and bool_and(total_amount = 0 and paid_amount = 0 and pending_amount = 0 and food_amount = 0) from invoice)),
  ('03_checkout_evidence_matches_invoice', (select count(*) = 1 and bool_and(e.settlement_snapshot->>'invoice_number' = i.invoice_number) from public.reservation_checkout_events e join fixture f on e.hotel_id = f.hotel_id and e.guest_session_id = f.session_id join invoice i on i.guest_session_id = e.guest_session_id)),
  ('04_no_payment_collections', (select count(*) = 0 from public.payment_collections p, fixture f where p.hotel_id = f.hotel_id and p.guest_session_id = f.session_id)),
  ('05_single_cancelled_food_order', (select count(*) = 1 and bool_and(order_status = 'cancelled' and total_amount = 20) from food)),
  ('06_single_food_cancellation_with_reason', (select count(*) = 1 and bool_and(e.message = 'STAGING QA c8d923a: deliberate cancellation regression; no food prepared and no payment collected.') from public.food_order_events e join food o on o.id = e.food_order_id and o.hotel_id = e.hotel_id where e.to_status = 'cancelled')),
  ('07_existing_hotel_owner_assigned', (select count(*) = 1 and bool_and(t.assigned_staff_id = '576291e8-2b10-4c53-8318-54e9a583c5c7') from cleaning t)),
  ('08_all_eight_checklist_items_complete', (select count(*) = 8 and bool_and(i.item_status = 'completed') from public.housekeeping_task_items i join cleaning t on t.id = i.task_id and t.hotel_id = i.hotel_id)),
  ('09_failure_reason_saved_once', (select count(*) = 1 and bool_and(i.notes = 'STAGING QA c8d923a: simulated inspection failure to verify rework. No real room defect.') from public.housekeeping_inspections i join cleaning t on t.id = i.task_id and t.hotel_id = i.hotel_id where i.result = 'failed')),
  ('10_optional_blank_pass_notes_saved_once', (select count(*) = 1 and bool_and(coalesce(trim(i.notes), '') = '') from public.housekeeping_inspections i join cleaning t on t.id = i.task_id and t.hotel_id = i.hotel_id where i.result = 'passed')),
  ('11_rework_cycle_audited', (select count(*) filter (where e.event_type = 'started') = 2 and count(*) filter (where e.event_type = 'cleaning_completed') = 2 and count(*) filter (where e.event_type = 'inspection_failed') = 1 and count(*) filter (where e.event_type = 'inspection_passed') = 1 from public.housekeeping_task_events e join cleaning t on t.id = e.task_id and t.hotel_id = e.hotel_id)),
  ('12_cleaning_ready_with_canonical_invoice_note', (select count(*) = 1 and bool_and(t.status = 'ready' and position(i.invoice_number in t.notes) > 0) from cleaning t join invoice i on i.guest_session_id = t.source_guest_session_id and i.hotel_id = t.hotel_id)),
  ('13_dummy_task_cancelled_with_reason', (select count(*) = 1 and bool_and(status = 'cancelled' and cancellation_reason = 'STAGING QA c8d923a: cancellation verified; dummy task only, no real housekeeping work requested.') from cancellation)),
  ('14_dummy_cancellation_audited_once', (select count(*) = 1 from public.housekeeping_task_events e join cancellation t on t.id = e.task_id and t.hotel_id = e.hotel_id where e.event_type = 'cancelled')),
  ('15_guest_tokens_revoked', (select count(*) > 0 and bool_and(a.status = 'revoked') from public.guest_access_tokens a, fixture f where a.hotel_id = f.hotel_id and a.guest_session_id = f.session_id)),
  ('16_both_staging_rooms_available', (select count(*) = 2 and bool_and(r.status = 'available') from public.rooms r, fixture f where r.hotel_id = f.hotel_id and r.room_number in ('101','102'))),
  ('17_no_open_room_102_tasks', (select count(*) = 0 from public.housekeeping_tasks t, fixture f where t.hotel_id = f.hotel_id and t.room_id = 'f7afde3e-ca57-473a-bf69-3e82b8755b72' and t.status not in ('ready','completed','cancelled'))),
  ('18_cashfree_still_unconfigured', (select count(*) = 1 and bool_and(status = 'pending' and environment = 'not_configured') from public.platform_provider_readiness where provider_key = 'cashfree_recurring'))
)
select test_name, coalesce(passed, false) as passed,
       count(*) over () as total_checks,
       count(*) filter (where passed) over () as passed_checks,
       count(*) filter (where not coalesce(passed, false)) over () as failed_checks
from checks order by test_name;
rollback;
