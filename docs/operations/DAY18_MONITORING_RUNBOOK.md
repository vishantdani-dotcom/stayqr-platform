# StayQR Day 18 — Monitoring and Operational Diagnostics Runbook

## Scope

Migration 059 creates the production monitoring foundation required by the locked Day 18 roadmap:

- tenant-scoped structured operational error events;
- frontend React/runtime failure capture;
- backend/Edge Function writer contract;
- request, release, route and hotel context;
- server-side redaction and fixed context allowlisting;
- repeated-incident deduplication with occurrence counts;
- manager-only health snapshots, searchable diagnostics and incident status actions;
- direct-table and anonymous-access closure.

This package does not configure an external monitoring vendor and does not add a service-role key to the browser.

## Privacy boundary

Never log raw guest tokens, invoice verification tokens, JWTs, passwords, cookies, authorization headers, email addresses, phone numbers, payment payloads, KYC documents or arbitrary application state.

The browser sanitizes before transport. Migration 059 sanitizes again and stores only this context allowlist:

- online state;
- visibility state;
- viewport;
- stack-frame count;
- network type;
- retryable flag.

Raw JavaScript stacks are not persisted.

## Frontend writer

The browser uses:

```js
await supabase.rpc('report_operational_error', {
  p_hotel_id: hotelId,
  p_payload: {
    source: 'client',
    environment: 'production',
    severity: 'error',
    event_name: 'reservation.load_failed',
    error_name: 'PostgrestError',
    error_code: 'PGRST116',
    message: 'Reservation could not be loaded.',
    route: '/app',
    scope: 'reservations',
    component: 'Reservations',
    request_id: crypto.randomUUID(),
    release: 'git-commit-or-release-name',
    context: {
      online: true,
      visibility_state: 'visible',
      viewport: '1440x900',
      stack_frames: 3,
      network_type: '4g',
      retryable: true
    }
  }
})
```

Authenticated callers cannot select a backend source. The database forces their source to `client` and requires hotel access.

## Backend and Edge Function writer

A trusted server using the Supabase service-role client may use the same RPC and select a backend source:

```js
await serviceClient.rpc('report_operational_error', {
  p_hotel_id: hotelId,
  p_payload: {
    source: 'edge_function',
    environment: 'production',
    severity: 'critical',
    event_name: 'cashfree.webhook_failed',
    error_code: 'SIGNATURE_INVALID',
    message: 'Webhook signature validation failed.',
    request_id: requestId,
    release: Deno.env.get('RELEASE_VERSION'),
    context: {
      retryable: false
    }
  }
})
```

The service-role key must remain only in a trusted server or Supabase Edge Function.

## Environment labels

Use these public, non-secret Vite values:

```text
VITE_APP_ENV=development|staging|production
VITE_APP_RELEASE=<Git commit, tag or deployment ID>
```

The Supabase URL and anonymous key remain configured through the existing environment variables.

## Incident workflow

1. Open **Operations & Communications Centre → Diagnostics**.
2. Review health status, unresolved counts, query-health state and delivery failures.
3. Search by incident ID, request ID, error code or sanitized message.
4. **Acknowledge** when an owner has accepted the incident.
5. **Resolve** after the underlying issue is fixed and verified.
6. **Reopen** if the failure recurs or the earlier resolution was incomplete.
7. Use the incident ID and request ID in support notes and deployment evidence.

## Health meanings

- **Healthy** — no unresolved errors, no critical errors, no invalid Day 18 indexes and no failed/retrying deliveries in the last 24 hours.
- **Degraded** — unresolved errors or delivery failures exist, but no current critical condition is detected.
- **Critical** — at least one unresolved critical error exists or a public index is invalid.

## Retention

Migration 059 does not automatically delete incidents. Define the production retention job during the remaining Day 18 infrastructure work. Recommended launch baseline:

- resolved/ignored events: retain 90 days;
- unresolved events: retain until resolved;
- critical release incidents: export to the incident record before deletion.

Do not add an unreviewed cron deletion job directly in production.

## Acceptance evidence

The migration returns a fixed 100-row acceptance result. Export the complete result as CSV without filtering or sorting.

Required result:

```text
100 rows
100 passed
0 failed
```

The migration acceptance inserts a reversible synthetic incident, validates redaction, deduplication, diagnostics, query health and incident status, then removes the synthetic row before completion.

## Rollback posture

The source installer makes no database change.

Migration 059 is additive. A database rollback must first remove frontend calls and operational use, then explicitly drop:

- `public.set_operational_incident_status`;
- `public.get_operational_diagnostics`;
- `public.get_operational_health_snapshot`;
- `public.report_operational_error`;
- private Day 18 sanitization/acceptance helpers;
- `public.operational_error_events`.

Do not drop the table after production logging begins without exporting required incident evidence.
