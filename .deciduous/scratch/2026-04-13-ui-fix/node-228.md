# Node 228 Scratch

## Results
- Implemented frontend profile wiring in Cappuccino shell:
  - fetch `/ui/profile` during startup
  - normalize/apply profile (`pds`, `relay`, `plc`, `appview`, `full`)
  - build only service-specific tabs/controllers/menus for active profile
  - derive endpoint groups from profile payload instead of hardcoded multi-service assumptions
- Added debug overrides:
  - `?ui_profile=<profile>`
  - `?profile=<profile>`
  - `?full=1|true`
- Hardened API client fallback when profile omits unrelated endpoint groups.

## Issues
- Browser-interaction validation is blocked by Browser MCP runtime path issue (`#222`), so visual interaction checks are pending.

## Useful Info
- Backend profile payloads for all services are returning expected values, so frontend bootstrap inputs are present and correct.
- `full` profile remains available for intentional multi-service debugging.

## Evidence (commands/screenshots/logs)
- Edited files:
  - `Garazyk/Sources/App/CappuccinoUI/AppController.j`
  - `Garazyk/Sources/App/CappuccinoUI/UIAPIClient.j`
- HTTP profile probes:
  - `curl -sS http://127.0.0.1:3583/ui/profile` -> `serviceProfile=pds`
  - `curl -sS http://127.0.0.1:3584/ui/profile` -> `serviceProfile=relay`
  - `curl -sS http://127.0.0.1:3582/ui/profile` -> `serviceProfile=plc`
  - `curl -sS http://127.0.0.1:4200/ui/profile` -> `serviceProfile=appview`

## Next
- Completed from implementation standpoint; rerun Browser MCP UI interactions once node `#222` blocker is removed.
