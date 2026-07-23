# Day 4 room-block status reason validation fix

## Issue
Submitting the browser prompt with a blank value while releasing or cancelling an active room block silently returned. The room block remained safe and active, but the required rejection message was missing.

## Correction
- Distinguish browser-prompt cancellation (`null`) from a submitted blank value.
- Show a visible error notice when a blank reason is submitted.
- Trim and normalise the reason before calling the RPC.
- Enforce the same validation again in the calendar API helper.
- Reject unsupported block status changes.
- Handle structured RPC rejection responses before invalidating and reloading the calendar.

## Expected runtime behaviour
- Pressing **Cancel** in the browser prompt closes it without a message or database change.
- Pressing **OK** with a blank or whitespace-only reason shows: `A reason is required to cancel/release this room block.`
- The room block stays active and unchanged.
- A non-blank reason continues through the server-validated status workflow.
