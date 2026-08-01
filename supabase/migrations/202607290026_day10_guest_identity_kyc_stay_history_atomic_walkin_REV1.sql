-- StayQR v1.0
-- Day 10 Migration 026 REV1
-- Guest identity, private KYC metadata, companion guests, stay history,
-- and authoritative atomic direct/walk-in check-in.
--
-- Based on the Day 10 baseline, supporting-contract and legacy-pairing audits:
--   * 39/39 historical direct sessions have exactly one one-to-one room-charge
--     candidate within 15 minutes (actual difference: 0-1 second).
--   * 0 rooms have multiple active sessions.
--   * 0 linked guest sessions have duplicate room charges.
--   * 8 duplicate phone groups exist and are intentionally preserved; phone is
--     indexed for repeat-guest search but is NOT made unique.
--   * 3 overdue test sessions are intentionally not auto-closed.
--
-- Transactional and safe to rerun.
-- This migration does not delete or merge any guest, stay, payment or audit row.

begin;

create schema if not exists private;

-- ---------------------------------------------------------------------------
-- 1. Canonical guest identity helpers
-- ---------------------------------------------------------------------------

create or replace function private.normalize_guest_phone(input_value text)
returns text
language sql
immutable
set search_path = ''
as $function$
  select nullif(
    regexp_replace(coalesce(input_value, ''), '[^0-9]', '', 'g'),
    ''
  );
$function$;

create or replace function private.normalize_guest_email(input_value text)
returns text
language sql
immutable
set search_path = ''
as $function$
  select nullif(lower(trim(coalesce(input_value, ''))), '');
$function$;

create or replace function private.normalize_guest_id_type(input_value text)
returns text
language sql
immutable
set search_path = ''
as $function$
  select nullif(lower(trim(coalesce(input_value, ''))), '');
$function$;

create or replace function private.normalize_guest_id_number(input_value text)
returns text
language sql
immutable
set search_path = ''
as $function$
  select nullif(
    upper(regexp_replace(coalesce(input_value, ''), '[^A-Za-z0-9]', '', 'g')),
    ''
  );
$function$;

alter table public.guests
  add column if not exists date_of_birth date,
  add column if not exists gender text,
  add column if not exists nationality text,
  add column if not exists country_of_residence text,
  add column if not exists address_line1 text,
  add column if not exists address_line2 text,
  add column if not exists city text,
  add column if not exists state_region text,
  add column if not exists postal_code text,
  add column if not exists purpose_of_visit text,
  add column if not exists is_foreign_guest boolean not null default false,
  add column if not exists normalized_phone text,
  add column if not exists normalized_email text,
  add column if not exists normalized_id_type text,
  add column if not exists normalized_id_number text,
  add column if not exists identity_verification_status text not null default 'unverified',
  add column if not exists updated_at timestamptz not null default now();

do $constraints$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.guests'::regclass
      and conname = 'guests_gender_check_day10'
  ) then
    alter table public.guests
      add constraint guests_gender_check_day10
      check (
        gender is null
        or gender in (
          'male',
          'female',
          'non_binary',
          'other',
          'prefer_not_to_say'
        )
      );
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.guests'::regclass
      and conname = 'guests_identity_verification_status_check_day10'
  ) then
    alter table public.guests
      add constraint guests_identity_verification_status_check_day10
      check (
        identity_verification_status in (
          'unverified',
          'pending',
          'verified',
          'rejected'
        )
      );
  end if;
end;
$constraints$;

create or replace function private.normalize_guest_identity_day10()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  new.full_name := trim(new.full_name);
  new.phone := nullif(trim(coalesce(new.phone, '')), '');
  new.email := nullif(trim(coalesce(new.email, '')), '');
  new.id_type := nullif(trim(coalesce(new.id_type, '')), '');
  new.id_number := nullif(trim(coalesce(new.id_number, '')), '');

  new.normalized_phone :=
    private.normalize_guest_phone(new.phone);
  new.normalized_email :=
    private.normalize_guest_email(new.email);
  new.normalized_id_type :=
    private.normalize_guest_id_type(new.id_type);
  new.normalized_id_number :=
    private.normalize_guest_id_number(new.id_number);
  new.updated_at := now();

  if length(new.full_name) = 0 then
    raise exception 'Guest full name is required.';
  end if;

  return new;
end;
$function$;

drop trigger if exists guests_normalize_identity_day10 on public.guests;
create trigger guests_normalize_identity_day10
before insert or update of
  full_name,
  phone,
  email,
  id_type,
  id_number
on public.guests
for each row
execute function private.normalize_guest_identity_day10();

update public.guests
set
  normalized_phone = private.normalize_guest_phone(phone),
  normalized_email = private.normalize_guest_email(email),
  normalized_id_type = private.normalize_guest_id_type(id_type),
  normalized_id_number = private.normalize_guest_id_number(id_number),
  updated_at = coalesce(updated_at, created_at, now())
where normalized_phone is distinct from private.normalize_guest_phone(phone)
   or normalized_email is distinct from private.normalize_guest_email(email)
   or normalized_id_type is distinct from private.normalize_guest_id_type(id_type)
   or normalized_id_number is distinct from private.normalize_guest_id_number(id_number)
   or updated_at is null;

create index if not exists idx_guests_hotel_normalized_phone_day10
  on public.guests (hotel_id, normalized_phone)
  where normalized_phone is not null;

create index if not exists idx_guests_hotel_normalized_email_day10
  on public.guests (hotel_id, normalized_email)
  where normalized_email is not null;

create index if not exists idx_guests_hotel_identity_day10
  on public.guests (
    hotel_id,
    normalized_id_type,
    normalized_id_number
  )
  where normalized_id_number is not null;

-- Document identity is suitable for strict duplicate prevention. Phone is not:
-- the legacy audit found 8 test-data phone groups and they remain preserved.
create unique index if not exists uq_guests_hotel_identity_day10
  on public.guests (
    hotel_id,
    normalized_id_type,
    normalized_id_number
  )
  where normalized_id_type is not null
    and normalized_id_number is not null;

-- ---------------------------------------------------------------------------
-- 2. Day 10 front-office and private KYC tables
-- ---------------------------------------------------------------------------

create table if not exists public.guest_documents (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  guest_id uuid not null,
  guest_session_id uuid,
  reservation_id uuid,
  document_type text not null,
  storage_bucket text not null default 'guest-documents',
  storage_path text not null,
  original_file_name text,
  mime_type text,
  file_size_bytes bigint,
  document_number_masked text,
  issue_country text,
  issued_on date,
  expires_on date,
  verification_status text not null default 'pending',
  verified_by uuid,
  verified_at timestamptz,
  rejection_reason text,
  uploaded_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,

  constraint guest_documents_hotel_fkey
    foreign key (hotel_id)
    references public.hotels(id)
    on delete cascade,

  constraint guest_documents_guest_fkey
    foreign key (hotel_id, guest_id)
    references public.guests(hotel_id, id)
    on delete cascade,

  constraint guest_documents_session_fkey
    foreign key (hotel_id, guest_session_id)
    references public.guest_sessions(hotel_id, id)
    on delete restrict,

  constraint guest_documents_reservation_fkey
    foreign key (hotel_id, reservation_id)
    references public.reservations(hotel_id, id)
    on delete restrict,

  constraint guest_documents_verified_by_fkey
    foreign key (verified_by)
    references auth.users(id)
    on delete set null,

  constraint guest_documents_uploaded_by_fkey
    foreign key (uploaded_by)
    references auth.users(id)
    on delete set null,

  constraint guest_documents_type_check
    check (
      document_type in (
        'aadhaar',
        'passport',
        'driving_licence',
        'voter_id',
        'pan',
        'visa',
        'form_c',
        'other'
      )
    ),

  constraint guest_documents_verification_check
    check (
      verification_status in (
        'pending',
        'verified',
        'rejected',
        'expired'
      )
    ),

  constraint guest_documents_storage_path_check
    check (length(trim(storage_path)) > 0),

  constraint guest_documents_size_check
    check (file_size_bytes is null or file_size_bytes >= 0),

  constraint guest_documents_expiry_check
    check (
      issued_on is null
      or expires_on is null
      or expires_on >= issued_on
    )
);

create unique index if not exists uq_guest_documents_active_path
  on public.guest_documents (hotel_id, storage_bucket, storage_path)
  where deleted_at is null;

create index if not exists idx_guest_documents_guest
  on public.guest_documents (hotel_id, guest_id, created_at desc);

create index if not exists idx_guest_documents_session
  on public.guest_documents (hotel_id, guest_session_id)
  where guest_session_id is not null;

create table if not exists public.guest_notes (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  guest_id uuid not null,
  guest_session_id uuid,
  note_type text not null default 'general',
  note text not null,
  is_private boolean not null default true,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint guest_notes_hotel_fkey
    foreign key (hotel_id)
    references public.hotels(id)
    on delete cascade,

  constraint guest_notes_guest_fkey
    foreign key (hotel_id, guest_id)
    references public.guests(hotel_id, id)
    on delete cascade,

  constraint guest_notes_session_fkey
    foreign key (hotel_id, guest_session_id)
    references public.guest_sessions(hotel_id, id)
    on delete cascade,

  constraint guest_notes_created_by_fkey
    foreign key (created_by)
    references auth.users(id)
    on delete set null,

  constraint guest_notes_type_check
    check (
      note_type in (
        'general',
        'preference',
        'warning',
        'service',
        'recovery',
        'kyc'
      )
    ),

  constraint guest_notes_note_check
    check (length(trim(note)) > 0)
);

create index if not exists idx_guest_notes_guest
  on public.guest_notes (hotel_id, guest_id, created_at desc);

create table if not exists public.guest_preferences (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  guest_id uuid not null,
  preference_key text not null,
  preference_value jsonb not null default '{}'::jsonb,
  source text not null default 'manual',
  is_active boolean not null default true,
  created_by uuid,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint guest_preferences_hotel_fkey
    foreign key (hotel_id)
    references public.hotels(id)
    on delete cascade,

  constraint guest_preferences_guest_fkey
    foreign key (hotel_id, guest_id)
    references public.guests(hotel_id, id)
    on delete cascade,

  constraint guest_preferences_created_by_fkey
    foreign key (created_by)
    references auth.users(id)
    on delete set null,

  constraint guest_preferences_updated_by_fkey
    foreign key (updated_by)
    references auth.users(id)
    on delete set null,

  constraint guest_preferences_key_check
    check (length(trim(preference_key)) > 0),

  constraint guest_preferences_source_check
    check (source in ('manual', 'stay', 'imported'))
);

create unique index if not exists uq_guest_preferences_active_key
  on public.guest_preferences (hotel_id, guest_id, lower(preference_key))
  where is_active;

create table if not exists public.guest_companions (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  guest_session_id uuid not null,
  primary_guest_id uuid not null,
  guest_id uuid not null,
  relationship text,
  guest_category text not null default 'adult',
  form_c_required boolean not null default false,
  created_by uuid,
  created_at timestamptz not null default now(),

  constraint guest_companions_hotel_fkey
    foreign key (hotel_id)
    references public.hotels(id)
    on delete cascade,

  constraint guest_companions_session_fkey
    foreign key (hotel_id, guest_session_id)
    references public.guest_sessions(hotel_id, id)
    on delete cascade,

  constraint guest_companions_primary_guest_fkey
    foreign key (hotel_id, primary_guest_id)
    references public.guests(hotel_id, id)
    on delete restrict,

  constraint guest_companions_guest_fkey
    foreign key (hotel_id, guest_id)
    references public.guests(hotel_id, id)
    on delete restrict,

  constraint guest_companions_created_by_fkey
    foreign key (created_by)
    references auth.users(id)
    on delete set null,

  constraint guest_companions_category_check
    check (guest_category in ('adult', 'child', 'infant')),

  constraint guest_companions_not_primary_check
    check (guest_id <> primary_guest_id)
);

create unique index if not exists uq_guest_companions_session_guest
  on public.guest_companions (hotel_id, guest_session_id, guest_id);

create index if not exists idx_guest_companions_guest
  on public.guest_companions (hotel_id, guest_id);

create table if not exists public.guest_stay_details (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  guest_session_id uuid not null,
  purpose_of_visit text,
  arrival_from text,
  next_destination text,
  arrival_mode text,
  arrival_transport_number text,
  departure_mode text,
  departure_transport_number text,
  passport_number text,
  passport_issue_country text,
  passport_issued_on date,
  passport_expires_on date,
  visa_number text,
  visa_type text,
  visa_issue_place text,
  visa_issued_on date,
  visa_expires_on date,
  date_of_arrival_in_india date,
  intended_duration_in_india_days integer,
  form_c_status text not null default 'not_required',
  form_c_reference text,
  form_c_submitted_at timestamptz,
  form_c_submitted_by uuid,
  early_checkin boolean not null default false,
  late_checkout boolean not null default false,
  special_notes text,
  created_by uuid,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint guest_stay_details_hotel_fkey
    foreign key (hotel_id)
    references public.hotels(id)
    on delete cascade,

  constraint guest_stay_details_session_fkey
    foreign key (hotel_id, guest_session_id)
    references public.guest_sessions(hotel_id, id)
    on delete cascade,

  constraint guest_stay_details_form_c_by_fkey
    foreign key (form_c_submitted_by)
    references auth.users(id)
    on delete set null,

  constraint guest_stay_details_created_by_fkey
    foreign key (created_by)
    references auth.users(id)
    on delete set null,

  constraint guest_stay_details_updated_by_fkey
    foreign key (updated_by)
    references auth.users(id)
    on delete set null,

  constraint guest_stay_details_form_c_status_check
    check (
      form_c_status in (
        'not_required',
        'pending',
        'ready',
        'submitted',
        'acknowledged',
        'rejected'
      )
    ),

  constraint guest_stay_details_duration_check
    check (
      intended_duration_in_india_days is null
      or intended_duration_in_india_days >= 0
    ),

  constraint guest_stay_details_passport_dates_check
    check (
      passport_issued_on is null
      or passport_expires_on is null
      or passport_expires_on >= passport_issued_on
    ),

  constraint guest_stay_details_visa_dates_check
    check (
      visa_issued_on is null
      or visa_expires_on is null
      or visa_expires_on >= visa_issued_on
    )
);

create unique index if not exists uq_guest_stay_details_session
  on public.guest_stay_details (hotel_id, guest_session_id);

create table if not exists public.stay_room_history (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  guest_session_id uuid not null,
  room_id uuid not null,
  segment_number integer not null,
  movement_type text not null default 'check_in',
  segment_start timestamptz not null,
  segment_end timestamptz,
  move_reason text,
  rate_amount numeric(12,2),
  created_by uuid,
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,

  constraint stay_room_history_hotel_fkey
    foreign key (hotel_id)
    references public.hotels(id)
    on delete cascade,

  constraint stay_room_history_session_fkey
    foreign key (hotel_id, guest_session_id)
    references public.guest_sessions(hotel_id, id)
    on delete cascade,

  constraint stay_room_history_room_fkey
    foreign key (hotel_id, room_id)
    references public.rooms(hotel_id, id)
    on delete restrict,

  constraint stay_room_history_created_by_fkey
    foreign key (created_by)
    references auth.users(id)
    on delete set null,

  constraint stay_room_history_segment_check
    check (segment_number > 0),

  constraint stay_room_history_movement_check
    check (
      movement_type in (
        'check_in',
        'move',
        'upgrade',
        'downgrade'
      )
    ),

  constraint stay_room_history_dates_check
    check (
      segment_end is null
      or segment_end > segment_start
    ),

  constraint stay_room_history_rate_check
    check (rate_amount is null or rate_amount >= 0)
);

create unique index if not exists uq_stay_room_history_segment
  on public.stay_room_history (
    hotel_id,
    guest_session_id,
    segment_number
  );

create unique index if not exists uq_stay_room_history_open_segment
  on public.stay_room_history (hotel_id, guest_session_id)
  where segment_end is null;

create index if not exists idx_stay_room_history_room_time
  on public.stay_room_history (hotel_id, room_id, segment_start desc);

create table if not exists public.walkin_checkin_events (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  guest_session_id uuid not null,
  guest_id uuid not null,
  room_id uuid not null,
  payment_id uuid not null,
  idempotency_key text not null,
  checked_in_by uuid,
  checked_in_at timestamptz not null default now(),
  request_snapshot jsonb not null default '{}'::jsonb,
  result_snapshot jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,

  constraint walkin_checkin_events_hotel_fkey
    foreign key (hotel_id)
    references public.hotels(id)
    on delete cascade,

  constraint walkin_checkin_events_session_fkey
    foreign key (hotel_id, guest_session_id)
    references public.guest_sessions(hotel_id, id)
    on delete restrict,

  constraint walkin_checkin_events_guest_fkey
    foreign key (hotel_id, guest_id)
    references public.guests(hotel_id, id)
    on delete restrict,

  constraint walkin_checkin_events_room_fkey
    foreign key (hotel_id, room_id)
    references public.rooms(hotel_id, id)
    on delete restrict,

  constraint walkin_checkin_events_payment_fkey
    foreign key (hotel_id, payment_id)
    references public.payments(hotel_id, id)
    on delete restrict,

  constraint walkin_checkin_events_checked_in_by_fkey
    foreign key (checked_in_by)
    references auth.users(id)
    on delete set null,

  constraint walkin_checkin_events_idempotency_check
    check (length(trim(idempotency_key)) >= 8)
);

create unique index if not exists uq_walkin_checkin_events_idempotency
  on public.walkin_checkin_events (hotel_id, idempotency_key);

create unique index if not exists uq_walkin_checkin_events_session
  on public.walkin_checkin_events (hotel_id, guest_session_id);

create unique index if not exists uq_walkin_checkin_events_payment
  on public.walkin_checkin_events (hotel_id, payment_id);

-- ---------------------------------------------------------------------------
-- 3. Updated-at trigger shared by Day 10 mutable tables
-- ---------------------------------------------------------------------------

create or replace function private.touch_updated_at_day10()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  new.updated_at := now();
  return new;
end;
$function$;

drop trigger if exists guest_documents_touch_updated_at_day10
  on public.guest_documents;
create trigger guest_documents_touch_updated_at_day10
before update on public.guest_documents
for each row
execute function private.touch_updated_at_day10();

drop trigger if exists guest_notes_touch_updated_at_day10
  on public.guest_notes;
create trigger guest_notes_touch_updated_at_day10
before update on public.guest_notes
for each row
execute function private.touch_updated_at_day10();

drop trigger if exists guest_preferences_touch_updated_at_day10
  on public.guest_preferences;
create trigger guest_preferences_touch_updated_at_day10
before update on public.guest_preferences
for each row
execute function private.touch_updated_at_day10();

drop trigger if exists guest_stay_details_touch_updated_at_day10
  on public.guest_stay_details;
create trigger guest_stay_details_touch_updated_at_day10
before update on public.guest_stay_details
for each row
execute function private.touch_updated_at_day10();

-- ---------------------------------------------------------------------------
-- 4. RLS and grants
-- ---------------------------------------------------------------------------

alter table public.guest_documents enable row level security;
alter table public.guest_notes enable row level security;
alter table public.guest_preferences enable row level security;
alter table public.guest_companions enable row level security;
alter table public.guest_stay_details enable row level security;
alter table public.stay_room_history enable row level security;
alter table public.walkin_checkin_events enable row level security;

revoke all on public.guest_documents from anon;
revoke all on public.guest_notes from anon;
revoke all on public.guest_preferences from anon;
revoke all on public.guest_companions from anon;
revoke all on public.guest_stay_details from anon;
revoke all on public.stay_room_history from anon;
revoke all on public.walkin_checkin_events from anon;

grant select, insert, update, delete
  on public.guest_documents,
     public.guest_notes,
     public.guest_preferences,
     public.guest_companions,
     public.guest_stay_details
  to authenticated;

grant select
  on public.stay_room_history,
     public.walkin_checkin_events
  to authenticated;

grant all
  on public.guest_documents,
     public.guest_notes,
     public.guest_preferences,
     public.guest_companions,
     public.guest_stay_details,
     public.stay_room_history,
     public.walkin_checkin_events
  to service_role;

drop policy if exists stayqr_day10_guest_documents_select
  on public.guest_documents;
create policy stayqr_day10_guest_documents_select
on public.guest_documents
for select
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array[
      'guests.view',
      'guests.manage',
      'checkin.manage',
      'checkout.manage'
    ]
  )
);

drop policy if exists stayqr_day10_guest_documents_insert
  on public.guest_documents;
create policy stayqr_day10_guest_documents_insert
on public.guest_documents
for insert
to authenticated
with check (
  private.user_has_any_permission(
    hotel_id,
    array['guests.manage', 'checkin.manage']
  )
);

drop policy if exists stayqr_day10_guest_documents_update
  on public.guest_documents;
create policy stayqr_day10_guest_documents_update
on public.guest_documents
for update
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array['guests.manage', 'checkin.manage']
  )
)
with check (
  private.user_has_any_permission(
    hotel_id,
    array['guests.manage', 'checkin.manage']
  )
);

drop policy if exists stayqr_day10_guest_documents_delete
  on public.guest_documents;
create policy stayqr_day10_guest_documents_delete
on public.guest_documents
for delete
to authenticated
using (
  private.user_has_permission(hotel_id, 'guests.manage')
);

drop policy if exists stayqr_day10_guest_notes_select
  on public.guest_notes;
create policy stayqr_day10_guest_notes_select
on public.guest_notes
for select
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array[
      'guests.view',
      'guests.manage',
      'checkin.manage',
      'checkout.manage'
    ]
  )
);

drop policy if exists stayqr_day10_guest_notes_write
  on public.guest_notes;
create policy stayqr_day10_guest_notes_write
on public.guest_notes
for all
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array['guests.manage', 'checkin.manage', 'checkout.manage']
  )
)
with check (
  private.user_has_any_permission(
    hotel_id,
    array['guests.manage', 'checkin.manage', 'checkout.manage']
  )
);

drop policy if exists stayqr_day10_guest_preferences_select
  on public.guest_preferences;
create policy stayqr_day10_guest_preferences_select
on public.guest_preferences
for select
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array[
      'guests.view',
      'guests.manage',
      'checkin.manage',
      'checkout.manage'
    ]
  )
);

drop policy if exists stayqr_day10_guest_preferences_write
  on public.guest_preferences;
create policy stayqr_day10_guest_preferences_write
on public.guest_preferences
for all
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array['guests.manage', 'checkin.manage', 'checkout.manage']
  )
)
with check (
  private.user_has_any_permission(
    hotel_id,
    array['guests.manage', 'checkin.manage', 'checkout.manage']
  )
);

drop policy if exists stayqr_day10_guest_companions_select
  on public.guest_companions;
create policy stayqr_day10_guest_companions_select
on public.guest_companions
for select
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array[
      'guests.view',
      'guests.manage',
      'checkin.manage',
      'checkout.manage'
    ]
  )
);

drop policy if exists stayqr_day10_guest_companions_write
  on public.guest_companions;
create policy stayqr_day10_guest_companions_write
on public.guest_companions
for all
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array['guests.manage', 'checkin.manage', 'checkout.manage']
  )
)
with check (
  private.user_has_any_permission(
    hotel_id,
    array['guests.manage', 'checkin.manage', 'checkout.manage']
  )
);

drop policy if exists stayqr_day10_guest_stay_details_select
  on public.guest_stay_details;
create policy stayqr_day10_guest_stay_details_select
on public.guest_stay_details
for select
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array[
      'guests.view',
      'guests.manage',
      'checkin.manage',
      'checkout.manage'
    ]
  )
);

drop policy if exists stayqr_day10_guest_stay_details_write
  on public.guest_stay_details;
create policy stayqr_day10_guest_stay_details_write
on public.guest_stay_details
for all
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array['guests.manage', 'checkin.manage', 'checkout.manage']
  )
)
with check (
  private.user_has_any_permission(
    hotel_id,
    array['guests.manage', 'checkin.manage', 'checkout.manage']
  )
);

drop policy if exists stayqr_day10_stay_room_history_select
  on public.stay_room_history;
create policy stayqr_day10_stay_room_history_select
on public.stay_room_history
for select
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array[
      'guests.view',
      'guests.manage',
      'checkin.manage',
      'checkout.manage'
    ]
  )
);

drop policy if exists stayqr_day10_walkin_events_select
  on public.walkin_checkin_events;
create policy stayqr_day10_walkin_events_select
on public.walkin_checkin_events
for select
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array[
      'guests.view',
      'guests.manage',
      'checkin.manage',
      'checkout.manage'
    ]
  )
);

-- ---------------------------------------------------------------------------
-- 5. Safe legacy one-to-one payment linkage and immutable history backfill
-- ---------------------------------------------------------------------------

with candidate_edges as (
  select
    gs.id as guest_session_id,
    p.id as payment_id,
    count(*) over (partition by gs.id) as session_candidate_count,
    count(*) over (partition by p.id) as payment_candidate_count,
    abs(
      extract(
        epoch from (
          p.created_at - coalesce(gs.created_at, gs.checkin_time)
        )
      )
    ) as difference_seconds
  from public.guest_sessions gs
  join public.payments p
    on p.hotel_id = gs.hotel_id
   and p.guest_id is not distinct from gs.guest_id
   and p.room_id is not distinct from gs.room_id
   and p.payment_type = 'room_charge'
   and p.guest_session_id is null
   and p.reservation_id is null
   and p.reservation_room_id is null
   and p.created_at >= coalesce(gs.created_at, gs.checkin_time)
   and p.created_at <=
     coalesce(gs.created_at, gs.checkin_time) + interval '15 minutes'
  where gs.reservation_id is null
),
safe_pairs as (
  select guest_session_id, payment_id
  from candidate_edges
  where session_candidate_count = 1
    and payment_candidate_count = 1
    and difference_seconds <= 900
)
update public.payments p
set guest_session_id = pair.guest_session_id
from safe_pairs pair
where p.id = pair.payment_id
  and p.guest_session_id is null;

do $health$
begin
  if exists (
    select 1
    from public.guest_sessions
    where status = 'active'
      and room_id is not null
    group by hotel_id, room_id
    having count(*) > 1
  ) then
    raise exception
      'Cannot install Day 10 active-room protection: multiple active stays exist for one room.';
  end if;

  if exists (
    select 1
    from public.payments
    where payment_type = 'room_charge'
      and guest_session_id is not null
    group by hotel_id, guest_session_id
    having count(*) > 1
  ) then
    raise exception
      'Cannot install Day 10 room-charge protection: duplicate linked room charges exist.';
  end if;
end;
$health$;

create unique index if not exists uq_guest_sessions_active_room_day10
  on public.guest_sessions (hotel_id, room_id)
  where status = 'active'
    and room_id is not null;

create unique index if not exists uq_payments_guest_session_room_charge_day10
  on public.payments (hotel_id, guest_session_id)
  where guest_session_id is not null
    and payment_type = 'room_charge';

insert into public.stay_room_history (
  hotel_id,
  guest_session_id,
  room_id,
  segment_number,
  movement_type,
  segment_start,
  segment_end,
  move_reason,
  rate_amount,
  created_by,
  metadata
)
select
  gs.hotel_id,
  gs.id,
  gs.room_id,
  1,
  'check_in',
  gs.checkin_time,
  case
    when gs.status = 'active' then null
    else greatest(
      coalesce(
        gs.checked_out_at,
        gs.expired_at,
        gs.checkout_time
      ),
      gs.checkin_time + interval '1 second'
    )
  end,
  'Legacy Day 10 history backfill',
  charge.amount,
  gs.checked_in_by,
  jsonb_build_object(
    'source', 'migration_026',
    'legacy_backfill', true,
    'reservation_id', gs.reservation_id,
    'reservation_room_id', gs.reservation_room_id
  )
from public.guest_sessions gs
left join lateral (
  select p.amount
  from public.payments p
  where p.hotel_id = gs.hotel_id
    and p.guest_session_id = gs.id
    and p.payment_type = 'room_charge'
  order by p.created_at, p.id
  limit 1
) charge on true
where gs.room_id is not null
on conflict (hotel_id, guest_session_id, segment_number)
do nothing;

insert into public.walkin_checkin_events (
  hotel_id,
  guest_session_id,
  guest_id,
  room_id,
  payment_id,
  idempotency_key,
  checked_in_by,
  checked_in_at,
  request_snapshot,
  result_snapshot,
  metadata
)
select
  gs.hotel_id,
  gs.id,
  gs.guest_id,
  gs.room_id,
  p.id,
  'legacy:' || gs.id::text,
  gs.checked_in_by,
  gs.checkin_time,
  jsonb_build_object(
    'legacy_backfill', true,
    'guest_session_id', gs.id,
    'guest_id', gs.guest_id,
    'room_id', gs.room_id,
    'checkout_time', gs.checkout_time,
    'room_charge', p.amount
  ),
  jsonb_build_object(
    'success', true,
    'legacy_backfill', true,
    'guest_session_id', gs.id,
    'guest_id', gs.guest_id,
    'room_id', gs.room_id,
    'payment_id', p.id
  ),
  jsonb_build_object(
    'source', 'migration_026',
    'payment_status', p.payment_status
  )
from public.guest_sessions gs
join public.payments p
  on p.hotel_id = gs.hotel_id
 and p.guest_session_id = gs.id
 and p.payment_type = 'room_charge'
where gs.reservation_id is null
on conflict (hotel_id, guest_session_id)
do nothing;

-- ---------------------------------------------------------------------------
-- 6. Server-owned repeat-guest resolution
-- ---------------------------------------------------------------------------

create or replace function private.resolve_or_create_guest_day10(
  target_hotel_id uuid,
  guest_payload jsonb
)
returns public.guests
language plpgsql
security definer
set search_path = ''
as $function$
declare
  guest_row public.guests%rowtype;
  guest_id_value uuid;
  normalized_phone_value text;
  normalized_email_value text;
  normalized_type_value text;
  normalized_number_value text;
  candidate_count integer := 0;
  candidate_id uuid;
  full_name_value text;
begin
  if guest_payload is null
     or jsonb_typeof(guest_payload) <> 'object'
  then
    raise exception 'Guest details must be a JSON object.';
  end if;

  if nullif(trim(guest_payload ->> 'id'), '') is not null then
    begin
      guest_id_value := (guest_payload ->> 'id')::uuid;
    exception
      when invalid_text_representation then
        raise exception 'Guest ID is invalid.';
    end;

    select g.*
    into guest_row
    from public.guests g
    where g.hotel_id = target_hotel_id
      and g.id = guest_id_value
    for update;

    if not found then
      raise exception 'Selected guest profile was not found for this hotel.';
    end if;

    return guest_row;
  end if;

  normalized_phone_value :=
    private.normalize_guest_phone(guest_payload ->> 'phone');
  normalized_email_value :=
    private.normalize_guest_email(guest_payload ->> 'email');
  normalized_type_value :=
    private.normalize_guest_id_type(guest_payload ->> 'id_type');
  normalized_number_value :=
    private.normalize_guest_id_number(guest_payload ->> 'id_number');

  if normalized_number_value is not null
     and normalized_type_value is null
  then
    raise exception 'ID type is required when an ID number is provided.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'stayqr:guest-identity:'
      || target_hotel_id::text
      || ':'
      || coalesce(
        normalized_type_value || ':' || normalized_number_value,
        normalized_email_value,
        normalized_phone_value,
        gen_random_uuid()::text
      ),
      0
    )
  );

  if normalized_number_value is not null then
    select
      count(*)::integer,
      (array_agg(g.id order by g.created_at, g.id))[1]
    into candidate_count, candidate_id
    from public.guests g
    where g.hotel_id = target_hotel_id
      and g.normalized_id_type is not distinct from normalized_type_value
      and g.normalized_id_number = normalized_number_value;

    if candidate_count > 1 then
      raise exception
        'Multiple guest profiles share this identity document. Select the intended guest explicitly.';
    end if;
  end if;

  if candidate_count = 0 and normalized_email_value is not null then
    select
      count(*)::integer,
      (array_agg(g.id order by g.created_at, g.id))[1]
    into candidate_count, candidate_id
    from public.guests g
    where g.hotel_id = target_hotel_id
      and g.normalized_email = normalized_email_value;

    if candidate_count > 1 then
      raise exception
        'Multiple guest profiles share this email. Select the intended guest explicitly.';
    end if;
  end if;

  if candidate_count = 0 and normalized_phone_value is not null then
    select
      count(*)::integer,
      (array_agg(g.id order by g.created_at, g.id))[1]
    into candidate_count, candidate_id
    from public.guests g
    where g.hotel_id = target_hotel_id
      and g.normalized_phone = normalized_phone_value;

    if candidate_count > 1 then
      raise exception
        'Multiple guest profiles share this phone number. Select the intended guest explicitly.';
    end if;
  end if;

  if candidate_count = 1 then
    select g.*
    into guest_row
    from public.guests g
    where g.hotel_id = target_hotel_id
      and g.id = candidate_id
    for update;

    update public.guests g
    set
      full_name = coalesce(
        nullif(trim(guest_payload ->> 'full_name'), ''),
        g.full_name
      ),
      phone = coalesce(
        nullif(trim(guest_payload ->> 'phone'), ''),
        g.phone
      ),
      email = coalesce(
        nullif(trim(guest_payload ->> 'email'), ''),
        g.email
      ),
      id_type = coalesce(
        nullif(trim(guest_payload ->> 'id_type'), ''),
        g.id_type
      ),
      id_number = coalesce(
        nullif(trim(guest_payload ->> 'id_number'), ''),
        g.id_number
      ),
      preferred_language = coalesce(
        nullif(trim(guest_payload ->> 'preferred_language'), ''),
        g.preferred_language
      ),
      date_of_birth = coalesce(
        nullif(guest_payload ->> 'date_of_birth', '')::date,
        g.date_of_birth
      ),
      gender = coalesce(
        nullif(lower(trim(guest_payload ->> 'gender')), ''),
        g.gender
      ),
      nationality = coalesce(
        nullif(trim(guest_payload ->> 'nationality'), ''),
        g.nationality
      ),
      country_of_residence = coalesce(
        nullif(trim(guest_payload ->> 'country_of_residence'), ''),
        g.country_of_residence
      ),
      address_line1 = coalesce(
        nullif(trim(guest_payload ->> 'address_line1'), ''),
        g.address_line1
      ),
      address_line2 = coalesce(
        nullif(trim(guest_payload ->> 'address_line2'), ''),
        g.address_line2
      ),
      city = coalesce(
        nullif(trim(guest_payload ->> 'city'), ''),
        g.city
      ),
      state_region = coalesce(
        nullif(trim(guest_payload ->> 'state_region'), ''),
        g.state_region
      ),
      postal_code = coalesce(
        nullif(trim(guest_payload ->> 'postal_code'), ''),
        g.postal_code
      ),
      purpose_of_visit = coalesce(
        nullif(trim(guest_payload ->> 'purpose_of_visit'), ''),
        g.purpose_of_visit
      ),
      is_foreign_guest = coalesce(
        (guest_payload ->> 'is_foreign_guest')::boolean,
        g.is_foreign_guest
      )
    where g.hotel_id = target_hotel_id
      and g.id = candidate_id
    returning g.* into guest_row;

    return guest_row;
  end if;

  full_name_value := nullif(trim(guest_payload ->> 'full_name'), '');

  if full_name_value is null then
    raise exception 'Guest full name is required.';
  end if;

  insert into public.guests (
    hotel_id,
    full_name,
    phone,
    email,
    id_type,
    id_number,
    preferred_language,
    date_of_birth,
    gender,
    nationality,
    country_of_residence,
    address_line1,
    address_line2,
    city,
    state_region,
    postal_code,
    purpose_of_visit,
    is_foreign_guest
  )
  values (
    target_hotel_id,
    full_name_value,
    nullif(trim(guest_payload ->> 'phone'), ''),
    nullif(trim(guest_payload ->> 'email'), ''),
    nullif(trim(guest_payload ->> 'id_type'), ''),
    nullif(trim(guest_payload ->> 'id_number'), ''),
    coalesce(
      nullif(trim(guest_payload ->> 'preferred_language'), ''),
      'english'
    ),
    nullif(guest_payload ->> 'date_of_birth', '')::date,
    nullif(lower(trim(guest_payload ->> 'gender')), ''),
    nullif(trim(guest_payload ->> 'nationality'), ''),
    nullif(trim(guest_payload ->> 'country_of_residence'), ''),
    nullif(trim(guest_payload ->> 'address_line1'), ''),
    nullif(trim(guest_payload ->> 'address_line2'), ''),
    nullif(trim(guest_payload ->> 'city'), ''),
    nullif(trim(guest_payload ->> 'state_region'), ''),
    nullif(trim(guest_payload ->> 'postal_code'), ''),
    nullif(trim(guest_payload ->> 'purpose_of_visit'), ''),
    coalesce((guest_payload ->> 'is_foreign_guest')::boolean, false)
  )
  returning * into guest_row;

  return guest_row;
end;
$function$;

revoke all on function private.resolve_or_create_guest_day10(uuid, jsonb)
  from public, anon, authenticated;

grant execute on function private.resolve_or_create_guest_day10(uuid, jsonb)
  to service_role;

-- ---------------------------------------------------------------------------
-- 7. Authoritative atomic walk-in check-in
-- ---------------------------------------------------------------------------

create or replace function public.check_in_walk_in_guest(
  target_hotel_id uuid,
  payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  existing_event public.walkin_checkin_events%rowtype;
  hotel_timezone text;
  room_row public.rooms%rowtype;
  room_type_row public.room_types%rowtype;
  guest_row public.guests%rowtype;
  companion_row public.guests%rowtype;
  companion_payload jsonb;
  companions_payload jsonb;
  stay_payload jsonb;
  request_id_value text;
  room_id_value uuid;
  checkin_time_value timestamptz;
  checkout_time_value timestamptz;
  starts_on_value date;
  ends_on_value date;
  room_charge_value numeric(12,2);
  adults_value integer;
  children_value integer;
  created_session_id uuid;
  created_payment_id uuid;
  companion_count integer := 0;
  companion_adults integer := 0;
  companion_children integer := 0;
  result_value jsonb;
begin
  perform private.assert_reservation_write_access(target_hotel_id);

  if payload is null or jsonb_typeof(payload) <> 'object' then
    raise exception 'Walk-in check-in payload must be a JSON object.';
  end if;

  request_id_value := nullif(trim(payload ->> 'request_id'), '');

  if request_id_value is null or length(request_id_value) < 8 then
    raise exception 'A stable request_id of at least 8 characters is required.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'stayqr:walkin:'
      || target_hotel_id::text
      || ':'
      || request_id_value,
      0
    )
  );

  select event.*
  into existing_event
  from public.walkin_checkin_events event
  where event.hotel_id = target_hotel_id
    and event.idempotency_key = request_id_value
  limit 1;

  if existing_event.id is not null then
    return coalesce(existing_event.result_snapshot, '{}'::jsonb)
      || jsonb_build_object('idempotent', true);
  end if;

  begin
    room_id_value := (payload ->> 'room_id')::uuid;
  exception
    when invalid_text_representation then
      raise exception 'Room ID is invalid.';
  end;

  if room_id_value is null then
    raise exception 'Room is required.';
  end if;

  begin
    checkin_time_value := coalesce(
      nullif(payload ->> 'checkin_time', '')::timestamptz,
      now()
    );
    checkout_time_value :=
      nullif(payload ->> 'checkout_time', '')::timestamptz;
    room_charge_value :=
      round(coalesce((payload ->> 'room_charge')::numeric, 0), 2);
    adults_value :=
      greatest(coalesce((payload ->> 'adults')::integer, 1), 1);
    children_value :=
      greatest(coalesce((payload ->> 'children')::integer, 0), 0);
  exception
    when invalid_text_representation
      or numeric_value_out_of_range then
      raise exception 'Check-in time, checkout time, occupancy or room charge is invalid.';
  end;

  if checkout_time_value is null
     or checkout_time_value <= checkin_time_value
  then
    raise exception 'Checkout time must be after check-in time.';
  end if;

  if room_charge_value < 0 then
    raise exception 'Room charge cannot be negative.';
  end if;

  companions_payload := coalesce(payload -> 'companions', '[]'::jsonb);

  if jsonb_typeof(companions_payload) <> 'array' then
    raise exception 'Companions must be a JSON array.';
  end if;

  select
    (
      count(*) filter (
        where coalesce(
          nullif(lower(trim(item ->> 'guest_category')), ''),
          'adult'
        ) = 'adult'
      )
    )::integer,
    (
      count(*) filter (
        where coalesce(
          nullif(lower(trim(item ->> 'guest_category')), ''),
          'adult'
        ) in ('child', 'infant')
      )
    )::integer
  into companion_adults, companion_children
  from jsonb_array_elements(companions_payload) as companion(item);

  if adults_value <> companion_adults + 1
     or children_value <> companion_children
  then
    raise exception
      'Adults/children counts must match the primary guest and companion categories.';
  end if;

  select h.timezone
  into hotel_timezone
  from public.hotels h
  where h.id = target_hotel_id
    and h.status = 'active'
  for update;

  if hotel_timezone is null then
    raise exception 'Active hotel or hotel timezone was not found.';
  end if;

  starts_on_value :=
    (checkin_time_value at time zone hotel_timezone)::date;
  ends_on_value :=
    (checkout_time_value at time zone hotel_timezone)::date;

  if ends_on_value <= starts_on_value then
    ends_on_value := starts_on_value + 1;
  end if;

  select room.*
  into room_row
  from public.rooms room
  where room.hotel_id = target_hotel_id
    and room.id = room_id_value
  for update;

  if not found then
    raise exception 'Selected room was not found for this hotel.';
  end if;

  if room_row.status <> 'available' then
    raise exception 'Selected room is not currently available.';
  end if;

  select room_type.*
  into room_type_row
  from public.room_types room_type
  where room_type.hotel_id = target_hotel_id
    and room_type.id = room_row.room_type_id;

  if not found then
    raise exception 'Selected room type was not found.';
  end if;

  if adults_value > room_type_row.max_adults
     or children_value > room_type_row.max_children
     or adults_value + children_value > room_type_row.max_occupancy
  then
    raise exception 'Guest count exceeds room capacity.';
  end if;

  if exists (
    select 1
    from public.guest_sessions session
    where session.hotel_id = target_hotel_id
      and session.room_id = room_id_value
      and session.status = 'active'
  ) then
    raise exception 'Selected room already has an active guest stay.';
  end if;

  if exists (
    select 1
    from public.room_inventory_allocations allocation
    where allocation.hotel_id = target_hotel_id
      and allocation.room_id = room_id_value
      and allocation.status = 'active'
      and allocation.stay_dates
        && daterange(starts_on_value, ends_on_value, '[)')
  ) then
    raise exception
      'Selected room is reserved, blocked or occupied during the requested stay.';
  end if;

  select *
  into guest_row
  from private.resolve_or_create_guest_day10(
    target_hotel_id,
    coalesce(payload -> 'guest', '{}'::jsonb)
  );

  insert into public.guest_sessions (
    hotel_id,
    room_id,
    guest_id,
    checkin_time,
    checkout_time,
    status,
    checked_in_by
  )
  values (
    target_hotel_id,
    room_id_value,
    guest_row.id,
    checkin_time_value,
    checkout_time_value,
    'active',
    auth.uid()
  )
  returning id into created_session_id;

  insert into public.payments (
    hotel_id,
    guest_id,
    room_id,
    amount,
    payment_type,
    payment_status,
    notes,
    payment_method,
    guest_session_id
  )
  values (
    target_hotel_id,
    guest_row.id,
    room_id_value,
    room_charge_value,
    'room_charge',
    'pending',
    coalesce(
      nullif(trim(payload ->> 'notes'), ''),
      format(
        'Walk-in room charge · Room %s · %s',
        room_row.room_number,
        guest_row.full_name
      )
    ),
    'cash',
    created_session_id
  )
  returning id into created_payment_id;

  update public.rooms
  set status = 'occupied'
  where hotel_id = target_hotel_id
    and id = room_id_value
    and status = 'available';

  if not found then
    raise exception
      'Room status changed during check-in. No check-in was committed.';
  end if;

  insert into public.stay_room_history (
    hotel_id,
    guest_session_id,
    room_id,
    segment_number,
    movement_type,
    segment_start,
    rate_amount,
    created_by,
    metadata
  )
  values (
    target_hotel_id,
    created_session_id,
    room_id_value,
    1,
    'check_in',
    checkin_time_value,
    room_charge_value,
    auth.uid(),
    jsonb_build_object(
      'source', 'check_in_walk_in_guest',
      'request_id', request_id_value
    )
  );

  for companion_payload in
    select companion.item
    from jsonb_array_elements(companions_payload) as companion(item)
  loop
    select *
    into companion_row
    from private.resolve_or_create_guest_day10(
      target_hotel_id,
      companion_payload
    );

    if companion_row.id = guest_row.id then
      raise exception 'Primary guest cannot also be added as a companion.';
    end if;

    insert into public.guest_companions (
      hotel_id,
      guest_session_id,
      primary_guest_id,
      guest_id,
      relationship,
      guest_category,
      form_c_required,
      created_by
    )
    values (
      target_hotel_id,
      created_session_id,
      guest_row.id,
      companion_row.id,
      nullif(trim(companion_payload ->> 'relationship'), ''),
      coalesce(
        nullif(lower(trim(companion_payload ->> 'guest_category')), ''),
        'adult'
      ),
      coalesce(
        (companion_payload ->> 'form_c_required')::boolean,
        false
      ),
      auth.uid()
    );

    companion_count := companion_count + 1;
  end loop;

  stay_payload := coalesce(payload -> 'stay_details', '{}'::jsonb);

  if jsonb_typeof(stay_payload) <> 'object' then
    raise exception 'Stay details must be a JSON object.';
  end if;

  insert into public.guest_stay_details (
    hotel_id,
    guest_session_id,
    purpose_of_visit,
    arrival_from,
    next_destination,
    arrival_mode,
    arrival_transport_number,
    departure_mode,
    departure_transport_number,
    passport_number,
    passport_issue_country,
    passport_issued_on,
    passport_expires_on,
    visa_number,
    visa_type,
    visa_issue_place,
    visa_issued_on,
    visa_expires_on,
    date_of_arrival_in_india,
    intended_duration_in_india_days,
    form_c_status,
    early_checkin,
    late_checkout,
    special_notes,
    created_by,
    updated_by
  )
  values (
    target_hotel_id,
    created_session_id,
    nullif(trim(stay_payload ->> 'purpose_of_visit'), ''),
    nullif(trim(stay_payload ->> 'arrival_from'), ''),
    nullif(trim(stay_payload ->> 'next_destination'), ''),
    nullif(trim(stay_payload ->> 'arrival_mode'), ''),
    nullif(trim(stay_payload ->> 'arrival_transport_number'), ''),
    nullif(trim(stay_payload ->> 'departure_mode'), ''),
    nullif(trim(stay_payload ->> 'departure_transport_number'), ''),
    nullif(trim(stay_payload ->> 'passport_number'), ''),
    nullif(trim(stay_payload ->> 'passport_issue_country'), ''),
    nullif(stay_payload ->> 'passport_issued_on', '')::date,
    nullif(stay_payload ->> 'passport_expires_on', '')::date,
    nullif(trim(stay_payload ->> 'visa_number'), ''),
    nullif(trim(stay_payload ->> 'visa_type'), ''),
    nullif(trim(stay_payload ->> 'visa_issue_place'), ''),
    nullif(stay_payload ->> 'visa_issued_on', '')::date,
    nullif(stay_payload ->> 'visa_expires_on', '')::date,
    nullif(stay_payload ->> 'date_of_arrival_in_india', '')::date,
    nullif(stay_payload ->> 'intended_duration_in_india_days', '')::integer,
    coalesce(
      nullif(trim(stay_payload ->> 'form_c_status'), ''),
      case
        when guest_row.is_foreign_guest then 'pending'
        else 'not_required'
      end
    ),
    coalesce((stay_payload ->> 'early_checkin')::boolean, false),
    coalesce((stay_payload ->> 'late_checkout')::boolean, false),
    nullif(trim(stay_payload ->> 'special_notes'), ''),
    auth.uid(),
    auth.uid()
  );

  result_value := jsonb_build_object(
    'success', true,
    'idempotent', false,
    'request_id', request_id_value,
    'hotel_id', target_hotel_id,
    'guest_id', guest_row.id,
    'guest_session_id', created_session_id,
    'room_id', room_id_value,
    'room_number', room_row.room_number,
    'payment_id', created_payment_id,
    'room_charge', room_charge_value,
    'checkin_time', checkin_time_value,
    'checkout_time', checkout_time_value,
    'companion_count', companion_count
  );

  insert into public.walkin_checkin_events (
    hotel_id,
    guest_session_id,
    guest_id,
    room_id,
    payment_id,
    idempotency_key,
    checked_in_by,
    checked_in_at,
    request_snapshot,
    result_snapshot,
    metadata
  )
  values (
    target_hotel_id,
    created_session_id,
    guest_row.id,
    room_id_value,
    created_payment_id,
    request_id_value,
    auth.uid(),
    checkin_time_value,
    jsonb_build_object(
      'request_id', request_id_value,
      'room_id', room_id_value,
      'checkout_time', checkout_time_value,
      'room_charge', room_charge_value,
      'guest_id', guest_row.id,
      'companion_count', companion_count
    ),
    result_value,
    jsonb_build_object(
      'source', 'check_in_walk_in_guest',
      'hotel_timezone', hotel_timezone
    )
  );

  perform private.write_activity_log(
    target_hotel_id,
    'front_office.walkin_checked_in',
    'guest_session',
    created_session_id,
    format(
      'Walk-in guest %s checked in to Room %s.',
      guest_row.full_name,
      room_row.room_number
    ),
    null,
    result_value,
    jsonb_build_object(
      'request_id', request_id_value,
      'guest_id', guest_row.id,
      'room_id', room_id_value,
      'payment_id', created_payment_id,
      'companion_count', companion_count
    )
  );

  return result_value;
end;
$function$;

revoke all on function public.check_in_walk_in_guest(uuid, jsonb)
  from public, anon;

grant execute on function public.check_in_walk_in_guest(uuid, jsonb)
  to authenticated, service_role;

comment on function public.check_in_walk_in_guest(uuid, jsonb) is
  'Day 10 authoritative atomic direct/walk-in check-in. Creates/reuses the guest, stay, room charge, inventory allocation, stay details, companions, room history and immutable event in one transaction.';

commit;
