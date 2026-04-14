# Node 229 Scratch

## Results
- Executed validation matrix components that are runnable in this environment:
  - UI asset build: pass
  - `xcodegen generate`: pass
  - service `/ui` + `/ui/profile` + Objective-J asset smoke across PDS/Relay/PLC/AppView: pass
  - HTTP regression probes for API precedence: pass for targeted endpoints
- Confirmed service-profile payload correctness for all services via `/ui/profile`.
- Confirmed Cappuccino shell boot markers present in served HTML (`<base href="/ui/">`, `OBJJ_MAIN_FILE="main.j"`).

## Issues
- Browser leg blocked by Browser MCP storage path error (`/.playwright-mcp` ENOENT; read-only root path).
- `xcodebuild` quality-gate commands fail in this environment with:
  - `error: couldn't create build system`
  - `error: couldn't create build environment`
- Existing `./build/tests/AllTests` execution did not complete cleanly (`EXIT:139` in captured run).

## Useful Info
- Local compose validation used alternate mapped ports due existing host `2583` conflict:
  - PDS `3583`, Relay `3584`, PLC `3582`, AppView `4200`.
- Official Cappuccino references checked during this pass:
  - https://www.cappuccino.dev/blog/2008/10/cappuccino-tools-bak.html
  - https://www.cappuccino.dev/learn/environment.html

## Evidence (commands/screenshots/logs)
- `./scripts/build_cappuccino_ui.sh` -> success
- `xcodegen generate` -> success
- `xcodebuild -scheme AllTests build` -> build-system/environment error
- `xcodebuild -scheme ATProtoPDS-CLI build` -> build-system/environment error
- `./build/tests/AllTests > /tmp/alltests-uifix-20260413.log` -> `EXIT:139`
- HTTP smoke/regression (localhost alt ports):
  - `/ui`, `/ui/profile`, `/ui/Frameworks/Objective-J/Objective-J.js` all `200` on 4 services
  - PDS `/xrpc/com.atproto.server.describeServer` -> `200`
  - Relay `/api/relay/health` -> `200`
  - PLC `/:did` sample route -> handled (`404 DID not found`)
  - AppView `/admin/backfill/status` -> `401` (expected unauthenticated)

## Next
- Re-open browser matrix after Browser MCP storage path is fixed (node `#222` / `#230`).
- Re-run Xcode quality gates in an environment where `xcodebuild` can create its build environment.
