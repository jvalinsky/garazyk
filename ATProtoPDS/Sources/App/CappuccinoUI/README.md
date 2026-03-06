# CappuccinoUI

Objective-J/Cappuccino web GUI for the ATProto PDS.

## Canonical Routes

| Route | Description |
|---|---|
| `GET /` | Default entrypoint — serves the Objective-J UI (cutover active) |
| `GET /ui` | Explicit Objective-J UI path (always available) |
| `GET /ui/*` | All Objective-J static assets |

All backend APIs remain on their existing paths: `/api/pds/*`, `/admin*`, `/api/mst/*`, `/xrpc/*`, `/oauth/*`.

## Legacy Fallback

To revert `GET /` to the legacy ExploreHandler, set `enableCappuccinoUIDefault = NO` on `PDSHttpServerBuilder` (see `PDSController.m`).

Legacy Explore assets in `Sources/App/Explore/Assets/` are preserved during the transition window and will be archived after soak period.

## Build

From repo root:

```bash
./scripts/build_cappuccino_ui.sh
```

This will:

1. Install npm dependencies in this directory.
2. Generate Cappuccino `Frameworks/` if missing.
3. Build the app with `jake release`.
4. Stage output at `ATProtoPDS/Sources/App/CappuccinoUI/dist/CappuccinoUI`.

## CMake integration

Frontend build is opt-in from CMake:

```bash
cmake -S . -B build -DBUILD_CAPPUCCINO_UI=ON
cmake --build build --target cappuccino-ui-build
```

## CI

The Objective-J build is a required CI check (`cappuccino-ui-build` job in `ci.yml`).
CI fails if the Cappuccino build fails.

## Controllers

| Controller | Lines | Scope |
|---|---|---|
| `ExplorerController.j` | ~2600 | Account/DID/PLC/collections/records/feed/profile/CID/OAuth |
| `AdminController.j` | ~1750 | Login/overview/accounts/reports/invites/audit/moderation |
| `MSTController.j` | ~780 | Account search/tree/stats/export/zoom |
| `OAuthDemoController.j` | ~880 | OAuth login/callback/session/post/records/logout |
