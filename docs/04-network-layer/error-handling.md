---
title: Error Handling
---

# Error Handling

## Overview

The `XrpcErrorHelper` provides standardized error response construction for XRPC endpoints. It ensures consistent error formats across all endpoints and sets appropriate HTTP status codes.

## Standard Error Format

All XRPC errors follow a consistent JSON format:

```json
{
  "error": "<ErrorCode>",
  "message": "<Human-readable description>"
}
```

**Example:**
```json
{
  "error": "InvalidRequest",
  "message": "Missing required parameter: repo"
}
```

## HTTP Status Codes

| Status | Error Code | Meaning |
|--------|-----------|---------|
| 400 | InvalidRequest | Request validation failed |
| 401 | AuthRequired | Authentication required |
| 403 | Forbidden | Authenticated but not authorized |
| 404 | NotFound | Requested resource not found |
| 405 | MethodNotAllowed | HTTP method not allowed |
| 409 | Conflict | Resource conflict (e.g., concurrent modification) |
| 500 | InternalServerError | Server-side error |

## Error Helper Methods

### Authentication Error (401)

```objc
+ (void)setAuthenticationError:(HttpResponse *)response
                       message:(nullable NSString *)message;
```

Sets 401 Unauthorized response.

**Implementation (from XrpcErrorHelper.m):**

```objc
+ (void)setAuthenticationError:(HttpResponse *)response
                       message:(NSString *)message {
    [self setError:response
        statusCode:HttpStatusUnauthorized
         errorCode:@"AuthRequired"
           message:message ?: @"Authentication required"];
}
```

**Example:**
```objc
[XrpcErrorHelper setAuthenticationError:response 
                                message:@"Invalid token"];
```

**Response:**
```

HTTP/1.1 401 Unauthorized
Content-Type: application/json

{
  "error": "AuthRequired",
  "message": "Invalid token"
}
```

### Authorization Error (403)

```objc
+ (void)setAuthorizationError:(HttpResponse *)response
                      message:(nullable NSString *)message;
```

Sets 403 Forbidden response.

**Implementation (from XrpcErrorHelper.m):**

```objc
+ (void)setAuthorizationError:(HttpResponse *)response
                      message:(NSString *)message {
    [self setError:response
        statusCode:HttpStatusForbidden
         errorCode:@"Forbidden"
           message:message ?: @"Forbidden"];
}
```

**Example:**
```objc
[XrpcErrorHelper setAuthorizationError:response 
                               message:@"Cannot modify other's repository"];
```

**Response:**
```

HTTP/1.1 403 Forbidden
Content-Type: application/json

{
  "error": "Forbidden",
  "message": "Cannot modify other's repository"
}
```

### Validation Error (400)

```objc
+ (void)setValidationError:(HttpResponse *)response
                   message:(nullable NSString *)message;
```

Sets 400 Bad Request response.

**Implementation (from XrpcErrorHelper.m):**

```objc
+ (void)setValidationError:(HttpResponse *)response
                   message:(NSString *)message {
    [self setError:response
        statusCode:HttpStatusBadRequest
         errorCode:@"InvalidRequest"
           message:message ?: @"Invalid request"];
}
```

**Example:**
```objc
[XrpcErrorHelper setValidationError:response 
                            message:@"Invalid email format"];
```

**Response:**
```

HTTP/1.1 400 Bad Request
Content-Type: application/json

{
  "error": "InvalidRequest",
  "message": "Invalid email format"
}
```

### Not Found Error (404)

```objc
+ (void)setNotFoundError:(HttpResponse *)response
                 message:(nullable NSString *)message;
```

Sets 404 Not Found response.

**Implementation (from XrpcErrorHelper.m):**

```objc
+ (void)setNotFoundError:(HttpResponse *)response
                 message:(NSString *)message {
    [self setError:response
        statusCode:HttpStatusNotFound
         errorCode:@"NotFound"
           message:message ?: @"Not found"];
}
```

**Example:**
```objc
[XrpcErrorHelper setNotFoundError:response 
                          message:@"Record not found"];
```

**Response:**
```

HTTP/1.1 404 Not Found
Content-Type: application/json

{
  "error": "NotFound",
  "message": "Record not found"
}
```

### Internal Server Error (500)

```objc
+ (void)setInternalServerError:(HttpResponse *)response
                       message:(nullable NSString *)message;
```

Sets 500 Internal Server Error response.

**Implementation (from XrpcErrorHelper.m):**

```objc
+ (void)setInternalServerError:(HttpResponse *)response
                       message:(NSString *)message {
    [self setError:response
        statusCode:HttpStatusInternalServerError
         errorCode:@"InternalServerError"
           message:message ?: @"Internal server error"];
}
```

**Example:**
```objc
[XrpcErrorHelper setInternalServerError:response 
                                message:@"Database connection failed"];
```

**Response:**
```

HTTP/1.1 500 Internal Server Error
Content-Type: application/json

{
  "error": "InternalServerError",
  "message": "Database connection failed"
}
```

### Method Not Allowed (405)

```objc
+ (void)setMethodNotAllowedError:(HttpResponse *)response
                   allowedMethod:(NSString *)allowedMethod
                         message:(nullable NSString *)message;
```

Sets 405 Method Not Allowed response.

**Implementation (from XrpcErrorHelper.m):**

```objc
+ (void)setMethodNotAllowedError:(HttpResponse *)response
                   allowedMethod:(NSString *)allowedMethod
                         message:(NSString *)message {
    response.statusCode = HttpStatusMethodNotAllowed;
    if (allowedMethod.length > 0) {
        [response setHeader:allowedMethod forKey:@"Allow"];
    }
    [response setJsonBody:@{
        @"error": @"MethodNotAllowed",
        @"message": message ?: [NSString stringWithFormat:@"Expected %@", allowedMethod]
    }];
}
```

**Example:**
```objc
[XrpcErrorHelper setMethodNotAllowedError:response 
                            allowedMethod:@"POST"
                                  message:@"Use POST to create records"];
```

**Response:**
```

HTTP/1.1 405 Method Not Allowed
Content-Type: application/json

{
  "error": "MethodNotAllowed",
  "message": "Use POST to create records"
}
```

## Custom Error Responses

### Generic Error

```objc
+ (void)setError:(HttpResponse *)response
      statusCode:(HttpStatusCode)statusCode
       errorCode:(NSString *)errorCode
         message:(NSString *)message;
```

Sets custom error response.

**Implementation (from XrpcErrorHelper.m):**

```objc
+ (void)setError:(HttpResponse *)response
      statusCode:(HttpStatusCode)statusCode
       errorCode:(NSString *)errorCode
         message:(NSString *)message {
    response.statusCode = statusCode;
    [response setJsonBody:@{
        @"error": errorCode,
        @"message": message
    }];
}
```

**Example:**
```objc
[XrpcErrorHelper setError:response
              statusCode:409
               errorCode:@"InvalidSwapCommit"
                 message:@"Repository was modified"];
```

## Convenience Methods

### Invalid Request Error

```objc
+ (void)setInvalidRequestError:(HttpResponse *)response
                       message:(NSString *)message;
```

Sets 400 Bad Request with InvalidRequest error code.

**Implementation (from XrpcErrorHelper.m):**

```objc
+ (void)setInvalidRequestError:(HttpResponse *)response
                       message:(NSString *)message {
    [self setError:response
        statusCode:HttpStatusBadRequest
         errorCode:@"InvalidRequest"
           message:message];
}
```

### Account Not Found Error

```objc
+ (void)setAccountNotFoundError:(HttpResponse *)response
                     identifier:(NSString *)identifier;
```

Sets 404 Not Found for account.

**Implementation (from XrpcErrorHelper.m):**

```objc
+ (void)setAccountNotFoundError:(HttpResponse *)response
                     identifier:(NSString *)identifier {
    [self setError:response
        statusCode:HttpStatusNotFound
         errorCode:@"AccountNotFound"
           message:[NSString stringWithFormat:@"Account not found: %@", identifier]];
}
```

**Example:**
```objc
[XrpcErrorHelper setAccountNotFoundError:response 
                             identifier:@"alice"];
```

**Response:**
```json
{
  "error": "AccountNotFound",
  "message": "Account not found: alice"
}
```

### Lexicon Not Found Error

```objc
+ (void)setLexiconNotFoundError:(HttpResponse *)response
                           nsid:(NSString *)nsid;
```

Sets 404 Not Found for lexicon.

**Example:**
```objc
[XrpcErrorHelper setLexiconNotFoundError:response 
                                   nsid:@"app.bsky.feed.post"];
```

**Response:**
```json
{
  "error": "LexiconNotFound",
  "message": "Lexicon not found: app.bsky.feed.post"
}
```

## Common Error Scenarios

### Missing Required Parameter

```objc
NSString *repo = params[@"repo"];
if (!repo) {
    [XrpcErrorHelper setValidationError:response 
                                message:@"Missing required parameter: repo"];
    return;
}
```

### Invalid Parameter Type

```objc
if (![repo isKindOfClass:[NSString class]]) {
    [XrpcErrorHelper setValidationError:response 
                                message:@"Parameter 'repo' must be a string"];
    return;
}
```

### Invalid Parameter Value

```objc
if (![repo hasPrefix:@"did:"]) {
    [XrpcErrorHelper setValidationError:response 
                                message:@"Parameter 'repo' must be a valid DID"];
    return;
}
```

### Authentication Required

```objc
NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                              jwtMinter:jwtMinter
                                        adminController:adminController
                                                request:request];

if (!did) {
    [XrpcErrorHelper setAuthenticationError:response];
    return;
}
```

### Authorization Failed

```objc
if (![repo isEqualToString:did]) {
    [XrpcErrorHelper setAuthorizationError:response 
                                   message:@"Cannot modify other's repository"];
    return;
}
```

### Resource Not Found

```objc
NSDictionary *record = [recordService getRecord:uri forDid:did error:&error];
if (!record) {
    [XrpcErrorHelper setNotFoundError:response 
                              message:@"Record not found"];
    return;
}
```

### Concurrent Modification

```objc
if (error.code == 409) {
    [XrpcErrorHelper setError:response
                  statusCode:409
                   errorCode:@"InvalidSwapCommit"
                     message:@"Repository was modified"];
    return;
}
```

### Service Layer Error

```objc
NSError *serviceError = nil;
NSDictionary *result = [service performOperation:params error:&serviceError];

if (!result) {
    if (serviceError.code == 404) {
        [XrpcErrorHelper setNotFoundError:response];
    } else if (serviceError.code == 403) {
        [XrpcErrorHelper setAuthorizationError:response];
    } else {
        [XrpcErrorHelper setInternalServerError:response 
                                        message:serviceError.localizedDescription];
    }
    return;
}
```

## Error Response Structure

### Complete Error Response

```

HTTP/1.1 400 Bad Request
Content-Type: application/json
Content-Length: 67

{
  "error": "InvalidRequest",
  "message": "Missing required parameter: repo"
}
```

### With Additional Headers

```

HTTP/1.1 401 Unauthorized
Content-Type: application/json
WWW-Authenticate: Bearer realm="PDS"
DPoP-Nonce: nonce-value

{
  "error": "AuthRequired",
  "message": "Authentication required"
}
```

## Best Practices

1. **Use Appropriate Status Codes**
   - 400 for validation errors
   - 401 for authentication failures
   - 403 for authorization failures
   - 404 for not found
   - 500 for server errors

2. **Provide Clear Messages**
   - Explain what went wrong
   - Suggest how to fix it
   - Include relevant details (parameter names, etc.)
   - Avoid exposing internal details

3. **Consistent Error Codes**
   - Use standard error codes
   - Document custom error codes
   - Keep error codes stable

4. **Error Logging**
   - Log all errors
   - Include request details
   - Track error frequency
   - Monitor error trends

5. **Error Recovery**
   - Provide actionable error messages
   - Suggest retry strategies
   - Include retry-after headers when appropriate
   - Document error handling in API docs

## Error Code Reference

| Error Code | HTTP Status | Meaning |
|-----------|------------|---------|
| AuthRequired | 401 | Authentication required |
| Forbidden | 403 | Not authorized |
| InvalidRequest | 400 | Request validation failed |
| NotFound | 404 | Resource not found |
| MethodNotAllowed | 405 | HTTP method not allowed |
| InvalidSwapCommit | 409 | Repository was modified |
| InternalServerError | 500 | Server-side error |
| AccountNotFound | 404 | Account not found |
| LexiconNotFound | 404 | Lexicon not found |

## Common Patterns

### Validation Pipeline

```objc
// 1. Check authentication
NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                              jwtMinter:jwtMinter
                                        adminController:adminController
                                                request:request];
if (!did) {
    [XrpcErrorHelper setAuthenticationError:response];
    return;
}

// 2. Parse request
NSDictionary *params = [NSJSONSerialization JSONObjectWithData:request.body
                                                       options:0
                                                         error:&parseError];
if (!params) {
    [XrpcErrorHelper setValidationError:response message:@"Invalid JSON"];
    return;
}

// 3. Validate parameters
if (!params[@"repo"]) {
    [XrpcErrorHelper setValidationError:response message:@"Missing repo"];
    return;
}

// 4. Check authorization
if (![params[@"repo"] isEqualToString:did]) {
    [XrpcErrorHelper setAuthorizationError:response];
    return;
}

// 5. Call service
NSError *error = nil;
NSDictionary *result = [service operation:params error:&error];
if (!result) {
    [XrpcErrorHelper setInternalServerError:response];
    return;
}

// 6. Return success
response.statusCode = 200;
response.body = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
```

## See Also

- [XRPC Dispatch](xrpc-dispatch)
- [Domain Methods](domain-methods)
- [Auth Helpers](auth-helpers)
