StayQR Day 10 — Guest History Frontend REV1

Install only after Migration 026 REV1 and the atomic walk-in frontend are accepted.

This patch keeps the existing Active Stays view unchanged and adds:
- Guest Directory & History tab
- Searchable canonical guest profiles
- Repeat-guest badge and stay counts
- Full guest identity/address profile
- Current and historical room stays
- Companion history
- Stay-purpose and travel route details
- Private guest notes
- Guest preferences
- Authorized private KYC metadata list

No service-role key, fixed hotel UUID, direct guest-session insert or direct payment insert is added.

After extraction:
1. cd Frontend
2. npm run check
3. npm run dev
4. Open Guests → Guest Directory & History
