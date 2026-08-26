# StayQR Post-Launch Batch B — Browser Blockers Fix REV1

- Adds an MP4 container-duration fallback for valid short videos when browser codec metadata cannot be decoded.
- Prevents zero-value legacy payments from manufacturing invalid zero-value folio collections during checkout.
- Exposes the audited platform flow explicitly as **View as Hotel** in Super Admin.
- Reports missing Supabase SMS provider configuration accurately instead of masking it as an app defect.

Phone OTP delivery still requires a configured SMS provider in the hosted Supabase project. StayQR does not fake phone verification.
