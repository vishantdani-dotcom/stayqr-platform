# StayQR Platform

StayQR is a multi-tenant hotel operations and guest-experience platform built around a permanent smart room QR that automatically activates a personalized guest guide for the current checked-in stay.

## Launch product

The commercial launch build includes:

- reservations, booking calendar, arrivals and departures
- front-desk check-in/out, room moves and stay extensions
- single, couple and family/multi-occupant stays
- rooms, inventory, housekeeping and maintenance
- guest CRM / Guest 360 and private KYC document capture
- OCR-assisted ID extraction and offline Aadhaar verification evidence
- folios, charges, payments, invoices and settlement workflows
- permanent room QR guides with automatic stay activation
- multilingual guest guide, food menu, ordering and service requests
- staff/RBAC, multi-property context and audited platform support access
- reports, revenue insights and manual/offline subscription billing

## Provider hold policy

The launch build deliberately keeps these external-provider automations disabled until StayQR explicitly reopens them:

- Meta WhatsApp Cloud API automated campaigns
- Cashfree recurring AutoPay
- formal UIDAI online authentication

Their hardened backend foundations may remain in source, but production safety flags must default to `false`. Hotels should not see provider-activation controls as launch requirements.

## Core QR model

Each room receives one high-entropy permanent QR. The same physical QR can be printed on a room standee and key-card sleeve.

1. Staff checks a guest into a room.
2. Existing guest-session triggers issue/rotate the signed stay token automatically.
3. Scanning `/room/<permanent-code>` resolves only the current active stay.
4. No PIN, login or receptionist QR action is required.
5. Extension keeps the permanent QR usable while signed access follows the updated checkout.
6. Room move stops the old room from resolving and activates the new room QR.
7. Checkout/expiry stops access automatically.
8. Authorized staff can emergency-revoke stay access or regenerate a compromised permanent room QR.

The public QR never contains a guest name, phone number, hotel database ID or raw stay token.

## Technology

- React + Vite
- Supabase Auth, Postgres, RLS, Storage and Edge Functions
- Netlify frontend hosting
- Local QR generation

## Local setup

```bash
npm ci
npm run dev
```

Use `.env.example` as the configuration reference. Never commit service-role keys, provider tokens or production credentials.

## Validation

For the launch-freeze source:

```bash
npm run lint
npm run build
node scripts/validate-final-product-freeze-rev9.mjs
```

Historical validation scripts are retained as engineering evidence, but the Final Product Freeze validator is authoritative for launch-facing wording and the zero-PIN permanent room QR workflow.

## Environment boundaries

- Staging and production use separate Supabase projects and Netlify sites.
- Migrations must be applied to the intended environment explicitly.
- External provider flags stay disabled unless a provider rollout is deliberately approved.
- Production changes require an explicit release decision after staging acceptance.

## Security principles

- hotel-scoped RLS and permission checks remain mandatory
- signed guest access remains rotating, revocable and checkout-bound
- permanent room QR codes are high-entropy physical credentials
- public guest routes expose no KYC documents or sensitive staff/admin data
- audited `View as Hotel` is required for platform support access
- destructive/security actions require explicit confirmation

## Release state

This repository is the StayQR application source. The public marketing website is finalized separately after the application release candidate is accepted.
