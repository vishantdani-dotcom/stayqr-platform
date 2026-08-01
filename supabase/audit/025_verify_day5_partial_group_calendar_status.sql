select *
from (
  values
    (
      'room_status_calendar_function',
      to_regprocedure(
        'public.get_booking_calendar_room_status(uuid,date,date,uuid,text[],text[],integer,integer)'
      ) is not null,
      'Calendar room cards and status filters use reservation-room status.'
    ),
    (
      'room_status_calendar_execute_grant',
      has_function_privilege(
        'authenticated',
        'public.get_booking_calendar_room_status(uuid,date,date,uuid,text[],text[],integer,integer)',
        'EXECUTE'
      ),
      'Authenticated hotel users can load the room-status-aware calendar.'
    ),
    (
      'day4_calendar_preserved',
      to_regprocedure(
        'public.get_booking_calendar(uuid,date,date,uuid,text[],text[],integer,integer)'
      ) is not null,
      'The original Day 4 authoritative read model remains installed.'
    )
) as tests(test_name, passed, details)
order by test_name;
