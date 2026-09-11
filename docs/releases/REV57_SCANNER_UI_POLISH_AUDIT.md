# StayQR REV57 — Scanner UI Polish Audit

## Scope

Final pre-production UI correction requested after REV55 acceptance.

Only the check-in ID scan/upload experience is changed:

- Mobile document-scanner modal uses the full phone viewport instead of a cramped card.
- Scanner header / close control / preview / camera status / crop controls / actions use the accepted StayQR REV54 blue-black + gold palette.
- The Scan or upload ID card, scan tile, upload tile, OCR progress and result card use the same accepted palette.
- Remove uses the REV55 destructive red semantic treatment.
- Review required / Could not auto-fill use an intentional warning badge and no longer wrap vertically.

## Explicitly unchanged

- OCR implementation and provider selection
- Camera capture logic and ImageCapture high-resolution path
- Native phone-camera fallback
- File upload flow
- Extracted-field mapping
- Check-in workflow
- Guest/document persistence
- Authentication / authorization / RLS
- Database schema / migrations
- Edge Functions
- Notifications and sound
- All previously accepted UI outside the scanner / simple ID capture surface
- Production

## Release boundary

REV57 is staging-only. Production remains blocked until browser acceptance of this scanner polish, after which the controlled production rollout package must be regenerated against the accepted REV57 HEAD.
