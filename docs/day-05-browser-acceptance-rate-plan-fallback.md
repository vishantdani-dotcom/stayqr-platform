# Day 5 browser acceptance — rate-plan fallback correction

The first version of audit 022 required an existing active rate plan with a positive base rate. The live selected property has rooms and active room types, but its matching rate plan is absent, inactive, or has a zero base rate. This caused the deterministic seed to stop before creating acceptance records.

The corrected audit now:

- selects an active hotel, room, and room type independently from pricing;
- reuses an existing positive active rate plan when one exists;
- otherwise creates one isolated temporary rate plan with code prefix `D5QA-` and a ₹1,500 test rate;
- records whether the rate plan was temporary in the private acceptance state;
- removes the temporary rate plan through audit 023;
- verifies no temporary acceptance rate plan remains through audit 024.

The failed original seed call was transactional, so no partial acceptance data was written. Replace the complete frontend source and rerun audit 022 directly.
