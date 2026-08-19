# StayQR v1.1 — Batch B Browser Acceptance Fix REV1

## Scope

This patch fixes the browser-acceptance defect found on the Netlify branch deploy for Batch B:

- **Operations Centre** now opens the existing Support workspace.
- **Report an issue** deep-links to Support and automatically opens a create-ticket form.
- The form uses the existing authenticated `create_support_ticket` RPC through `createSupportTicket(...)`.
- No new database objects, migrations, RLS rules, or production changes are introduced.
- Published StayQR support hours remain **09:00–19:00 IST, Monday–Saturday**.

## Files

- `src/App.jsx`
- `src/pages/dashboard/Dashboard.jsx`
- `src/pages/operationscenter/OperationsCenter.jsx`
- `src/pages/operationscenter/OperationsCenter.css`
- `scripts/validate-postlaunch-batch2-browserfix.mjs`

## Acceptance

Run:

```powershell
node scripts/validate-postlaunch-batch2-browserfix.mjs
npm run test:postlaunch-batch2
npm run lint
npm run build
git diff --check
```

Expected:

- Browser-fix source gate: `PASS (9/9)`
- Batch B source gate: `PASS (41/41)`
- ESLint: `0 errors, 7 inherited warnings`
- Build: PASS
- `git diff --check`: no actual errors

Then push the feature branch and wait for a new **Netlify Branch Deploy**. Do **not** use Publish deploy.
