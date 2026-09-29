begin;

-- Rolls back only Migration 124 schema/runtime additions.
-- It intentionally does NOT reverse room-charge amounts already confirmed by hotel staff.

drop function if exists public.reconcile_active_stay_room_charge(uuid, uuid, jsonb);
drop table if exists public.guest_session_room_charge_events;

commit;
