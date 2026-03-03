# [NSID] Endpoint

<!-- 
Template for documenting XRPC endpoints.
Replace all [placeholders] with actual content.
Remove this comment block when creating actual documentation.
-->

## Overview

**NSID:** `[com.atproto.domain.methodName]`  
**Method:** `[GET/POST/DELETE]`  
**Authentication:** `[Required/Optional/None]`  
**Rate Limited:** `[Yes/No]`

[Brief description of what this endpoint does. 1-2 sentences.]

## Request

### HTTP Method

```
[POST/GET/DELETE] /xrpc/[com.atproto.domain.methodName]
```

### Headers

| Header | Required | Description |
|--------|----------|-------------|
| `Authorization` | [Yes/No] | [Bearer token with JWT access token] |
| `Content-Type` | [Yes/No] | [application/json or other] |
| `[Other-Header]` | [Yes/No] | [Description] |

### Parameters

[For GET requests, these are query parameters. For POST requests, these are in the JSON body.]

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `[param1]` | `[string]` | [Yes/No] | [Description of parameter] |
| `[param2]` | `[number]` | [Yes/No] | [Description of parameter] |
| `[param3]` | `[object]` | [Yes/No] | [Description of parameter] |
| `[param4]` | `[array]` | [Yes/No] | [Description of parameter] |

### Request Body Schema

[For POST requests with JSON body]

```json
{
  "[param1]": "[value]",
  "[param2]": 123,
  "[param3]": {
    "[nested1]": "[value]",
    "[nested2]": "[value]"
  },
  "[param4]": ["[item1]", "[item2]"]
}
```

### Example Request

```bash
curl -X [POST/GET/DELETE] \
  https://pds.example.com/xrpc/[com.atproto.domain.methodName] \
  -H "Authorization: Bearer [ACCESS_TOKEN]" \
  -H "Content-Type: application/json" \
  -d '{
    "[param1]": "[example_value]",
    "[param2]": 123
  }'
```

## Response

### Success Response (200 OK)

```json
{
  "[field1]": "[value]",
  "[field2]": 123,
  "[field3]": {
    "[nested1]": "[value]",
    "[nested2]": "[value]"
  }
}
```

### Response Fields

| Field | Type | Description |
|-------|------|-------------|
| `[field1]` | `[string]` | [Description of field] |
| `[field2]` | `[number]` | [Description of field] |
| `[field3]` | `[object]` | [Description of field] |

### Example Response

```json
{
  "[field1]": "[example_value]",
  "[field2]": 123,
  "[field3]": {
    "[nested1]": "[example_value]",
    "[nested2]": "[example_value]"
  }
}
```

## Error Responses

### Common Errors

| Status Code | Error Code | Description |
|-------------|------------|-------------|
| 400 | `InvalidRequest` | [When this error occurs] |
| 401 | `AuthenticationRequired` | [When this error occurs] |
| 403 | `Forbidden` | [When this error occurs] |
| 404 | `NotFound` | [When this error occurs] |
| 409 | `Conflict` | [When this error occurs] |
| 500 | `InternalServerError` | [When this error occurs] |

### Error Response Format

```json
{
  "error": "[ErrorCode]",
  "message": "[Human-readable error message]"
}
```

### Example Error Response

```json
{
  "error": "InvalidRequest",
  "message": "Missing required parameter: [param1]"
}
```

## Implementation

### Handler Location

**File:** `ATProtoPDS/Sources/Network/[XrpcDomainMethods].m`  
**Method:** `handle[MethodName]:response:`

### Handler Implementation

```objc
- (void)handle[MethodName]:(HttpRequest *)request 
                  response:(HttpResponse *)response {
    // 1. Extract authentication
    NSString *authHeader = [request headerForName:@"Authorization"];
    NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                  jwtMinter:self.jwtMinter
                                            adminController:self.adminController
                                                    request:request];
    
    if (!did) {
        [XrpcErrorHelper setAuthenticationError:response];
        return;
    }
    
    // 2. Parse request parameters
    NSError *parseError = nil;
    NSDictionary *params = [NSJSONSerialization JSONObjectWithData:request.body
                                                           options:0
                                                             error:&parseError];
    
    if (!params) {
        [XrpcErrorHelper setValidationError:response message:@"Invalid JSON"];
        return;
    }
    
    // Extract parameters
    NSString *[param1] = params[@"[param1]"];
    NSNumber *[param2] = params[@"[param2]"];
    
    // 3. Validate parameters
    if (![param1]) {
        [XrpcErrorHelper setValidationError:response 
                                    message:@"Missing required parameter: [param1]"];
        return;
    }
    
    // 4. Call service layer
    NSError *serviceError = nil;
    NSDictionary *result = [self.[serviceName] [methodName]:[param1]
                                                    [param2]:[param2]
                                                      error:&serviceError];
    
    if (!result) {
        [XrpcErrorHelper setInternalServerError:response 
                                        message:serviceError.localizedDescription];
        return;
    }
    
    // 5. Serialize response
    NSError *serializeError = nil;
    NSData *responseData = [NSJSONSerialization dataWithJSONObject:result
                                                           options:0
                                                             error:&serializeError];
    
    if (!responseData) {
        [XrpcErrorHelper setInternalServerError:response];
        return;
    }
    
    response.statusCode = 200;
    response.body = responseData;
    [response setHeaderValue:@"application/json" forName:@"Content-Type"];
}
```

### Registration

```objc
- (void)registerMethodsWithRegistry:(XrpcDispatcher *)dispatcher {
    [dispatcher registerHandler:^(HttpRequest *request, HttpResponse *response) {
        [self handle[MethodName]:request response:response];
    } forNSID:@"[com.atproto.domain.methodName]"];
}
```

### Service Layer Integration

This endpoint delegates to:

**Service:** `[ServiceClassName]`  
**Method:** `[methodName]:error:`

```objc
- ([ReturnType])[methodName]:(Type1)[param1]
                    [param2]:(Type2)[param2]
                       error:(NSError **)error;
```

## Authorization

[Describe authorization requirements and checks]

- [Authorization requirement 1]
- [Authorization requirement 2]
- [Authorization requirement 3]

### Example Authorization Check

```objc
// Verify user can only modify their own repository
if (![repo isEqualToString:did]) {
    [XrpcErrorHelper setAuthorizationError:response 
                                   message:@"Cannot modify other user's repository"];
    return;
}
```

## Validation Rules

[List validation rules for parameters]

1. **[param1]**
   - [Validation rule 1]
   - [Validation rule 2]
   - [Validation rule 3]

2. **[param2]**
   - [Validation rule 1]
   - [Validation rule 2]

3. **[param3]**
   - [Validation rule 1]
   - [Validation rule 2]

## Rate Limiting

[Describe rate limiting rules if applicable]

- **Limit:** [X requests per Y seconds]
- **Scope:** [Per user / Per IP / Global]
- **Headers:** `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`

## Side Effects

[Describe any side effects of calling this endpoint]

- [Side effect 1]
- [Side effect 2]
- [Side effect 3]

## Usage Examples

### Example 1: [Common Use Case]

[Description of the use case]

```objc
// Objective-C example
NSError *error = nil;
NSDictionary *result = [service [methodName]:[param1]
                                     [param2]:[param2]
                                        error:&error];

if (result) {
    // Handle success
    NSString *[field1] = result[@"[field1]"];
} else {
    // Handle error
    NSLog(@"Error: %@", error.localizedDescription);
}
```

### Example 2: [Another Use Case]

[Description of the use case]

```bash
# cURL example
curl -X [POST/GET/DELETE] \
  https://pds.example.com/xrpc/[com.atproto.domain.methodName] \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "[param1]": "[value]",
    "[param2]": 123
  }'
```

## Testing

### Unit Test Location

**File:** `ATProtoPDS/Tests/Network/[XrpcDomainMethods]Tests.m`  
**Test Method:** `test[MethodName]`

### Example Test

```objc
- (void)test[MethodName] {
    // Setup
    [XrpcDomainMethods] *methods = [[XrpcDomainMethods] alloc] initWithServices:mockServices];
    HttpRequest *request = [self createMockRequest];
    HttpResponse *response = [[HttpResponse alloc] init];
    
    // Execute
    [methods handle[MethodName]:request response:response];
    
    // Assert
    XCTAssertEqual(response.statusCode, 200);
    NSDictionary *result = [NSJSONSerialization JSONObjectWithData:response.body
                                                           options:0
                                                             error:nil];
    XCTAssertNotNil(result[@"[field1]"]);
}
```

## Performance Considerations

[Optional section - include if relevant]

- [Performance consideration 1]
- [Performance consideration 2]
- [Performance consideration 3]

## Security Considerations

[Optional section - include if relevant]

- [Security consideration 1]
- [Security consideration 2]
- [Security consideration 3]

## Related Endpoints

- [`[com.atproto.domain.relatedMethod1]`](./related-endpoint-1.md) — [Brief description]
- [`[com.atproto.domain.relatedMethod2]`](./related-endpoint-2.md) — [Brief description]
- [`[com.atproto.domain.relatedMethod3]`](./related-endpoint-3.md) — [Brief description]

## See Also

- [Domain Methods](../04-network-layer/domain-methods.md)
- [XRPC Dispatch](../04-network-layer/xrpc-dispatch.md)
- [Auth Helpers](../04-network-layer/auth-helpers.md)
- [Error Handling](../04-network-layer/error-handling.md)
- [[Related Service]](../03-application-layer/[service].md)

---

**Version:** [Version number when this was added/updated]  
**Last Updated:** [Date]  
**Lexicon:** [Link to lexicon definition if available]  
**Source Files:** `ATProtoPDS/Sources/Network/[XrpcDomainMethods].h`, `ATProtoPDS/Sources/Network/[XrpcDomainMethods].m`
