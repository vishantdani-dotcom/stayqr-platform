# Day 5 reservation confirmation status and PDF currency fix

## Defects found during browser acceptance

The group booking `RES-2026-000002` was partially checked in, but the confirmation outputs used the reservation-header status `checked_in`. The downloaded PDF and print output therefore did not match the room-level state already shown by Reservations and Booking Calendar.

The downloaded jsPDF file also used the Indian rupee glyph with jsPDF's built-in Helvetica font. That font does not contain the glyph, so some PDF renderers displayed a superscript-like replacement character instead of the currency symbol.

## Corrections

- Derive the confirmation booking status from active reservation-room statuses.
- Display `Partially Checked In` when checked-in and pending rooms coexist.
- Include each room's independent status in PDF, Print and WhatsApp output.
- Filter cancelled and released room rows consistently across all outputs.
- Use ASCII currency codes such as `INR 9,000.00` inside downloaded PDFs.
- Preserve browser-native localized currency formatting in Print and WhatsApp.
- Keep total, tax, discount, deposit and balance fields consistent across outputs.
- Include special requests and hotel terms consistently in PDF and Print.

No database migration is required. The authoritative confirmation RPC already returns room-level statuses.
