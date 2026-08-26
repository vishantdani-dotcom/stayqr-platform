# StayQR Batch B — Guest Directory Action Bar UI Fix REV1

## Issue
At desktop widths, the Guest Directory search input used `width: 100%` inside a
flex row shared with Export CSV and Refresh directory. This caused the action
buttons to compress and clip.

## Fix
- Give the search field flexible width independent of the buttons.
- Give Export CSV and Refresh directory stable readable widths.
- Stack the toolbar earlier on narrower desktop/tablet layouts.
- Make all controls full-width on mobile.
- Preserve the existing CSV export logic and privacy notice.

## Database / API impact
None.
