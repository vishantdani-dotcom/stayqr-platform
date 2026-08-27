# StayQR Post-Launch — Day 2 Support & Incident Readiness

Status: OPERATIONAL PACKAGE LOCKED FOR STABILIZATION

## Severity matrix
- P0 — production unavailable, tenant leak, major financial/data-loss/security blocker.
- P1 — serious operational failure with no safe workaround.
- P2 — important non-critical defect or operational improvement.
- P3 — minor UX/cosmetic/nice-to-have issue.

## Intake and triage
1. Record time, hotel, actor, affected module, screenshot/error and reproducibility.
2. Classify severity and category: production defect / configuration / training / feature request.
3. For P0/P1, stop unsafe writes and preserve evidence.
4. Escalate provider-specific issues to Supabase, Netlify or Cashfree where applicable.
5. Close only after runtime verification and evidence.

## Existing authority
The accepted Day 20 incident/rollback, operational support, support ownership and production operational ownership documents remain authoritative. This file does not replace them.

## Stabilization rule
No visual redesign, speculative feature, one-hotel custom workflow or v1.1 feature is treated as a production hotfix without classification.

Acceptance: support issues can be received, classified, escalated and closed without improvising a new process.
