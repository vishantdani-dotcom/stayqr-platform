-- ============================================================================
-- StayQR v1.0
-- Corrective Migration: 202607220004_reservation_deposit_delete_sync_fix
--
-- PURPOSE
-- Make reservation deposit synchronization safe for INSERT, UPDATE and DELETE.
--
-- WHY REQUIRED
-- In a PostgreSQL DELETE trigger, NEW is not available. The original Day 3
-- trigger used COALESCE(NEW..., OLD...), which is not safe when a deposit is
-- deleted or when reservation deletion cascades to reservation_payments.
--
-- SAFETY
-- - Transactional.
-- - Does not change existing business records.
-- - Replaces only the private deposit-total helper/trigger function.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202607220004_reservation_deposit_delete_sync_fix')
);

do $$
begin
  if to_regclass('public.reservation_payments') is null
     or to_regclass('public.reservations') is null
  then
    raise exception
      'Corrective migration stopped: Day 3 Reservation tables are missing.';
  end if;
end
$$;

create or replace function private.recalculate_reservation_deposit_total(
  target_hotel_id uuid,
  target_reservation_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  collected_total numeric(12,2);
begin
  if target_hotel_id is null or target_reservation_id is null then
    return;
  end if;

  select coalesce(
    sum(payment.amount) filter (
      where payment.payment_status = 'collected'
    ),
    0
  )::numeric(12,2)
  into collected_total
  from public.reservation_payments payment
  where payment.hotel_id = target_hotel_id
    and payment.reservation_id = target_reservation_id;

  update public.reservations reservation
  set
    deposit_collected = collected_total,
    updated_by = coalesce(auth.uid(), reservation.updated_by),
    updated_at = now()
  where reservation.hotel_id = target_hotel_id
    and reservation.id = target_reservation_id;
end;
$$;

create or replace function private.sync_reservation_deposit_total()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform private.recalculate_reservation_deposit_total(
      new.hotel_id,
      new.reservation_id
    );

    return new;
  end if;

  if tg_op = 'DELETE' then
    perform private.recalculate_reservation_deposit_total(
      old.hotel_id,
      old.reservation_id
    );

    return old;
  end if;

  -- UPDATE: always refresh the new parent.
  perform private.recalculate_reservation_deposit_total(
    new.hotel_id,
    new.reservation_id
  );

  -- Also refresh the old parent if a trusted future workflow moves a payment.
  if old.hotel_id is distinct from new.hotel_id
     or old.reservation_id is distinct from new.reservation_id
  then
    perform private.recalculate_reservation_deposit_total(
      old.hotel_id,
      old.reservation_id
    );
  end if;

  return new;
end;
$$;

revoke all on function private.recalculate_reservation_deposit_total(
  uuid,
  uuid
) from public;

revoke all on function private.sync_reservation_deposit_total()
from public;

drop trigger if exists reservation_payments_sync_deposit
on public.reservation_payments;

create trigger reservation_payments_sync_deposit
after insert or update of
  hotel_id,
  reservation_id,
  amount,
  payment_status
or delete
on public.reservation_payments
for each row
execute function private.sync_reservation_deposit_total();

do $$
begin
  if to_regprocedure(
    'private.recalculate_reservation_deposit_total(uuid,uuid)'
  ) is null
  then
    raise exception
      'Corrective migration stopped: recalculation helper is missing.';
  end if;

  if not exists (
    select 1
    from information_schema.triggers
    where trigger_schema = 'public'
      and event_object_table = 'reservation_payments'
      and trigger_name = 'reservation_payments_sync_deposit'
  ) then
    raise exception
      'Corrective migration stopped: deposit trigger is missing.';
  end if;
end
$$;

commit;

-- A blank pg_advisory_xact_lock row is expected.
