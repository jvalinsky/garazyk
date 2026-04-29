# Web UI API Wiring & Modernization

## Objective
Fully wire up the remaining Web UI APIs, migrate the Admin UI to use modern Ozone-based moderation, and implement real-time health checks.

## Progress Tracking
- [x] Phase 1: Moderation Frontend Migration (Ozone)
- [x] Phase 2: Real-Time Health & Metrics Wiring
- [x] Phase 3: Invite Code Management Reconciliation
- [x] Phase 4: Explore UI Edge-Case Verification
- [x] Phase 5: Chat API Wiring & Admin UI Integration

## Decision Log
- Migrating from `com.atproto.admin` to `tools.ozone.moderation` because the backend has deprecated the former.
- Implemented `fetchBlob:` in `ExploreHandler.m` using global blob metadata lookup in `PDSDatabase`.
- Wired up `PDSMetrics` to the `/admin/health` API for real-time monitoring.
- Registered missing `chat.bsky.convo` endpoints (`listConvos`, `getMessages`, `sendMessage`, `getConvo`) and wired them to `ChatService`.
- Added "Chat" section to Admin UI with Conversations and Messages management.
- Enhanced `AdminPartialHandler` template engine to handle `{{#if}}...{{else}}...{{/if}}` and nested loops via iterative replacement.
- Fixed race condition segfault in asset MIME type initialization.
- Added a beautiful portal page at root `/` to unified PDS Explorer and Admin Center.

## Technical Details
- Frontend: `Garazyk/Sources/App/AdminUI/Assets/js/admin-panel.js`
- Backend Handlers: `PDSAdminHandler.m`, `XrpcToolsOzonePack.m`, `XrpcAdminMethods.m`
- Health: `PDSAdminHandler.m` -> `PDSMetrics`
