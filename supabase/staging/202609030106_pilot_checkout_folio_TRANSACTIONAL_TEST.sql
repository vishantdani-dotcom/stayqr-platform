-- STAGING ONLY: eecinuhvkxlbdvyuazal. No test records or money movements persist.
-- Every scenario is rolled back, then the entire transaction is rolled back.
begin;
set local statement_timeout = '120s';
select set_config('request.jwt.claim.sub', 'fe46129f-afe4-4d2d-b3fc-e8cbf95d9aae', true);
select set_config('request.jwt.claims', '{"sub":"fe46129f-afe4-4d2d-b3fc-e8cbf95d9aae","role":"authenticated"}', true);
set local role authenticated;
do $test$
declare
  hotel_id_value constant uuid := 'c6f16ea5-dcb0-40c3-a483-e628a5ea177c';
  room_id_value constant uuid := 'f7afde3e-ca57-473a-bf69-3e82b8755b72';
  scenario record;
  checkin_result jsonb;
  checkout_result jsonb;
  approval_result jsonb;
  session_id_value uuid;
  folio_row public.folios%rowtype;
  invoice_row public.invoices%rowtype;
  before_count integer;
  expected_total numeric;
  prior_collection numeric;
  rejected boolean;
  passed integer := 0;
begin
  if not exists (select 1 from public.hotels where id = hotel_id_value and slug = '20e-test-hotel')
     or not exists (select 1 from public.rooms where hotel_id = hotel_id_value and id = room_id_value and status = 'available') then
    raise exception 'Staging fixture guard failed; no occupied room may be used.';
  end if;
  for scenario in select * from (values
    ('full_fixed', 0::numeric, 'fixed', 2500::numeric, 0::numeric, null::text),
    ('full_percentage', 0, 'percentage', 100, 0, null),
    ('partial', 0, 'fixed', 500, 0, null),
    ('no_discount', 0, 'fixed', 0, 0, null),
    ('tax_full_discount', 12, 'fixed', 2800, 0, null),
    ('tax_partial_discount', 12, 'fixed', 500, 0, null),
    ('prepaid_partial_discount', 0, 'fixed', 500, 0, null),
    ('prepaid_settled_discount', 0, 'fixed', 500, 0, null),
    ('existing_discount_no_duplicate', 0, 'fixed', 500, 500, null),
    ('existing_discount_delta_only', 0, 'fixed', 500, 250, null),
    ('existing_discount_conflict', 0, 'fixed', 0, 500, 'below amounts already posted'),
    ('reason_required', 0, 'fixed', 2500, 0, 'reason in invoice notes')
  ) as cases(name, tax_rate, discount_type, discount_value, existing_discount, expected_error)
  loop
    begin
      checkin_result := public.check_in_walk_in_guest(hotel_id_value, jsonb_build_object(
        'request_id', gen_random_uuid()::text, 'room_id', room_id_value,
        'checkin_time', now() - interval '1 minute', 'checkout_time', now() + interval '1 hour',
        'room_charge', 2500, 'adults', 1, 'children', 0,
        'guest', jsonb_build_object('full_name', 'ROLLED BACK - folio regression', 'preferred_language', 'en'),
        'companions', '[]'::jsonb, 'stay_details', '{}'::jsonb,
        'notes', 'Staging transactional test; no real guest or payment.'
      ));
      session_id_value := (checkin_result ->> 'guest_session_id')::uuid;
      select * into strict folio_row from public.folios where hotel_id = hotel_id_value and guest_session_id = session_id_value;
      if scenario.existing_discount > 0 then
        approval_result := public.request_folio_discount(hotel_id_value, folio_row.id, 'fixed',
          scenario.existing_discount, 'ROLLED BACK - existing discount', gen_random_uuid()::text);
        perform public.review_folio_discount(hotel_id_value, (approval_result -> 'approval' ->> 'id')::uuid,
          true, 'ROLLED BACK - test approval', gen_random_uuid()::text);
      end if;
      expected_total := 2500 + 2500 * scenario.tax_rate / 100 -
        case when scenario.discount_type = 'percentage' then (2500 + 2500 * scenario.tax_rate / 100) * scenario.discount_value / 100
        else scenario.discount_value end;
      prior_collection := case scenario.name when 'prepaid_partial_discount' then 500
        when 'prepaid_settled_discount' then 2000 else 0 end;
      if prior_collection > 0 then
        perform public.post_folio_collection(hotel_id_value, folio_row.id, prior_collection,
          'cash', 'ROLLED BACK TEST ONLY', null, null, gen_random_uuid()::text);
      end if;
      rejected := false;
      begin
        checkout_result := public.checkout_guest_session(hotel_id_value, session_id_value,
          scenario.tax_rate, scenario.discount_type, scenario.discount_value,
          expected_total > 0, 'cash', null,
          case when scenario.name = 'reason_required' then null else 'ROLLED BACK - approved test discount; no real money.' end, false);
      exception when others then
        if scenario.expected_error is null or position(scenario.expected_error in sqlerrm) = 0 then raise; end if;
        rejected := true;
      end;
      if scenario.expected_error is not null then
        if not rejected then raise exception 'Expected rejection missing: %', scenario.name; end if;
        if exists (select 1 from public.invoices where hotel_id = hotel_id_value and guest_session_id = session_id_value)
           or not exists (select 1 from public.guest_sessions where id = session_id_value and status = 'active') then
          raise exception 'Rejected checkout changed the stay/invoice.';
        end if;
      else
        select * into strict invoice_row from public.invoices where hotel_id = hotel_id_value and id = (checkout_result ->> 'invoice_id')::uuid;
        select * into strict folio_row from public.folios where hotel_id = hotel_id_value and id = invoice_row.folio_id;
        if folio_row.balance_amount <> 0 or folio_row.status <> 'settled'
           or folio_row.charges_amount <> 2500 or folio_row.tax_amount <> invoice_row.tax_amount
           or folio_row.discount_amount <> invoice_row.discount_amount
           or folio_row.collection_amount <> expected_total
           or (checkout_result ->> 'previously_paid')::numeric <> prior_collection
           or (checkout_result ->> 'amount_collected_at_checkout')::numeric <> expected_total - prior_collection
           or invoice_row.total_amount <> expected_total or invoice_row.pending_amount <> 0
           or invoice_row.paid_amount <> expected_total or invoice_row.finalized_at is null then
          raise exception 'Invoice/folio mismatch in %: invoice total %, folio balance %, discount %, collections %',
            scenario.name, invoice_row.total_amount, folio_row.balance_amount, folio_row.discount_amount, folio_row.collection_amount;
        end if;
        if expected_total = 0 and (exists (select 1 from public.payment_collections where hotel_id = hotel_id_value and guest_session_id = session_id_value)
          or exists (select 1 from public.folio_collections where hotel_id = hotel_id_value and folio_id = folio_row.id)) then
          raise exception 'Complimentary checkout created a collection.';
        end if;
        if exists (select 1 from public.folio_adjustments a left join public.discount_approvals d on d.id = a.approval_id
          where a.hotel_id = hotel_id_value and a.folio_id = folio_row.id
            and (d.status is distinct from 'approved' or d.reviewed_by is null or d.hotel_id <> a.hotel_id or d.folio_id <> a.folio_id)) then
          raise exception 'Discount lacks same-hotel approval evidence.';
        end if;
        select count(*) into before_count from public.folio_adjustments where hotel_id = hotel_id_value and folio_id = folio_row.id;
        if scenario.name = 'existing_discount_no_duplicate' and before_count <> 1 then raise exception 'Existing discount duplicated.'; end if;
        if scenario.name = 'existing_discount_delta_only' and before_count <> 2 then raise exception 'Only delta should be approved.'; end if;
        rejected := false;
        begin
          perform public.checkout_guest_session(hotel_id_value, session_id_value, 0, 'fixed', 0, false, 'cash', null, 'duplicate', false);
        exception when others then
          if sqlerrm not ilike '%already checked out%' then raise; end if;
          rejected := true;
        end;
        if not rejected or before_count <> (select count(*) from public.folio_adjustments where hotel_id = hotel_id_value and folio_id = folio_row.id) then
          raise exception 'Duplicate checkout changed discount evidence.';
        end if;
      end if;
      raise sqlstate 'ZX001' using message = 'scenario passed; roll back fixture';
    exception when sqlstate 'ZX001' then
      passed := passed + 1;
      raise notice 'PASS % (all scenario records rolled back)', scenario.name;
    end;
  end loop;
  if passed <> 12 then raise exception 'Expected 12 scenarios, got %', passed; end if;
end;
$test$;
do $security$
declare
  rejected boolean;
begin
  rejected := false;
  begin
    perform public.checkout_guest_session('00000000-0000-0000-0000-000000000106',
      'e50ee898-1edd-44f2-b2de-bbbc78de8a95', 0, 'fixed', 2500, false, 'cash', null, 'cross-hotel test', false);
  exception when others then
    if sqlerrm <> 'Reservation write access denied.' then raise; end if;
    rejected := true;
  end;
  if not rejected then raise exception 'Cross-hotel checkout was not denied.'; end if;
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000107', true);
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000107","role":"authenticated"}', true);
  rejected := false;
  begin
    perform public.checkout_guest_session('c6f16ea5-dcb0-40c3-a483-e628a5ea177c',
      'e50ee898-1edd-44f2-b2de-bbbc78de8a95', 0, 'fixed', 2500, false, 'cash', null, 'denied actor test', false);
  exception when others then
    if sqlerrm <> 'Reservation write access denied.' then raise; end if;
    rejected := true;
  end;
  if not rejected then raise exception 'Unprivileged actor checkout was not denied.'; end if;
end;
$security$;
reset role;
do $acl$
begin
  if has_function_privilege('anon', 'private.pilot_prepare_checkout_folio(uuid,uuid,numeric,numeric,numeric,numeric,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'private.pilot_prepare_checkout_folio(uuid,uuid,numeric,numeric,numeric,numeric,text)', 'EXECUTE') then
    raise exception 'Private helper must not be callable directly by browser roles.';
  end if;
end;
$acl$;
rollback;
select 'PASS 12 checkout/folio scenarios + 3 authorization checks; all fixtures and simulated collections rolled back.' as result;
