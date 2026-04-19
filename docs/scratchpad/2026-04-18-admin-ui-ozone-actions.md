# Admin UI Ozone Actions (2026-04-18)

## Scope
- Complete Ozone CRUD/action controls for team, sets, templates, and verification.
- Add Safe Links, scheduled moderation actions, and config/setting controls in admin UI.

## Decisions
- Implement Ozone mutating actions via existing XRPC endpoints with authenticated JSON requests from the admin client.

## Actions Implemented
- Added Ozone wrapper/list partials for verification, safe links, scheduled actions, and config.
- Implemented client-side action handlers for team/set/template CRUD, verification grant/revoke, safe-link add/update/remove, scheduled create/cancel, and config/settings updates.

## Outcome
- Ozone admin UI now exposes end-to-end operational controls for core moderation workflows.

## Linked Deciduous Nodes
- `496` goal: Complete Ozone admin operational controls in UI
- `497` decision: How should Ozone mutating controls be executed from Admin UI?
- `498` option (chosen): Use direct authenticated JSON calls to existing tools.ozone endpoints
- `499` option (rejected): Add dedicated admin wrapper endpoints for every Ozone action first
- `500` action: Add Ozone partial wrappers and list partials for verification/safelinks/scheduled/config
- `501` action: Implement Ozone CRUD/action handlers in admin-ozone.js
- `502` action: Expose new Ozone pages in sidebar and route coverage
- `503` outcome: Ozone admin UI now supports core moderation operations end-to-end
