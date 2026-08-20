-- StayQR Post-Launch Batch B
-- Migration 090: zero-value checkout / folio compatibility guard

begin;
set local lock_timeout = '10s';
set local statement_timeout = '180s';
select pg_advisory_xact_lock(hashtext('stayqr:202608200090:zero-folio-collection-guard'));

do $repair$
declare
  v_def text;
  v_old text :=
    '  if' || E'\n' ||
    '    lower(coalesce(payment_row.payment_status, ''pending'')) = ''paid''' || E'\n' ||
    '    and actual_collection_count = 0' || E'\n' ||
    '  then';
  v_new text :=
    '  if' || E'\n' ||
    '    -- POSTLAUNCH_BATCH2_ZERO_PAYMENT_FOLIO_GUARD_REV1' || E'\n' ||
    '    lower(coalesce(payment_row.payment_status, ''pending'')) = ''paid''' || E'\n' ||
    '    and coalesce(payment_row.amount, 0) > 0' || E'\n' ||
    '    and actual_collection_count = 0' || E'\n' ||
    '  then';
begin
  if to_regprocedure('private.day11_sync_payment(uuid)') is null then
    raise exception 'Migration 090 stopped: private.day11_sync_payment(uuid) is missing.';
  end if;

  select pg_get_functiondef('private.day11_sync_payment(uuid)'::regprocedure) into v_def;

  if position('POSTLAUNCH_BATCH2_ZERO_PAYMENT_FOLIO_GUARD_REV1' in v_def) > 0 then
    return;
  end if;

  if position(v_old in v_def) = 0 then
    raise exception 'Migration 090 stopped: expected Day 11 paid-fallback block was not found.';
  end if;

  v_def := replace(v_def, v_old, v_new);
  execute v_def;
end;
$repair$;

comment on function private.day11_sync_payment(uuid) is
'Synchronizes one legacy payments charge into an authoritative folio. Post-launch Batch B Migration 090 prevents zero-value paid payment rows from manufacturing invalid folio collections.';

do $verify$
declare v_def text;
begin
  select pg_get_functiondef('private.day11_sync_payment(uuid)'::regprocedure) into v_def;
  if position('POSTLAUNCH_BATCH2_ZERO_PAYMENT_FOLIO_GUARD_REV1' in v_def) = 0 then
    raise exception 'Migration 090 verification failed: zero-payment guard marker missing.';
  end if;
  if position('and coalesce(payment_row.amount, 0) > 0' in v_def) = 0 then
    raise exception 'Migration 090 verification failed: positive-amount guard missing.';
  end if;
end;
$verify$;

commit;
