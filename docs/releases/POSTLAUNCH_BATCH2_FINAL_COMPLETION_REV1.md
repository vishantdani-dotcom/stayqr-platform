# StayQR Post-Launch Batch B — Final Completion REV1

Authoritative Batch B scope: items **3, 4, 5, 8, 11, 13, 14**.

## Preserved and regression-locked
- **3:** platform-only Super Admin with explicit timed/audited safe hotel support access; no silent impersonation.
- **4:** hotel support/report issue actions plus guest hotel-management escalation and emergency direct call.

## Completed in this patch
- **5:** editable staff profile/avatar plus real phone verification through Supabase Auth OTP. `phone_verified_at` is synchronized only from an Auth-confirmed phone.
- **8:** hotel dashboard logo and cover image use the existing tenant-scoped `guest-guide-media` library and a permission-guarded branding RPC.
- **11:** Amenities now include tenant-scoped image/short-video gallery upload, display, metadata editing and removal.
- **13:** a dedicated **Media Manager** centralizes tenant media; the existing Guest Guide media library is extended to controlled MP4/WebM short video: approved categories only, 20 MB server/client cap and 30-second client duration cap. Guest Guide Builder and guest-facing guide render the same unified media records.
- **14:** each room receives one stable permanent QR identity. A current checked-in stay receives a fresh six-digit PIN challenge. The PIN is stored only as bcrypt, locks after five failures, expires with the stay and is revoked when the stay changes/ends. Successful PIN verification resolves into StayQR's existing signed, rotating and revocable guest token; it does not replace or bypass that token lifecycle.

## Staging database files
For fastest staging execution, run `supabase/staging/202608200088_089_postlaunch_batch2_final_STAGING_APPLY_AND_ACCEPT.sql` once. The canonical files remain:

1. `supabase/migrations/202608200088_postlaunch_batch2_final_completion.sql`
2. `supabase/audit/202608200089_postlaunch_batch2_final_completion_ACCEPTANCE.sql`

Expected audit summary:
`POSTLAUNCH_BATCH2_FINAL_DATABASE_ACCEPTANCE: PASS (24/24)`

## Production safety
This package is for the existing staging branch and StayQR Staging first. It does not authorize a production database migration or Netlify Publish deploy.
