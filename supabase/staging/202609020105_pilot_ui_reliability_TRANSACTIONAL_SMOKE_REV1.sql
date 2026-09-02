-- STAGING ONLY: eecinuhvkxlbdvyuazal / 20E Test Hotel.
-- Every generated stay, invoice, task and audit event is rolled back.
begin;
select set_config('request.jwt.claim.sub', 'fe46129f-afe4-4d2d-b3fc-e8cbf95d9aae', true);
select set_config('request.jwt.claims', jsonb_build_object('sub', 'fe46129f-afe4-4d2d-b3fc-e8cbf95d9aae', 'role', 'authenticated')::text, true);
set local role authenticated;

do $smoke$
declare
  hotel_id_value constant uuid := 'c6f16ea5-dcb0-40c3-a483-e628a5ea177c';
  room_id_value constant uuid := 'f7afde3e-ca57-473a-bf69-3e82b8755b72';
  checkin_result jsonb;
  checkout_result jsonb;
  session_id_value uuid;
  invoice_row public.invoices%rowtype;
  snapshot_number text;
  task_notes text;
  duplicate_rejected boolean := false;
begin
  if not exists (select 1 from public.hotels where id = hotel_id_value and slug = '20e-test-hotel') then
    raise exception 'Staging fixture guard failed.';
  end if;
  if not exists (select 1 from public.rooms where id = room_id_value and hotel_id = hotel_id_value and status = 'available') then
    raise exception 'Staging test room must be available; no existing stay will be modified.';
  end if;
  checkin_result := public.check_in_walk_in_guest(hotel_id_value, jsonb_build_object(
    'request_id', gen_random_uuid()::text, 'room_id', room_id_value,
    'checkin_time', now() - interval '1 minute', 'checkout_time', now() + interval '1 hour',
    'room_charge', 2500, 'adults', 1, 'children', 0,
    'guest', jsonb_build_object('full_name', 'Pilot UI Regression - rolled back', 'preferred_language', 'en'),
    'companions', '[]'::jsonb, 'stay_details', '{}'::jsonb,
    'notes', 'Transactional staging regression; no real guest or payment.'
  ));
  session_id_value := (checkin_result->>'guest_session_id')::uuid;
  if session_id_value is null then raise exception 'Check-in returned no stay ID.'; end if;

  checkout_result := public.checkout_guest_session(hotel_id_value, session_id_value, 0, 'fixed', 2500, false, 'cash', null,
    'Complimentary staging regression; no payment collected; rolled back.', false);
  select * into strict invoice_row from public.invoices
    where hotel_id = hotel_id_value and id = (checkout_result->>'invoice_id')::uuid;
  if checkout_result->>'invoice_number' is distinct from invoice_row.invoice_number then
    raise exception 'Invoice reference regression: response %, persisted %', checkout_result->>'invoice_number', invoice_row.invoice_number;
  end if;
  select settlement_snapshot->>'invoice_number' into strict snapshot_number
    from public.reservation_checkout_events where hotel_id = hotel_id_value and guest_session_id = session_id_value;
  if snapshot_number is distinct from invoice_row.invoice_number then raise exception 'Checkout evidence uses a different invoice reference.'; end if;
  select notes into strict task_notes from public.housekeeping_tasks
    where hotel_id = hotel_id_value and id = (checkout_result->>'housekeeping_task_id')::uuid;
  if position(invoice_row.invoice_number in task_notes) = 0 then raise exception 'Housekeeping evidence uses a different invoice reference.'; end if;
  if invoice_row.total_amount <> 0 or invoice_row.paid_amount <> 0 or invoice_row.pending_amount <> 0
    or (checkout_result->>'amount_collected_at_checkout')::numeric <> 0 then
    raise exception 'Complimentary checkout must have zero invoice balance and zero collection.';
  end if;
  if exists (select 1 from public.payment_collections where hotel_id = hotel_id_value and guest_session_id = session_id_value) then
    raise exception 'No synthetic payment collection may be created.';
  end if;
  begin
    perform public.checkout_guest_session(hotel_id_value, session_id_value, 0, 'fixed', 2500, false, 'cash', null, 'Duplicate regression', false);
  exception when others then
    if sqlerrm not ilike '%already checked out%' then raise; end if;
    duplicate_rejected := true;
  end;
  if not duplicate_rejected then raise exception 'Duplicate checkout was not rejected.'; end if;
end;
$smoke$;

rollback;
select 'PASS: persisted invoice number, checkout evidence, housekeeping note, zero collection, duplicate rejection; all test records rolled back.' as result;
