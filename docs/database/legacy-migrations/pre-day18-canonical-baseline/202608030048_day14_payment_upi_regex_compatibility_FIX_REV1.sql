-- StayQR v1.0 — Day 14 Migration 048 REV1
-- Guest Guide Payment UPI Regex Compatibility Fix
-- Date: 2026-08-03
--
-- ROOT CAUSE
-- Migration 047 used a PostgreSQL bounded repetition upper limit of 256 in the
-- UPI check expression. PostgreSQL's regular-expression engine rejects that
-- repetition bound with: invalid regular expression: invalid repetition count(s).
--
-- FIX
-- Replace the constraint with conservative, valid bounds and preserve all
-- existing payment-profile data.
--
-- EXPECTED RESULT
-- 12 rows, all passed=true.

begin;

alter table public.guest_guide_payment_profiles
  drop constraint if exists guest_guide_payment_profiles_upi_check;

alter table public.guest_guide_payment_profiles
  add constraint guest_guide_payment_profiles_upi_check
  check (
    upi_id is null
    or upi_id ~ '^[A-Za-z0-9._-]{2,200}@[A-Za-z0-9.-]{2,120}$'
  );

commit;

with checks(test_name, passed, details) as (
  values
    (
      '01_payment_profiles_table_exists',
      to_regclass('public.guest_guide_payment_profiles') is not null,
      'Guest-guide payment profile table exists.'
    ),
    (
      '02_upi_column_exists',
      exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'guest_guide_payment_profiles'
          and column_name = 'upi_id'
          and data_type = 'text'
      ),
      'UPI ID column exists.'
    ),
    (
      '03_upi_constraint_exists',
      exists (
        select 1
        from pg_constraint c
        join pg_class t on t.oid = c.conrelid
        join pg_namespace n on n.oid = t.relnamespace
        where n.nspname = 'public'
          and t.relname = 'guest_guide_payment_profiles'
          and c.conname = 'guest_guide_payment_profiles_upi_check'
          and c.contype = 'c'
      ),
      'Corrected UPI check constraint exists.'
    ),
    (
      '04_constraint_no_256_bound',
      not exists (
        select 1
        from pg_constraint c
        join pg_class t on t.oid = c.conrelid
        join pg_namespace n on n.oid = t.relnamespace
        where n.nspname = 'public'
          and t.relname = 'guest_guide_payment_profiles'
          and c.conname = 'guest_guide_payment_profiles_upi_check'
          and pg_get_constraintdef(c.oid) like '%{2,256}%'
      ),
      'Invalid repetition bound 256 is absent.'
    ),
    (
      '05_common_ybl_upi_valid',
      'vishant.dani@ybl' ~ '^[A-Za-z0-9._-]{2,200}@[A-Za-z0-9.-]{2,120}$',
      'Common YBL-style UPI ID passes.'
    ),
    (
      '06_common_hdfc_upi_valid',
      '9371303050@hdfc' ~ '^[A-Za-z0-9._-]{2,200}@[A-Za-z0-9.-]{2,120}$',
      'Common HDFC-style UPI ID passes.'
    ),
    (
      '07_missing_handle_rejected',
      not ('hotelpayment' ~ '^[A-Za-z0-9._-]{2,200}@[A-Za-z0-9.-]{2,120}$'),
      'Value without a UPI handle is rejected.'
    ),
    (
      '08_spaces_rejected',
      not ('hotel name@ybl' ~ '^[A-Za-z0-9._-]{2,200}@[A-Za-z0-9.-]{2,120}$'),
      'UPI ID containing spaces is rejected.'
    ),
    (
      '09_existing_rows_valid',
      not exists (
        select 1
        from public.guest_guide_payment_profiles
        where upi_id is not null
          and not (
            upi_id ~ '^[A-Za-z0-9._-]{2,200}@[A-Za-z0-9.-]{2,120}$'
          )
      ),
      'All existing non-null UPI IDs satisfy the corrected constraint.'
    ),
    (
      '10_payment_rpc_retained',
      to_regprocedure(
        'public.upsert_guest_guide_payment_profile(uuid,jsonb)'
      ) is not null,
      'Payment profile RPC remains installed.'
    ),
    (
      '11_payment_rls_retained',
      coalesce((
        select c.relrowsecurity
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public'
          and c.relname = 'guest_guide_payment_profiles'
      ), false),
      'Payment profile RLS remains enabled.'
    ),
    (
      '12_anon_no_payment_write',
      not (
        has_table_privilege(
          'anon',
          'public.guest_guide_payment_profiles',
          'INSERT'
        )
        or has_table_privilege(
          'anon',
          'public.guest_guide_payment_profiles',
          'UPDATE'
        )
        or has_table_privilege(
          'anon',
          'public.guest_guide_payment_profiles',
          'DELETE'
        )
      ),
      'Anonymous users still cannot directly change payment profiles.'
    )
)
select test_name, passed, details
from checks
order by test_name;
