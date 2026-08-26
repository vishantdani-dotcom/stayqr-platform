# StayQR Post-Launch Batch 1 Local Evidence

Evidence date: 2026-08-18 UTC

Authoritative input: `StayQR_PostLaunch_Source_d921c1f.zip` at locked commit `d921c1f633a5d609cebd3b4c65884e891dd5f956` plus `StayQR_PostLaunch_Marketing.zip`.

## Passed in the supplied source workspace

| Gate | Result |
|---|---:|
| Relative frontend imports | PASS — 224 resolved |
| Day 7 frontend security | PASS — 15/15 |
| Day 8 onboarding | PASS — 14/14 |
| Day 9 commercial | PASS — 20 required / 7 blocked |
| Day 10 front office | PASS — 69 required / 13 blocked |
| Day 11 folio/settlement | PASS — 41 required / 11 blocked |
| Day 12 invoices/cashier | PASS — 61 required / 13 blocked |
| Day 13 operations | PASS — 45 required / 14 blocked |
| Day 14 guest experience | PASS — 16 required / 7 blocked |
| Day 14 final builder | PASS — 30 required / 11 blocked |
| Day 15 food/service | PASS — 32 required / 12 blocked |
| Day 17 final current source | PASS — 58 required / 16 blocked |
| Local QR engine | PASS — 5/5 |
| Day 18 frontend/performance source | PASS — 78 required / 11 blocked / 41 lazy routes |
| Day 18 monitoring source | PASS — 61 required / 12 blocked |
| Day 18 infrastructure source | PASS — 58 required / 12 blocked |
| Batch 1 source acceptance | PASS — 43/43 |
| Marketing deployment copies | PASS — byte-identical |
| Marketing inline JavaScript parse | PASS |
| Locked Day 20 migration hash | PASS — unchanged |
| Locked operational support runbook hash | PASS — unchanged |

## Prepared, not falsely marked passed

| Gate | Current state | Required completion evidence |
|---|---|---|
| ESLint | OPEN — uploaded source archive contains no `node_modules`; local command correctly returned `eslint: not found` | Run `npm ci && npm run lint`; expected `0 errors / 7 inherited warnings` |
| Vite production build | OPEN — uploaded source archive contains no `node_modules`; local command correctly returned `vite: not found` | Run `npm ci && npm run build`; expected exit 0 and `dist` |
| Database migration execution | OPEN | Apply migration 083 in staging and run audit 084: `PASS (16/16)` |
| Edge runtime/Cashfree sandbox | OPEN | Signed sandbox PAID webhook provisions exactly one hotel/subscription; duplicate is idempotent |
| Responsive browser matrix | OPEN | 1440/1024/768/393/390 acceptance recorded |
| Production deploy and public smoke | OPEN | `POSTLAUNCH_BATCH1_LIVE_SMOKE: PASS (12/12)` plus controlled paid lifecycle |

An offline `npm ci` was attempted and stopped because one or more lockfile tarballs were not cached. No dependency or lockfile was changed. Network installation was not substituted with unpinned packages.

## Regression provenance

1. The source archive’s Day 7 gate interpreted legal warning prose containing “service-role” as executable browser secret usage. The detector now checks actual secret/identifier forms.
2. The inherited Day 10 gate found a real direct browser update to `guest_documents.deleted_at`. Batch migration 083 adds `soft_delete_guest_document`, including tenant permission, row lock, guest verification reconciliation and activity evidence; the browser calls that RPC.
3. The Day 18 route-count gate used an obsolete exact count. It now verifies all required lazy routes while allowing additive lazy routes and explicitly includes subscription checkout.
4. The Day 17 final source gate used a line-ending-sensitive JWT restoration check even though Audit 071 contains the restore calls. The detector now accepts safe whitespace/CRLF variants.
5. The historical Day 18 canonical-baseline script intentionally rejects any migration added after the canonical baseline; it is not a post-launch migration acceptance gate. Batch audit 084 is the applicable additive database gate.

Release status at packaging: **SOURCE ACCEPTANCE PASSED; DEPENDENCY, STAGING, CASHFREE RUNTIME AND PRODUCTION GATES OPEN.**
