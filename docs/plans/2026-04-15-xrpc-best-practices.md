---
title: "XRPC Implementation Best Practices"
---

# XRPC Implementation Best Practices

> **Status:** Reference Document
> **Generated:** 2026-04-15

---

## Overview

This document codifies best practices for implementing XRPC endpoints in the Garazyk PDS codebase. These patterns are derived from existing implementations and ensure consistency, security, and maintainability.

---

## 1. Authentication Pattern

**Always check authentication first, before any other logic:**

```objc
// 1. Check for Authorization header
NSString *authHeader = [request headerForKey:@"Authorization"];
if (!authHeader) {
    [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
    return;
}

// 2. Extract and validate DID from header
NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                    jwtMinter:jwtMinter
                                              adminController:adminController
                                                      request:request
                                                     response:response];
if (!actorDID) {
    return; // Error response already set by extractDIDFromAuthHeader
}

// 3. actorDID is now available for authorization checks
```

---

## 2. Input Validation

### 2.1 Validate Request Body Exists

```objc
NSDictionary *body = request.jsonBody;
if (!body || ![body isKindOfClass:[NSDictionary class]]) {
    [XrpcErrorHelper setValidationError:response message:@"Missing request body"];
    return;
}
```

### 2.2 Validate Required Fields

```objc
// String field
NSString *requiredField = body[@"requiredField"];
if (!requiredField || ![requiredField isKindOfClass:[NSString class]]) {
    [XrpcErrorHelper setValidationError:response message:@"requiredField is required"];
    return;
}

// Integer field with bounds
NSInteger limit = 50; // default
if (body[@"limit"]) {
    NSInteger parsedLimit = [body[@"limit"] integerValue];
    if (parsedLimit < 1 || parsedLimit > 100) {
        [XrpcErrorHelper setValidationError:response message:@"limit must be between 1 and 100"];
        return;
    }
    limit = parsedLimit;
}
```

### 2.3 Validate Optional Fields

```objc
NSString *optionalCursor = nil;
if (body[@"cursor"] && [body[@"cursor"] isKindOfClass:[NSString class]]) {
    optionalCursor = body[@"cursor"];
}
```

---

## 3. Error Response Patterns

**Always use XrpcErrorHelper for consistent errors:**

| Error Type | Method | Use For |
|------------|--------|---------|
| Authentication | `setAuthenticationError:message:` | Missing/invalid auth header |
| Authorization | `setForbiddenError:message:` | Auth ok, but not allowed |
| Validation | `setValidationError:message:` | Invalid input parameters |
| Not Found | `setNotFoundError:message:` | Resource doesn't exist |
| Internal Server | `setInternalServerError:message:` | Unexpected errors |

```objc
// Example: Proper error handling flow
NSError *error = nil;
NSDictionary *result = [service doOperationWithError:&error];
if (!result) {
    if (error.code == kPDSNotFoundError) {
        [XrpcErrorHelper setNotFoundError:response message:@"Resource not found"];
    } else if (error.code == kPDSValidationError) {
        [XrpcErrorHelper setValidationError:response message:error.localizedDescription];
    } else {
        [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Operation failed"];
    }
    return;
}
```

---

## 4. Pagination Pattern

**All list endpoints must support pagination:**

```objc
// Input parsing with defaults and bounds
NSInteger limit = 50;
NSString *cursor = nil;

if (body[@"limit"]) {
    limit = MIN(MAX([body[@"limit"] integerValue], 1), 100);
}
if (body[@"cursor"] && [body[@"cursor"] isKindOfClass:[NSString class]]) {
    cursor = body[@"cursor"];
}

// Service call
NSDictionary *result = [service getItemsForActor:actorDID
                                            limit:limit
                                          cursor:cursor
                                            error:&error];
if (!result) {
    [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
    return;
}

NSArray *items = result[@"items"];
NSString *nextCursor = result[@"nextCursor"];

// Response
response.statusCode = HttpStatusOK;
[response setJsonBody:@{
    @"items": items ?: @[],
    @"cursor": nextCursor ?: [NSNull null]
}];
```

---

## 5. Service Layer Integration

### 5.1 Instantiate Service with Dependencies

```objc
// In registerWithDispatcher: method
ActorService *actorService = [[ActorService alloc] initWithDatabase:appViewDatabase];
GraphService *graphService = [[GraphService alloc] initWithDatabase:appViewDatabase];
```

### 5.2 Service Error Handling

```objc
NSError *error = nil;
NSDictionary *profile = [actorService getProfileForActor:actorDID error:&error];

if (!profile) {
    if (error) {
        // Log for debugging
        PDS_LOG_ERROR(@"Failed to get profile for %@: %@", actorDID, error);
        
        // Check error type
        if ([error.domain isEqualToString:PDSDatabaseErrorDomain]) {
            [XrpcErrorHelper setInternalServerError:response message:@"Database error"];
        } else {
            [XrpcErrorHelper setNotFoundError:response message:@"Actor not found"];
        }
    } else {
        [XrpcErrorHelper setNotFoundError:response message:@"Actor not found"];
    }
    return;
}
```

---

## 6. Logging

### 6.1 Endpoint Registration

```objc
PDS_LOG_INFO(@"Registered app.bsky.actor.* endpoints");
```

### 6.2 Request Handling

```objc
PDS_LOG_DEBUG(@"getSuggestions called for actor: %@", actorDID);
```

### 6.3 Errors

```objc
PDS_LOG_ERROR(@"Failed to fetch notifications for %@: %@", actorDID, error);
```

---

## 7. Response Patterns

### 7.1 Simple Success

```objc
response.statusCode = HttpStatusOK;
[response setJsonBody:@{@"success": @YES}];
```

### 7.2 Object Response

```objc
response.statusCode = HttpStatusOK;
[response setJsonBody:@{
    @"profile": @{
        @"did": actorDID,
        @"handle": profile[@"handle"],
        @"displayName": profile[@"displayName"] ?: [NSNull null]
    }
}];
```

### 7.3 Array Response with Metadata

```objc
response.statusCode = HttpStatusOK;
[response setJsonBody:@{
    @"actors": actors,
    @"cursor": nextCursor ?: [NSNull null]
}];
```

---

## 8. Query Parameters (GET Requests)

**For GET endpoints that use query parameters:**

```objc
// Get required query param
NSString *uri = [request queryParamForKey:@"uri"];
if (!uri) {
    [XrpcErrorHelper setValidationError:response message:@"Missing uri parameter"];
    return;
}

// Get optional query param with default
NSInteger limit = 50;
NSString *limitStr = [request queryParamForKey:@"limit"];
if (limitStr) {
    limit = MIN(MAX([limitStr integerValue], 1), 100);
}
```

---

## 9. Thread Safety

- **Services are created per-request** or as **singletons** with immutable dependencies
- **Database access** is serialized through `PDSDatabasePool`
- **Use weak references** in blocks to avoid retain cycles:
  ```objc
  __weak typeof(self) weakSelf = self;
  [dispatcher registerMethod:@"endpoint" handler:^(HttpRequest *request, HttpResponse *response) {
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) return;
      // Use strongSelf
  }];
  ```

---

## 10. Test Coverage Requirements

Each endpoint should have tests for:

| Test Case | Description |
|-----------|-------------|
| Auth Required | No Authorization header → 401 |
| Auth Invalid | Invalid/malformed auth → 401 |
| Validation Error | Missing required field → 400 |
| Not Found | Valid request, resource missing → 404 |
| Success | Valid request, valid resource → 200 + correct body |
| Pagination | Test cursor behavior |

---

## 11. Code Template

```objc
// Endpoint registration
[dispatcher registerAppBskyNamespaceEndpoint:^(HttpRequest *request, HttpResponse *response) {
    
    // 1. Auth check
    NSString *authHeader = [request headerForKey:@"Authorization"];
    if (!authHeader) {
        [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
        return;
    }
    
    NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                        jwtMinter:jwtMinter
                                                  adminController:adminController
                                                          request:request
                                                         response:response];
    if (!actorDID) return;
    
    // 2. Parse input
    NSDictionary *body = request.jsonBody;
    // ... validation
    
    // 3. Call service
    NSError *error = nil;
    NSDictionary *result = [service doSomethingForActor:actorDID error:&error];
    if (!result) {
        [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
        return;
    }
    
    // 4. Return
    response.statusCode = HttpStatusOK;
    [response setJsonBody:result];
}];
```

---

## Related Documents

- [2026-04-15-xrpc-service-implementation-guide.md](./2026-04-15-xrpc-service-implementation-guide.md)
- [2026-04-15-xrpc-audit-stub-fix-plan.md](./2026-04-15-xrpc-audit-stub-fix-plan.md)
