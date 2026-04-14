# Node 226 Scratch

## Results
- Added AppView service UI routes:
  - `GET /ui`
  - `GET /ui/*`
- Bound AppView runtime to profile `appview` in shared Cappuccino handler.
- Kept AppView root info JSON and `/admin/backfill/*` behavior unchanged.
- Updated build linkage (`ATProtoRuntime`) where needed for direct handler usage.

## Issues
- None found in AppView route precedence smoke.

## Useful Info
- Admin backfill endpoint remains auth-protected; `401` is expected for unauthenticated probes.

## Evidence (commands/screenshots/logs)
- Edited files:
  - `Garazyk/Sources/AppView/Server/AppViewRuntime.m`
  - `CMakeLists.txt`
- Smoke:
  - `curl -sS -w '%{http_code}' http://127.0.0.1:4200/ui` -> `200`
  - `curl -sS http://127.0.0.1:4200/ui/profile` -> `serviceProfile=appview`
  - `curl -sS -w '%{http_code}' http://127.0.0.1:4200/admin/backfill/status` -> `401`
  - `curl -sS http://127.0.0.1:4200/` -> `{"service":"syrena","type":"app.bsky.appview",...}`

## Next
- Completed; no follow-up for this node.
