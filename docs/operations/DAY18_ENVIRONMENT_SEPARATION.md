# StayQR Day 18 — Environment Separation

## Locked environments

StayQR uses three explicit application labels:

| Environment | Purpose | Supabase project | Netlify context |
|---|---|---|---|
| `development` | Local engineering only | Local or dedicated development project | Local/Vite |
| `staging` | Destructive validation, restore drill and Deploy Preview | Dedicated staging/restore project | Deploy Preview and branch deploy |
| `production` | Live hotel operations | Production project only | Production deploy |

The staging and production Supabase URLs must never be identical.

## Browser-safe variables

Only these public Vite values belong in the browser build:

```text
VITE_SUPABASE_URL
VITE_SUPABASE_ANON_KEY
VITE_APP_ENV
VITE_APP_RELEASE
```

The anonymous/publishable key is acceptable only while RLS and trusted RPC
boundaries remain enforced.

Never expose any variable whose browser name contains:

```text
SERVICE_ROLE
SECRET
PRIVATE
DATABASE_URL
```

## Netlify configuration

Set values in the Netlify UI with Build scope rather than committing real
values to Git.

Production context:

```text
VITE_APP_ENV=production
VITE_APP_RELEASE=<commit SHA or release tag>
VITE_SUPABASE_URL=<production project URL>
VITE_SUPABASE_ANON_KEY=<production public key>
```

Deploy Preview and branch-deploy contexts:

```text
VITE_APP_ENV=staging
VITE_APP_RELEASE=<deploy commit SHA>
VITE_SUPABASE_URL=<staging project URL>
VITE_SUPABASE_ANON_KEY=<staging public key>
```

## Guard

Run:

```powershell
npm run env:day18
```

For staging/production, the guard rejects placeholders, non-HTTPS hosted
URLs, untraceable releases, privileged browser-variable names and reuse of
the same Supabase project when comparison URLs are supplied.

## Destructive-test rule

Backup restore, refund, deletion and rate-limit stress tests must run against
staging or a disposable restore target. They must not run first against
production.
