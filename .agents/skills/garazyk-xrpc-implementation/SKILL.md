---
name: garazyk-xrpc-implementation
description: Add, fix, or review Garazyk XRPC handlers from AT Protocol lexicons. Covers lexicon shape, request/response validation, route packs, method registration, auth middleware, service boundaries, XCTest coverage, coverage reports, and scenario coverage.
---

# Garazyk XRPC Implementation

Use this skill when adding or repairing an XRPC endpoint, syncing code with lexicons, reviewing route registration, or turning coverage gaps into implemented handlers.

## Primary files

- Route packs: `Garazyk/Sources/Network/*Pack.{h,m}`, `Garazyk/Sources/*/*Xrpc*Pack.{h,m}`
- Registry/routing: `Garazyk/Sources/Network/XrpcMethodRegistry.*`, `XrpcRoutePack.*`, `XrpcRoutePackRegistrar.*`, `XrpcHandler.*`, `XrpcHandlerContext.*`
- Middleware/auth: `XrpcMiddleware.*`, `XrpcAuthHelper.*`, `XrpcServiceAuthHelper.*`, `XrpcProxyHandler.*`
- Lexicon resolver/validation: `XrpcLexiconResolver.*`, `ATProtoValidator.*`
- Coverage tooling: `scripts/docs/generate_xrpc_coverage_report.cjs`, `scripts/docs/xrpc_coverage_scope_expanded.txt`
- Scenarios: `scripts/scenarios/scenarios/*.ts`, runner `scripts/run_scenarios.ts`
- Tests: `Garazyk/Tests/Network/`, relevant service/database test directories, `Garazyk/Tests/test_main.m`

## Implementation workflow

### 1. Identify the contract

Start from the lexicon and record:

- NSID and type: query, procedure, or subscription
- params, input encoding, output encoding
- required vs optional fields
- array/object constraints and unions
- error names and status semantics
- auth requirements and service boundary

If lexicons are vendored or generated elsewhere, note the source path before editing code. Do not invent fields; preserve ATProto names and casing.

### 2. Locate the correct route pack

Use the NSID prefix:

| NSID family | Common route pack |
| --- | --- |
| `com.atproto.server.*` | `XrpcServerPack` |
| `com.atproto.repo.*` | `XrpcRepoPack` |
| `com.atproto.sync.*` | `XrpcSyncPack`, relay route packs |
| `com.atproto.identity.*` | `XrpcIdentityPack` |
| `app.bsky.actor.*` | `XrpcAppBskyActorPack` |
| `app.bsky.feed.*` | `XrpcAppBskyFeedPack` |
| `app.bsky.graph.*` | `XrpcAppBskyGraphPack` |
| `app.bsky.notification.*` | `XrpcAppBskyNotificationPack` |
| `app.bsky.*` miscellany | existing `XrpcAppBsky*Pack` |
| `chat.bsky.*` | `XrpcChatBsky*Pack`, Germ server packs |
| `tools.ozone.*` | `XrpcToolsOzonePack`, moderation/label packs |
| admin/private | `XrpcAdminPack` or service-specific admin handlers |

If no pack exists, add the smallest route pack consistent with nearby patterns and register it through the standard registrar path.

### 3. Register the method

Match existing route-pack style. Confirm:

- Method NSID is exact.
- HTTP verb and body/query handling match query/procedure type.
- Handler is reachable from the service binary that should expose it.
- Duplicate registrations are not introduced.
- Coverage report no longer lists the method as missing/stubbed.

Run or inspect:

```bash
node scripts/docs/generate_xrpc_coverage_report.cjs --source-only --fail-on-duplicates
```

### 4. Validate request and response shape

For every handler:

- Parse query params separately from JSON body.
- Treat required fields as required; reject malformed types early.
- Apply limits for arrays, strings, pagination, and binary input.
- Preserve lexicon output names exactly.
- Return ATProto/XRPC-style errors through existing helpers.
- Never build SQL by string interpolation; use prepared statements.
- Redact tokens, passwords, DPoP material, emails/phones where appropriate in logs.

Prefer existing helpers before adding new validation primitives.

### 5. Wire auth deliberately

Classify the endpoint before coding:

- public no-auth
- bearer-token user auth
- admin auth
- service-to-service auth
- OAuth/DPoP-protected
- proxy/write-through endpoint

Check middleware order. Do not rely on handler-internal checks if an existing middleware should enforce the boundary. Tests should include at least one negative auth path for protected methods.

### 6. Delegate to service layer

Handlers should be thin:

1. parse and validate input
2. authorize
3. call service/database layer
4. serialize lexicon-shaped response
5. map domain errors to XRPC errors

Avoid putting persistence, cryptography, or cross-service orchestration directly in route-pack code unless the existing architecture already does so for that family.

## Test checklist

Add/update XCTest coverage near the endpoint family:

- success response shape
- missing required field
- malformed type/value
- auth missing/invalid/wrong scope
- relevant service-layer error mapping
- pagination/cursor behavior if applicable
- route registration if the family has registration tests

Use `garazyk_find_test_class` to locate/register tests. Use `garazyk_build_test` rather than ad-hoc build commands.

## Scenario coverage

Add or extend a scenario when behavior is cross-service, protocol-facing, or regression-prone.

- Use `adding-scenario` for new scenario files.
- Use `atproto-scenario-testing` for runner conventions.
- Prefer bounded polling over fixed sleeps for AppView/Relay eventual consistency.
- Record artifacts useful for triage: DIDs, URIs, CIDs, cursors, response status.

Run the smallest relevant scenario first:

```bash
./scripts/run_scenarios.ts --no-setup NN --verbose
```

## Definition of done

- Lexicon contract understood and cited in notes.
- Route registered exactly once in the right service.
- Request validation and response shape match lexicon.
- Auth boundary is explicit and tested.
- XCTest coverage added and registered.
- XRPC coverage report passes for touched method family.
- Scenario coverage exists for cross-service behavior.
