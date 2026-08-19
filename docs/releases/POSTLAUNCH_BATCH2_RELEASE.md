# StayQR Post-Launch Batch B Release

## Scope

This staging-first release completes the remaining operational and customer-service work approved after Batch A:

- Super Admin platform metrics for hotels, guests, active stays, guest document scans, reservations, rooms and staff.
- Platform-admin hotel access presented as explicit timed, audited support access instead of ordinary property switching.
- Hotel dashboard shortcuts, hotel logo/photo treatment and direct Operations Centre/report-issue actions.
- Staff self-profile editing for full name, phone and a private JPEG/PNG/WebP profile photo up to 5 MB.
- Guest directory CSV export that excludes identity documents.
- Consent-confirmed WhatsApp click-to-chat from an individual guest record. This is not an automated or bulk broadcast facility.
- Guest-facing management escalation through the existing hotel service-request workflow.

## Support statement

The customer-facing support statement remains **09:00–19:00 IST, Monday–Saturday**. This batch does not publish a 24×7 staffed-support claim.

## Security boundaries

- The `staff-avatars` bucket is private and scoped to the authenticated staff member and their hotel.
- Staff may update only their own active profile in the explicitly selected hotel.
- Platform-wide metrics require `private.is_platform_admin()` and are never exposed to anonymous users.
- CSV export is generated locally from the currently authorized hotel view and excludes guest identity documents.
- WhatsApp opens a user-confirmed click-to-chat URL only; StayQR does not send an automated campaign.

## Deployment boundary

Apply and validate this release on **StayQR Staging** (`eecinuhvkxlbdvyuazal`) and its branch deploy first. Production (`rbyirbovbkguzvwijyaj`) remains untouched until staging acceptance is explicitly approved.

## Deferred to Batch C

The built-in document scanner/Aadhaar workflow, amenity media, broader video uploads and permanent room-wise QR lifecycle remain out of this release.
