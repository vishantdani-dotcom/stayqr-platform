# StayQR V1.1 - Final Release Decision

Decision: GO FOR CONTROLLED PRODUCTION RELEASE

The V1.1-A, V1.1-B and V1.1-C locked release chain has passed final consolidated source and evidence validation.

This decision means the V1.1 release candidate is technically accepted for a controlled production rollout.

It does NOT itself deploy V1.1 to production.

## Release constraints

1. Production remains unchanged until explicit production authorization is given.
2. A production rollout must use the final immutable V1.1 release tag created by this lock.
3. Rollout must include pre-deploy production health/release identity verification.
4. Database migrations must be applied in repository order with production-only verification.
5. A controlled Hotel Apex canary/regression must verify core reservation, folio, guest access and new V1.1 navigation.
6. WhatsApp Meta Cloud automated sending stays disabled until real sender credentials, approved templates and explicit activation approval are available.
7. Any P0/P1 regression stops rollout and triggers rollback/recovery.

Final release status: READY FOR CONTROLLED PRODUCTION RELEASE.
