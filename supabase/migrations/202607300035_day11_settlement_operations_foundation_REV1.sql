-- StayQR v1.0
-- Day 11 Migration 035 REV1
-- Authoritative settlement operations
--
-- Requires accepted Migrations 032 REV2, 033 REV2 and 034 REV1.
-- No real gateway call is made. Signature verification remains in a trusted
-- server/edge function; PostgreSQL receives only normalized safe fields.

begin;

-- ---------------------------------------------------------------------------
-- 0. Preflight
-- ---------------------------------------------------------------------------

do $preflight$
declare
  missing_objects text;
  existing_targets text;
  runtime_rows bigint;
begin
  select string_agg(object_name, ', ' order by object_name)
  into missing_objects
  from (
    values
      ('public.folios', to_regclass('public.folios') is not null),
      ('public.folio_items', to_regclass('public.folio_items') is not null),
      ('public.folio_collections', to_regclass('public.folio_collections') is not null),
      ('public.discount_approvals', to_regclass('public.discount_approvals') is not null),
      ('public.refunds', to_regclass('public.refunds') is not null),
      ('public.credit_notes', to_regclass('public.credit_notes') is not null),
      ('public.folio_adjustments', to_regclass('public.folio_adjustments') is not null),
      ('public.payment_webhook_events', to_regclass('public.payment_webhook_events') is not null),
      ('private.day11_valid_auth_actor(uuid)', to_regprocedure('private.day11_valid_auth_actor(uuid)') is not null),
      ('private.day11_normalize_payment_method(text)', to_regprocedure('private.day11_normalize_payment_method(text)') is not null),
      ('private.write_folio_event(uuid,uuid,text,text,uuid,jsonb,jsonb)', to_regprocedure('private.write_folio_event(uuid,uuid,text,text,uuid,jsonb,jsonb)') is not null)
  ) as required_object(object_name, object_exists)
  where not object_exists;

  if missing_objects is not null then
    raise exception 'Migration 035 prerequisites missing: %', missing_objects;
  end if;

  select string_agg(object_name, ', ' order by object_name)
  into existing_targets
  from (
    values
      ('public.post_folio_collection', to_regprocedure('public.post_folio_collection(uuid,uuid,numeric,text,text,text,text,text)') is not null),
      ('public.post_folio_split_collection', to_regprocedure('public.post_folio_split_collection(uuid,uuid,jsonb,text)') is not null),
      ('public.request_folio_discount', to_regprocedure('public.request_folio_discount(uuid,uuid,text,numeric,text,text)') is not null),
      ('public.request_folio_refund', to_regprocedure('public.request_folio_refund(uuid,uuid,uuid,numeric,text,text)') is not null),
      ('public.issue_folio_credit_note', to_regprocedure('public.issue_folio_credit_note(uuid,uuid,numeric,text,text)') is not null),
      ('public.reconcile_payment_webhook_event', to_regprocedure('public.reconcile_payment_webhook_event(text,text,text,boolean,text,uuid,uuid,numeric,text,uuid,text,text,jsonb)') is not null)
  ) as target_object(object_name, object_exists)
  where object_exists;

  if existing_targets is not null then
    raise exception 'Migration 035 target functions already exist: %', existing_targets;
  end if;

  select
    (select count(*) from public.discount_approvals)
    + (select count(*) from public.refunds)
    + (select count(*) from public.credit_notes)
    + (select count(*) from public.folio_adjustments)
    + (select count(*) from public.payment_webhook_events)
  into runtime_rows;

  if runtime_rows <> 0 then
    raise exception 'Migration 035 requires empty settlement runtime tables; found % rows.', runtime_rows;
  end if;

  if exists (select 1 from public.folios where balance_amount < 0) then
    raise exception 'Migration 035 cannot start with a negative folio balance.';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. Hard constraints
-- ---------------------------------------------------------------------------

alter table public.folios
  add constraint folios_balance_nonnegative_check
  check (balance_amount >= 0) not valid;

alter table public.folios
  validate constraint folios_balance_nonnegative_check;

alter table public.refunds
  drop constraint refunds_processed_check;

alter table public.refunds
  add constraint refunds_processed_check
  check (
    status <> 'processed'
    or (
      processed_at is not null
      and (
        processed_by is not null
        or coalesce(metadata ->> 'processed_by_system','false') = 'true'
      )
    )
  ),
  add constraint refunds_collection_required_check
  check (folio_collection_id is not null);

create unique index uq_refunds_provider_refund
  on public.refunds(provider, provider_refund_id)
  where provider is not null and provider_refund_id is not null;

create index idx_refunds_collection_status
  on public.refunds(hotel_id, folio_collection_id, status);

-- ---------------------------------------------------------------------------
-- 2. Current actor helper
-- ---------------------------------------------------------------------------

create or replace function private.day11_require_current_actor()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid;
begin
  actor_id_value := private.day11_valid_auth_actor(auth.uid());
  if actor_id_value is null then
    raise exception 'A valid authenticated StayQR actor is required.';
  end if;
  return actor_id_value;
end;
$function$;

revoke all on function private.day11_require_current_actor()
from public, anon, authenticated;
grant execute on function private.day11_require_current_actor() to service_role;

-- ---------------------------------------------------------------------------
-- 3. Authoritative equation and automatic open/settled state
-- ---------------------------------------------------------------------------

create or replace function private.recalculate_folio(
  target_hotel_id uuid,
  target_folio_id uuid
)
returns public.folios
language plpgsql
security definer
set search_path = ''
as $function$
declare
  folio_row public.folios%rowtype;
  charges_value numeric(14,2);
  tax_value numeric(14,2);
  collection_value numeric(14,2);
  discount_value numeric(14,2);
  refund_value numeric(14,2);
  credit_value numeric(14,2);
  balance_value numeric(14,2);
  next_status text;
  actor_id_value uuid;
begin
  select folio.* into folio_row
  from public.folios folio
  where folio.hotel_id = target_hotel_id and folio.id = target_folio_id
  for update;

  if not found then raise exception 'Folio was not found.'; end if;

  select
    coalesce(sum(item.amount) filter (where item.posting_status = 'posted' and item.item_kind = 'charge'), 0),
    coalesce(sum(item.amount) filter (where item.posting_status = 'posted' and item.item_kind = 'tax'), 0)
  into charges_value, tax_value
  from public.folio_items item
  where item.hotel_id = target_hotel_id and item.folio_id = target_folio_id;

  select coalesce(sum(collection.amount), 0)
  into collection_value
  from public.folio_collections collection
  where collection.hotel_id = target_hotel_id
    and collection.folio_id = target_folio_id
    and collection.status = 'posted';

  select
    coalesce(sum(adjustment.amount) filter (where adjustment.status = 'posted' and adjustment.adjustment_type = 'discount'), 0),
    coalesce(sum(adjustment.amount) filter (where adjustment.status = 'posted' and adjustment.adjustment_type = 'refund'), 0),
    coalesce(sum(adjustment.amount) filter (where adjustment.status = 'posted' and adjustment.adjustment_type in ('credit_note','writeoff')), 0)
  into discount_value, refund_value, credit_value
  from public.folio_adjustments adjustment
  where adjustment.hotel_id = target_hotel_id and adjustment.folio_id = target_folio_id;

  balance_value := charges_value - discount_value + tax_value - collection_value + refund_value - credit_value;
  if balance_value < 0 then
    raise exception 'Folio operation would create negative balance %.', balance_value;
  end if;

  actor_id_value := private.day11_valid_auth_actor(auth.uid());
  next_status := case
    when folio_row.status = 'voided' then 'voided'
    when balance_value = 0 and charges_value + tax_value > 0 then 'settled'
    else 'open'
  end;

  update public.folios
  set charges_amount = charges_value,
      discount_amount = discount_value,
      tax_amount = tax_value,
      collection_amount = collection_value,
      refund_amount = refund_value,
      credit_amount = credit_value,
      balance_amount = balance_value,
      status = next_status,
      settled_at = case when next_status = 'settled' then coalesce(settled_at, now()) else null end,
      settled_by = case when next_status = 'settled' then coalesce(settled_by, actor_id_value) else null end,
      lock_version = lock_version + 1
  where hotel_id = target_hotel_id and id = target_folio_id
  returning * into folio_row;

  return folio_row;
end;
$function$;

-- Existing child recalculation triggers now also maintain settlement status.

-- ---------------------------------------------------------------------------
-- 4. Child write guards
-- ---------------------------------------------------------------------------

create or replace function private.day11_validate_collection_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  folio_row public.folios%rowtype;
  old_effect numeric(14,2) := 0;
  new_effect numeric(14,2) := 0;
  delta_value numeric(14,2);
begin
  if tg_op = 'UPDATE' then
    if old.hotel_id is distinct from new.hotel_id
       or old.folio_id is distinct from new.folio_id
       or old.amount is distinct from new.amount
       or old.payment_method is distinct from new.payment_method
       or old.collection_group_id is distinct from new.collection_group_id
       or old.source_table is distinct from new.source_table
       or old.source_id is distinct from new.source_id
       or old.idempotency_key is distinct from new.idempotency_key
    then
      raise exception 'Posted collection identity and amount are immutable.';
    end if;
    old_effect := case when old.status = 'posted' then old.amount else 0 end;
  end if;

  new_effect := case when new.status = 'posted' then new.amount else 0 end;
  delta_value := new_effect - old_effect;

  select folio.* into folio_row
  from public.folios folio
  where folio.hotel_id = new.hotel_id and folio.id = new.folio_id
  for update;

  if not found then raise exception 'Collection folio was not found.'; end if;
  if folio_row.status = 'voided' then raise exception 'A voided folio cannot accept collections.'; end if;
  if delta_value > 0 and folio_row.balance_amount - delta_value < 0 then
    raise exception 'Collection exceeds open balance %. Additional collection %.', folio_row.balance_amount, delta_value;
  end if;
  return new;
end;
$function$;

create or replace function private.day11_validate_adjustment_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  folio_row public.folios%rowtype;
  old_effect numeric(14,2) := 0;
  new_effect numeric(14,2) := 0;
  delta_value numeric(14,2);
  linked_status text;
  linked_hotel_id uuid;
  linked_folio_id uuid;
begin
  if tg_op = 'UPDATE' then
    if old.hotel_id is distinct from new.hotel_id
       or old.folio_id is distinct from new.folio_id
       or old.adjustment_type is distinct from new.adjustment_type
       or old.amount is distinct from new.amount
       or old.balance_effect is distinct from new.balance_effect
       or old.approval_id is distinct from new.approval_id
       or old.refund_id is distinct from new.refund_id
       or old.credit_note_id is distinct from new.credit_note_id
       or old.idempotency_key is distinct from new.idempotency_key
    then
      raise exception 'Posted adjustment identity and amount are immutable.';
    end if;
    old_effect := case when old.status = 'posted' then old.balance_effect else 0 end;
  end if;

  if new.adjustment_type = 'discount' then
    if new.approval_id is null or new.refund_id is not null or new.credit_note_id is not null then
      raise exception 'Discount adjustment requires only approval_id.';
    end if;
    select approval.status, approval.hotel_id, approval.folio_id
    into linked_status, linked_hotel_id, linked_folio_id
    from public.discount_approvals approval where approval.id = new.approval_id;
    if linked_status <> 'approved' or linked_hotel_id <> new.hotel_id or linked_folio_id <> new.folio_id then
      raise exception 'Discount adjustment must reference the approved same-folio request.';
    end if;
  elsif new.adjustment_type = 'refund' then
    if new.refund_id is null or new.approval_id is not null or new.credit_note_id is not null then
      raise exception 'Refund adjustment requires only refund_id.';
    end if;
    select refund.status, refund.hotel_id, refund.folio_id
    into linked_status, linked_hotel_id, linked_folio_id
    from public.refunds refund where refund.id = new.refund_id;
    if linked_status <> 'processed' or linked_hotel_id <> new.hotel_id or linked_folio_id <> new.folio_id then
      raise exception 'Refund adjustment must reference the processed same-folio refund.';
    end if;
  elsif new.adjustment_type = 'credit_note' then
    if new.credit_note_id is null or new.approval_id is not null or new.refund_id is not null then
      raise exception 'Credit adjustment requires only credit_note_id.';
    end if;
    select credit.status, credit.hotel_id, credit.folio_id
    into linked_status, linked_hotel_id, linked_folio_id
    from public.credit_notes credit where credit.id = new.credit_note_id;
    if linked_hotel_id <> new.hotel_id or linked_folio_id <> new.folio_id
       or (new.status = 'posted' and linked_status <> 'issued')
       or (new.status = 'voided' and linked_status <> 'voided')
    then
      raise exception 'Credit adjustment must match the same-folio credit-note state.';
    end if;
  elsif new.adjustment_type = 'writeoff' then
    if new.approval_id is not null or new.refund_id is not null or new.credit_note_id is not null then
      raise exception 'Writeoff cannot reference discount/refund/credit records.';
    end if;
  end if;

  new_effect := case when new.status = 'posted' then new.balance_effect else 0 end;
  delta_value := new_effect - old_effect;

  select folio.* into folio_row
  from public.folios folio
  where folio.hotel_id = new.hotel_id and folio.id = new.folio_id
  for update;

  if not found then raise exception 'Adjustment folio was not found.'; end if;
  if folio_row.status = 'voided' then raise exception 'A voided folio cannot accept adjustments.'; end if;
  if folio_row.balance_amount + delta_value < 0 then
    raise exception 'Adjustment exceeds open balance %. Effect %.', folio_row.balance_amount, delta_value;
  end if;
  return new;
end;
$function$;

create or replace function private.day11_validate_refund_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  collection_row public.folio_collections%rowtype;
  reserved_amount numeric(14,2);
begin
  if tg_op = 'UPDATE' then
    if old.hotel_id is distinct from new.hotel_id
       or old.folio_id is distinct from new.folio_id
       or old.folio_collection_id is distinct from new.folio_collection_id
       or old.amount is distinct from new.amount
       or old.payment_method is distinct from new.payment_method
       or old.idempotency_key is distinct from new.idempotency_key
    then
      raise exception 'Refund identity, source collection and amount are immutable.';
    end if;
    if old.status = 'processed' and new.status <> 'processed' then
      raise exception 'A processed refund cannot be reversed in place.';
    end if;
    if old.status in ('failed','cancelled') and new.status <> old.status then
      raise exception 'A failed or cancelled refund requires a new request.';
    end if;
  end if;

  select collection.* into collection_row
  from public.folio_collections collection
  where collection.hotel_id = new.hotel_id and collection.id = new.folio_collection_id
  for share;

  if not found then raise exception 'Refund source collection was not found.'; end if;
  if collection_row.folio_id <> new.folio_id or collection_row.status <> 'posted' then
    raise exception 'Refund must reference a posted collection from the same folio.';
  end if;
  if new.payment_method <> collection_row.payment_method then
    raise exception 'Refund method must match source collection.';
  end if;

  select coalesce(sum(refund.amount),0) into reserved_amount
  from public.refunds refund
  where refund.hotel_id = new.hotel_id
    and refund.folio_collection_id = new.folio_collection_id
    and refund.status in ('pending','processed')
    and refund.id is distinct from new.id;

  if new.status in ('pending','processed') and reserved_amount + new.amount > collection_row.amount then
    raise exception 'Refund exceeds collection %. Reserved %, attempted %.', collection_row.amount, reserved_amount, new.amount;
  end if;
  return new;
end;
$function$;

drop trigger if exists folio_collections_validate_settlement on public.folio_collections;
create trigger folio_collections_validate_settlement
before insert or update on public.folio_collections
for each row execute function private.day11_validate_collection_write();

drop trigger if exists folio_adjustments_validate_settlement on public.folio_adjustments;
create trigger folio_adjustments_validate_settlement
before insert or update on public.folio_adjustments
for each row execute function private.day11_validate_adjustment_write();

drop trigger if exists refunds_validate_settlement on public.refunds;
create trigger refunds_validate_settlement
before insert or update on public.refunds
for each row execute function private.day11_validate_refund_write();

-- ---------------------------------------------------------------------------
-- 5. Automatic adjustment posting
-- ---------------------------------------------------------------------------

create or replace function private.day11_post_discount_adjustment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  should_post boolean := false;
begin
  if new.status = 'approved' then
    if tg_op = 'INSERT' then
      should_post := true;
    elsif tg_op = 'UPDATE' and old.status is distinct from new.status then
      should_post := true;
    end if;
  end if;

  if should_post then
    insert into public.folio_adjustments(
      hotel_id, folio_id, adjustment_type, amount, balance_effect, status,
      reason, approval_id, idempotency_key, posted_by, metadata
    ) values (
      new.hotel_id, new.folio_id, 'discount', new.requested_amount,
      -new.requested_amount, 'posted', new.reason, new.id,
      'discount-approval:' || new.id::text, new.reviewed_by,
      jsonb_build_object('discount_type',new.discount_type,'requested_value',new.requested_value,'source','discount_approval','day',11)
    ) on conflict (hotel_id,idempotency_key) do nothing;
  end if;
  return new;
end;
$function$;

create or replace function private.day11_post_refund_adjustment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  should_post boolean := false;
begin
  if new.status = 'processed' then
    if tg_op = 'INSERT' then
      should_post := true;
    elsif tg_op = 'UPDATE' and old.status is distinct from new.status then
      should_post := true;
    end if;
  end if;

  if should_post then
    insert into public.folio_adjustments(
      hotel_id, folio_id, adjustment_type, amount, balance_effect, status,
      reason, refund_id, idempotency_key, posted_by, metadata
    ) values (
      new.hotel_id, new.folio_id, 'refund', new.amount, new.amount, 'posted',
      new.reason, new.id, 'refund:' || new.id::text, new.processed_by,
      jsonb_build_object('folio_collection_id',new.folio_collection_id,'provider',new.provider,'provider_refund_id',new.provider_refund_id,'source','refund','day',11)
    ) on conflict (hotel_id,idempotency_key) do nothing;
  end if;
  return new;
end;
$function$;

create or replace function private.day11_post_credit_adjustment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  should_post boolean := false;
  should_void boolean := false;
begin
  if new.status = 'issued' then
    if tg_op = 'INSERT' then
      should_post := true;
    elsif tg_op = 'UPDATE' and old.status is distinct from new.status then
      should_post := true;
    end if;
  elsif tg_op = 'UPDATE' and new.status = 'voided' and old.status is distinct from new.status then
    should_void := true;
  end if;

  if should_post then
    insert into public.folio_adjustments(
      hotel_id, folio_id, adjustment_type, amount, balance_effect, status,
      reason, credit_note_id, idempotency_key, posted_by, metadata
    ) values (
      new.hotel_id, new.folio_id, 'credit_note', new.amount, -new.amount,
      'posted', new.reason, new.id, 'credit-note:' || new.id::text,
      new.issued_by, jsonb_build_object('credit_note_number',new.credit_note_number,'source','credit_note','day',11)
    ) on conflict (hotel_id,idempotency_key) do nothing;
  elsif should_void then
    update public.folio_adjustments adjustment
    set status = 'voided',
        voided_at = coalesce(adjustment.voided_at,new.voided_at,now()),
        voided_by = coalesce(adjustment.voided_by,new.voided_by),
        void_reason = coalesce(adjustment.void_reason,new.void_reason)
    where adjustment.hotel_id = new.hotel_id
      and adjustment.credit_note_id = new.id
      and adjustment.status = 'posted';
  end if;
  return new;
end;
$function$;

drop trigger if exists discount_approvals_post_adjustment on public.discount_approvals;
create trigger discount_approvals_post_adjustment
after insert or update on public.discount_approvals
for each row execute function private.day11_post_discount_adjustment();

drop trigger if exists refunds_post_adjustment on public.refunds;
create trigger refunds_post_adjustment
after insert or update on public.refunds
for each row execute function private.day11_post_refund_adjustment();

drop trigger if exists credit_notes_post_adjustment on public.credit_notes;
create trigger credit_notes_post_adjustment
after insert or update on public.credit_notes
for each row execute function private.day11_post_credit_adjustment();

-- ---------------------------------------------------------------------------
-- 6. Internal collection posting
-- ---------------------------------------------------------------------------

create or replace function private.day11_post_collection(
  target_hotel_id uuid,
  target_folio_id uuid,
  amount_value numeric,
  payment_method_value text,
  collection_group_id_value uuid,
  transaction_reference_value text,
  provider_value text,
  provider_payment_id_value text,
  provider_event_id_value text,
  source_table_value text,
  source_id_value uuid,
  idempotency_key_value text,
  collected_at_value timestamptz,
  actor_id_value uuid,
  metadata_value jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  folio_row public.folios%rowtype;
  existing_row public.folio_collections%rowtype;
  inserted_row public.folio_collections%rowtype;
  normalized_method text;
  request_key text;
begin
  if amount_value is null or amount_value <= 0 then
    raise exception 'Collection amount must be positive.';
  end if;

  request_key := nullif(trim(idempotency_key_value),'');
  if request_key is null then raise exception 'Collection idempotency key is required.'; end if;

  normalized_method := private.day11_normalize_payment_method(payment_method_value);

  perform pg_advisory_xact_lock(hashtextextended(
    'stayqr:folio-settlement:' || target_hotel_id::text || ':' || target_folio_id::text, 0
  ));

  select collection.* into existing_row
  from public.folio_collections collection
  where collection.hotel_id = target_hotel_id and collection.idempotency_key = request_key
  limit 1;

  if existing_row.id is not null then
    if existing_row.folio_id <> target_folio_id
       or existing_row.amount <> amount_value
       or existing_row.payment_method <> normalized_method
    then
      raise exception 'Collection idempotency key conflicts with a different request.';
    end if;
    return jsonb_build_object('ok',true,'idempotent',true,'collection',to_jsonb(existing_row));
  end if;

  select folio.* into folio_row
  from public.folios folio
  where folio.hotel_id = target_hotel_id and folio.id = target_folio_id
  for update;

  if not found then raise exception 'Folio was not found.'; end if;
  if folio_row.status = 'voided' then raise exception 'A voided folio cannot accept collection.'; end if;
  if amount_value > folio_row.balance_amount then
    raise exception 'Collection amount % exceeds open balance %.', amount_value, folio_row.balance_amount;
  end if;

  insert into public.folio_collections(
    hotel_id, folio_id, collection_group_id, amount, payment_method, status,
    transaction_reference, provider, provider_payment_id, provider_event_id,
    source_table, source_id, idempotency_key, collected_at, collected_by, metadata
  ) values (
    target_hotel_id, target_folio_id, coalesce(collection_group_id_value,gen_random_uuid()),
    amount_value, normalized_method, 'posted', nullif(trim(transaction_reference_value),''),
    nullif(trim(provider_value),''), nullif(trim(provider_payment_id_value),''),
    nullif(trim(provider_event_id_value),''), nullif(trim(source_table_value),''),
    source_id_value, request_key, coalesce(collected_at_value,now()),
    private.day11_valid_auth_actor(actor_id_value),
    coalesce(metadata_value,'{}'::jsonb) || jsonb_build_object(
      'source',coalesce(nullif(trim(source_table_value),''),'settlement_rpc'),'day',11
    )
  ) returning * into inserted_row;

  perform private.write_folio_event(
    target_hotel_id,target_folio_id,'folio.collection.posted','folio_collection',inserted_row.id,
    to_jsonb(inserted_row),jsonb_build_object('idempotency_key',request_key,'collection_group_id',inserted_row.collection_group_id,'day',11)
  );

  return jsonb_build_object('ok',true,'idempotent',false,'collection',to_jsonb(inserted_row));
end;
$function$;

revoke all on function private.day11_post_collection(
  uuid,uuid,numeric,text,uuid,text,text,text,text,text,uuid,text,timestamptz,uuid,jsonb
) from public, anon, authenticated;
grant execute on function private.day11_post_collection(
  uuid,uuid,numeric,text,uuid,text,text,text,text,text,uuid,text,timestamptz,uuid,jsonb
) to service_role;

-- ---------------------------------------------------------------------------
-- 7. Partial and split/multi-method collection RPCs
-- ---------------------------------------------------------------------------

create or replace function public.post_folio_collection(
  target_hotel_id uuid,
  target_folio_id uuid,
  amount_value numeric,
  payment_method_value text,
  transaction_reference_value text default null,
  provider_value text default null,
  provider_payment_id_value text default null,
  request_id_value text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid;
  request_key text;
begin
  if not private.user_has_any_permission(target_hotel_id,array['payments.manage','checkout.manage','invoices.manage']::text[]) then
    raise exception 'Collection posting access denied.';
  end if;
  actor_id_value := private.day11_require_current_actor();
  request_key := coalesce(nullif(trim(request_id_value),''),gen_random_uuid()::text);

  return private.day11_post_collection(
    target_hotel_id,target_folio_id,amount_value,payment_method_value,gen_random_uuid(),
    transaction_reference_value,provider_value,provider_payment_id_value,null,
    'settlement_rpc',null,'collection:' || request_key,now(),actor_id_value,
    jsonb_build_object('request_id',request_key,'posting_mode','single')
  ) || jsonb_build_object('request_id',request_key);
end;
$function$;

create or replace function public.post_folio_split_collection(
  target_hotel_id uuid,
  target_folio_id uuid,
  collection_lines jsonb,
  request_id_value text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid;
  request_key text;
  request_hash text;
  line_count integer;
  existing_count integer;
  existing_hash_count integer;
  group_id_value uuid;
  total_value numeric(14,2) := 0;
  line_record record;
  line_amount numeric(14,2);
  line_method text;
  line_result jsonb;
  result_rows jsonb := '[]'::jsonb;
  folio_row public.folios%rowtype;
begin
  if not private.user_has_any_permission(target_hotel_id,array['payments.manage','checkout.manage','invoices.manage']::text[]) then
    raise exception 'Split collection posting access denied.';
  end if;
  actor_id_value := private.day11_require_current_actor();

  if jsonb_typeof(collection_lines) <> 'array' then raise exception 'collection_lines must be a JSON array.'; end if;
  line_count := jsonb_array_length(collection_lines);
  if line_count < 2 then raise exception 'Split collection requires at least two payment lines.'; end if;

  request_key := coalesce(nullif(trim(request_id_value),''),gen_random_uuid()::text);
  request_hash := md5(collection_lines::text);

  perform pg_advisory_xact_lock(hashtextextended(
    'stayqr:folio-split:' || target_hotel_id::text || ':' || target_folio_id::text || ':' || request_key,0
  ));

  select count(*),
         count(*) filter (where collection.metadata ->> 'split_request_hash' = request_hash),
         (min(collection.collection_group_id::text))::uuid
  into existing_count, existing_hash_count, group_id_value
  from public.folio_collections collection
  where collection.hotel_id = target_hotel_id
    and collection.folio_id = target_folio_id
    and collection.metadata ->> 'split_request_id' = request_key;

  if existing_count > 0 then
    if existing_count <> line_count or existing_hash_count <> existing_count then
      raise exception 'Split collection idempotency key conflicts with different lines.';
    end if;
    select coalesce(jsonb_agg(to_jsonb(collection) order by (collection.metadata ->> 'split_line_number')::integer),'[]'::jsonb)
    into result_rows
    from public.folio_collections collection
    where collection.hotel_id = target_hotel_id
      and collection.folio_id = target_folio_id
      and collection.metadata ->> 'split_request_id' = request_key;
    return jsonb_build_object('ok',true,'idempotent',true,'request_id',request_key,'request_hash',request_hash,'collection_group_id',group_id_value,'collections',result_rows);
  end if;

  for line_record in
    select element.value as line, element.ordinality::integer as line_number
    from jsonb_array_elements(collection_lines) with ordinality as element(value,ordinality)
  loop
    begin
      line_amount := (line_record.line ->> 'amount')::numeric;
    exception when others then
      raise exception 'Split line % has invalid amount.',line_record.line_number;
    end;
    if line_amount <= 0 then raise exception 'Split line % amount must be positive.',line_record.line_number; end if;
    line_method := nullif(trim(line_record.line ->> 'payment_method'),'');
    if line_method is null then raise exception 'Split line % payment_method is required.',line_record.line_number; end if;
    total_value := total_value + line_amount;
  end loop;

  select folio.* into folio_row
  from public.folios folio
  where folio.hotel_id = target_hotel_id and folio.id = target_folio_id
  for update;
  if not found then raise exception 'Folio was not found.'; end if;
  if total_value > folio_row.balance_amount then
    raise exception 'Split collection total % exceeds open balance %.',total_value,folio_row.balance_amount;
  end if;

  group_id_value := gen_random_uuid();
  for line_record in
    select element.value as line, element.ordinality::integer as line_number
    from jsonb_array_elements(collection_lines) with ordinality as element(value,ordinality)
  loop
    line_result := private.day11_post_collection(
      target_hotel_id,target_folio_id,(line_record.line ->> 'amount')::numeric,
      line_record.line ->> 'payment_method',group_id_value,
      line_record.line ->> 'transaction_reference',line_record.line ->> 'provider',
      line_record.line ->> 'provider_payment_id',null,'settlement_rpc',null,
      'split-collection:' || request_key || ':' || line_record.line_number::text,
      now(),actor_id_value,jsonb_build_object(
        'request_id',request_key,'posting_mode','split','split_request_id',request_key,
        'split_request_hash',request_hash,'split_line_number',line_record.line_number,
        'split_line_count',line_count
      )
    );
    result_rows := result_rows || jsonb_build_array(line_result -> 'collection');
  end loop;

  return jsonb_build_object('ok',true,'idempotent',false,'request_id',request_key,'request_hash',request_hash,'collection_group_id',group_id_value,'total_amount',total_value,'collections',result_rows);
end;
$function$;

-- ---------------------------------------------------------------------------
-- 8. Discount approval workflow
-- ---------------------------------------------------------------------------

create or replace function public.request_folio_discount(
  target_hotel_id uuid,
  target_folio_id uuid,
  discount_type_value text,
  requested_value_value numeric,
  reason_value text,
  request_id_value text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid;
  folio_row public.folios%rowtype;
  approval_row public.discount_approvals%rowtype;
  request_key text;
  amount_value numeric(14,2);
  normalized_type text;
begin
  if not private.user_has_any_permission(target_hotel_id,array['payments.manage','checkout.manage','invoices.manage']::text[]) then
    raise exception 'Discount request access denied.';
  end if;
  actor_id_value := private.day11_require_current_actor();
  normalized_type := lower(trim(discount_type_value));
  if normalized_type not in ('fixed','percentage') then raise exception 'Discount type must be fixed or percentage.'; end if;
  if requested_value_value is null or requested_value_value <= 0 then raise exception 'Discount value must be positive.'; end if;
  if normalized_type = 'percentage' and requested_value_value > 100 then raise exception 'Percentage discount cannot exceed 100.'; end if;
  if nullif(trim(reason_value),'') is null then raise exception 'Discount reason is required.'; end if;
  request_key := coalesce(nullif(trim(request_id_value),''),gen_random_uuid()::text);

  select approval.* into approval_row
  from public.discount_approvals approval
  where approval.hotel_id = target_hotel_id and approval.idempotency_key = 'discount-request:' || request_key
  limit 1;
  if approval_row.id is not null then
    return jsonb_build_object('ok',true,'idempotent',true,'request_id',request_key,'approval',to_jsonb(approval_row));
  end if;

  select folio.* into folio_row
  from public.folios folio
  where folio.hotel_id = target_hotel_id and folio.id = target_folio_id
  for update;
  if not found then raise exception 'Folio was not found.'; end if;
  if folio_row.status = 'voided' or folio_row.balance_amount <= 0 then
    raise exception 'Discount requires a non-voided folio with positive balance.';
  end if;

  amount_value := case when normalized_type = 'fixed' then round(requested_value_value,2)
                       else round(folio_row.balance_amount * requested_value_value / 100,2) end;
  if amount_value <= 0 or amount_value > folio_row.balance_amount then
    raise exception 'Discount amount % exceeds open balance %.',amount_value,folio_row.balance_amount;
  end if;

  insert into public.discount_approvals(
    hotel_id,folio_id,discount_type,requested_value,requested_amount,reason,status,
    requested_by,idempotency_key,metadata
  ) values (
    target_hotel_id,target_folio_id,normalized_type,requested_value_value,amount_value,
    trim(reason_value),'pending',actor_id_value,'discount-request:' || request_key,
    jsonb_build_object('calculation_base',folio_row.balance_amount,'request_id',request_key,'day',11)
  ) returning * into approval_row;

  perform private.write_folio_event(target_hotel_id,target_folio_id,'folio.discount.requested','discount_approval',approval_row.id,to_jsonb(approval_row),jsonb_build_object('request_id',request_key,'day',11));
  return jsonb_build_object('ok',true,'idempotent',false,'request_id',request_key,'approval',to_jsonb(approval_row));
end;
$function$;

create or replace function public.review_folio_discount(
  target_hotel_id uuid,
  target_approval_id uuid,
  approve_value boolean,
  review_notes_value text default null,
  request_id_value text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid;
  approval_row public.discount_approvals%rowtype;
  folio_row public.folios%rowtype;
  target_status text;
  request_key text;
begin
  if not private.user_has_any_permission(target_hotel_id,array['payments.manage','checkout.manage','invoices.manage']::text[]) then
    raise exception 'Discount review access denied.';
  end if;
  actor_id_value := private.day11_require_current_actor();
  target_status := case when approve_value then 'approved' else 'rejected' end;
  request_key := coalesce(nullif(trim(request_id_value),''),gen_random_uuid()::text);

  select approval.* into approval_row
  from public.discount_approvals approval
  where approval.hotel_id = target_hotel_id and approval.id = target_approval_id
  for update;
  if not found then raise exception 'Discount approval was not found.'; end if;
  if approval_row.status <> 'pending' then
    if approval_row.status = target_status then
      return jsonb_build_object('ok',true,'idempotent',true,'request_id',request_key,'approval',to_jsonb(approval_row));
    end if;
    raise exception 'Discount request is already %.',approval_row.status;
  end if;

  if approve_value then
    select folio.* into folio_row
    from public.folios folio
    where folio.hotel_id = target_hotel_id and folio.id = approval_row.folio_id
    for update;
    if folio_row.status = 'voided' or approval_row.requested_amount > folio_row.balance_amount then
      raise exception 'Approved discount % exceeds current open balance %.',approval_row.requested_amount,folio_row.balance_amount;
    end if;
  end if;

  update public.discount_approvals
  set status = target_status, reviewed_by = actor_id_value, reviewed_at = now(),
      review_notes = nullif(trim(review_notes_value),''),
      metadata = metadata || jsonb_build_object('review_request_id',request_key,'review_decision',target_status)
  where hotel_id = target_hotel_id and id = target_approval_id
  returning * into approval_row;

  perform private.write_folio_event(target_hotel_id,approval_row.folio_id,'folio.discount.' || target_status,'discount_approval',approval_row.id,to_jsonb(approval_row),jsonb_build_object('request_id',request_key,'day',11));
  return jsonb_build_object('ok',true,'idempotent',false,'request_id',request_key,'approval',to_jsonb(approval_row));
end;
$function$;

-- ---------------------------------------------------------------------------
-- 9. Partial refund workflow
-- ---------------------------------------------------------------------------

create or replace function public.request_folio_refund(
  target_hotel_id uuid,
  target_folio_id uuid,
  target_collection_id uuid,
  amount_value numeric,
  reason_value text,
  request_id_value text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid;
  collection_row public.folio_collections%rowtype;
  refund_row public.refunds%rowtype;
  request_key text;
  reserved_value numeric(14,2);
  available_value numeric(14,2);
begin
  if not private.user_has_any_permission(target_hotel_id,array['payments.manage','checkout.manage','invoices.manage']::text[]) then
    raise exception 'Refund request access denied.';
  end if;
  actor_id_value := private.day11_require_current_actor();
  if amount_value is null or amount_value <= 0 then raise exception 'Refund amount must be positive.'; end if;
  if nullif(trim(reason_value),'') is null then raise exception 'Refund reason is required.'; end if;
  request_key := coalesce(nullif(trim(request_id_value),''),gen_random_uuid()::text);

  select refund.* into refund_row
  from public.refunds refund
  where refund.hotel_id = target_hotel_id and refund.idempotency_key = 'refund-request:' || request_key
  limit 1;
  if refund_row.id is not null then
    if refund_row.folio_id <> target_folio_id or refund_row.folio_collection_id <> target_collection_id or refund_row.amount <> amount_value then
      raise exception 'Refund idempotency key conflicts with a different request.';
    end if;
    return jsonb_build_object('ok',true,'idempotent',true,'request_id',request_key,'refund',to_jsonb(refund_row));
  end if;

  select collection.* into collection_row
  from public.folio_collections collection
  where collection.hotel_id = target_hotel_id and collection.folio_id = target_folio_id and collection.id = target_collection_id
  for update;
  if not found or collection_row.status <> 'posted' then raise exception 'Posted source collection was not found.'; end if;

  select coalesce(sum(refund.amount),0) into reserved_value
  from public.refunds refund
  where refund.hotel_id = target_hotel_id and refund.folio_collection_id = target_collection_id
    and refund.status in ('pending','processed');
  available_value := collection_row.amount - reserved_value;
  if amount_value > available_value then
    raise exception 'Refund amount % exceeds refundable collection balance %.',amount_value,available_value;
  end if;

  insert into public.refunds(
    hotel_id,folio_id,folio_collection_id,amount,payment_method,status,reason,
    provider,idempotency_key,requested_by,metadata
  ) values (
    target_hotel_id,target_folio_id,target_collection_id,amount_value,collection_row.payment_method,
    'pending',trim(reason_value),collection_row.provider,'refund-request:' || request_key,
    actor_id_value,jsonb_build_object('request_id',request_key,'source_collection_amount',collection_row.amount,'source_collection_reference',collection_row.transaction_reference,'day',11)
  ) returning * into refund_row;

  perform private.write_folio_event(target_hotel_id,target_folio_id,'folio.refund.requested','refund',refund_row.id,to_jsonb(refund_row),jsonb_build_object('request_id',request_key,'day',11));
  return jsonb_build_object('ok',true,'idempotent',false,'request_id',request_key,'refundable_before',available_value,'refund',to_jsonb(refund_row));
end;
$function$;

create or replace function private.day11_process_refund(
  target_refund_id uuid,
  provider_refund_id_value text,
  transaction_reference_value text,
  actor_id_value uuid,
  system_processing boolean,
  metadata_value jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  refund_row public.refunds%rowtype;
begin
  select refund.* into refund_row
  from public.refunds refund where refund.id = target_refund_id for update;
  if not found then raise exception 'Refund was not found.'; end if;
  if refund_row.status = 'processed' then return jsonb_build_object('ok',true,'idempotent',true,'refund',to_jsonb(refund_row)); end if;
  if refund_row.status <> 'pending' then raise exception 'Only pending refund can be processed; current status %.',refund_row.status; end if;
  if not system_processing and private.day11_valid_auth_actor(actor_id_value) is null then
    raise exception 'Manual refund processing requires a valid actor.';
  end if;

  update public.refunds
  set status = 'processed',
      transaction_reference = coalesce(nullif(trim(transaction_reference_value),''),transaction_reference),
      provider_refund_id = coalesce(nullif(trim(provider_refund_id_value),''),provider_refund_id),
      processed_at = now(),
      processed_by = case when system_processing then null else private.day11_valid_auth_actor(actor_id_value) end,
      provider = coalesce(nullif(trim(metadata_value ->> 'provider'),''),provider),
      failure_reason = null,
      metadata = metadata || coalesce(metadata_value,'{}'::jsonb) || jsonb_build_object('processed_by_system',system_processing,'day',11)
  where id = target_refund_id
  returning * into refund_row;

  perform private.write_folio_event(refund_row.hotel_id,refund_row.folio_id,'folio.refund.processed','refund',refund_row.id,to_jsonb(refund_row),coalesce(metadata_value,'{}'::jsonb) || jsonb_build_object('system_processing',system_processing,'day',11));
  return jsonb_build_object('ok',true,'idempotent',false,'refund',to_jsonb(refund_row));
end;
$function$;

create or replace function public.process_folio_refund(
  target_hotel_id uuid,
  target_refund_id uuid,
  provider_refund_id_value text default null,
  transaction_reference_value text default null,
  request_id_value text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid;
  refund_hotel_id uuid;
  request_key text;
begin
  if not private.user_has_any_permission(target_hotel_id,array['payments.manage','checkout.manage','invoices.manage']::text[]) then
    raise exception 'Refund processing access denied.';
  end if;
  actor_id_value := private.day11_require_current_actor();
  select refund.hotel_id into refund_hotel_id from public.refunds refund where refund.id = target_refund_id;
  if refund_hotel_id is null or refund_hotel_id <> target_hotel_id then raise exception 'Refund was not found in selected hotel.'; end if;
  request_key := coalesce(nullif(trim(request_id_value),''),gen_random_uuid()::text);
  return private.day11_process_refund(target_refund_id,provider_refund_id_value,transaction_reference_value,actor_id_value,false,jsonb_build_object('request_id',request_key,'processing_source','manual_rpc')) || jsonb_build_object('request_id',request_key);
end;
$function$;

-- ---------------------------------------------------------------------------
-- 10. Credit notes
-- ---------------------------------------------------------------------------

create or replace function public.issue_folio_credit_note(
  target_hotel_id uuid,
  target_folio_id uuid,
  amount_value numeric,
  reason_value text,
  request_id_value text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid;
  folio_row public.folios%rowtype;
  credit_row public.credit_notes%rowtype;
  request_key text;
  generated_id uuid := gen_random_uuid();
  hotel_timezone text;
begin
  if not private.user_has_any_permission(target_hotel_id,array['payments.manage','checkout.manage','invoices.manage']::text[]) then
    raise exception 'Credit note issue access denied.';
  end if;
  actor_id_value := private.day11_require_current_actor();
  if amount_value is null or amount_value <= 0 then raise exception 'Credit note amount must be positive.'; end if;
  if nullif(trim(reason_value),'') is null then raise exception 'Credit note reason is required.'; end if;
  request_key := coalesce(nullif(trim(request_id_value),''),gen_random_uuid()::text);

  select credit.* into credit_row
  from public.credit_notes credit
  where credit.hotel_id = target_hotel_id and credit.idempotency_key = 'credit-note:' || request_key
  limit 1;
  if credit_row.id is not null then
    if credit_row.folio_id <> target_folio_id or credit_row.amount <> amount_value then raise exception 'Credit note idempotency conflict.'; end if;
    return jsonb_build_object('ok',true,'idempotent',true,'request_id',request_key,'credit_note',to_jsonb(credit_row));
  end if;

  select folio.* into folio_row
  from public.folios folio
  where folio.hotel_id = target_hotel_id and folio.id = target_folio_id
  for update;
  if not found then raise exception 'Folio was not found.'; end if;
  select hotel.timezone into hotel_timezone from public.hotels hotel where hotel.id = target_hotel_id;
  if folio_row.status = 'voided' or amount_value > folio_row.balance_amount then
    raise exception 'Credit note amount % exceeds open balance %.',amount_value,folio_row.balance_amount;
  end if;

  insert into public.credit_notes(
    id,hotel_id,folio_id,credit_note_number,amount,status,reason,idempotency_key,issued_by,metadata
  ) values (
    generated_id,target_hotel_id,target_folio_id,
    'CN-' || to_char(now() at time zone coalesce(hotel_timezone,'Asia/Kolkata'),'YYYYMMDD') || '-' || upper(substr(replace(generated_id::text,'-',''),1,8)),
    amount_value,'issued',trim(reason_value),'credit-note:' || request_key,actor_id_value,
    jsonb_build_object('request_id',request_key,'day',11)
  ) returning * into credit_row;

  perform private.write_folio_event(target_hotel_id,target_folio_id,'folio.credit_note.issued','credit_note',credit_row.id,to_jsonb(credit_row),jsonb_build_object('request_id',request_key,'day',11));
  return jsonb_build_object('ok',true,'idempotent',false,'request_id',request_key,'credit_note',to_jsonb(credit_row));
end;
$function$;

create or replace function public.void_folio_credit_note(
  target_hotel_id uuid,
  target_credit_note_id uuid,
  void_reason_value text,
  request_id_value text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid;
  credit_row public.credit_notes%rowtype;
  request_key text;
begin
  if not private.user_has_any_permission(target_hotel_id,array['payments.manage','checkout.manage','invoices.manage']::text[]) then
    raise exception 'Credit note void access denied.';
  end if;
  actor_id_value := private.day11_require_current_actor();
  if nullif(trim(void_reason_value),'') is null then raise exception 'Credit note void reason is required.'; end if;
  request_key := coalesce(nullif(trim(request_id_value),''),gen_random_uuid()::text);

  select credit.* into credit_row
  from public.credit_notes credit
  where credit.hotel_id = target_hotel_id and credit.id = target_credit_note_id
  for update;
  if not found then raise exception 'Credit note was not found.'; end if;
  if credit_row.status = 'voided' then return jsonb_build_object('ok',true,'idempotent',true,'request_id',request_key,'credit_note',to_jsonb(credit_row)); end if;
  if credit_row.status <> 'issued' then raise exception 'Only issued credit note can be voided.'; end if;

  update public.credit_notes
  set status = 'voided',voided_at = now(),voided_by = actor_id_value,
      void_reason = trim(void_reason_value),metadata = metadata || jsonb_build_object('void_request_id',request_key)
  where hotel_id = target_hotel_id and id = target_credit_note_id
  returning * into credit_row;

  perform private.write_folio_event(target_hotel_id,credit_row.folio_id,'folio.credit_note.voided','credit_note',credit_row.id,to_jsonb(credit_row),jsonb_build_object('request_id',request_key,'day',11));
  return jsonb_build_object('ok',true,'idempotent',false,'request_id',request_key,'credit_note',to_jsonb(credit_row));
end;
$function$;

-- ---------------------------------------------------------------------------
-- 11. Provider-neutral webhook reconciliation
-- ---------------------------------------------------------------------------

create or replace function public.reconcile_payment_webhook_event(
  provider_value text,
  provider_event_id_value text,
  event_type_value text,
  signature_valid_value boolean,
  payload_hash_value text,
  target_hotel_id uuid default null,
  target_folio_id uuid default null,
  amount_value numeric default null,
  payment_method_value text default null,
  target_refund_id uuid default null,
  provider_object_id_value text default null,
  transaction_reference_value text default null,
  safe_metadata_value jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  webhook_row public.payment_webhook_events%rowtype;
  normalized_provider text;
  normalized_event_type text;
  collection_result jsonb;
  refund_result jsonb;
  collection_id_value uuid;
  refund_row public.refunds%rowtype;
begin
  normalized_provider := lower(trim(provider_value));
  normalized_event_type := lower(trim(event_type_value));

  if nullif(normalized_provider,'') is null
     or nullif(trim(provider_event_id_value),'') is null
     or nullif(normalized_event_type,'') is null
     or nullif(trim(payload_hash_value),'') is null
  then
    raise exception 'Provider, event ID, event type and payload hash are required.';
  end if;

  insert into public.payment_webhook_events(
    hotel_id,provider,provider_event_id,event_type,signature_valid,payload_hash,
    event_status,processing_attempts,folio_id,refund_id,safe_metadata
  ) values (
    target_hotel_id,normalized_provider,trim(provider_event_id_value),normalized_event_type,
    signature_valid_value,trim(payload_hash_value),'received',0,target_folio_id,target_refund_id,
    coalesce(safe_metadata_value,'{}'::jsonb) || jsonb_build_object(
      'amount',amount_value,'payment_method',payment_method_value,
      'provider_object_id',provider_object_id_value,'transaction_reference',transaction_reference_value,'day',11
    )
  ) on conflict (provider,provider_event_id) do nothing;

  select event_record.* into webhook_row
  from public.payment_webhook_events event_record
  where event_record.provider = normalized_provider
    and event_record.provider_event_id = trim(provider_event_id_value)
  for update;

  if webhook_row.payload_hash <> trim(payload_hash_value) then
    raise exception 'Webhook event ID was reused with a different payload hash.';
  end if;

  if webhook_row.event_type <> normalized_event_type
     or webhook_row.signature_valid is distinct from signature_valid_value
  then
    raise exception 'Webhook event ID conflicts with different normalized event attributes.';
  end if;

  if webhook_row.event_status in ('processed','ignored') then
    return jsonb_build_object('ok',true,'idempotent',true,'webhook_event',to_jsonb(webhook_row));
  end if;

  update public.payment_webhook_events
  set processing_attempts = processing_attempts + 1
  where id = webhook_row.id
  returning * into webhook_row;

  if not signature_valid_value then
    update public.payment_webhook_events
    set event_status = 'failed',processed_at = now(),
        last_error = 'Trusted signature verifier reported invalid signature.'
    where id = webhook_row.id
    returning * into webhook_row;
    return jsonb_build_object('ok',false,'idempotent',false,'reason','invalid_signature','webhook_event',to_jsonb(webhook_row));
  end if;

  begin
    if normalized_event_type = 'payment.succeeded' then
      if target_hotel_id is null or target_folio_id is null or amount_value is null or amount_value <= 0
         or nullif(trim(payment_method_value),'') is null
      then
        raise exception 'payment.succeeded requires hotel, folio, positive amount and payment method.';
      end if;

      collection_result := private.day11_post_collection(
        target_hotel_id,target_folio_id,amount_value,payment_method_value,gen_random_uuid(),
        transaction_reference_value,normalized_provider,provider_object_id_value,
        trim(provider_event_id_value),'payment_webhook_events',webhook_row.id,
        'webhook:' || normalized_provider || ':' || trim(provider_event_id_value),
        webhook_row.received_at,null,
        coalesce(safe_metadata_value,'{}'::jsonb) || jsonb_build_object(
          'webhook_event_id',webhook_row.id,'provider_event_id',trim(provider_event_id_value)
        )
      );

      collection_id_value := (collection_result -> 'collection' ->> 'id')::uuid;
      update public.payment_webhook_events
      set event_status = 'processed',processed_at = now(),last_error = null,
          folio_collection_id = collection_id_value,folio_id = target_folio_id,hotel_id = target_hotel_id
      where id = webhook_row.id
      returning * into webhook_row;

    elsif normalized_event_type = 'payment.failed' then
      update public.payment_webhook_events
      set event_status = 'ignored',processed_at = now(),last_error = null
      where id = webhook_row.id returning * into webhook_row;

    elsif normalized_event_type = 'refund.succeeded' then
      if target_refund_id is null then raise exception 'refund.succeeded requires refund_id.'; end if;
      select refund.* into refund_row from public.refunds refund where refund.id = target_refund_id;
      if not found then raise exception 'Webhook refund was not found.'; end if;

      refund_result := private.day11_process_refund(
        target_refund_id,provider_object_id_value,transaction_reference_value,null,true,
        coalesce(safe_metadata_value,'{}'::jsonb) || jsonb_build_object(
          'webhook_event_id',webhook_row.id,'provider',normalized_provider,'provider_event_id',trim(provider_event_id_value)
        )
      );

      update public.payment_webhook_events
      set event_status = 'processed',processed_at = now(),last_error = null,
          hotel_id = refund_row.hotel_id,folio_id = refund_row.folio_id,refund_id = refund_row.id
      where id = webhook_row.id returning * into webhook_row;

    elsif normalized_event_type = 'refund.failed' then
      if target_refund_id is null then raise exception 'refund.failed requires refund_id.'; end if;
      update public.refunds refund
      set status = 'failed',
          failure_reason = coalesce(nullif(trim(safe_metadata_value ->> 'failure_reason'),''),'Provider reported refund failure.'),
          metadata = refund.metadata || coalesce(safe_metadata_value,'{}'::jsonb) || jsonb_build_object('failed_webhook_event_id',webhook_row.id)
      where refund.id = target_refund_id and refund.status = 'pending'
      returning refund.* into refund_row;
      if refund_row.id is null then raise exception 'Pending webhook refund was not found.'; end if;

      update public.payment_webhook_events
      set event_status = 'processed',processed_at = now(),last_error = null,
          hotel_id = refund_row.hotel_id,folio_id = refund_row.folio_id,refund_id = refund_row.id
      where id = webhook_row.id returning * into webhook_row;

    else
      update public.payment_webhook_events
      set event_status = 'ignored',processed_at = now(),last_error = 'Unsupported normalized event type.'
      where id = webhook_row.id returning * into webhook_row;
    end if;
  exception when others then
    update public.payment_webhook_events
    set event_status = 'failed',processed_at = now(),last_error = sqlerrm
    where id = webhook_row.id returning * into webhook_row;
    return jsonb_build_object('ok',false,'idempotent',false,'reason','processing_failed','error',sqlerrm,'webhook_event',to_jsonb(webhook_row));
  end;

  return jsonb_build_object('ok',true,'idempotent',false,'collection_result',collection_result,'refund_result',refund_result,'webhook_event',to_jsonb(webhook_row));
end;
$function$;

-- ---------------------------------------------------------------------------
-- 12. Security: authenticated clients must use guarded RPCs
-- ---------------------------------------------------------------------------

revoke insert, update, delete
on public.folios,
   public.folio_items,
   public.folio_collections,
   public.discount_approvals,
   public.refunds,
   public.credit_notes,
   public.folio_adjustments,
   public.payment_webhook_events,
   public.folio_events
from authenticated;

grant select
on public.folios,
   public.folio_items,
   public.folio_collections,
   public.discount_approvals,
   public.refunds,
   public.credit_notes,
   public.folio_adjustments,
   public.payment_webhook_events,
   public.folio_events
to authenticated;

revoke all on function public.reconcile_payment_webhook_event(
  text,text,text,boolean,text,uuid,uuid,numeric,text,uuid,text,text,jsonb
) from public, anon, authenticated;
grant execute on function public.reconcile_payment_webhook_event(
  text,text,text,boolean,text,uuid,uuid,numeric,text,uuid,text,text,jsonb
) to service_role;

revoke all on function public.post_folio_collection(uuid,uuid,numeric,text,text,text,text,text) from public, anon;
revoke all on function public.post_folio_split_collection(uuid,uuid,jsonb,text) from public, anon;
revoke all on function public.request_folio_discount(uuid,uuid,text,numeric,text,text) from public, anon;
revoke all on function public.review_folio_discount(uuid,uuid,boolean,text,text) from public, anon;
revoke all on function public.request_folio_refund(uuid,uuid,uuid,numeric,text,text) from public, anon;
revoke all on function public.process_folio_refund(uuid,uuid,text,text,text) from public, anon;
revoke all on function public.issue_folio_credit_note(uuid,uuid,numeric,text,text) from public, anon;
revoke all on function public.void_folio_credit_note(uuid,uuid,text,text) from public, anon;

grant execute on function public.post_folio_collection(uuid,uuid,numeric,text,text,text,text,text) to authenticated, service_role;
grant execute on function public.post_folio_split_collection(uuid,uuid,jsonb,text) to authenticated, service_role;
grant execute on function public.request_folio_discount(uuid,uuid,text,numeric,text,text) to authenticated, service_role;
grant execute on function public.review_folio_discount(uuid,uuid,boolean,text,text) to authenticated, service_role;
grant execute on function public.request_folio_refund(uuid,uuid,uuid,numeric,text,text) to authenticated, service_role;
grant execute on function public.process_folio_refund(uuid,uuid,text,text,text) to authenticated, service_role;
grant execute on function public.issue_folio_credit_note(uuid,uuid,numeric,text,text) to authenticated, service_role;
grant execute on function public.void_folio_credit_note(uuid,uuid,text,text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 13. Normalize current settlement status without creating runtime records
-- ---------------------------------------------------------------------------

do $settlement_state$
declare
  folio_record record;
begin
  for folio_record in
    select folio.hotel_id, folio.id from public.folios folio order by folio.hotel_id,folio.id
  loop
    perform private.recalculate_folio(folio_record.hotel_id,folio_record.id);
  end loop;
end;
$settlement_state$;

comment on function public.post_folio_split_collection(uuid,uuid,jsonb,text) is
'Idempotent partial split/multi-method collection group; aggregate amount cannot exceed open folio balance.';

comment on function public.request_folio_refund(uuid,uuid,uuid,numeric,text,text) is
'Collection-linked partial refund request with pending+processed reservation against over-refund.';

comment on function public.reconcile_payment_webhook_event(text,text,text,boolean,text,uuid,uuid,numeric,text,uuid,text,text,jsonb) is
'Provider-neutral idempotent payment/refund webhook reconciliation. Signature verification occurs outside PostgreSQL.';

commit;
