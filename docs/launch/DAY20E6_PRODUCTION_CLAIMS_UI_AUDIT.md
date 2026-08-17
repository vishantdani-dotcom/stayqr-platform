# StayQR Day 20E-6 — Production Claims / Website / Settings Audit

## App remediation
- duplicate dead-end Settings sidebar item removed;
- Operations Centre → System settings remains authoritative;
- legacy internal settings navigation opens the real System settings tab;
- hard-coded Dashboard placeholder guest/payment/service data removed;
- hard-coded Guests=3 and Service Requests=5 sidebar badges removed.

## Locked marketing catalogue
| Plan | Monthly | Annual | Rooms | Property | Trial |
|---|---:|---:|---:|---:|---:|
| Starter | ₹999 | ₹9,999 | 20 | 1 | 14 days |
| Growth | ₹2,499 | ₹24,999 | 50 | 1 | 14 days |
| Scale | ₹4,999 | ₹49,999 | 100 | 1 | 14 days |

Enterprise / Custom applies beyond standard Scale limits or for multi-property requirements.

Removed/replaced stale or unproven claims including ₹8,000, 12-room setup, free one-year maintenance, premium support included, unverified testimonials and quantified performance claims.

20E-6 passes only after source verification, build, lint, local UI checks, production app deployment and marketing deployment pass.
