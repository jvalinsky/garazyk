# Node 225 Scratch

## Results
- Cut over PDS default UI routing:
  - removed default wildcard `GET /*` UI catch-all path
  - added explicit `GET /` UI entry route (served by Cappuccino handler)
- Registered PDS `/ui` routes using explicit `serviceProfile:@"pds"` through route pack.
- Preserved existing PDS XRPC/API behavior.

## Issues
- None observed for PDS route collisions after cutover.

## Useful Info
- Route precedence now avoids wildcard interference with non-UI API paths.

## Evidence (commands/screenshots/logs)
- Edited files:
  - `Garazyk/Sources/Network/PDSHttpServerBuilder.m`
  - `Garazyk/Sources/Network/PDSHttpCappuccinoUIRoutePack.m`
- Regression probes:
  - `curl -sS -w '%{http_code}' http://127.0.0.1:3583/` -> `200` (UI shell)
  - `curl -sS -w '%{http_code}' http://127.0.0.1:3583/not-real` -> `404`
  - `curl -sS -w '%{http_code}' http://127.0.0.1:3583/xrpc/com.atproto.server.describeServer` -> `200`
  - `curl -sS http://127.0.0.1:3583/ui/profile` -> `serviceProfile=pds`

## Next
- Completed; no follow-up for this node.
