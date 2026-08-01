# Day 7 REV3 migration correction

The original Day 7 migration exposed two source-specific PostgreSQL issues before commit:

1. PL/pgSQL `%ROWTYPE` records were combined with scalar fields in a multi-item `INTO` list.
2. The legacy `food_order_items` table did not carry `hotel_id`, although the Day 7 guest food RPC and RLS policy correctly required hotel-scoped line items.

REV3 separates record/scalar reads and upgrades `food_order_items` transactionally:

- add `hotel_id` when absent;
- reject orphaned order/menu references;
- backfill from `food_orders.hotel_id`;
- reject any order/menu cross-hotel mismatch;
- make `hotel_id` mandatory;
- enforce future consistency through `food_order_items_enforce_tenant`;
- retain the existing simple PostgREST relationships to avoid ambiguous nested selects.

The migration remains wrapped in `BEGIN`/`COMMIT`, so any failure rolls back the complete run.
