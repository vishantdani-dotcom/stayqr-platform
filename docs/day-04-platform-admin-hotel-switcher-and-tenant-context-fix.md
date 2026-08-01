# Day 4 Platform Admin Hotel Switcher and Tenant Context Fix

## Defect

Platform Admin could see a selected property name in the sidebar while the Dashboard continued to show hard-coded or stale information for another hotel. The previous property badge and avatar were not actionable.

## Production correction

### Canonical tenant selection

`src/lib/tenantContext.js` now owns the selected property. Selection is validated against the authenticated user's resolved hotel access and stored under a user-scoped key. The old global local-storage key is removed so a different login cannot inherit stale property context.

A failed switch restores the previous valid property and reloads the previous tenant context.

### Application-wide invalidation

`src/App.jsx` stores the complete tenant context and exposes one switch action to the Sidebar and Navbar. On a successful switch:

- the new tenant context becomes authoritative;
- the current role/staff projection is refreshed;
- pending cross-page navigation is cleared;
- the main page tree is remounted using the selected hotel ID;
- every page therefore reloads using `getCurrentHotel()` from the updated canonical context.

A blocking switching overlay prevents repeated selection while the new context is resolving.

### Working switcher surfaces

A reusable `HotelSwitcher` is available in:

- the upper-left Sidebar property area;
- the Navbar user/avatar menu.

It identifies the current property, lists resolved authorized properties, shows property status, and exposes loading, empty and error states.

### Dashboard correction

The Dashboard now receives the selected hotel from `App.jsx` and scopes every query to its ID. Hard-coded VD Stay Inn identity, ratings and fake property totals were removed from `HotelOverviewCard.jsx`.

### Stale-response protection

Dashboard requests use a request sequence, and Navbar notification requests validate both request order and active hotel ID. A late response from the previous property cannot replace data for the newly selected property.

### Logout

Logout clears all persisted selected-hotel keys before signing out.

## Acceptance gate

1. Switch VD Stay Inn to Hotel Apex Stay Inn.
2. Confirm Sidebar, Navbar and Dashboard show Apex.
3. Confirm Dashboard room/guest/request/order statistics are Apex-scoped.
4. Open Reservations and Booking Calendar; confirm Apex only.
5. Switch back to VD and repeat.
6. Rapidly attempt a second switch while the overlay is active; it must be ignored.
7. Refresh; the current user's selected property must resolve consistently.
8. Logout and login; no mixed context may appear.
9. `npm run check` must report zero errors.
10. Commit, push and confirm a clean working tree.
