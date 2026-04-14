# Node 224 Scratch

## Results
- Added Relay service UI routes:
  - `GET /ui`
  - `GET /ui/*`
- Bound Relay runtime to service profile `relay` in shared Cappuccino handler.
- Kept Relay root info JSON and existing relay API endpoints unchanged.

## Issues
- None observed for route precedence in Relay.

## Useful Info
- Relay health endpoint still responds on same API namespace (`/api/relay/health`).

## Evidence (commands/screenshots/logs)
- Edited file:
  - `Garazyk/Binaries/zuk/main.m`
- Smoke:
  - `curl -sS -o /tmp/relay_ui.html -w '%{http_code}' http://127.0.0.1:3584/ui` -> `200`
  - `curl -sS http://127.0.0.1:3584/ui/profile` -> `serviceProfile=relay`
  - `curl -sS -w '%{http_code}' http://127.0.0.1:3584/api/relay/health` -> `200`
  - `curl -sS http://127.0.0.1:3584/` -> `{"service":"zuk","type":"com.atproto.relay",...}`

## Next
- Completed; no follow-up for this node.
