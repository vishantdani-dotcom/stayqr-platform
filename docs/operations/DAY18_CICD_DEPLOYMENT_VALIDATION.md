# StayQR Day 18 — CI/CD and Deployment Validation

## GitHub Actions

The workflow `.github/workflows/day18-production-validation.yml` runs on
pull requests, pushes to the Day 18 branch and manual dispatch.

The validation job:

1. checks out source with read-only repository permission;
2. uses Node.js 22;
3. installs the exact lockfile with `npm ci`;
4. runs all accepted Day 17/18 source, build, monitoring, performance, lint,
   environment and infrastructure gates;
5. uploads the built `dist` directory and infrastructure evidence as a
   short-retention artifact.

The workflow does not receive a service-role key, database password or
production Supabase secret.

## Netlify deployment

Netlify Git integration remains responsible for Deploy Preview and branch
deployment creation. `netlify.toml` is authoritative for build, publish,
headers, rewrites and code-based rate limits.

Set real environment values in Netlify UI per context. Do not place them in
`netlify.toml` or Git.

## Manual live-smoke job

After Netlify creates a Deploy Preview:

1. copy the HTTPS preview URL;
2. open GitHub Actions;
3. run **Day 18 Production Validation** manually;
4. provide `deploy_url`;
5. confirm both jobs are green.

The live-smoke job validates:

- HTTPS;
- app shell;
- `/app` deep-link rewrite;
- built JS reachability;
- immutable asset cache;
- CSP, HSTS, referrer, frame, MIME and permissions headers.

## Required Day 18 deployment evidence

Keep:

- green GitHub Actions run URL/screenshot;
- uploaded artifact name and commit SHA;
- Netlify Deploy Preview URL;
- Netlify post-processing log showing valid rate-limit rules;
- live-smoke output;
- final local/remote commit hash match;
- clean working tree.

A source-only pass is not the final Day 18 exit gate. The restore drill,
Netlify preview and live smoke must also pass.
