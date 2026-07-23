StayQR Day 4 — Platform Admin Hotel Switcher and Tenant Context Fix

This is a complete Frontend overlay package based on the completed Day 4 v5 source.
It fixes the remaining production defects where the sidebar could show one property while the Dashboard or another module showed data from another property.

Included corrections
- Working property switcher in the upper-left sidebar.
- Working user/avatar menu with a second property switcher and Logout action.
- One canonical selected-hotel context for the complete authenticated application.
- All main page modules remount and reload authoritative data after a property switch.
- Dashboard hotel identity and statistics are fully selected-hotel scoped; hard-coded VD Stay Inn content is removed.
- Per-user property persistence prevents one login from inheriting another user's saved property.
- Logout clears the saved property context.
- Switching overlay disables duplicate/rapid switch actions.
- Failed switches roll back to the previous valid property and show a visible error.
- Notification requests are guarded so a late response from the previous property cannot overwrite the current property's notifications.

Apply
1. Stop npm run dev with Ctrl+C.
2. Extract this ZIP.
3. Open the extracted Frontend folder.
4. Copy everything inside it into your existing:
   C:\Users\HP\Documents\StayQR\Frontend
5. Choose Replace the files in the destination.
6. Do not delete the existing Frontend folder first. This package excludes .env, node_modules, dist and .git.
7. Run:
   npm run check
   npm run dev
8. Hard-refresh the browser with Ctrl+Shift+R.

Acceptance sequence
- Open the sidebar property selector.
- Switch VD Stay Inn -> Hotel Apex Stay Inn.
- Confirm sidebar, navbar, Dashboard property card, Dashboard statistics and any opened module all show Apex only.
- Open Booking Calendar and Reservations and confirm their hotel field is Apex.
- Switch Apex -> VD and repeat.
- Refresh the browser and confirm the selected property is preserved for the current signed-in user.
- Logout and log back in; confirm no mixed Apex/VD context appears.
- Final gate: npm run check has 0 errors and Git working tree is clean after commit/push.
