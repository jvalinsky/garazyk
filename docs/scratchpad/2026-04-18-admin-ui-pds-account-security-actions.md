# Admin UI PDS Account + Security Actions (2026-04-18)

## Scope
- Complete account/security admin actions for HTMX and API parity.
- Ensure mutating admin actions accept both JSON and form-encoded payloads.

## Decisions
- User account actions now invoke existing `com.atproto.admin.*` XRPC methods rather than duplicating account mutation logic.
- Bulk actions and invite operations parse both JSON and form-encoded payloads using shared parser helpers.

## Actions Implemented
- Updated user edit-email/edit-handle/reset-password/send-email PUT flows to parse form data.
- Wired account mutation and send-email flows to XRPC dispatcher-backed admin endpoints.
- Fixed security session revocation data integrity by preserving full token and exposing display prefix separately.
- Fixed security list context rendering path for template loops.

## Outcome
- PDS admin mutating actions work end-to-end with HTMX form submissions and existing backend XRPC handlers.

## Linked Deciduous Nodes
- `475` goal: Complete PDS account and security admin actions end-to-end
- `476` decision: Should account action handlers mutate DB directly or call existing admin XRPC methods?
- `477` option (chosen): Dispatch account actions through existing `com.atproto.admin` XRPC methods
- `481` option (rejected): Keep direct database writes inside `PDSAdminHandler`
- `478` action: Support form-encoded payload parsing for invites, account actions, and bulk operations
- `479` action: Wire account edit/reset/send-email UI actions to admin XRPC dispatcher
- `480` outcome: PDS account and security actions execute correctly from HTMX admin UI
