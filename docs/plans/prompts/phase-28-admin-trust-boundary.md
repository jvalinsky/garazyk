# Phase 28: Admin + AdminUIServer trust-boundary sweep

**depends_on: [S15, S16]**

## Mission

Sweep the Admin and AdminUIServer trust boundaries (~8,000 lines across
`Garazyk/Sources/Admin/` and `Garazyk/Sources/AdminUIServer/`) for the same
defect classes fixed in S8 (auth boundary), S13 (registration), and S15 (chat):
untyped JSON extraction at XRPC handler entry, admin session/auth gaps, and
HTML template injection surfaces. The Admin module controls PDS configuration,
DID lists, invite codes, and installer commands. AdminUIServer serves the
HTMX-based web dashboard with route handlers for every ATProto namespace
(AppView, Chat, Ozone, PDS, PLC, Relay, Security, Video).

## Read First

- **Workstream**: `docs/plans/workstreams/01-security-and-protocol-correctness.md`
  § S17 (to be created — evidence from this audit).
- **Key Files**:
  - `Garazyk/Sources/Admin/PDSAdminAuth.m` (admin auth, DID list management,
    invite code creation, installer commands)
  - `Garazyk/Sources/Admin/AdminMiddleware.m` (auth middleware, DID list
    verification)
  - `Garazyk/Sources/AdminUIServer/UIAuthManager.m` (UI session/auth manager)
  - `Garazyk/Sources/AdminUIServer/UIServerRuntime.m` + route categories
    (AppViewRoutes, ChatRoutes, DataExplorerRoutes, MSTRoutes, OzoneRoutes,
    PDSRoutes, PLCRoutes, RelayRoutes, SecurityRoutes, VideoRoutes)
  - `Garazyk/Sources/AdminUIServer/UITemplateEngine.m` (HTML rendering,
    template variable injection)
  - `Garazyk/Sources/AdminUIServer/UIBackendClient.m` (backend API calls,
    auth forwarding)
  - Existing tests: `Garazyk/Tests/Admin/PDSAdminAuthTests.m`,
    `Garazyk/Tests/Admin/PDSAdminMiddlewareTests.m`
- **References**: ADR 0013 (claim type mismatches), S8/S13/S15 (isKindOfClass
  sweep patterns), phase-26 prompt (AdminMiddleware DID list gap).

## Decisions (Do Not Re-Litigate)

1. **isKindOfClass sweep**: All `body[@"key"]` extractions in Admin handler code
   and AdminUIServer route handlers must be guarded with
   `isKindOfClass:[NSString class]` (or appropriate NSArray/NSDictionary type).
   Non-matching → 400.
2. **Admin auth pattern**: Admin endpoints already parse DID lists with
   `isKindOfClass` guards in some paths (PDSAdminAuth.m:239, :291, :305).
   The sweep must verify ALL extraction sites are consistent.
3. **Template injection**: The `UITemplateEngine` must apply HTML escaping
   to all user-controlled values inserted into templates. Any unescaped
   `%@` or `stringByAppendingFormat:` with untrusted data is a finding.
4. **Session auth forwarding**: AdminUIServer's `UIBackendClient` forwards
   auth headers to backend services. These must be validated (isKindOfClass,
   newline check) per the B2 fix pattern from S16.
5. **Rejection semantics**: Non-string values → 400 InvalidRequest.
   Auth failures → 401. Forbidden operations → 403.

## Slices

1. **Admin isKindOfClass sweep**: Audit PDSAdminAuth.m and AdminMiddleware.m
   for unguarded `body[@"key"]` extractions. Add isKindOfClass guards with
   400 rejection where missing. The DID list parsing already has some guards
   (:239, :291) — verify completeness.
2. **AdminUIServer route handler sweep**: Audit all route categories
   (AppViewRoutes, ChatRoutes, DataExplorerRoutes, MSTRoutes, OzoneRoutes,
   PDSRoutes, PLCRoutes, RelayRoutes, SecurityRoutes, VideoRoutes) for
   unguarded JSON extraction and add isKindOfClass guards.
3. **Template engine HTML escaping**: Audit `UITemplateEngine.m` for
   template variable injection points. Ensure all user-controlled values
   are HTML-escaped before interpolation. Flag any unescaped `%@` patterns.
4. **AdminUIServer auth forwarding**: Audit `UIBackendClient.m` auth header
   forwarding paths. Add isKindOfClass + newline validation per the B2
   (Beskid) fix pattern from S16 slice 4.
5. **AdminMiddleware DID list verification**: Complete the phase-26 slice 1
   gap — verify DID list operations are gated behind admin auth.
6. **Acceptance gate tests**: Add tests to `PDSAdminAuthTests` and
   `PDSAdminMiddlewareTests` covering:
   - Non-string body fields return 400
   - Template variables are escaped (XSS prevention)
   - Auth header injection rejected (newline in Bearer token → 400)
   - Unauthenticated admin endpoints return 401

## Gate

- Non-string body fields in Admin/AdminUIServer handlers → 400.
- Unauthenticated admin endpoints → 401.
- Auth header with embedded newline → 400 (header injection prevention).
- Template engine escapes HTML entities in user-controlled values.
- DID list operations require admin auth (not just any valid JWT).
- All existing admin tests pass (`PDSAdminAuthTests`, `PDSAdminMiddlewareTests`).
- `./build/tests/AllTests --gated=run` passes.

## Rollback

Each slice is self-contained:
- Slice 1 (isKindOfClass): If a downstream handler relies on non-string values
  passing through, revert that specific guard and add a targeted coercion.
- Slice 3 (HTML escaping): If escaping breaks intentional HTML in templates
  (e.g., status badges), use an explicit allowlist rather than removing
  the guard.
- Slice 4 (auth forwarding): If existing integrations rely on raw auth header
  passthrough, revert and add the B2 pattern as an opt-in per-route config.

## Execution

```bash
# Build
cmake --build build --target AllTests --parallel 4

# Run admin tests
./build/tests/AllTests --filter 'PDSAdminAuthTests' --gated=run
./build/tests/AllTests --filter 'PDSAdminMiddlewareTests' --gated=run

# Full gate
./build/tests/AllTests --gated=run
```
