# StayQR Commercial-Ready Browser Acceptance REV1

Run this once on the Commercial-Ready staging deployment after the consolidated staging SQL returns **52/52 TRUE**.

## A. Hotel Owner Billing Portal — 12 checks

1. Sign in as a Hotel Owner and select Hotel Apex Stay Inn.
2. Open **Billing & AutoPay** from the sidebar.
3. Current plan, subscription status, billing cycle and renewal date show real database values.
4. Payment/request history loads without cross-hotel rows.
5. Monthly and yearly plan prices render correctly.
6. Current plan is disabled and labelled Current plan.
7. Upgrade/downgrade creates exactly one owner request.
8. Refresh does not duplicate the request.
9. With Cashfree recurring pending, **Set up AutoPay** records the request and displays provider activation pending; it must not display AutoPay active.
10. A cancellation reason shorter than 3 characters is rejected.
11. Valid cancellation schedules cancellation at period end and shows that state after refresh.
12. **Keep subscription** removes the scheduled cancellation without cancelling the active paid period.

## B. Dashboard Activation Score — 10 checks

1. Activation Score appears directly below the hotel overview.
2. Percentage equals the sum of completed weighted items.
3. Total weight equals 100.
4. Hotel Profile action opens Hotel Profile.
5. Rooms action opens Rooms.
6. Staff action opens Staff.
7. Guest Guide action opens Guest Guide Builder.
8. QR action opens QR Guides.
9. Billing action opens Billing & AutoPay.
10. Refreshing the dashboard recalculates the score from database state.

## C. Cashfree recurring / AutoPay — 10 checks

1. Provider pending state is truthful with safety flag OFF.
2. After approved sandbox setup, create a mandate from the owner portal.
3. Owner identity/contact validation rejects incomplete customer data.
4. Cashfree authorization is completed by the owner.
5. Webhook signature verification rejects an unsigned request.
6. Valid authorization webhook changes mandate/AutoPay status once.
7. Successful charge records exact-once recurring evidence and next charge state.
8. Failed charge records failure code/message and past-due state.
9. Retry records a separate attempt without duplicating the provider event.
10. Cancel/reactivate stays consistent in Cashfree, StayQR subscription and owner history.

## D. Meta WhatsApp + 24×7 support — 8 checks

1. Platform Hub shows provider activation incomplete before Meta configuration.
2. Enabling the automated channel is rejected without active sender + approved template.
3. Consent and active suppression are both rechecked before every send.
4. `WHATSAPP_AUTOMATION_ENABLED=false` blocks sends even when UI settings are enabled.
5. Approved staging template send returns a provider message ID.
6. Status webhook updates delivery evidence.
7. Repeated provider failures open the hotel circuit breaker.
8. Dashboard and Billing show 24×7 support; WhatsApp link appears only after the real number is configured.

## E. UIDAI online + offline fallback — 10 checks

1. Online consent is separate from offline consent.
2. Online authentication is blocked before consent.
3. With provider pending, request returns provider activation pending and never success.
4. Offline XML verification still works.
5. Secure QR evidence still works.
6. After authorized staging setup, OTP request returns a request ID and clears Aadhaar from the browser form.
7. Invalid OTP records no verified evidence.
8. Valid OTP records verified, masked/hash-only evidence.
9. Database inspection confirms no Aadhaar number, OTP, PID or biometrics are stored.
10. Cross-hotel access to UIDAI request evidence is denied.

## Required result

- 50/50 browser checks confirmed.
- Existing V1.1 A/B/C regression suite passes.
- P0/P1 = 0/0.
- Production changed = NO.
