# StayQR REV58 — Scanner UI Structural Rework Audit

## Why REV57 was not accepted

REV57 improved colours and responsive dimensions, but the browser evidence showed two remaining structural problems:

1. The scanner modal was still rendered inside the application tree. A constrained/transformed mobile ancestor could therefore make `position: fixed` behave like a fixed element inside the narrow app surface rather than the real browser viewport.
2. The alignment frame was positioned relative to the whole scanner stage instead of a preview-only wrapper, so its dashed outline could visually collide with status/instruction rows.
3. The Remove control could still be squeezed by generic/mobile button layout rules.

## REV58 correction

- Render the scanner modal into `document.body` with React `createPortal`.
- Add a dedicated `.document-camera-preview` wrapper around the live `<video>` and scanner frame.
- Scope fullscreen scanner CSS globally to `body > .document-scanner-modal`.
- Use explicit REV54 palette values inside the portal because CSS variables defined on `#root` do not inherit into a body-level portal sibling.
- Keep status/instruction/capture controls outside the camera overlay.
- Give Remove a fixed usable desktop/tablet control size and its own full-width row on narrow phones.
- Preserve the Review required warning badge as a clean no-wrap amber pill.

## Explicitly unchanged

- getUserMedia constraints
- high-resolution ImageCapture still path
- native phone-camera fallback
- torch and zoom behaviour
- crop and rotate behaviour
- OCR provider/logic
- extracted-field mapping
- document persistence
- check-in workflow
- authentication / authorization / RLS
- database / migrations
- Edge Functions
- notifications / sound
- all UI outside this ID scan/upload surface
- production

## Release boundary

REV58 is staging-only. Production rollout remains blocked until the owner approves the two browser screens.
