# StayQR Day 7 — Guest Access and RLS Foundation REV3

Run in this order:

1. `npm run check`
2. Supabase migration `202607260013_day7_guest_access_and_rls_foundation.sql`
3. Audit `037_verify_day7_guest_access_and_rls_foundation.sql`

Expected Audit 037 result: **22 rows, every `passed` value = `true`.**

REV3 includes the source-schema compatibility repair for `food_order_items.hotel_id`, safe legacy backfill, cross-hotel validation, and a tenant-enforcement trigger. It deliberately avoids a second order/menu foreign-key relationship so existing nested PostgREST queries remain unambiguous.

Do not use the earlier v1/REV2 migration. The failed executions were inside a transaction and were rolled back automatically.

Legacy `/guest/{roomNumber}` and `/food/{roomNumber}` URLs are intentionally rejected after this package. Guest access requires a hotel slug and signed stay token.
