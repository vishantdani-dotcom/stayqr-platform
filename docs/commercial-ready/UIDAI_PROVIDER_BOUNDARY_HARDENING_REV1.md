# StayQR UIDAI Provider Boundary Hardening REV1

Prepared: 4 September 2026

## Scope

Provider-agnostic hardening only. No UIDAI/Aadhaar provider has been onboarded, no credentials were configured, no external UIDAI request was made, and `UIDAI_ONLINE_AUTH_ENABLED` must remain OFF until an authorized route and staging contract are approved.

## Implemented

- OTP dispatch can no longer treat a generic provider `success` status as identity verification.
- Verification rejects expired, terminal, in-progress, over-attempt and stay-binding-mismatched requests before provider contact.
- Requests preserve their original `guest_session_id`; caller substitution is rejected.
- Verification attempts are bounded and claimed with a checked state transition before the provider call.
- Provider endpoint/provider-name/response semantics are validated before trust decisions.
- Raw provider error messages are not returned to the browser, preventing Aadhaar/OTP echo leakage.
- Database creation/update/evidence/finalization failures fail closed rather than returning verification success.
- Provider-verified-but-evidence-not-yet-persisted requests use `evidence_pending`; retries reconcile evidence without contacting the provider again.
- Aadhaar/OTP frontend state is cleared after failed provider attempts as well as successful attempts.
- Existing offline Aadhaar verification remains unchanged.

## Database change

Migration `202609040108_uidai_online_auth_provider_boundary_hardening_REV1.sql` adds bounded attempts, expiry, provider verification timestamp, and controlled `verifying` / `evidence_pending` states.

## Local validation

- Existing synthetic provider-boundary probe: all 10 UIDAI checks PASS.
- The same consolidated probe still reports 2 WhatsApp webhook failures, which are separate from this UIDAI batch.
- Commercial-Ready source validation: 74/74 PASS.
- Pilot Manual Billing source validation: 42/42 PASS.
- ESLint: 0 errors, 7 inherited warnings.
- Production build was not re-run successfully in this Linux container because the uploaded `node_modules` contains Windows-native Rolldown bindings. Re-run `npm.cmd ci` and `npm.cmd run build` on the user's Windows repository before acceptance.

## Remaining external dependency

StayQR still requires an authorized Aadhaar authentication route/provider and its staging/API contract. Do not activate the flag or bind a generic/unofficial Aadhaar lookup API. Provider-specific payload signing, endpoint contract, error codes, certificates/keys and authorization evidence must be implemented only from the chosen authorized provider's official contract.
