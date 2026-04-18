# Web UI API Wiring & Modernization

## Objective
Fully wire up the remaining Web UI APIs, migrate the Admin UI to use modern Ozone-based moderation, and implement real-time health checks.

## Progress Tracking
- [x] Phase 1: Moderation Frontend Migration (Ozone)
- [x] Phase 2: Real-Time Health & Metrics Wiring
- [x] Phase 3: Invite Code Management Reconciliation
- [x] Phase 4: Explore UI Edge-Case Verification

## Decision Log
- Migrating from `com.atproto.admin` to `tools.ozone.moderation` because the backend has deprecated the former.
- Implemented `fetchBlob:` in `ExploreHandler.m` using global blob metadata lookup in `PDSDatabase`.
- Wired up `PDSMetrics` to the `/admin/health` API for real-time monitoring.

## Technical Details
- Frontend: `Garazyk/Sources/App/AdminUI/Assets/js/admin-panel.js`
- Backend Handlers: `PDSAdminHandler.m`, `XrpcToolsOzonePack.m`, `XrpcAdminMethods.m`
- Health: `PDSAdminHandler.m` -> `PDSMetrics`
