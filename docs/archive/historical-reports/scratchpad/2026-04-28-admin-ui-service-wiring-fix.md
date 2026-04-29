# Admin UI Service Wiring Fix

## Goal

Make existing Admin UI panels call real, service-correct backend endpoints while keeping browser traffic pointed at the UI server. Server-side code should handle service probing and admin calls to avoid CORS issues and token exposure.

## Working Notes

- Add private PDS admin routes for account sessions and app passwords, protected by `PDSAdminAuth.authenticateHeaders`.
- Session IDs must be hashes derived from refresh tokens, never raw token values.
- Centralize UI backend URL construction so all service calls produce exact paths, queries, and bearer headers.
- Keep the existing panels; fix wiring for Security, Chat lock, Ozone reports/settings, PLC list responses, overview probes, and Connections save/test.

## Implementation Decisions

- Use a new `PDSHttpPDSAdminRoutePack` registered from `PDSHttpServerBuilder` for private PDS operational APIs.
- Keep refresh token lookup/revoke inside `PDSServiceDatabases`; public route responses only see SHA-256 token hashes.
- Use `UIBackendClient` as the single service URL/probe boundary for Admin UI panels and connection tests.

## Verification

- `xcodegen generate` succeeded.
- `xcodebuild -scheme AllTests build` is currently blocked by unrelated untracked video test sources:
  - `Garazyk/Tests/Database/PDSVideoJobsTests.m`
  - `Garazyk/Tests/Media/`
- The new Admin UI/PDS admin test objects compile directly through CMake:
  - `UIBackendClientTests.m.o`
  - `UIServerRuntimeTests.m.o`
  - `PDSHttpPDSAdminRoutePackTests.m.o`
- `xcodebuild -scheme kaszlak build` succeeded.

## Deciduous Links

- Goal node: 636
- Option node: 637
- Decision node: 638
- Action node: 639
