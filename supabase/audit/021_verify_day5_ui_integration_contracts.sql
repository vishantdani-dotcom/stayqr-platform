select *
from (
  values
    (
      'operations_group_partial_checkin',
      position(
        'reservation_status in (''confirmed'', ''checked_in'')'
        in lower(pg_get_functiondef('public.get_reservation_operations(uuid,date,integer)'::regprocedure))
      ) > 0,
      'Remaining confirmed rooms stay in arrival queues after the first room of a group reservation checks in.'
    ),
    (
      'operations_unallocated_partial_group',
      position(
        'reservation_status in (''tentative'', ''confirmed'', ''checked_in'')'
        in lower(pg_get_functiondef('public.get_reservation_operations(uuid,date,integer)'::regprocedure))
      ) > 0,
      'Unallocated room rows remain visible for partially checked-in group reservations.'
    ),
    (
      'confirmation_cancellation_policy',
      position(
        '''cancellation_policy'', rp.cancellation_policy'
        in lower(pg_get_functiondef('public.get_reservation_confirmation(uuid,uuid)'::regprocedure))
      ) > 0,
      'Confirmation snapshot includes the room-level cancellation policy.'
    ),
    (
      'confirmation_meal_plan',
      position(
        '''meal_plan'', rp.meal_plan'
        in lower(pg_get_functiondef('public.get_reservation_confirmation(uuid,uuid)'::regprocedure))
      ) > 0,
      'Confirmation snapshot includes the room-level meal plan.'
    ),
    (
      'operations_execute_grant',
      has_function_privilege('authenticated', 'public.get_reservation_operations(uuid,date,integer)', 'EXECUTE'),
      'Authenticated hotel users can load arrivals and departures.'
    ),
    (
      'confirmation_execute_grant',
      has_function_privilege('authenticated', 'public.get_reservation_confirmation(uuid,uuid)', 'EXECUTE'),
      'Authenticated hotel users can generate reservation confirmations.'
    )
) as tests(test_name, passed, details)
order by test_name;
