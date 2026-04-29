# Admin UI Chat Actions (2026-04-18)

## Scope
- Complete chat moderation/action flows in Admin UI for existing chat endpoints.
- Ensure chat partial routes resolve through `AdminPartialHandler` for wrapper + detail/list flows.

## Decisions
- Use incremental action wiring on top of existing chat list/detail partials instead of introducing a new bespoke chat admin backend.

## Actions Implemented
- Added message-level delete action wiring in chat message audit view.
- Added direct wrapper routing for chat groups and invite-links through partial templates.

## Outcome
- Chat admin pages now include deterministic action wiring for key moderation actions.

## Linked Deciduous Nodes
- `489` goal: Complete chat admin action flows in Admin UI
- `492` decision: How should chat moderation actions be wired in admin UI?
- `490` option (chosen): Wire chat actions directly to existing chat.bsky endpoints
- `491` option (rejected): Introduce new admin-specific chat proxy endpoints first
- `493` action: Route chat groups and invite-links through AdminPartialHandler
- `495` action: Add chat message delete moderation action in audit view
- `494` outcome: Chat admin action flow coverage completed for this slice
