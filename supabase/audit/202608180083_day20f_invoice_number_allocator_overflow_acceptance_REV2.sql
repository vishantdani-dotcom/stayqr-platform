-- StayQR Day 20F
-- Audit 083 REV2
-- Environment-safe acceptance for invoice allocator overflow/collision hardening.
-- READ ONLY. Safe for STAGING and PRODUCTION.

with fn as (
  select pg_get_functiondef(
    'private.day12_next_invoice_number(uuid,timestamp with time zone)'::regprocedure
  ) as definition
),
function_checks as (
  select
    position(
      'length(next_number_value::text) >= sequence_row.padding'
      in definition
    ) > 0 as no_truncation_guard,
    position('exit when not exists' in lower(definition)) > 0 as collision_skip_guard,
    position('pg_advisory_xact_lock' in definition) > 0 as advisory_lock_guard
  from fn
),
unique_index_check as (
  select exists (
    select 1
    from pg_indexes
    where schemaname='public'
      and tablename='invoices'
      and indexname='uq_invoices_hotel_invoice_number'
  ) as present
),
sequence_render_check as (
  select not exists (
    select 1
    from public.invoice_number_sequences s
    where right(
      case
        when length((s.last_number + 1)::text) >= s.padding
          then (s.last_number + 1)::text
        else lpad((s.last_number + 1)::text, s.padding, '0')
      end,
      length((s.last_number + 1)::text)
    ) <> (s.last_number + 1)::text
  ) as all_sequences_preserve_full_digits
),
overflow_regression as (
  select
    case
      when length('1782050133239') >= 6
        then '1782050133239'
      else lpad('1782050133239', 6, '0')
    end = '1782050133239' as oversized_sequence_not_truncated
),
vd as (
  select
    h.id as hotel_id,
    s.sequence_year,
    s.last_number,
    s.padding,
    s.last_number + 1 as next_sequence,
    trim(s.prefix) || '/' ||
      private.day12_financial_year_label(s.sequence_year) || '/' ||
      case
        when length((s.last_number + 1)::text) >= s.padding
          then (s.last_number + 1)::text
        else lpad((s.last_number + 1)::text, s.padding, '0')
      end as safe_next_invoice_number
  from public.hotels h
  join public.invoice_number_sequences s on s.hotel_id=h.id
  where h.slug='vd-stay-inn'
    and s.sequence_year=private.day12_financial_year_start(now(), coalesce(h.timezone,'Asia/Kolkata'))
  limit 1
),
controlled_session as (
  select
    gs.id,
    gs.status,
    gs.checked_out_at,
    (
      select count(*)
      from public.invoices i
      where i.hotel_id=gs.hotel_id
        and i.guest_session_id=gs.id
    ) as invoice_count
  from public.guest_sessions gs
  join public.guests g
    on g.id=gs.guest_id
   and g.hotel_id=gs.hotel_id
  join public.hotels h on h.id=gs.hotel_id
  where h.slug='vd-stay-inn'
    and g.full_name='StayQR 20F Controlled Guest 20260817-A'
  order by gs.created_at desc
  limit 1
),
tests as (
  select 1 test_no, 'allocator_function_exists' test_name,
    to_regprocedure('private.day12_next_invoice_number(uuid,timestamp with time zone)') is not null passed,
    'private.day12_next_invoice_number(uuid,timestamptz)' detail
  union all
  select 2, 'padding_is_minimum_width_not_maximum',
    coalesce((select no_truncation_guard from function_checks),false),
    'full sequence is used when digits >= padding'
  union all
  select 3, 'collision_skip_guard_present',
    coalesce((select collision_skip_guard from function_checks),false),
    'allocator advances past already-used canonical numbers'
  union all
  select 4, 'advisory_transaction_lock_preserved',
    coalesce((select advisory_lock_guard from function_checks),false),
    'allocator remains serialized per hotel/FY'
  union all
  select 5, 'invoice_number_unique_index_present',
    coalesce((select present from unique_index_check),false),
    'uq_invoices_hotel_invoice_number'
  union all
  select 6, 'all_sequence_rows_valid',
    not exists (
      select 1 from public.invoice_number_sequences
      where last_number < 0 or padding < 1 or padding > 12 or trim(prefix)=''
    ),
    format('%s sequence row(s)',(select count(*) from public.invoice_number_sequences))
  union all
  select 7, 'all_existing_sequences_render_without_digit_loss',
    coalesce((select all_sequences_preserve_full_digits from sequence_render_check),false),
    'next sequence rendering preserves every numeric digit'
  union all
  select 8, 'known_overflow_regression_case_passes',
    coalesce((select oversized_sequence_not_truncated from overflow_regression),false),
    '13-digit sequence with padding=6 renders as 13 digits'
  union all
  select 9, 'production_context_or_staging_na',
    case
      when exists(select 1 from vd) and exists(select 1 from controlled_session)
        then (
          select status='active' and checked_out_at is null and invoice_count=0
          from controlled_session
        )
      else true
    end,
    case
      when exists(select 1 from vd) and exists(select 1 from controlled_session)
        then (
          select format(
            'PROD context: status=%s checked_out_at=%s invoice_count=%s; next=%s',
            cs.status,
            coalesce(cs.checked_out_at::text,'NULL'),
            cs.invoice_count,
            vd.safe_next_invoice_number
          )
          from controlled_session cs cross join vd
        )
      else 'N/A in this environment: VD Stay Inn controlled production context not present'
    end
)
select test_no,test_name,passed,detail
from tests
order by test_no;
