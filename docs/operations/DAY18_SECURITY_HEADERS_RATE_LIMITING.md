# StayQR Day 18 — Security Headers and Rate Limiting

## Delivery-layer controls

`netlify.toml` adds:

- Content Security Policy;
- HSTS;
- clickjacking protection;
- MIME sniffing protection;
- referrer restrictions;
- permissions restrictions;
- long-lived immutable caching for hashed assets;
- revalidation for the SPA document;
- SPA deep-link rewrites;
- code-based request ceilings.

## Rate-limit rules

Two code-based Netlify rules are defined:

| Path | Limit | Window | Aggregation |
|---|---:|---:|---|
| `/guest/*` | 120 | 60 seconds | IP and domain |
| `/*` | 600 | 60 seconds | IP and domain |

Requests above the ceiling receive the platform's default `429` response.

These limits protect Netlify-delivered paths. They do not magically protect
browser requests sent directly to Supabase. Direct public/anonymous database
or Edge Function operations still require RLS, trusted RPC validation,
idempotency and, where abuse risk remains, a separately reviewed Supabase
rate-limit control.

## Content Security Policy

The production policy blocks objects, frames, foreign form actions and
foreign scripts. It permits:

- same-origin JavaScript;
- inline CSS required by the current application;
- HTTPS images;
- Supabase HTTPS and realtime WebSocket connections;
- same-origin/blob workers.

`unsafe-eval` is prohibited.

## Deployment evidence

Netlify validates code-based rate-limit rules during deploy post-processing.
An invalid rule may not fail the whole deploy, so the deploy log must be
checked explicitly for successful rate-limit-rule validation.

After deployment run:

```powershell
$env:STAYQR_DEPLOY_URL = "https://<deploy-preview>.netlify.app"
node .\scripts\day18-live-deploy-smoke.mjs
```

The smoke validates the SPA shell, deep-link rewrite, immutable asset cache
and required response headers. It does not intentionally flood the site.
