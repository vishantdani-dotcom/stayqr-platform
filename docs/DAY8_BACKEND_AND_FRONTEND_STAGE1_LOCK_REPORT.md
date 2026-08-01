# StayQR v1.0 — Day 8 Backend and Frontend Stage 1 Lock Report

## Backend acceptance

| Package | Result |
|---|---:|
| Migration 017 — onboarding/settings/floors/trial foundation | 12/12 |
| Migration 018 — atomic onboarding and trial RPCs | 18/18 |
| Audit 044 REV3 — authenticated runtime acceptance | 24/24 |
| Audit 045 — configuration schema contract | 30 diagnostic rows, 0 risks |
| Migration 019 — inventory/defaults/bulk rooms | 24/24 |
| Audit 046 — configuration runtime acceptance | 28/28 |
| Audit 047 — helper cleanup and frontend readiness | 18/18 |

The temporary runtime audit helpers were removed. Permanent onboarding and configuration RPCs remain authenticated-only, and anonymous execution remains blocked.

## Permanent Day 8 RPC surface

- `bootstrap_hotel_onboarding(jsonb)`
- `save_hotel_onboarding_step(uuid,text,jsonb)`
- `activate_hotel_trial(uuid,uuid,integer)`
- `get_hotel_onboarding_readiness(uuid)`
- `refresh_hotel_onboarding_readiness(uuid)`
- `seed_hotel_menu_defaults(uuid)`
- `seed_hotel_configuration_defaults(uuid)`
- `configure_hotel_inventory(uuid,jsonb)`
- `import_hotel_rooms(uuid,jsonb)`

## Frontend Stage 1 scope

The frontend now supports owner registration, unassigned-user onboarding, atomic hotel creation, tenant activation, resumable setup, structured hotel settings, inventory configuration, room CSV import, amenities, service request categories, starter menu configuration and authoritative readiness review.

The Super Admin page no longer performs separate browser inserts for hotels and subscriptions. Hotel creation is routed through the atomic onboarding RPC.

## Source validation

- Relative imports: 150 resolved
- Day 7 security source gate: 15/15
- Day 8 onboarding source gate: 13/13
- Local QR engine: 5/5
- ESLint: 0 errors; 16 pre-existing React Hook warnings

## Remaining Day 8 exit work

- Install the complete frontend package on Windows.
- Confirm login/signup rendering.
- Confirm Platform Admin Hotel Setup rendering.
- Run a controlled reversible browser onboarding acceptance.
- Verify tenant switch, reload/resume and final readiness UI.
- Lock Day 8 only after browser evidence passes.
