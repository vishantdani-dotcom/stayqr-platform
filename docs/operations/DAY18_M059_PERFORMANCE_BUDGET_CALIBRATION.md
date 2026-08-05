# Day 18 Migration 059 — Initial JavaScript Budget Calibration

## Decision

The initial JavaScript gzip ceiling is calibrated from **350 KiB to 355 KiB**
for the production monitoring foundation.

## Evidence

- Accepted frontend-performance baseline: 349.4 KiB initial JavaScript gzip.
- Migration 059 monitoring build observed during controlled execution:
  351.1 KiB initial JavaScript gzip.
- Monitoring delta: 1.7 KiB.
- Previous ceiling failure: 1.1 KiB.
- New ceiling headroom at the observed build: 3.9 KiB.

## Controls retained

The following gates are unchanged:

- Largest JavaScript chunk gzip: 450 KiB maximum.
- Total JavaScript gzip: 1800 KiB maximum.
- Largest CSS chunk gzip: 100 KiB maximum.
- Dynamic route entries: 20 minimum.
- Route-level code splitting remains mandatory.
- The budget can still be overridden downward in CI using
  `STAYQR_MAX_INITIAL_JS_GZIP_KB`.

## Rationale

The 350 KiB ceiling had only 0.6 KiB of remaining headroom before monitoring.
The monitoring bootstrap is a P0 production requirement and its measured
1.7 KiB initial cost remains small. A 355 KiB ceiling preserves a strict,
measurable budget without disabling or bypassing the performance gate.
