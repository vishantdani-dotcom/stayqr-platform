-- Fragment composed inside the staging-only rollback transaction by the runner.
-- RPC calls run as authenticated under production-equivalent finance grants.
do $issued_tests$
declare
  hotel_id_value constant uuid := 'c6f16ea5-dcb0-40c3-a483-e628a5ea177c';
  room_id_value constant uuid := 'f7afde3e-ca57-473a-bf69-3e82b8755b72';
  scenario record;
  checked_in jsonb;
  result_value jsonb;
  approval_result jsonb;
  collection_result jsonb;
  refund_result jsonb;
  session_value uuid;
  invoice_value public.invoices%rowtype;
  folio_value public.folios%rowtype;
  invoice_before jsonb;
  folio_before jsonb;
  evidence_before jsonb;
  snapshot_value jsonb;
  token_value uuid;
  expected_total numeric;
  rejected boolean;
  passed integer := 0;
begin
  for scenario in select * from (values
    ('native_paid_stale_pending', false, 0::numeric, 0::numeric, 0::numeric, null::text),
    ('native_full_discount', false, 2500, 2500, 0, null),
    ('native_partial_discount', false, 500, 500, 0, null),
    ('native_direct_legacy', false, 500, 500, 0, null),
    ('compat_missing_full_discount', true, 2500, 0, 0, null),
    ('compat_discount_delta', true, 500, 250, 0, null),
    ('compat_missing_tax_full_discount', true, 2800, 0, 12, null),
    ('unpaid_invoice_rejected', false, 0, 0, 0, 'authoritative folio balance'),
    ('tax_mismatch_rejected', false, 0, 0, 0, 'uses tax'),
    ('discount_mismatch_rejected', false, 0, 0, 0, 'uses discount value'),
    ('charge_discrepancy_rejected', false, 0, 0, 0, 'folio charges differ'),
    ('refunded_pending_rejected', false, 0, 0, 0, 'authoritative folio balance'),
    ('refunded_recollected', false, 0, 0, 0, null),
    ('credit_requires_review', false, 0, 0, 0, 'authoritative folio balance'),
    ('missing_reason_rejected', true, 2500, 0, 0, 'reason in invoice notes')
  ) as cases(name, compatibility, desired_discount, prior_discount, tax_rate, expected_error) loop
    begin
      execute 'set local role authenticated';
      if current_user <> 'authenticated' then raise exception 'Test must run under authenticated role.'; end if;
      checked_in := public.check_in_walk_in_guest(hotel_id_value, jsonb_build_object(
        'request_id', gen_random_uuid()::text, 'room_id', room_id_value,
        'checkin_time', now() - interval '1 minute', 'checkout_time', now() + interval '1 hour',
        'room_charge', 2500, 'adults', 1, 'children', 0,
        'guest', jsonb_build_object('full_name', 'ROLLED BACK - issued checkout 107', 'preferred_language', 'en'),
        'companions', '[]'::jsonb, 'stay_details', '{}'::jsonb,
        'notes', 'Synthetic staging fixture; all records and simulated money are rolled back.'
      ));
      session_value := (checked_in ->> 'guest_session_id')::uuid;
      select * into strict folio_value from public.folios where hotel_id=hotel_id_value and guest_session_id=session_value;
      if scenario.prior_discount > 0 then
        approval_result := public.request_folio_discount(hotel_id_value,folio_value.id,'fixed',scenario.prior_discount,
          'ROLLED BACK - approved fixture discount',gen_random_uuid()::text);
        perform public.review_folio_discount(hotel_id_value,(approval_result->'approval'->>'id')::uuid,true,
          'ROLLED BACK - test approval',gen_random_uuid()::text);
      end if;
      expected_total := 2500 + 2500*scenario.tax_rate/100 - scenario.desired_discount;
      if scenario.compatibility then
        -- Isolated legacy-format fixture setup only; the checkout itself is NOT privileged.
        execute 'reset role';
        insert into public.invoices(hotel_id,guest_session_id,room_id,guest_id,invoice_number,
          room_amount,food_amount,manual_amount,service_amount,subtotal_amount,tax_percent,tax_amount,
          discount_type,discount_value,discount_amount,previous_paid_amount,amount_to_collect,total_amount,
          payment_status,invoice_status,paid_amount,pending_amount,checkin_time,checkout_time,stay_hours,stay_nights,invoice_notes)
        select hotel_id_value,session_value,s.room_id,s.guest_id,'ROLLED-BACK-'||gen_random_uuid()::text,
          2500,0,0,0,2500,scenario.tax_rate,2500*scenario.tax_rate/100,
          'fixed',scenario.desired_discount,scenario.desired_discount,expected_total,0,expected_total,
          'paid','paid',expected_total,0,s.checkin_time,now(),1,1,'ROLLED BACK - old-format issued test invoice'
        from public.guest_sessions s where s.hotel_id=hotel_id_value and s.id=session_value
        returning * into invoice_value;
        insert into public.invoice_items(invoice_id,hotel_id,guest_id,room_id,item_type,description,quantity,unit_price,amount,source_id)
        values(invoice_value.id,hotel_id_value,invoice_value.guest_id,invoice_value.room_id,'room','ROLLED BACK room',1,2500,2500,session_value);
        token_value := gen_random_uuid();
        snapshot_value := private.day12_build_invoice_snapshot(hotel_id_value,invoice_value.id,now(),token_value);
        update public.invoices set snapshot_json=snapshot_value,snapshot_hash=private.day12_hash_snapshot(snapshot_value),
          verification_token=token_value,finalized_at=now(),finalized_by=auth.uid()
          where hotel_id=hotel_id_value and id=invoice_value.id returning * into invoice_value;
        execute 'set local role authenticated';
      else
        result_value := public.issue_folio_invoice(hotel_id_value,folio_value.id,'exempt',current_date,gen_random_uuid()::text);
        select * into strict invoice_value from public.invoices where hotel_id=hotel_id_value and id=(result_value->>'invoice_id')::uuid;
      end if;
      invoice_before := to_jsonb(invoice_value);
      if expected_total > 0 and scenario.name not in ('unpaid_invoice_rejected','credit_requires_review') then
        collection_result := public.post_folio_collection(hotel_id_value,folio_value.id,expected_total,
          'cash','ROLLED BACK - simulated collection',null,null,gen_random_uuid()::text);
      end if;
      if scenario.name in ('refunded_pending_rejected','refunded_recollected') then
        refund_result := public.request_folio_refund(hotel_id_value,folio_value.id,
          (collection_result->'collection'->>'id')::uuid,500,'ROLLED BACK - simulated refund',gen_random_uuid()::text);
        perform public.process_folio_refund(hotel_id_value,(refund_result->'refund'->>'id')::uuid,
          null,'ROLLED BACK refund',gen_random_uuid()::text);
        if scenario.name='refunded_recollected' then
          perform public.post_folio_collection(hotel_id_value,folio_value.id,500,'cash','ROLLED BACK recollection',null,null,gen_random_uuid()::text);
        end if;
      end if;
      if scenario.name='credit_requires_review' then
        perform public.issue_folio_credit_note(hotel_id_value,folio_value.id,2500,'ROLLED BACK credit',gen_random_uuid()::text);
      end if;
      if scenario.name='charge_discrepancy_rejected' then
        execute 'reset role';
        insert into public.folio_items(hotel_id,folio_id,item_kind,description,quantity,unit_amount,amount,source_table,source_id,posted_by)
          values(hotel_id_value,folio_value.id,'charge','ROLLED BACK extra charge',1,100,100,'pilot107_fixture',gen_random_uuid(),auth.uid());
        execute 'set local role authenticated';
      end if;
      select to_jsonb(f) into folio_before from public.folios f where f.hotel_id=hotel_id_value and f.id=folio_value.id;
      evidence_before := jsonb_build_object(
        'collections',(select coalesce(jsonb_agg(to_jsonb(c) order by c.id),'[]') from public.folio_collections c where c.hotel_id=hotel_id_value and c.folio_id=folio_value.id),
        'payments',(select coalesce(jsonb_agg(to_jsonb(p) order by p.id),'[]') from public.payments p where p.hotel_id=hotel_id_value and p.guest_session_id=session_value),
        'items',(select coalesce(jsonb_agg(to_jsonb(i) order by i.id),'[]') from public.invoice_items i where i.hotel_id=hotel_id_value and i.invoice_id=invoice_value.id));
      rejected := false;
      begin
        if current_user <> 'authenticated' then raise exception 'Checkout must use real authenticated role.'; end if;
        if scenario.name='native_direct_legacy' then
          result_value := public.checkout_guest_session_day20_legacy(hotel_id_value,session_value,invoice_value.tax_percent,
            invoice_value.discount_type,invoice_value.discount_value,false,'cash',null,'ROLLED BACK issued checkout',false);
        else
          result_value := public.checkout_guest_session(hotel_id_value,session_value,
            case when scenario.name='tax_mismatch_rejected' then 1 else invoice_value.tax_percent end,
            invoice_value.discount_type,
            case when scenario.name='discount_mismatch_rejected' then 1 else invoice_value.discount_value end,
            false,'cash',null,case when scenario.name='missing_reason_rejected' then null else 'ROLLED BACK - approved issued discount' end,false);
        end if;
      exception when others then
        if scenario.expected_error is null or position(scenario.expected_error in sqlerrm)=0 then
          raise exception 'Case % unexpected error: %',scenario.name,sqlerrm;
        end if;
        rejected := true;
      end;
      if (select to_jsonb(i) from public.invoices i where i.hotel_id=hotel_id_value and i.id=invoice_value.id) is distinct from invoice_before then
        raise exception 'Immutable invoice changed in %',scenario.name;
      end if;
      if evidence_before is distinct from jsonb_build_object(
        'collections',(select coalesce(jsonb_agg(to_jsonb(c) order by c.id),'[]') from public.folio_collections c where c.hotel_id=hotel_id_value and c.folio_id=folio_value.id),
        'payments',(select coalesce(jsonb_agg(to_jsonb(p) order by p.id),'[]') from public.payments p where p.hotel_id=hotel_id_value and p.guest_session_id=session_value),
        'items',(select coalesce(jsonb_agg(to_jsonb(i) order by i.id),'[]') from public.invoice_items i where i.hotel_id=hotel_id_value and i.invoice_id=invoice_value.id)) then
        raise exception 'Issued checkout changed money or invoice lines in %',scenario.name;
      end if;
      if scenario.expected_error is not null then
        if not rejected or not exists(select 1 from public.guest_sessions where hotel_id=hotel_id_value and id=session_value and status='active')
          or (select to_jsonb(f) from public.folios f where f.hotel_id=hotel_id_value and f.id=folio_value.id) is distinct from folio_before then
          raise exception 'Rejected checkout left changes in %',scenario.name;
        end if;
      else
        select * into strict folio_value from public.folios where hotel_id=hotel_id_value and id=folio_value.id;
        if result_value->>'invoice_id' <> invoice_value.id::text or result_value->>'invoice_number' <> invoice_value.invoice_number
          or (result_value->>'amount_collected_at_checkout')::numeric <> 0
          or folio_value.balance_amount<>0 or folio_value.status<>'settled'
          or folio_value.discount_amount<>scenario.desired_discount or folio_value.tax_amount<>2500*scenario.tax_rate/100
          or not exists(select 1 from public.guest_sessions where hotel_id=hotel_id_value and id=session_value and status='completed') then
          raise exception 'Issued checkout result/folio mismatch in %',scenario.name;
        end if;
        result_value := public.checkout_guest_session(hotel_id_value,session_value,invoice_value.tax_percent,
          invoice_value.discount_type,invoice_value.discount_value,false,'cash',null,'ROLLED BACK repeat',false);
        if result_value->>'already_checked_out'<>'true' or (result_value->>'amount_collected_at_checkout')::numeric<>0
          or result_value->>'invoice_id'<>invoice_value.id::text
          or (select count(*) from public.reservation_checkout_events where hotel_id=hotel_id_value and guest_session_id=session_value)<>1 then
          raise exception 'Issued retry was not idempotent in %',scenario.name;
        end if;
      end if;
      raise sqlstate 'ZX107' using message='PASS - roll back scenario';
    exception when sqlstate 'ZX107' then
      passed := passed+1;
      raise notice 'PASS issued % (all scenario records rolled back)',scenario.name;
    end;
  end loop;
  if passed<>15 then raise exception 'Expected 15 issued checkout cases; got %',passed; end if;
end;
$issued_tests$;
