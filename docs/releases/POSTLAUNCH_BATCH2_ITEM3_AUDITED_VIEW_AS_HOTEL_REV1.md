# Post-launch Batch B — Item 3 Audited View as Hotel REV1

- Platform Admin now starts in platform-only Super Admin scope with no automatically selected hotel.
- Ordinary HotelSwitcher remains unavailable to the Platform Admin account.
- Hotel context is activated only when a non-expired `support_access_sessions` row exists for that Platform Admin and hotel.
- Starting **View as Hotel** enters the selected hotel immediately through the audited session.
- Active sessions can be resumed from Super Admin > Support.
- Session expiry clears hotel context and returns the user to platform scope.
- Hotel support mode has explicit **Return to Super Admin** controls.
- Existing server-authoritative `start_safe_support_access` / `end_safe_support_access` audit trail is preserved.
- No production configuration or database mutation is included in this frontend authorization/navigation patch.
