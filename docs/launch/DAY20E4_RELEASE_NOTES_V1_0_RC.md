# StayQR v1.0 — Release Candidate Notes

**Release stage:** Day 20 commercial/launch readiness RC  
**Date:** 17 August 2026  
**Final production tag/hash:** intentionally pending Day 20G final Go/No-Go

## Product scope

StayQR v1.0 is the launch candidate for independent/small hospitality operations, providing a connected hotel operations and guest-experience platform rather than a QR-only product.

## Major capabilities in this release candidate

### Hotel and SaaS foundation

- multi-tenant hotel context and hotel switching;
- tenant-scoped authorization/RLS foundation;
- hotel onboarding/readiness workflow;
- subscription/trial/commercial lifecycle foundation;
- staff identities, invitations, roles and access controls.

### Reservations and front desk

- reservation/availability foundation;
- booking calendar and room allocation;
- walk-in/check-in workflow;
- guest identity/history and companion data;
- stay move/extension/overdue operations;
- checkout workflow.

### Guest experience

- signed/rotating/revocable stay-bound guest QR access;
- premium guest guide and hotel-editable content/media;
- multilingual guest experience support implemented by the product;
- guest food ordering and service-request workflows;
- guest access invalidation on checkout/expiry/revocation as designed.

### Finance and audit

- authoritative folio foundation;
- charges, collections, refunds/credits/settlement controls;
- invoice and receipt workflows;
- cashier shifts;
- Night Audit;
- reports and CSV/PDF exports.

### Hotel operations

- rooms/inventory governance;
- housekeeping workflow;
- maintenance/out-of-order lifecycle;
- menu and food-order operations;
- service-request routing/operations;
- amenities configuration.

### Notifications, support and administration

- notification/activity foundation;
- support workspace;
- announcements;
- hotel system settings;
- operational diagnostics/health/incidents.

### Production hardening

- query/index/performance hardening;
- lazy loading/code splitting and error boundaries;
- structured operational diagnostics with redaction boundary;
- environment separation;
- security headers/rate-limit configuration;
- CI/CD deployment validation;
- database backup/restore drill;
- separate Storage object backup/recovery verification.

### Commercial/legal readiness

Published production legal/service suite includes:

- Privacy Policy;
- Terms of Service;
- Acceptable Use Policy;
- Data Processing Agreement;
- SLA / Service Commitments;
- Support + Escalation Policy;
- Subscription / Cancellation / Refund Policy;
- Security + Responsible Disclosure;
- Cookie & Browser Storage Notice;
- central Legal & Policies hub.

## Launch documentation

Day 20E-4 adds:

- hotel onboarding guide;
- owner/admin runbook;
- staff quick start;
- operational support runbook;
- incident/rollback runbook;
- commercial demo script;
- known limitations.

## Release-control note

These are release-candidate notes. The immutable launch package, final production branch/tag and exact production commit hash are not created until the final Day 20G Go/No-Go acceptance is green.

See `DAY20E4_KNOWN_LIMITATIONS_V1_0.md` before making sales or implementation commitments.
