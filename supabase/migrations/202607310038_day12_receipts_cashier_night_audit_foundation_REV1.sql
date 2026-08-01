
-- StayQR v1.0 — Day 12 Migration 038 REV1
-- Receipts, cashier shifts, accounting CSV and night audit
-- Requires Migration 036 (70/70) and Migration 037 (60/60 + 40/40).
-- Controlled VD Stay Inn source: 38 posted collections / INR 199475.
begin;

do $preflight$
declare
  missing text;
  existing text;
  c bigint;
  a numeric;
begin
  select string_agg(name, ', ' order by name)
  into missing
  from (
    values
      ('public.folios', to_regclass('public.folios') is not null),
      ('public.folio_collections', to_regclass('public.folio_collections') is not null),
      ('public.refunds', to_regclass('public.refunds') is not null),
      ('public.invoices', to_regclass('public.invoices') is not null),
      ('public.credit_notes', to_regclass('public.credit_notes') is not null),
      ('public.folio_source_exceptions', to_regclass('public.folio_source_exceptions') is not null),
      ('public.payment_webhook_events', to_regclass('public.payment_webhook_events') is not null),
      ('public.housekeeping_tasks', to_regclass('public.housekeeping_tasks') is not null),
      ('private.day11_require_current_actor()', to_regprocedure('private.day11_require_current_actor()') is not null),
      ('private.day11_valid_auth_actor(uuid)', to_regprocedure('private.day11_valid_auth_actor(uuid)') is not null),
      ('private.user_has_any_permission(uuid,text[])', to_regprocedure('private.user_has_any_permission(uuid,text[])') is not null),
      ('private.day12_financial_year_start(timestamptz,text)', to_regprocedure('private.day12_financial_year_start(timestamp with time zone,text)') is not null),
      ('private.day12_financial_year_label(integer)', to_regprocedure('private.day12_financial_year_label(integer)') is not null),
      ('private.day12_hash_snapshot(jsonb)', to_regprocedure('private.day12_hash_snapshot(jsonb)') is not null)
  ) v(name, ok)
  where not ok;

  if missing is not null then
    raise exception 'Migration 038 prerequisites missing: %', missing;
  end if;

  select string_agg(name, ', ' order by name)
  into existing
  from (
    values
      ('public.receipts', to_regclass('public.receipts')),
      ('public.receipt_number_sequences', to_regclass('public.receipt_number_sequences')),
      ('public.cashier_shifts', to_regclass('public.cashier_shifts')),
      ('public.cashier_shift_entries', to_regclass('public.cashier_shift_entries')),
      ('public.night_audits', to_regclass('public.night_audits')),
      ('public.night_audit_exceptions', to_regclass('public.night_audit_exceptions')),
      ('public.accounting_exports', to_regclass('public.accounting_exports'))
  ) v(name, oid_value)
  where oid_value is not null;

  if existing is not null then
    raise exception 'Migration 038 target objects already exist: %', existing;
  end if;

  select count(*), coalesce(sum(amount),0)
  into c, a
  from public.folio_collections
  where hotel_id='77d850d0-016d-4155-bc44-a6207d30e7b9'::uuid
    and status='posted';

  if c<>38 or a<>199475 then
    raise exception 'Controlled collection state changed: % rows / % amount.', c, a;
  end if;
end;
$preflight$;

create table public.receipt_number_sequences (
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  financial_year_start integer not null check (financial_year_start between 2000 and 9999),
  prefix text not null default 'RCPT' check (length(trim(prefix)) between 1 and 30),
  last_number bigint not null default 0 check (last_number>=0),
  padding integer not null default 6 check (padding between 1 and 12),
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(hotel_id,financial_year_start)
);

create table public.cashier_shifts (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete restrict,
  shift_number text not null,
  status text not null default 'open' check (status in ('open','closed','voided')),
  opened_at timestamptz not null default now(),
  opened_by uuid not null references auth.users(id) on delete restrict,
  opening_cash numeric(14,2) not null default 0 check (opening_cash>=0),
  closed_at timestamptz,
  closed_by uuid references auth.users(id) on delete set null,
  expected_cash numeric(14,2),
  declared_cash numeric(14,2),
  cash_variance numeric(14,2),
  close_notes text,
  open_idempotency_key text not null,
  close_idempotency_key text,
  snapshot_json jsonb,
  snapshot_hash text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cashier_shifts_close_check check (
    status='open' or (
      closed_at is not null and closed_by is not null
      and expected_cash is not null and expected_cash>=0
      and declared_cash is not null and declared_cash>=0
      and cash_variance is not null
      and snapshot_json is not null and snapshot_hash is not null
    )
  )
);
create unique index uq_cashier_shifts_hotel_id_id on public.cashier_shifts(hotel_id,id);
create unique index uq_cashier_shifts_number on public.cashier_shifts(hotel_id,shift_number);
create unique index uq_cashier_shifts_open_request on public.cashier_shifts(hotel_id,open_idempotency_key);
create unique index uq_cashier_shifts_close_request on public.cashier_shifts(hotel_id,close_idempotency_key) where close_idempotency_key is not null;
create unique index uq_cashier_shifts_one_open_per_actor on public.cashier_shifts(hotel_id,opened_by) where status='open';

create table public.receipts (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete restrict,
  folio_id uuid not null,
  folio_collection_id uuid not null,
  cashier_shift_id uuid,
  receipt_number text not null,
  receipt_status text not null default 'issued' check (receipt_status in ('issued','voided')),
  currency_code text not null default 'INR' check (currency_code ~ '^[A-Z]{3}$'),
  amount numeric(14,2) not null check (amount>0),
  payment_method text not null check (payment_method in ('cash','card','upi','bank_transfer','payment_link','other')),
  transaction_reference text,
  provider text,
  provider_payment_id text,
  issued_at timestamptz not null,
  issued_by uuid references auth.users(id) on delete set null,
  voided_at timestamptz,
  voided_by uuid references auth.users(id) on delete set null,
  void_reason text,
  idempotency_key text not null,
  snapshot_json jsonb not null,
  snapshot_hash text not null check (length(trim(snapshot_hash))=64),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key(hotel_id,folio_id) references public.folios(hotel_id,id) on delete restrict,
  foreign key(hotel_id,folio_collection_id) references public.folio_collections(hotel_id,id) on delete restrict,
  foreign key(hotel_id,cashier_shift_id) references public.cashier_shifts(hotel_id,id) on delete restrict,
  constraint receipts_void_check check (
    receipt_status='issued' or (voided_at is not null and nullif(trim(void_reason),'') is not null)
  ),
  constraint uq_receipts_hotel_id_id unique(hotel_id,id)
);
create unique index uq_receipts_number on public.receipts(hotel_id,receipt_number);
create unique index uq_receipts_collection on public.receipts(hotel_id,folio_collection_id);
create unique index uq_receipts_idempotency on public.receipts(hotel_id,idempotency_key);

create table public.cashier_shift_entries (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete restrict,
  cashier_shift_id uuid not null,
  entry_type text not null check (entry_type in ('collection','refund','cash_adjustment')),
  direction text not null check (direction in ('inflow','outflow')),
  amount numeric(14,2) not null check (amount>0),
  net_effect numeric(14,2) not null,
  payment_method text check (payment_method is null or payment_method in ('cash','card','upi','bank_transfer','payment_link','other')),
  folio_id uuid,
  folio_collection_id uuid,
  refund_id uuid,
  receipt_id uuid,
  source_table text not null,
  source_id uuid not null,
  occurred_at timestamptz not null,
  actor_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  foreign key(hotel_id,cashier_shift_id) references public.cashier_shifts(hotel_id,id) on delete cascade,
  foreign key(hotel_id,folio_id) references public.folios(hotel_id,id) on delete restrict,
  foreign key(hotel_id,folio_collection_id) references public.folio_collections(hotel_id,id) on delete restrict,
  foreign key(hotel_id,refund_id) references public.refunds(hotel_id,id) on delete restrict,
  foreign key(hotel_id,receipt_id) references public.receipts(hotel_id,id) on delete restrict,
  constraint cashier_shift_entries_effect_check check (
    (direction='inflow' and net_effect=amount)
    or (direction='outflow' and net_effect=-amount)
  )
);
create unique index uq_cashier_shift_entries_source
  on public.cashier_shift_entries(hotel_id,cashier_shift_id,entry_type,source_table,source_id);

create table public.night_audits (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete restrict,
  business_date date not null,
  audit_number text not null,
  status text not null default 'closed' check (status in ('closed','voided')),
  closed_with_exceptions boolean not null default false,
  started_at timestamptz not null,
  closed_at timestamptz not null,
  closed_by uuid not null references auth.users(id) on delete restrict,
  close_notes text,
  blocker_count integer not null default 0 check (blocker_count>=0),
  warning_count integer not null default 0 check (warning_count>=0),
  exception_count integer not null default 0,
  charges_amount numeric(14,2) not null default 0 check (charges_amount>=0),
  discounts_amount numeric(14,2) not null default 0 check (discounts_amount>=0),
  taxes_amount numeric(14,2) not null default 0 check (taxes_amount>=0),
  collections_amount numeric(14,2) not null default 0 check (collections_amount>=0),
  refunds_amount numeric(14,2) not null default 0 check (refunds_amount>=0),
  credits_amount numeric(14,2) not null default 0 check (credits_amount>=0),
  open_balance_amount numeric(14,2) not null default 0 check (open_balance_amount>=0),
  idempotency_key text not null,
  snapshot_json jsonb not null,
  snapshot_hash text not null check (length(trim(snapshot_hash))=64),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint night_audits_count_check check (exception_count=blocker_count+warning_count),
  constraint uq_night_audits_hotel_id_id unique(hotel_id,id)
);
create unique index uq_night_audits_business_date on public.night_audits(hotel_id,business_date) where status='closed';
create unique index uq_night_audits_number on public.night_audits(hotel_id,audit_number);
create unique index uq_night_audits_request on public.night_audits(hotel_id,idempotency_key);

create table public.night_audit_exceptions (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete restrict,
  night_audit_id uuid not null,
  exception_type text not null,
  severity text not null check (severity in ('blocker','warning')),
  entity_type text,
  entity_id uuid,
  amount numeric(14,2),
  message text not null check (length(trim(message))>0),
  status text not null default 'open' check (status in ('open','resolved','waived')),
  acknowledged boolean not null default false,
  resolution_notes text,
  source_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  foreign key(hotel_id,night_audit_id) references public.night_audits(hotel_id,id) on delete cascade
);

create table public.accounting_exports (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete restrict,
  night_audit_id uuid,
  export_type text not null default 'accounting_csv' check (export_type in ('accounting_csv','collections_csv','invoice_csv','gst_csv')),
  date_from date not null,
  date_to date not null check (date_to>=date_from),
  file_name text not null,
  content_type text not null default 'text/csv',
  row_count integer not null check (row_count>=0),
  csv_content text not null check (length(csv_content)>0),
  content_hash text not null check (length(trim(content_hash))=64),
  idempotency_key text not null,
  generated_at timestamptz not null default now(),
  generated_by uuid not null references auth.users(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb,
  foreign key(hotel_id,night_audit_id) references public.night_audits(hotel_id,id) on delete restrict,
  constraint uq_accounting_exports_hotel_id_id unique(hotel_id,id)
);
create unique index uq_accounting_exports_request on public.accounting_exports(hotel_id,idempotency_key);

alter table public.receipt_number_sequences enable row level security;
alter table public.cashier_shifts enable row level security;
alter table public.receipts enable row level security;
alter table public.cashier_shift_entries enable row level security;
alter table public.night_audits enable row level security;
alter table public.night_audit_exceptions enable row level security;
alter table public.accounting_exports enable row level security;

create policy stayqr_receipt_sequences_select on public.receipt_number_sequences for select to authenticated
using (private.user_has_any_permission(hotel_id,array['payments.view','payments.manage','invoices.view','invoices.manage','checkout.manage']::text[]));
create policy stayqr_cashier_shifts_select on public.cashier_shifts for select to authenticated
using (private.user_has_any_permission(hotel_id,array['payments.view','payments.manage','invoices.view','invoices.manage','checkout.manage']::text[]));
create policy stayqr_receipts_select on public.receipts for select to authenticated
using (private.user_has_any_permission(hotel_id,array['payments.view','payments.manage','invoices.view','invoices.manage','checkout.manage']::text[]));
create policy stayqr_shift_entries_select on public.cashier_shift_entries for select to authenticated
using (private.user_has_any_permission(hotel_id,array['payments.view','payments.manage','invoices.view','invoices.manage','checkout.manage']::text[]));
create policy stayqr_night_audits_select on public.night_audits for select to authenticated
using (private.user_has_any_permission(hotel_id,array['payments.view','payments.manage','invoices.view','invoices.manage','checkout.manage']::text[]));
create policy stayqr_night_exceptions_select on public.night_audit_exceptions for select to authenticated
using (private.user_has_any_permission(hotel_id,array['payments.view','payments.manage','invoices.view','invoices.manage','checkout.manage']::text[]));
create policy stayqr_accounting_exports_select on public.accounting_exports for select to authenticated
using (private.user_has_any_permission(hotel_id,array['payments.view','payments.manage','invoices.view','invoices.manage','checkout.manage']::text[]));

create or replace function private.day12_hash_text(v text)
returns text language sql immutable security invoker set search_path=''
as $f$
  select encode(extensions.digest(convert_to(coalesce(v,''),'UTF8'),'sha256'),'hex');
$f$;

create or replace function private.day12_csv_escape(v text)
returns text language sql immutable security invoker set search_path=''
as $f$
  select '"'||replace(coalesce(v,''),'"','""')||'"';
$f$;

create or replace function private.day12_current_open_cashier_shift(h uuid, actor uuid)
returns uuid language sql stable security definer set search_path=''
as $f$
  select id from public.cashier_shifts
  where hotel_id=h and opened_by=actor and status='open'
  order by opened_at desc limit 1;
$f$;

create or replace function private.day12_next_receipt_number(h uuid, occurred timestamptz)
returns jsonb language plpgsql security definer set search_path=''
as $f$
declare
  tz text;
  fy integer;
  label text;
  seq public.receipt_number_sequences%rowtype;
begin
  select timezone into tz from public.hotels where id=h;
  if tz is null then raise exception 'Hotel not found.'; end if;
  fy:=private.day12_financial_year_start(coalesce(occurred,now()),tz);
  label:=private.day12_financial_year_label(fy);
  perform pg_advisory_xact_lock(hashtextextended('stayqr:receipt-seq:'||h::text||':'||fy::text,0));
  insert into public.receipt_number_sequences(hotel_id,financial_year_start,prefix,last_number,padding,updated_by)
  values(h,fy,'RCPT',0,6,private.day11_valid_auth_actor(auth.uid()))
  on conflict(hotel_id,financial_year_start) do nothing;
  update public.receipt_number_sequences
  set last_number=last_number+1,updated_by=private.day11_valid_auth_actor(auth.uid()),updated_at=now()
  where hotel_id=h and financial_year_start=fy
  returning * into seq;
  return jsonb_build_object(
    'receipt_number',trim(seq.prefix)||'/'||label||'/'||lpad(seq.last_number::text,seq.padding,'0'),
    'financial_year_start',fy,'financial_year_label',label,'sequence_number',seq.last_number
  );
end;
$f$;

create or replace function private.day12_guard_receipt_immutability()
returns trigger language plpgsql security definer set search_path=''
as $f$
declare
  o jsonb;
  n jsonb;
begin
  if tg_op='DELETE' then raise exception 'Receipts are immutable and cannot be deleted.'; end if;
  if old.receipt_status='voided' then raise exception 'Voided receipts are immutable.'; end if;
  o:=to_jsonb(old)-'receipt_status'-'voided_at'-'voided_by'-'void_reason'-'metadata'-'updated_at';
  n:=to_jsonb(new)-'receipt_status'-'voided_at'-'voided_by'-'void_reason'-'metadata'-'updated_at';
  if n is distinct from o then raise exception 'Issued receipt financial identity is immutable.'; end if;
  if new.receipt_status<>'voided' or new.voided_at is null or nullif(trim(new.void_reason),'') is null then
    raise exception 'Receipt updates are limited to a complete void transition.';
  end if;
  new.updated_at:=now();
  return new;
end;
$f$;
create trigger receipts_day12_immutable before update or delete on public.receipts
for each row execute function private.day12_guard_receipt_immutability();

create or replace function private.day12_issue_receipt_for_collection(collection_id_value uuid)
returns jsonb language plpgsql security definer set search_path=''
as $f$
declare
  c public.folio_collections%rowtype;
  fol public.folios%rowtype;
  r public.receipts%rowtype;
  num jsonb;
  shift_id uuid;
  snap jsonb;
  hash_value text;
begin
  select * into c from public.folio_collections where id=collection_id_value;
  if not found then return jsonb_build_object('ok',true,'skipped',true,'reason','collection_not_found'); end if;
  select * into r from public.receipts where hotel_id=c.hotel_id and folio_collection_id=c.id;
  if r.id is not null then return jsonb_build_object('ok',true,'idempotent',true,'receipt',to_jsonb(r)); end if;
  if c.status<>'posted' then return jsonb_build_object('ok',true,'skipped',true,'reason','collection_not_posted'); end if;
  select * into fol from public.folios where hotel_id=c.hotel_id and id=c.folio_id;
  if not found then raise exception 'Collection folio not found.'; end if;
  shift_id:=private.day12_current_open_cashier_shift(c.hotel_id,c.collected_by);
  num:=private.day12_next_receipt_number(c.hotel_id,c.collected_at);
  snap:=jsonb_build_object(
    'schema','stayqr.receipt.snapshot','version',1,
    'receipt_number',num->>'receipt_number',
    'hotel',(select to_jsonb(h) from public.hotels h where h.id=c.hotel_id),
    'folio',to_jsonb(fol),'collection',to_jsonb(c),'cashier_shift_id',shift_id,'issued_at',c.collected_at
  );
  hash_value:=private.day12_hash_snapshot(snap);
  insert into public.receipts(
    hotel_id,folio_id,folio_collection_id,cashier_shift_id,receipt_number,receipt_status,currency_code,
    amount,payment_method,transaction_reference,provider,provider_payment_id,issued_at,issued_by,
    idempotency_key,snapshot_json,snapshot_hash,metadata
  ) values (
    c.hotel_id,c.folio_id,c.id,shift_id,num->>'receipt_number','issued',fol.currency_code,
    c.amount,c.payment_method,c.transaction_reference,c.provider,c.provider_payment_id,c.collected_at,
    private.day11_valid_auth_actor(c.collected_by),'collection:'||c.id::text,snap,hash_value,
    jsonb_build_object('financial_year_start',(num->>'financial_year_start')::integer,'source','folio_collection')
  ) returning * into r;
  return jsonb_build_object('ok',true,'idempotent',false,'receipt',to_jsonb(r));
end;
$f$;

create or replace function private.day12_sync_collection_receipt_shift()
returns trigger language plpgsql security definer set search_path=''
as $f$
declare
  result_value jsonb;
  receipt_id_value uuid;
  shift_id_value uuid;
begin
  if new.status='posted' then
    result_value:=private.day12_issue_receipt_for_collection(new.id);
    receipt_id_value:=nullif(result_value#>>'{receipt,id}','')::uuid;
    shift_id_value:=private.day12_current_open_cashier_shift(new.hotel_id,new.collected_by);
    if shift_id_value is not null and receipt_id_value is not null then
      insert into public.cashier_shift_entries(
        hotel_id,cashier_shift_id,entry_type,direction,amount,net_effect,payment_method,
        folio_id,folio_collection_id,receipt_id,source_table,source_id,occurred_at,actor_id,metadata
      ) values (
        new.hotel_id,shift_id_value,'collection','inflow',new.amount,new.amount,new.payment_method,
        new.folio_id,new.id,receipt_id_value,'folio_collections',new.id,new.collected_at,
        private.day11_valid_auth_actor(new.collected_by),
        jsonb_build_object('transaction_reference',new.transaction_reference,'provider',new.provider)
      ) on conflict(hotel_id,cashier_shift_id,entry_type,source_table,source_id) do nothing;
    end if;
  elsif tg_op='UPDATE' and old.status='posted' and new.status in ('voided','reversed') then
    update public.receipts
    set receipt_status='voided',voided_at=coalesce(new.voided_at,now()),
        voided_by=private.day11_valid_auth_actor(new.voided_by),
        void_reason=coalesce(nullif(trim(new.void_reason),''),'Source collection was '||new.status||'.'),
        metadata=metadata||jsonb_build_object('source_collection_status',new.status)
    where hotel_id=new.hotel_id and folio_collection_id=new.id and receipt_status='issued';
  end if;
  return new;
end;
$f$;
create trigger folio_collections_day12_receipt_shift
after insert or update of status on public.folio_collections
for each row execute function private.day12_sync_collection_receipt_shift();

create or replace function private.day12_sync_refund_shift()
returns trigger language plpgsql security definer set search_path=''
as $f$
declare
  shift_id_value uuid;
begin
  if new.status='processed' and (tg_op='INSERT' or old.status is distinct from new.status) then
    shift_id_value:=private.day12_current_open_cashier_shift(new.hotel_id,new.processed_by);
    if shift_id_value is not null then
      insert into public.cashier_shift_entries(
        hotel_id,cashier_shift_id,entry_type,direction,amount,net_effect,payment_method,
        folio_id,folio_collection_id,refund_id,source_table,source_id,occurred_at,actor_id,metadata
      ) values (
        new.hotel_id,shift_id_value,'refund','outflow',new.amount,-new.amount,new.payment_method,
        new.folio_id,new.folio_collection_id,new.id,'refunds',new.id,coalesce(new.processed_at,now()),
        private.day11_valid_auth_actor(new.processed_by),
        jsonb_build_object('transaction_reference',new.transaction_reference,'provider',new.provider)
      ) on conflict(hotel_id,cashier_shift_id,entry_type,source_table,source_id) do nothing;
    end if;
  end if;
  return new;
end;
$f$;
create trigger refunds_day12_cashier_shift after insert or update of status on public.refunds
for each row execute function private.day12_sync_refund_shift();

create or replace function private.day12_build_cashier_shift_snapshot(h uuid, shift_id_value uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $f$
declare
  s public.cashier_shifts%rowtype;
  entry_count_value integer;
  inflow_value numeric;
  outflow_value numeric;
  cash_net_value numeric;
  methods jsonb;
begin
  select * into s from public.cashier_shifts where hotel_id=h and id=shift_id_value;
  if not found then raise exception 'Cashier shift not found.'; end if;
  select count(*),
         coalesce(sum(amount) filter(where direction='inflow'),0),
         coalesce(sum(amount) filter(where direction='outflow'),0),
         coalesce(sum(net_effect) filter(where payment_method='cash'),0)
  into entry_count_value,inflow_value,outflow_value,cash_net_value
  from public.cashier_shift_entries where hotel_id=h and cashier_shift_id=shift_id_value;
  select coalesce(jsonb_object_agg(method_value,payload),'{}'::jsonb)
  into methods
  from (
    select coalesce(payment_method,'unclassified') method_value,
           jsonb_build_object(
             'entries',count(*),
             'inflow',coalesce(sum(amount) filter(where direction='inflow'),0),
             'outflow',coalesce(sum(amount) filter(where direction='outflow'),0),
             'net',coalesce(sum(net_effect),0)
           ) payload
    from public.cashier_shift_entries
    where hotel_id=h and cashier_shift_id=shift_id_value
    group by coalesce(payment_method,'unclassified')
  ) q;
  return jsonb_build_object(
    'shift',to_jsonb(s),'entry_count',entry_count_value,'inflow_amount',inflow_value,
    'outflow_amount',outflow_value,'net_amount',inflow_value-outflow_value,
    'cash_net',cash_net_value,'expected_cash',s.opening_cash+cash_net_value,
    'method_breakdown',methods,
    'entries',coalesce((select jsonb_agg(to_jsonb(e) order by e.occurred_at,e.id)
                        from public.cashier_shift_entries e
                        where e.hotel_id=h and e.cashier_shift_id=shift_id_value),'[]'::jsonb)
  );
end;
$f$;

create or replace function public.open_cashier_shift(h uuid, opening_cash_value numeric, request_id_value text)
returns jsonb language plpgsql security definer set search_path=''
as $f$
declare
  actor uuid;
  request_key text;
  s public.cashier_shifts%rowtype;
  open_s public.cashier_shifts%rowtype;
  n text;
begin
  if not private.user_has_any_permission(h,array['payments.manage','checkout.manage','invoices.manage']::text[]) then
    raise exception 'Cashier shift opening access denied.';
  end if;
  actor:=private.day11_require_current_actor();
  request_key:=nullif(trim(request_id_value),'');
  if request_key is null or length(request_key)<8 then raise exception 'Request ID of at least eight characters required.'; end if;
  if opening_cash_value is null or opening_cash_value<0 then raise exception 'Opening cash cannot be negative.'; end if;
  select * into s from public.cashier_shifts where hotel_id=h and open_idempotency_key=request_key;
  if s.id is not null then return jsonb_build_object('ok',true,'idempotent',true,'shift',to_jsonb(s)); end if;
  select * into open_s from public.cashier_shifts where hotel_id=h and opened_by=actor and status='open';
  if open_s.id is not null then raise exception 'Current cashier already has an open shift.'; end if;
  n:='CS/'||to_char(now() at time zone (select timezone from public.hotels where id=h),'YYYYMMDD-HH24MISS')
     ||'/'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  insert into public.cashier_shifts(hotel_id,shift_number,status,opened_at,opened_by,opening_cash,open_idempotency_key,metadata)
  values(h,n,'open',now(),actor,opening_cash_value,request_key,jsonb_build_object('request_id',request_key,'day',12))
  returning * into s;
  return jsonb_build_object('ok',true,'idempotent',false,'shift',to_jsonb(s));
end;
$f$;

create or replace function public.close_cashier_shift(
  h uuid, shift_id_value uuid, declared_cash_value numeric, notes_value text, request_id_value text
)
returns jsonb language plpgsql security definer set search_path=''
as $f$
declare
  actor uuid;
  request_key text;
  s public.cashier_shifts%rowtype;
  snap jsonb;
  hash_value text;
  expected_value numeric;
begin
  if not private.user_has_any_permission(h,array['payments.manage','checkout.manage','invoices.manage']::text[]) then
    raise exception 'Cashier shift closing access denied.';
  end if;
  actor:=private.day11_require_current_actor();
  request_key:=nullif(trim(request_id_value),'');
  if request_key is null or length(request_key)<8 then raise exception 'Request ID of at least eight characters required.'; end if;
  if declared_cash_value is null or declared_cash_value<0 then raise exception 'Declared cash cannot be negative.'; end if;
  select * into s from public.cashier_shifts where hotel_id=h and id=shift_id_value for update;
  if not found then raise exception 'Cashier shift not found.'; end if;
  if s.status='closed' then
    if s.close_idempotency_key=request_key then
      return jsonb_build_object('ok',true,'idempotent',true,'shift',to_jsonb(s),'snapshot',s.snapshot_json);
    end if;
    raise exception 'Cashier shift already closed.';
  end if;
  if s.opened_by<>actor then raise exception 'Only opening cashier can close shift.'; end if;
  snap:=private.day12_build_cashier_shift_snapshot(h,shift_id_value);
  expected_value:=(snap->>'expected_cash')::numeric;
  snap:=snap||jsonb_build_object(
    'declared_cash',declared_cash_value,'cash_variance',declared_cash_value-expected_value,
    'closed_at',now(),'closed_by',actor,'close_notes',nullif(trim(notes_value),''),
    'close_request_id',request_key
  );
  hash_value:=private.day12_hash_snapshot(snap);
  update public.cashier_shifts
  set status='closed',closed_at=now(),closed_by=actor,expected_cash=expected_value,
      declared_cash=declared_cash_value,cash_variance=declared_cash_value-expected_value,
      close_notes=nullif(trim(notes_value),''),close_idempotency_key=request_key,
      snapshot_json=snap,snapshot_hash=hash_value,
      metadata=metadata||jsonb_build_object('close_request_id',request_key),updated_at=now()
  where hotel_id=h and id=shift_id_value returning * into s;
  return jsonb_build_object('ok',true,'idempotent',false,'shift',to_jsonb(s),'snapshot',snap);
end;
$f$;

create or replace function public.get_cashier_shift_report(h uuid, shift_id_value uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $f$
begin
  if not private.user_has_any_permission(h,array['payments.view','payments.manage','invoices.view','invoices.manage','checkout.manage']::text[]) then
    raise exception 'Cashier shift report access denied.';
  end if;
  return private.day12_build_cashier_shift_snapshot(h,shift_id_value);
end;
$f$;

create or replace function private.day12_build_day_close_preview(h uuid, business_date_value date)
returns jsonb language plpgsql stable security definer set search_path=''
as $f$
declare
  hotel_row public.hotels%rowtype;
  period_end timestamptz;
  x jsonb:='[]'::jsonb;
  blockers integer;
  warnings integer;
  financial jsonb;
begin
  select * into hotel_row from public.hotels where id=h;
  if not found then raise exception 'Hotel not found.'; end if;
  if business_date_value is null then raise exception 'Business date required.'; end if;
  period_end:=(business_date_value+1)::timestamp at time zone hotel_row.timezone;

  x:=x||coalesce((select jsonb_agg(jsonb_build_object(
    'exception_type','open_folio','severity','blocker','entity_type','folio','entity_id',id,
    'amount',balance_amount,'message','Open folio '||folio_number||' has balance '||balance_amount::text,
    'source_snapshot',to_jsonb(f)
  ) order by balance_amount desc,id)
  from public.folios f where hotel_id=h and status='open' and balance_amount>0),'[]'::jsonb);

  x:=x||coalesce((select jsonb_agg(jsonb_build_object(
    'exception_type','active_stay','severity','blocker','entity_type','guest_session','entity_id',id,
    'amount',null,'message','Guest session remains active.','source_snapshot',to_jsonb(s)
  ) order by checkin_time,id)
  from public.guest_sessions s where hotel_id=h and status='active'),'[]'::jsonb);

  x:=x||coalesce((select jsonb_agg(jsonb_build_object(
    'exception_type','overdue_stay','severity','blocker','entity_type','guest_session','entity_id',id,
    'amount',null,'message','Active stay is past effective checkout.','source_snapshot',to_jsonb(s)
  ) order by coalesce(extended_until,checkout_time),id)
  from public.guest_sessions s
  where hotel_id=h and status='active' and coalesce(extended_until,checkout_time)<period_end),'[]'::jsonb);

  x:=x||coalesce((select jsonb_agg(jsonb_build_object(
    'exception_type','financial_source_exception','severity','warning','entity_type',source_table,
    'entity_id',source_id,'amount',null,'message','Financial source remains unmapped: '||source_table,
    'source_snapshot',to_jsonb(e)
  ) order by last_seen_at,id)
  from public.folio_source_exceptions e where hotel_id=h and status='open'),'[]'::jsonb);

  x:=x||coalesce((select jsonb_agg(jsonb_build_object(
    'exception_type','pending_refund','severity','blocker','entity_type','refund','entity_id',id,
    'amount',amount,'message','Refund remains pending.','source_snapshot',to_jsonb(r)
  ) order by requested_at,id)
  from public.refunds r where hotel_id=h and status='pending'),'[]'::jsonb);

  x:=x||coalesce((select jsonb_agg(jsonb_build_object(
    'exception_type','unresolved_gateway_event','severity','blocker','entity_type','payment_webhook_event',
    'entity_id',id,'amount',null,'message','Gateway event remains '||event_status||'.',
    'source_snapshot',to_jsonb(e)
  ) order by received_at,id)
  from public.payment_webhook_events e where hotel_id=h and event_status in ('received','failed')),'[]'::jsonb);

  x:=x||coalesce((select jsonb_agg(jsonb_build_object(
    'exception_type','open_cashier_shift','severity','blocker','entity_type','cashier_shift','entity_id',id,
    'amount',opening_cash,'message','Cashier shift '||shift_number||' remains open.',
    'source_snapshot',to_jsonb(s)
  ) order by opened_at,id)
  from public.cashier_shifts s where hotel_id=h and status='open'),'[]'::jsonb);

  x:=x||coalesce((select jsonb_agg(jsonb_build_object(
    'exception_type','unreceipted_collection','severity','blocker','entity_type','folio_collection',
    'entity_id',c.id,'amount',c.amount,'message','Posted collection has no receipt.',
    'source_snapshot',to_jsonb(c)
  ) order by c.collected_at,c.id)
  from public.folio_collections c left join public.receipts r
    on r.hotel_id=c.hotel_id and r.folio_collection_id=c.id
  where c.hotel_id=h and c.status='posted' and r.id is null),'[]'::jsonb);

  x:=x||coalesce((select jsonb_agg(jsonb_build_object(
    'exception_type','draft_invoice','severity','warning','entity_type','invoice','entity_id',id,
    'amount',total_amount,'message','Invoice remains draft.','source_snapshot',to_jsonb(i)
  ) order by created_at,id)
  from public.invoices i where hotel_id=h and invoice_status='draft' and finalized_at is null),'[]'::jsonb);

  x:=x||coalesce((select jsonb_agg(jsonb_build_object(
    'exception_type','unfinished_housekeeping','severity','warning','entity_type','housekeeping_task',
    'entity_id',id,'amount',null,'message','Housekeeping task remains '||coalesce(status,'unknown')||'.',
    'source_snapshot',to_jsonb(t)
  ) order by created_at,id)
  from public.housekeeping_tasks t
  where hotel_id=h and coalesce(status,'pending') not in ('completed','cancelled','inspected','ready')),'[]'::jsonb);

  select count(*) filter(where value->>'severity'='blocker'),
         count(*) filter(where value->>'severity'='warning')
  into blockers,warnings from jsonb_array_elements(x);

  select jsonb_build_object(
    'folios',count(*),'open_folios',count(*) filter(where status='open'),
    'settled_folios',count(*) filter(where status='settled'),
    'charges_amount',coalesce(sum(charges_amount),0),
    'discounts_amount',coalesce(sum(discount_amount),0),
    'taxes_amount',coalesce(sum(tax_amount),0),
    'collections_amount',coalesce(sum(collection_amount),0),
    'refunds_amount',coalesce(sum(refund_amount),0),
    'credits_amount',coalesce(sum(credit_amount),0),
    'open_balance_amount',coalesce(sum(balance_amount),0),
    'equation_failures',count(*) filter(where balance_amount<>charges_amount-discount_amount+tax_amount-collection_amount+refund_amount-credit_amount)
  ) into financial from public.folios where hotel_id=h;

  return jsonb_build_object(
    'schema','stayqr.day_close.preview','version',1,'hotel_id',h,'business_date',business_date_value,
    'timezone',hotel_row.timezone,'generated_at',now(),'blocker_count',blockers,'warning_count',warnings,
    'exception_count',blockers+warnings,'financial_summary',financial,'exceptions',x
  );
end;
$f$;

create or replace function public.preview_day_close(h uuid, business_date_value date)
returns jsonb language plpgsql stable security definer set search_path=''
as $f$
begin
  if not private.user_has_any_permission(h,array['payments.view','payments.manage','invoices.view','invoices.manage','checkout.manage']::text[]) then
    raise exception 'Day-close preview access denied.';
  end if;
  return private.day12_build_day_close_preview(h,business_date_value);
end;
$f$;

create or replace function private.day12_build_accounting_csv(h uuid, d1 date, d2 date)
returns jsonb language plpgsql stable security definer set search_path=''
as $f$
declare
  tz text;
  start_at timestamptz;
  end_at timestamptz;
  header text:='business_date,entry_type,document_number,folio_number,invoice_number,payment_method,amount,tax_amount,reference,event_at';
  body text;
  csv text;
  rows_count integer;
begin
  if d1 is null or d2 is null or d2<d1 then raise exception 'Accounting export date range invalid.'; end if;
  select timezone into tz from public.hotels where id=h;
  if tz is null then raise exception 'Hotel not found.'; end if;
  start_at:=d1::timestamp at time zone tz;
  end_at:=(d2+1)::timestamp at time zone tz;

  select count(*),string_agg(row_text,E'\n' order by event_at,sort_order,document_number)
  into rows_count,body
  from (
    select c.collected_at event_at,1 sort_order,r.receipt_number document_number,
      private.day12_csv_escape((c.collected_at at time zone tz)::date::text)||','||
      private.day12_csv_escape('collection')||','||private.day12_csv_escape(r.receipt_number)||','||
      private.day12_csv_escape(f.folio_number)||','||private.day12_csv_escape(coalesce(i.invoice_number,''))||','||
      private.day12_csv_escape(c.payment_method)||','||private.day12_csv_escape(c.amount::text)||','||
      private.day12_csv_escape('0')||','||
      private.day12_csv_escape(coalesce(c.transaction_reference,c.provider_payment_id,''))||','||
      private.day12_csv_escape(c.collected_at::text) row_text
    from public.folio_collections c
    join public.folios f on f.hotel_id=c.hotel_id and f.id=c.folio_id
    join public.receipts r on r.hotel_id=c.hotel_id and r.folio_collection_id=c.id
    left join public.invoices i on i.hotel_id=c.hotel_id and i.folio_id=c.folio_id
      and i.invoice_origin='authoritative' and i.finalized_at is not null
    where c.hotel_id=h and c.status='posted' and c.collected_at>=start_at and c.collected_at<end_at

    union all

    select r.processed_at,2,'REFUND/'||r.id::text,
      private.day12_csv_escape((r.processed_at at time zone tz)::date::text)||','||
      private.day12_csv_escape('refund')||','||private.day12_csv_escape('REFUND/'||r.id::text)||','||
      private.day12_csv_escape(f.folio_number)||','||private.day12_csv_escape(coalesce(i.invoice_number,''))||','||
      private.day12_csv_escape(r.payment_method)||','||private.day12_csv_escape((-r.amount)::text)||','||
      private.day12_csv_escape('0')||','||
      private.day12_csv_escape(coalesce(r.transaction_reference,r.provider_refund_id,''))||','||
      private.day12_csv_escape(r.processed_at::text)
    from public.refunds r
    join public.folios f on f.hotel_id=r.hotel_id and f.id=r.folio_id
    left join public.invoices i on i.hotel_id=r.hotel_id and i.folio_id=r.folio_id
      and i.invoice_origin='authoritative' and i.finalized_at is not null
    where r.hotel_id=h and r.status='processed' and r.processed_at>=start_at and r.processed_at<end_at

    union all

    select i.finalized_at,3,i.invoice_number,
      private.day12_csv_escape(i.invoice_date::text)||','||private.day12_csv_escape('invoice')||','||
      private.day12_csv_escape(i.invoice_number)||','||private.day12_csv_escape(f.folio_number)||','||
      private.day12_csv_escape(i.invoice_number)||','||private.day12_csv_escape('')||','||
      private.day12_csv_escape(i.total_amount::text)||','||private.day12_csv_escape(i.tax_amount::text)||','||
      private.day12_csv_escape(i.snapshot_hash)||','||private.day12_csv_escape(i.finalized_at::text)
    from public.invoices i
    join public.folios f on f.hotel_id=i.hotel_id and f.id=i.folio_id
    where i.hotel_id=h and i.invoice_origin='authoritative' and i.finalized_at>=start_at and i.finalized_at<end_at

    union all

    select c.issued_at,4,c.credit_note_number,
      private.day12_csv_escape((c.issued_at at time zone tz)::date::text)||','||private.day12_csv_escape('credit_note')||','||
      private.day12_csv_escape(c.credit_note_number)||','||private.day12_csv_escape(f.folio_number)||','||
      private.day12_csv_escape(coalesce(i.invoice_number,''))||','||private.day12_csv_escape('')||','||
      private.day12_csv_escape((-c.amount)::text)||','||private.day12_csv_escape('0')||','||
      private.day12_csv_escape(c.reason)||','||private.day12_csv_escape(c.issued_at::text)
    from public.credit_notes c
    join public.folios f on f.hotel_id=c.hotel_id and f.id=c.folio_id
    left join public.invoices i on i.hotel_id=c.hotel_id and i.folio_id=c.folio_id
      and i.invoice_origin='authoritative' and i.finalized_at is not null
    where c.hotel_id=h and c.status='issued' and c.issued_at>=start_at and c.issued_at<end_at
  ) q;

  csv:=header||case when coalesce(body,'')='' then '' else E'\n'||body end;
  return jsonb_build_object('date_from',d1,'date_to',d2,'row_count',rows_count,'csv_content',csv,'content_hash',private.day12_hash_text(csv));
end;
$f$;

create or replace function private.day12_create_accounting_export(
  h uuid,audit_id_value uuid,d1 date,d2 date,request_key text,actor uuid
)
returns public.accounting_exports language plpgsql security definer set search_path=''
as $f$
declare
  e public.accounting_exports%rowtype;
  payload jsonb;
begin
  select * into e from public.accounting_exports where hotel_id=h and idempotency_key=request_key;
  if e.id is not null then return e; end if;
  payload:=private.day12_build_accounting_csv(h,d1,d2);
  insert into public.accounting_exports(
    hotel_id,night_audit_id,export_type,date_from,date_to,file_name,content_type,row_count,
    csv_content,content_hash,idempotency_key,generated_by,metadata
  ) values (
    h,audit_id_value,'accounting_csv',d1,d2,
    'stayqr-accounting-'||d1::text||case when d2=d1 then '' else '-to-'||d2::text end||'.csv',
    'text/csv',(payload->>'row_count')::integer,payload->>'csv_content',payload->>'content_hash',
    request_key,actor,jsonb_build_object('generated_from',case when audit_id_value is null then 'manual_export' else 'night_audit' end)
  ) returning * into e;
  return e;
end;
$f$;

create or replace function public.generate_accounting_csv(h uuid,d1 date,d2 date,request_id_value text)
returns jsonb language plpgsql security definer set search_path=''
as $f$
declare
  actor uuid;
  request_key text;
  e public.accounting_exports%rowtype;
  existed boolean;
begin
  if not private.user_has_any_permission(h,array['invoices.manage','payments.manage','checkout.manage']::text[]) then
    raise exception 'Accounting export access denied.';
  end if;
  actor:=private.day11_require_current_actor();
  request_key:=nullif(trim(request_id_value),'');
  if request_key is null or length(request_key)<8 then raise exception 'Request ID of at least eight characters required.'; end if;
  existed:=exists(select 1 from public.accounting_exports where hotel_id=h and idempotency_key=request_key);
  e:=private.day12_create_accounting_export(h,null,d1,d2,request_key,actor);
  return jsonb_build_object('ok',true,'idempotent',existed,'export',to_jsonb(e));
end;
$f$;

create or replace function private.day12_guard_closed_night_audit()
returns trigger language plpgsql security definer set search_path=''
as $f$
begin
  if tg_op='DELETE' then raise exception 'Closed night audits are immutable and cannot be deleted.'; end if;
  raise exception 'Closed night audits are immutable.';
end;
$f$;
create trigger night_audits_day12_immutable before update or delete on public.night_audits
for each row execute function private.day12_guard_closed_night_audit();

create or replace function public.close_night_audit(
  h uuid,business_date_value date,acknowledge_exceptions boolean,notes_value text,request_id_value text
)
returns jsonb language plpgsql security definer set search_path=''
as $f$
declare
  actor uuid;
  request_key text;
  existing public.night_audits%rowtype;
  audit_row public.night_audits%rowtype;
  export_row public.accounting_exports%rowtype;
  preview jsonb;
  financial jsonb;
  snap jsonb;
  hash_value text;
  b integer;
  w integer;
  er record;
begin
  if not private.user_has_any_permission(h,array['invoices.manage','payments.manage','checkout.manage']::text[]) then
    raise exception 'Night-audit close access denied.';
  end if;
  actor:=private.day11_require_current_actor();
  request_key:=nullif(trim(request_id_value),'');
  if request_key is null or length(request_key)<8 then raise exception 'Request ID of at least eight characters required.'; end if;
  perform pg_advisory_xact_lock(hashtextextended('stayqr:night-audit:'||h::text||':'||business_date_value::text,0));
  select * into existing from public.night_audits where hotel_id=h and idempotency_key=request_key;
  if existing.id is not null then
    return jsonb_build_object('ok',true,'idempotent',true,'night_audit',to_jsonb(existing),'snapshot',existing.snapshot_json);
  end if;
  if exists(select 1 from public.night_audits where hotel_id=h and business_date=business_date_value and status='closed') then
    raise exception 'Business date % is already closed.',business_date_value;
  end if;
  preview:=private.day12_build_day_close_preview(h,business_date_value);
  b:=(preview->>'blocker_count')::integer;
  w:=(preview->>'warning_count')::integer;
  if b>0 and not coalesce(acknowledge_exceptions,false) then
    raise exception 'Day close has % blocker(s). Explicit acknowledgement is required.',b;
  end if;
  financial:=preview->'financial_summary';
  snap:=preview||jsonb_build_object(
    'closed_at',now(),'closed_by',actor,'acknowledged_exceptions',coalesce(acknowledge_exceptions,false),
    'close_notes',nullif(trim(notes_value),''),'request_id',request_key
  );
  hash_value:=private.day12_hash_snapshot(snap);
  insert into public.night_audits(
    hotel_id,business_date,audit_number,status,closed_with_exceptions,started_at,closed_at,closed_by,close_notes,
    blocker_count,warning_count,exception_count,charges_amount,discounts_amount,taxes_amount,collections_amount,
    refunds_amount,credits_amount,open_balance_amount,idempotency_key,snapshot_json,snapshot_hash,metadata
  ) values (
    h,business_date_value,'NA/'||to_char(business_date_value,'YYYYMMDD'),'closed',(b+w)>0,now(),now(),actor,
    nullif(trim(notes_value),''),b,w,b+w,(financial->>'charges_amount')::numeric,(financial->>'discounts_amount')::numeric,
    (financial->>'taxes_amount')::numeric,(financial->>'collections_amount')::numeric,(financial->>'refunds_amount')::numeric,
    (financial->>'credits_amount')::numeric,(financial->>'open_balance_amount')::numeric,request_key,snap,hash_value,
    jsonb_build_object('acknowledged_exceptions',coalesce(acknowledge_exceptions,false),'day',12)
  ) returning * into audit_row;

  for er in select value from jsonb_array_elements(preview->'exceptions')
  loop
    insert into public.night_audit_exceptions(
      hotel_id,night_audit_id,exception_type,severity,entity_type,entity_id,amount,message,status,acknowledged,
      resolution_notes,source_snapshot
    ) values (
      h,audit_row.id,er.value->>'exception_type',er.value->>'severity',er.value->>'entity_type',
      nullif(er.value->>'entity_id','')::uuid,nullif(er.value->>'amount','')::numeric,er.value->>'message',
      case when coalesce(acknowledge_exceptions,false) then 'waived' else 'open' end,
      coalesce(acknowledge_exceptions,false),
      case when coalesce(acknowledge_exceptions,false) then nullif(trim(notes_value),'') else null end,
      coalesce(er.value->'source_snapshot','{}'::jsonb)
    );
  end loop;

  export_row:=private.day12_create_accounting_export(
    h,audit_row.id,business_date_value,business_date_value,'night-audit-export:'||audit_row.id::text,actor
  );
  return jsonb_build_object(
    'ok',true,'idempotent',false,'night_audit',to_jsonb(audit_row),'snapshot',snap,'accounting_export',to_jsonb(export_row)
  );
end;
$f$;

create or replace function public.get_night_audit_snapshot(h uuid,audit_id_value uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $f$
declare
  a public.night_audits%rowtype;
begin
  if not private.user_has_any_permission(h,array['payments.view','payments.manage','invoices.view','invoices.manage','checkout.manage']::text[]) then
    raise exception 'Night-audit snapshot access denied.';
  end if;
  select * into a from public.night_audits where hotel_id=h and id=audit_id_value;
  if not found then raise exception 'Night audit not found.'; end if;
  return jsonb_build_object(
    'night_audit',to_jsonb(a),'snapshot',a.snapshot_json,
    'hash_valid',a.snapshot_hash=private.day12_hash_snapshot(a.snapshot_json),
    'exceptions',coalesce((select jsonb_agg(to_jsonb(e) order by e.severity,e.exception_type,e.id)
                           from public.night_audit_exceptions e
                           where e.hotel_id=h and e.night_audit_id=audit_id_value),'[]'::jsonb),
    'exports',coalesce((select jsonb_agg(to_jsonb(x) order by x.generated_at,x.id)
                        from public.accounting_exports x
                        where x.hotel_id=h and x.night_audit_id=audit_id_value),'[]'::jsonb)
  );
end;
$f$;

do $backfill$
declare r record;
begin
  for r in select id from public.folio_collections where status='posted' order by hotel_id,collected_at,id
  loop
    perform private.day12_issue_receipt_for_collection(r.id);
  end loop;
end;
$backfill$;

revoke all on public.receipt_number_sequences,public.cashier_shifts,public.receipts,
  public.cashier_shift_entries,public.night_audits,public.night_audit_exceptions,
  public.accounting_exports from public,anon,authenticated;
grant select on public.receipt_number_sequences,public.cashier_shifts,public.receipts,
  public.cashier_shift_entries,public.night_audits,public.night_audit_exceptions,
  public.accounting_exports to authenticated;
grant all on public.receipt_number_sequences,public.cashier_shifts,public.receipts,
  public.cashier_shift_entries,public.night_audits,public.night_audit_exceptions,
  public.accounting_exports to service_role;

revoke all on function private.day12_hash_text(text) from public,anon,authenticated;
revoke all on function private.day12_csv_escape(text) from public,anon,authenticated;
revoke all on function private.day12_current_open_cashier_shift(uuid,uuid) from public,anon,authenticated;
revoke all on function private.day12_next_receipt_number(uuid,timestamptz) from public,anon,authenticated;
revoke all on function private.day12_issue_receipt_for_collection(uuid) from public,anon,authenticated;
revoke all on function private.day12_build_cashier_shift_snapshot(uuid,uuid) from public,anon,authenticated;
revoke all on function private.day12_build_day_close_preview(uuid,date) from public,anon,authenticated;
revoke all on function private.day12_build_accounting_csv(uuid,date,date) from public,anon,authenticated;
revoke all on function private.day12_create_accounting_export(uuid,uuid,date,date,text,uuid) from public,anon,authenticated;
grant execute on function private.day12_hash_text(text) to service_role;
grant execute on function private.day12_csv_escape(text) to service_role;
grant execute on function private.day12_current_open_cashier_shift(uuid,uuid) to service_role;
grant execute on function private.day12_next_receipt_number(uuid,timestamptz) to service_role;
grant execute on function private.day12_issue_receipt_for_collection(uuid) to service_role;
grant execute on function private.day12_build_cashier_shift_snapshot(uuid,uuid) to service_role;
grant execute on function private.day12_build_day_close_preview(uuid,date) to service_role;
grant execute on function private.day12_build_accounting_csv(uuid,date,date) to service_role;
grant execute on function private.day12_create_accounting_export(uuid,uuid,date,date,text,uuid) to service_role;

revoke all on function public.open_cashier_shift(uuid,numeric,text) from public,anon;
revoke all on function public.close_cashier_shift(uuid,uuid,numeric,text,text) from public,anon;
revoke all on function public.get_cashier_shift_report(uuid,uuid) from public,anon;
revoke all on function public.preview_day_close(uuid,date) from public,anon;
revoke all on function public.generate_accounting_csv(uuid,date,date,text) from public,anon;
revoke all on function public.close_night_audit(uuid,date,boolean,text,text) from public,anon;
revoke all on function public.get_night_audit_snapshot(uuid,uuid) from public,anon;
grant execute on function public.open_cashier_shift(uuid,numeric,text) to authenticated,service_role;
grant execute on function public.close_cashier_shift(uuid,uuid,numeric,text,text) to authenticated,service_role;
grant execute on function public.get_cashier_shift_report(uuid,uuid) to authenticated,service_role;
grant execute on function public.preview_day_close(uuid,date) to authenticated,service_role;
grant execute on function public.generate_accounting_csv(uuid,date,date,text) to authenticated,service_role;
grant execute on function public.close_night_audit(uuid,date,boolean,text,text) to authenticated,service_role;
grant execute on function public.get_night_audit_snapshot(uuid,uuid) to authenticated,service_role;

comment on table public.receipts is 'Immutable one-per-collection receipt evidence.';
comment on table public.cashier_shifts is 'Cashier opening/closing declaration and method-wise evidence.';
comment on table public.night_audits is 'Immutable business-date close with explicit unresolved exception evidence.';
comment on table public.accounting_exports is 'Checksum-protected accounting CSV.';
commit;
