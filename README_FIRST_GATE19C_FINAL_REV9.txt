StayQR Day 19 — Gate 19C FINAL REV9
====================================

The REV8 screenshot proves the remaining issue is ONLY Audit 078's two
own-tenant Storage positive controls:

  20_hotel_assets_positive_control
  25_guest_documents_positive_control

All cross-tenant Storage attacks passed. The full tenant-table write matrix
passed. The hotel_onboarding breach is blocked.

The failed positive control was invalid because it performed direct SQL
INSERT/UPDATE/DELETE against Supabase-managed storage.objects. Supabase requires
object deletion through the Storage API.

REV9 changes ONLY those positive controls. It keeps every live cross-tenant
Storage attack unchanged and evaluates the exact StayQR own-tenant RLS
path/permission predicates under the authenticated Hotel A owner.

No migration is executed.

RUN:
  cd C:\StayQR_D18_WORK
  powershell -NoProfile -ExecutionPolicy Bypass -File ".\RUN_DAY19_GATE19C_FINAL_REV9.ps1"
