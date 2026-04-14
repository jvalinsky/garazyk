# Node 223 Scratch

## Results
- Refactored shared Cappuccino static serving into `CappuccinoUIHandler` with service profile support.
- Added `GET /ui/profile` payload generation: `serviceProfile`, `availableServices`, `endpointBases`, `uiEntrypoint`.
- Replaced brittle fixed-depth asset lookup with deterministic multi-root candidate search:
  - executable ancestor chain
  - cwd ancestor chain
  - data directory ancestor chain
  - explicit env override `PDS_CAPPUCCINO_UI_PATH`
  - packaged system paths
- Preserved boot contract and shell semantics (`/ui`, `/ui/*`, `<base href="/ui/">`, `OBJJ_MAIN_FILE="main.j"`).

## Issues
- No functional regressions seen in HTTP smoke for shared serving paths.

## Useful Info
- Official Cappuccino docs confirm `<base>`-tag driven resource root behavior for deployments:
  - https://www.cappuccino.dev/blog/2008/10/cappuccino-tools-bak.html
- Official Cappuccino environment docs emphasize `index` vs `index-debug` runtime loading behavior:
  - https://www.cappuccino.dev/learn/environment.html

## Evidence (commands/screenshots/logs)
- Edited files:
  - `Garazyk/Sources/App/CappuccinoUI/CappuccinoUIHandler.h`
  - `Garazyk/Sources/App/CappuccinoUI/CappuccinoUIHandler.m`
  - `Garazyk/Sources/Network/PDSHttpCappuccinoUIRoutePack.h`
  - `Garazyk/Sources/Network/PDSHttpCappuccinoUIRoutePack.m`
- Smoke checks (alt compose ports):
  - `curl -sS http://127.0.0.1:3583/ui/profile` -> profile `pds`
  - `curl -sS http://127.0.0.1:3584/ui/profile` -> profile `relay`
  - `curl -sS http://127.0.0.1:3582/ui/profile` -> profile `plc`
  - `curl -sS http://127.0.0.1:4200/ui/profile` -> profile `appview`

## Next
- Completed; no follow-up for this node.
