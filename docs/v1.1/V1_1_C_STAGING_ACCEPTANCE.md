# V1.1-C Consolidated Staging Browser Acceptance

Use StayQR Staging only, local app on 127.0.0.1:5173, controlled hotel **20E Test Hotel**.

Complete this as one block:

1. **Platform Hub / Group View** — verify the authorized-property count is at least 2, open the second authorized property with **Switch to property**, then return to 20E Test Hotel. No unauthorized property must appear.
2. **WhatsApp Resilience** — save: provider channel OFF, transactional ON, marketing OFF, failure threshold 3, cooldown 15. The page must show LOCKED/manual-safe unless a real active provider and approved template exist.
3. **Consent + campaign** — Guests → Communications: for `V11B Acceptance Fix 300826`, record Transactional consent and prepare one manual campaign named `V11C Controlled Transactional 300826` with only that guest. Do not invoke Meta Cloud.
4. **Opt-out proof** — for `V11B Ops Guest 300826` (or another existing controlled guest), record Marketing consent, then revoke it / Opt out. Confirm the guest becomes suppressed.
5. **Regression** — Platform Hub, Guests Communications, Super Admin login boundary (if available), Revenue Growth, Ops Automation, Reports, Folio & Settlement all load without visible regression. Production is not used.

Then run `V1_1_C_FINAL_BROWSER_ACCEPTANCE_103_READ_ONLY.sql` in StayQR Staging. Required: **24/24 TRUE**.
