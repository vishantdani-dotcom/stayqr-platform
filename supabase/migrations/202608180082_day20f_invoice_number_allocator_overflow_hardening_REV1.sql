-- StayQR Day 20F
-- Migration 082 REV1
-- Invoice-number allocator overflow/collision hardening.
--
-- Root cause found during the first controlled hotel go-live:
-- invoice_number_sequences.last_number can legitimately exceed the configured
-- display padding. PostgreSQL lpad(text, length, fill) truncates text when the
-- requested length is shorter than the input, so a 13-digit sequence with
-- padding=6 was rendered as only its first 6 digits and collided with an
-- existing invoice number.
--
-- This migration:
-- 1) treats padding as a MINIMUM display width, never a maximum;
-- 2) preserves the existing sequence value (no rewind / no invoice renumbering);
-- 3) skips any already-used canonical invoice number under the same hotel;
-- 4) keeps the existing advisory transaction lock for concurrency safety.
--
-- No existing invoice rows are modified.

create or replace function private.day12_next_invoice_number(
  target_hotel_id uuid,
  occurred_at_value timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  hotel_row public.hotels%rowtype;
  sequence_row public.invoice_number_sequences%rowtype;
  financial_year_start_value integer;
  financial_year_label_value text;
  next_number_value bigint;
  generated_number text;
  rendered_sequence text;
  collision_attempts integer := 0;
begin
  select hotel.*
  into hotel_row
  from public.hotels hotel
  where hotel.id = target_hotel_id;

  if not found then
    raise exception 'Hotel was not found.';
  end if;

  financial_year_start_value :=
    private.day12_financial_year_start(
      occurred_at_value,
      hotel_row.timezone
    );

  financial_year_label_value :=
    private.day12_financial_year_label(
      financial_year_start_value
    );

  perform pg_advisory_xact_lock(
    hashtextextended(
      'stayqr:invoice-sequence:'
      || target_hotel_id::text
      || ':'
      || financial_year_start_value::text,
      0
    )
  );

  insert into public.invoice_number_sequences (
    hotel_id,
    sequence_year,
    prefix,
    last_number,
    padding,
    reset_annually,
    updated_by
  )
  values (
    target_hotel_id,
    financial_year_start_value,
    'INV',
    0,
    6,
    true,
    private.day11_valid_auth_actor(auth.uid())
  )
  on conflict (hotel_id, sequence_year)
  do nothing;

  loop
    update public.invoice_number_sequences
    set
      last_number = last_number + 1,
      updated_at = now(),
      updated_by = private.day11_valid_auth_actor(auth.uid())
    where hotel_id = target_hotel_id
      and sequence_year = financial_year_start_value
    returning *
    into sequence_row;

    if not found then
      raise exception 'Invoice number sequence could not be allocated.';
    end if;

    next_number_value := sequence_row.last_number;

    -- Padding is a minimum width. Never truncate a sequence that has already
    -- grown beyond the configured padding.
    rendered_sequence :=
      case
        when length(next_number_value::text) >= sequence_row.padding
          then next_number_value::text
        else lpad(
          next_number_value::text,
          sequence_row.padding,
          '0'
        )
      end;

    generated_number :=
      trim(sequence_row.prefix)
      || '/'
      || financial_year_label_value
      || '/'
      || rendered_sequence;

    -- A legacy/current-state drift must not surface as a unique-key failure.
    -- Under the advisory transaction lock, advance until an unused canonical
    -- invoice number is found.
    exit when not exists (
      select 1
      from public.invoices invoice
      where invoice.hotel_id = target_hotel_id
        and invoice.invoice_number = generated_number
    );

    collision_attempts := collision_attempts + 1;

    if collision_attempts >= 10000 then
      raise exception
        'Invoice number allocation exhausted collision guard for hotel % and financial year %.',
        target_hotel_id,
        financial_year_start_value;
    end if;
  end loop;

  return jsonb_build_object(
    'invoice_number', generated_number,
    'financial_year_start', financial_year_start_value,
    'financial_year_label', financial_year_label_value,
    'sequence_number', next_number_value,
    'prefix', sequence_row.prefix,
    'padding', sequence_row.padding
  );
end;
$$;

alter function private.day12_next_invoice_number(uuid, timestamptz)
  owner to postgres;

comment on function private.day12_next_invoice_number(uuid, timestamptz)
is 'Concurrency-safe Indian financial-year invoice allocator. Padding is a minimum width; oversized sequences are never truncated, and already-used canonical numbers are skipped under an advisory transaction lock.';
