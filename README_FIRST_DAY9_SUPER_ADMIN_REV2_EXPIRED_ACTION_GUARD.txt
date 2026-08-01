StayQR Day 9 Super Admin Commercial Frontend REV2

Purpose
- Prevents the Manage dialog from offering manual renewal for expired or cancelled subscriptions.
- Aligns the frontend exactly with renew_hotel_subscription, which accepts only active, past_due and suspended subscriptions.
- Directs expired/cancelled recovery through the controlled Cashfree Payment Link action.
- Disables Annual billing when the selected plan has no annual price.
- Makes renewal audit notes required for eligible renewal actions.

No database migration is included or required.
Cashfree remains in Test Environment until final Day 9 acceptance.
