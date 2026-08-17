# StayQR Day 20 — Production Operational Ownership

**Status:** Day 20 launch ownership baseline — 20E-5 locked candidate.
**Primary production/support owner:** Vishant Dani
**Primary support channel:** support@stayqr.in
**Privacy / grievance channel:** vishantdani@gmail.com

## 1. Launch ownership matrix

| Responsibility | Launch owner | Escalation / provider |
|---|---|---|
| Production service ownership | Vishant Dani | — |
| Production monitoring / diagnostics | Vishant Dani | Netlify / Supabase where provider action is required |
| Standard customer support | Vishant Dani | — |
| P0 / P1 incident commander | Vishant Dani | Relevant infrastructure provider where required |
| Security incident escalation | Vishant Dani | Relevant provider / lawful authority where applicable |
| Privacy / data-protection escalation | Vishant Dani | Hotel controller / relevant provider where applicable |
| Production database change approval | Vishant Dani | Supabase where provider action is required |
| Production deployment / rollback approval | Vishant Dani | Netlify where provider action is required |
| Payment-provider escalation | Vishant Dani | Cashfree |
| Financial-integrity escalation | Vishant Dani | Cashfree / relevant bank or provider where required |
| Final launch Go / No-Go owner | Vishant Dani | — |

## 2. Support window

**09:00–19:00 IST, Monday–Saturday**

Requests may be submitted at any time. Critical reports outside staffed hours are handled on a reasonable-efforts basis unless a separately signed agreement provides enhanced coverage.

Acknowledgement targets: P0 within 2 staffed-support hours; P1 within 4 staffed-support hours; P2 within 1 business day; P3 within 2 business days. These are acknowledgement targets, not guaranteed resolution times.

## 3. Provider baseline

- **Cashfree** — currently proven active payment provider.
- **Supabase** — production backend/auth/database/storage infrastructure provider.
- **Netlify** — production frontend hosting/CDN/deployment provider.

Historical/provider-neutral references are not evidence that another provider is active.

## 4. Escalation rule

Escalate immediately to the launch owner for P0/P1 incidents, suspected tenant-isolation failures, material security incidents, material data-loss risk, financial-integrity risk, suspected personal-data breach, or rollback decisions.

Until an explicit owner is delegated and recorded, **Vishant Dani remains the accountable launch owner for every responsibility above**.
