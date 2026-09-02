# Pilot Manual Billing REV1

## Scope

This patch supports the first one or two pilot hotels while Cashfree production onboarding is deferred. Production remains untouched. The patch is intended for local development and the StayQR staging project only.

## Operating rule

Hotel access must be activated or renewed only after StayQR has confirmed receipt of the offline payment. The Super Admin records:

- the hotel and plan;
- the amount and paid subscription period;
- UPI/PhonePe, bank transfer, cash or another verified method;
- the provider transaction reference or a unique StayQR cash receipt number;
- the payment time and an audit note.

The database then records the immutable payment evidence and activates or renews the subscription in the same transaction. A duplicate submission key or payment reference cannot create a second activation.

## Hotel-facing behavior

The owner Billing screen truthfully displays manual/offline pilot billing, the paid-through date and recent receipt/reference evidence. AutoPay stays unavailable while Cashfree provider readiness is pending.

## Super Admin workflow

1. Confirm that the payment is visible in the authorized collection account or that a numbered cash receipt has been issued.
2. Open **Hotels & subscriptions**, choose the hotel and click **Manage**.
3. Select **Record offline payment & activate / renew**.
4. Verify plan, amount, dates, payment method and unique reference.
5. Enter an audit note and submit once.
6. Confirm the new row under **Billing ledger → Confirmed offline payments** and the hotel's active paid-through date.

Do not treat a screenshot or customer claim alone as settled money. Retain the bank/UPI confirmation or signed cash receipt outside StayQR according to the business's accounting process.

## Deferred work

Cashfree production KYC, settlement bank verification, production API credentials, webhook configuration and a live low-value end-to-end payment remain deferred. Those steps must be completed before enabling `CASHFREE_SUBSCRIPTIONS_ENABLED=true` in any production environment.
