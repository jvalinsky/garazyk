# Node 227 Scratch

## Results
- Added PLC service UI routes before dynamic DID handlers:
  - `GET /ui`
  - `GET /ui/*`
- Bound PLC runtime to profile `plc` in shared Cappuccino handler.
- Preserved dynamic DID route handlers (`/:did`, `/:did/log`, etc.) and legacy root/static routing behavior.

## Issues
- In local compose, PLC legacy root (`/`) returns `{"error":"Assets not found"}` because legacy PLC static assets are not present in this runtime image.
- This is a pre-existing packaging/runtime condition; `/ui` profile shell path works.

## Useful Info
- DID route still resolves through existing handler chain (returns DID-specific JSON errors rather than UI content), confirming precedence is intact.

## Evidence (commands/screenshots/logs)
- Edited file:
  - `Garazyk/Sources/PLC/PLCServer.m`
- Smoke/regression:
  - `curl -sS -w '%{http_code}' http://127.0.0.1:3582/ui` -> `200`
  - `curl -sS http://127.0.0.1:3582/ui/profile` -> `serviceProfile=plc`
  - `curl -sS -w '%{http_code}' http://127.0.0.1:3582/did:plc:testdid` -> `404` with `{"error":"DID not found"}`
  - `curl -sS -w '%{http_code}' http://127.0.0.1:3582/` -> `404` with `{"error":"Assets not found"}`

## Next
- Completed for `/ui` integration; legacy root asset packaging can be handled separately if needed.
