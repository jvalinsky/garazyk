# Admin UI PLC + Sync Operator Controls (2026-04-18)

## Scope
- Add PLC signing/submission flow in Admin UI.
- Add operator sync controls for host/repo inspection and crawl/update triggering.

## Decisions
- Use explicit operator-triggered controls with immediate JSON feedback instead of hidden background automation.

## Actions Implemented
- Added PLC operations partial (`request` -> `sign` -> `submit`) and client handlers.
- Added sync operator controls page for list hosts, host status, repo status, crawl request, and notify update.
- Added sidebar and route coverage for new PLC/relay control pages.

## Outcome
- Admin operators can execute PLC and sync maintenance actions directly from the UI.

## Linked Deciduous Nodes
- `504` goal: Add PLC signing flow and sync operator controls to Admin UI
- `505` decision: How should PLC and sync controls present operator feedback?
- `506` option (chosen): Provide explicit operator-triggered controls with immediate JSON output
- `507` option (rejected): Run controls implicitly in background without surfaced payloads
- `508` action: Add PLC operations page and client handlers for request/sign/submit
- `509` action: Add sync operator controls page and client handlers
- `510` action: Extend admin routes/sidebar for PLC operations and relay operators
- `511` outcome: PLC and sync operator controls are available in Admin UI
