# StayQR Post-Launch — Day 6 Usage & Feedback Review

Status: CONSOLIDATED REVIEW COMPLETE FOR CURRENT EVIDENCE

## Current classification

### P0
No P0 was reproduced during the accepted staging Gate C flow.

### P1
Historical Batch 3 access regression:
- broken commit: d9b369aadf9b8a12bcdad5c62e2be30f8032465b
- classification: production access regression / P1 class
- rule: never redeploy this broken commit
- accepted post-launch source baseline used for staging recovery: bd4d269f43988a6337f15b686380e1664dab4219
- current live production status: NEEDS VERIFICATION under production authorization

### Closed configuration/schema issues
- Apex foundation readiness repair: accepted before Gate C.
- Staff phone_verified_at / avatar_path schema parity: repaired and accepted.
- Gate C staging final state: both QA rooms Available, no transaction residue.

## Customer feedback register
Historical Apex requests include:
- bathtub instructions
- emergency numbers
- image replacement
- review CTA
- logo link
- essentials dialer
- QR expiry after checkout
- check-in/out capture
- language selection

These are customer feedback inputs. They are not automatically open P0/P1 defects. Existing implemented behavior must be verified against live hotel configuration before any new code work.

## v1.1 candidate backlog
Keep as candidates until Day 7 evidence supports planning:
- direct website booking widget
- corporate profiles / rates
- split-stay / split-bill refinements
- laundry / lost-and-found
- scheduled reports
- WhatsApp Business API automation
- simple inventory
- KOT printer improvements
- multi-property improvements
- accounting connectors / CSV templates
- additional operational refinements backed by repeated usage evidence

## Do-not-build-yet list
Do not start the above candidates merely because one hotel asks.
Do not add unverified marketing claims.
Do not claim new 24×7 staffed support while the published support-hours policy remains unchanged.
Do not duplicate existing hotel, guest, payment, subscription, KYC, media or QR foundations.

Day 6 decision: feedback is classified before code work.
