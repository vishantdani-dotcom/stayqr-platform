# StayQR Commercial-Ready Provider Configuration REV1

Production remains OFF until each provider is approved, configured, proven in staging and explicitly authorized for rollout.

## 1. Cashfree recurring / AutoPay

Current product behavior is fail-closed: owner actions are recorded, but AutoPay never shows active until Cashfree and the mandate confirm it.

Provider-side work:

1. In the existing Cashfree merchant account, request/confirm access to Subscriptions / recurring payments and UPI AutoPay mandates.
2. Confirm sandbox access first, then production access.
3. Register the staging webhook endpoint ending in `/functions/v1/cashfree-subscription-webhook` for subscription, authorization and payment lifecycle events.
4. Keep `CASHFREE_SUBSCRIPTIONS_ENABLED=false` until the staging mandate lifecycle passes.
5. Store `CASHFREE_CLIENT_ID`, `CASHFREE_CLIENT_SECRET`, `CASHFREE_MODE`, and `CASHFREE_SUBSCRIPTIONS_API_VERSION=2026-01-01` as Supabase Edge Function secrets. Never place secrets in Vite variables or the database.
6. Mark `cashfree_recurring` active using `set_commercial_provider_readiness` only after Cashfree supplies a merchant/capability reference and staging evidence.
7. Set `CASHFREE_SUBSCRIPTIONS_ENABLED=true` in staging only, deploy `cashfree-recurring` and `cashfree-subscription-webhook`, then complete create → authorization → charge → webhook → retry/cancel acceptance.

Official references:

- https://www.cashfree.com/docs/api-reference/payments/latest/subscription/overview
- https://www.cashfree.com/docs/api-reference/payments/latest/subscription/create-subscription
- https://www.cashfree.com/docs/api-reference/payments/latest/subscription/manage-subscription
- https://www.cashfree.com/docs/api-reference/payments/latest/subscription/raise-a-charge-or-create-an-auth

## 2. Meta WhatsApp Cloud API

Current product behavior remains fail-closed: consent, suppression, published provider-approved templates, hotel sender status, circuit health, Edge credentials and `WHATSAPP_AUTOMATION_ENABLED=true` must all pass before a message can send.

Provider-side work:

1. Create the StayQR Meta Business Portfolio using the proprietorship's legal business details.
2. Create or connect the WhatsApp Business Account and add the dedicated StayQR number.
3. Complete business/number verification when Meta requests it.
4. Record the WABA ID and phone-number ID. Use a system-user/permanent token strategy appropriate for production; never store the token in the database.
5. Create transactional templates first, submit them to Meta and wait for Approved status.
6. Store `WHATSAPP_ACCESS_TOKEN` and `WHATSAPP_GRAPH_API_VERSION` as Edge Function secrets.
7. Mark platform `meta_whatsapp` readiness active with evidence, then configure the hotel sender through `configure_meta_whatsapp_provider`.
8. Reconcile template IDs/statuses. Keep `WHATSAPP_AUTOMATION_ENABLED=false` until a staging template send and status webhook pass.
9. Configure the same dedicated number in `configure_stayqr_support_profile` for the 24×7 support link.

Official reference:

- https://developers.facebook.com/docs/whatsapp/cloud-api/get-started

## 3. Formal UIDAI online Aadhaar authentication

StayQR does not call an unofficial Aadhaar API and never fakes authentication. Offline XML and Secure QR remain available while formal onboarding is pending.

Provider/legal work for the StayQR proprietorship:

1. Select an authorized AUA/KUA/Sub-AUA route and confirm the exact permitted hospitality identity-verification purpose, consent text, retention rules and authentication modalities.
2. Complete the provider/UIDAI application, agreements, security assessment and production approval required for that route.
3. Obtain the provider's staging contract, endpoint, token/certificate strategy and transaction evidence requirements.
4. Configure `UIDAI_AUTH_PROVIDER`, `UIDAI_AUTH_PROVIDER_URL`, `UIDAI_AUTH_PROVIDER_TOKEN` and a strong `UIDAI_HASH_PEPPER` as Edge Function secrets.
5. Mark `uidai_online` active only with the authorized-route reference and evidence.
6. Set `UIDAI_ONLINE_AUTH_ENABLED=true` in staging and deploy `uidai-online-auth`.
7. Prove consent → OTP request → OTP verification → masked/hash-only evidence → failure/expiry behavior. Verify the database contains no Aadhaar number, OTP, PID or biometrics.
8. Production activation still requires explicit StayQR rollout authorization.

Official references:

- https://uidai.gov.in/en/authentication-partners
- https://uidai.gov.in/en/authentication-requesting-agency

## 4. 24×7 StayQR support

- Primary channel: the same dedicated StayQR WhatsApp number.
- After-hours owner: Founder.
- Critical incidents can be raised 24×7.
- Support Guard remains reason-bound, audited, time-limited and never becomes silent impersonation.
- Configure the real E.164 WhatsApp number only after it is confirmed; until then the UI truthfully shows configuration pending.
