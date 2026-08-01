# StayQR v1.0 — Day 9 Super Admin Commercial Frontend

## Scope

This package replaces the earlier primitive Super Admin page with one controlled commercial operations centre for:

- global SaaS metrics and MRR;
- hotels and subscription lifecycle;
- plans, pricing and capacity limits;
- Cashfree test payment links;
- usage counters;
- support tickets and Platform Admin triage;
- explicit, time-bound safe support access;
- immutable subscription and webhook evidence;
- global and hotel-targeted announcements.

## Trusted backend boundary

The browser reads the commercial control model through `get_super_admin_commercial_data`. Subscription mutations use the accepted Day 9 lifecycle RPCs. Cashfree payment links are created only through the `cashfree-create-payment-link` Edge Function. The frontend never writes provider ledger, subscription lifecycle event or webhook rows directly and contains no provider secret or Supabase service-role credential.

## Backend prerequisites

Install and accept the locked Day 9 backend before using this frontend:

1. Migration 020 REV2 — commercial/lifecycle/platform foundation.
2. Migration 021 — lifecycle, limits, metrics and support RPCs.
3. Migration 023 REV2 — safe-support end-action ambiguity fix.
4. Migration 024 REV2 — Cashfree-ready payment-link ledger, provider lifecycle action and controlled commercial RPC.
5. Accepted Cashfree Edge Functions and test credentials.

Cashfree remains in the **test environment** for this package. Production-mode activation is deliberately outside this frontend release.

## Installation

1. Back up the current `Frontend` folder.
2. Replace it with the `Frontend` folder from this package.
3. Copy the existing local `.env` file into the replacement folder. Do not place service-role or Cashfree secrets in `.env` used by Vite.
4. Run:

```bash
npm install
npm run check
npm run dev
```

5. Sign in with the active Platform Admin account and open **Super Admin** from the sidebar.

## Browser acceptance checklist

### Overview

- Controlled dashboard snapshot loads.
- MRR, hotel, trial, support, webhook and capacity cards render.
- Cashfree banner clearly states test environment.
- Reconciliation requires confirmation.

### Hotels and subscriptions

- Search filters hotels by name, slug, city, state, plan and status.
- Usage opens authoritative server-calculated counters.
- Extend, suspend, reactivate, change plan, renew and cancel use RPC actions.
- Each destructive/repeatable lifecycle submission shows a stable idempotency key.

### Plans

- Create a reversible test plan, edit it and confirm limits/prices persist.
- Room and staff limits remain server-enforced; this frontend only configures/displays them.

### Cashfree payment links

- Create one test payment link for a controlled hotel/plan.
- Confirm the returned link appears in the ledger after refresh.
- Confirm no direct browser insert/update is made to `subscription_payment_links`.

### Support

- Create or triage a support ticket.
- Add a ticket message.
- Start safe support access with an explicit reason, duration and approved permissions.
- End the session and confirm its audit state refreshes.

### Events and announcements

- Subscription events and webhook status appear without raw webhook payload/header bodies.
- Create a draft or published announcement and confirm visibility rules.

## Source validation

The package adds:

```bash
npm run security:day9
```

This source gate verifies all required controlled RPC/Edge Function contracts and rejects browser-side service-role/provider secrets and direct writes to protected subscription, payment-link, lifecycle-event and webhook tables.
