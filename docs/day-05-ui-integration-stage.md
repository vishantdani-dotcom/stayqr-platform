# Day 5 UI Integration Stage

This stage connects the verified Day 5 database foundation to the browser.

Included:

- Arrivals & Departures operational page.
- Atomic reservation-room check-in from operations and reservation details.
- Group / multi-room add and remove controls.
- Independent room-level check-in for partially checked-in group bookings.
- Authoritative reservation confirmation PDF, print and WhatsApp actions.
- Reservation check-in link from the direct-stay page.
- Hotel-scoped navigation and tenant remounting.
- Operations read-model hardening for partially checked-in group bookings.
- Confirmation read-model hardening with cancellation policy and meal plan.

Execution:

1. Overlay the complete Frontend package.
2. Run migration `202607240008_day5_operations_and_confirmation_hardening.sql`.
3. Run audit `021_verify_day5_ui_integration_contracts.sql` and confirm every row is true.
4. Run `npm run check` locally.
5. Start `npm run dev` and perform the browser checklist supplied with the package.

This stage is not the final Day 5 exit gate. Deterministic browser data, rollback tests,
deposit-transfer verification, booking-to-checkout smoke testing and repository closure
remain after the UI is verified.
