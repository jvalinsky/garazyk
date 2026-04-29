# Admin UI Client Action Determinism (2026-04-18)

## Scope
- Ensure delegated `data-action` handlers resolve the clicked control deterministically.
- Ensure HTMX requests include admin auth headers so action requests are authorized.

## Decisions
- Delegated handlers now pass the resolved button element (`closest('[data-action]')`) directly into action functions.
- HTMX `configRequest` hook injects `Authorization` and `X-Admin-Token` from session storage.

## Actions Implemented
- Patched `admin-chat.js`, `admin-ozone.js`, `admin-security.js` to stop using `event.currentTarget` in delegated listeners.
- Added action error handling for Ozone delete operations.
- Patched templates with unsupported parent-loop references and normalized action data attributes.

## Outcome
- Client-side admin actions consistently execute against the intended control and carry auth context for backend processing.

## Linked Deciduous Nodes
- `482` goal: Make admin client-side actions deterministic and authenticated
- `483` decision: How should delegated admin action handlers resolve click targets?
- `485` option (chosen): Pass the resolved `[data-action]` element directly into action handlers
- `484` option (rejected): Use `event.currentTarget` from delegated document click handlers
- `486` action: Patch delegated action listeners in chat/ozone/security modules
- `487` action: Inject admin auth headers for all HTMX requests
- `488` outcome: Admin data-action controls execute the intended operation with auth context
