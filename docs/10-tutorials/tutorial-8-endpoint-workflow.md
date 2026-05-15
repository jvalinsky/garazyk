---
title: "Tutorial 8: Endpoint Workflow"
---

# Tutorial 8: Endpoint Workflow

This tutorial explains how to add or modify an endpoint in Garazyk. Following a consistent workflow ensures that routing, validation, domain logic, and documentation remain aligned.

## Step 1: Choose the Surface

Determine where the endpoint belongs based on its purpose:

- **XRPC:** Use for AT Protocol or application-level surfaces.
- **Admin API (`/api/pds/*`):** Use for internal inspection, contributor tools, or operator workflows.
- **UI:** Use for rendering views in the Explorer or Admin dashboard.

## Step 2: Find the Registration Point

| Surface | Location |
| --- | --- |
| XRPC | `XrpcMethodRegistry.m` |
| Admin/Explorer | `PDSHttpServerBuilder.m` |
| UI | `CappuccinoUIHandler.m` or specific UI controllers |

Registration defines the request shape and applies initial middleware.

## Step 3: Enforce Guard Rails

Protect the server by applying validation and rate limiting at the entry point.

### Input Validation
Use `PDSInputValidator` to sanitize identifiers like handles, DIDs, and record keys before they reach your service logic.

```objectivec
PDSInputValidator *validator = [PDSInputValidator sharedValidator];
if (![validator isValidHandle:handle]) {
    return [XrpcError invalidRequest:@"Invalid handle"];
}
```

### Rate Limiting
Apply rate limits to all public endpoints using `RateLimiter`.

```objectivec
RateLimitResult *result = [[RateLimiter sharedLimiter] checkRateLimitForIP:request.remoteAddress];
if (!result.allowed) {
    return [XrpcError rateLimitExceeded:result];
}
```

## Step 4: Implement Domain Logic

Keep route handlers thin. Business rules should reside in dedicated services or controllers.

Ask: *Which domain object owns the invariant this endpoint depends on?*
- **Auth/Account:** `PDSAccountService`
- **Records:** `PDSRecordService`
- **Moderation:** `ChatModerationService` or `AgeAssuranceService`

## Step 5: Verification

Verify your changes starting from the smallest trust boundary:

1. **Unit Tests:** Prove the service logic works in isolation.
2. **Subsystem Tests:** Verify the route handler and its integration with services.
3. **Integration Tests:** Use `AllTests` or manual `curl` commands against a running server.

### Manual Check
```bash
./build/bin/kaszlak serve --config ./config.json --foreground &
curl -sS http://127.0.0.1:2583/xrpc/your.new.endpoint
```

## Step 6: Update Tooling and Docs

If the endpoint is contributor-facing, ensure it appears in the generated documentation and tools:

- Update generated OpenAPI descriptors.
- Verify the endpoint in the `/api/pds/docs` view.
- Update [API Reference](../11-reference/api-reference) if the change affects the public protocol contract.

## Troubleshooting

| Symptom | Cause | Resolution |
| --- | --- | --- |
| 404 Not Found | Registration mismatch | Check `PDSHttpServerBuilder` or `XrpcMethodRegistry`. |
| Auth Failure | Incorrect auth helper | Verify the expected issuer and bearer token configuration. |
| Stale UI | Explorer not updated | Check `ExploreHandler` or the relevant UI controller. |

## See Also

- [Codebase Map](../01-getting-started/codebase-map)
- [Request Lifecycle](../01-getting-started/request-lifecycle)
- [Explorer and OpenAPI](../11-reference/explorer-openapi-ui)
