# High Priority Findings

## H1: PLC `/export` endpoint buffers all operations in memory

### Spec Reference

https://web.plc.directory/spec/v0.1/did-plc — The `/export` endpoint returns newline-delimited JSON (JSONL) with operations in chronological order.

### Current Implementation

`PLCServer.m:658-705`:

```objc
- (void)handleExport:(HttpRequest *)req response:(HttpResponse *)resp {
    // ...
    NSArray<PLCOperation *> *ops = [self.store exportOperationsAfter:afterDate count:count error:&error];
    // ...
    NSMutableString *jsonLines = [NSMutableString string];
    for (PLCOperation *op in ops) {
        // Build entry dictionary
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:entry options:0 error:nil];
        NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        [jsonLines appendString:jsonStr];
        [jsonLines appendString:@"\n"];
    }
    resp.statusCode = HttpStatusOK;
    resp.contentType = @"application/jsonlines; charset=utf-8";
    [resp setBodyString:jsonLines];
}
```

The entire response is built as a single `NSMutableString` before sending. For a directory with millions of operations, this will:
1. Consume excessive memory
2. Delay the first byte of response until all operations are serialized
3. Potentially OOM the server process

### Reference Implementation

The Bluesky PLC directory server (TypeScript) streams operations one at a time using chunked transfer encoding, keeping memory usage constant regardless of directory size.

### Remediation

Implement streaming response:
1. Add chunked transfer encoding support to `HttpResponse`
2. Process operations in batches (e.g., 100 at a time)
3. Write each JSONL line to the response stream immediately
4. Flush between batches to reduce latency

---

## H2: `com.atproto.server.getAccount` handler declared but not wired

### Spec Reference

https://atproto.com/specs/xrpc — Declared XRPC methods must have working handlers.

### Current Implementation

**Declaration**: `XrpcHandler.h:158`:
```objc
/*! Registers handler for com.atproto.server.getAccount. */
```

**Registration**: `XrpcHandler.m:264`:
```objc
[self registerMethod:@"com.atproto.server.getAccount" handler:handler];
```

**But**: `XrpcServerMethods.m` does NOT include a `getAccount` handler in `registerAccountLifecycleEndpoints:`. The method is registered on the dispatcher with a generic handler wrapper, but no actual implementation is provided.

**Implementation exists**: `PDSAccountService.m:390-399`:
```objc
- (nullable NSDictionary *)getAccountForDid:(NSString *)did error:(NSError **)error {
    PDSDatabaseAccount *account = [_accountRepository accountForDid:did error:error];
    if (!account) return nil;
    return @{
        @"did": account.did ?: @"",
        @"handle": account.handle ?: @"",
        @"email": account.email ?: @""  // ← Also problematic, see M4
    };
}
```

### Impact

Clients calling `com.atproto.server.getAccount` will receive a 501 Not Implemented or empty response.

### Remediation

Add handler registration in `registerAccountLifecycleEndpoints:`:
```objc
[dispatcher registerComAtprotoServerGetAccount:^(HttpRequest *request, HttpResponse *response) {
    NSString *authHeader = [request headerForKey:@"Authorization"];
    NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader ...];
    if (!did) { /* 401 */ return; }
    
    NSError *error = nil;
    NSDictionary *account = [accountService getAccountForDid:did error:&error];
    if (!account) { /* 404 or 500 */ return; }
    
    response.statusCode = HttpStatusOK;
    [response setJsonBody:account];
}];
```

---

## H3: `deactivateAccount` uses `takeDownAccount` semantics

### Spec Reference

https://atproto.com/guides/account-lifecycle — Deactivation is a user-initiated, reversible action. The account status should be `"deactivated"`, not `"takendown"`.

### Current Implementation

`XrpcServerMethods.m:1300-1324`:
```objc
[dispatcher registerComAtprotoServerDeactivateAccount:^(HttpRequest *request, HttpResponse *response) {
    // ...
    NSDictionary *body = request.jsonBody;
    NSString *reason = body[@"reason"];
    NSError *error = nil;
    BOOL success = [adminController takeDownAccount:did reason:reason ?: @"User deactivation" error:&error];
    // ...
}];
```

This calls `takeDownAccount:` which sets the takedown status. User deactivation and admin takedown are semantically different operations:

| Action | `active` | `status` | Who initiates |
|--------|----------|----------|---------------|
| Deactivation | `false` | `"deactivated"` | User |
| Takedown | `false` | `"takendown"` | Admin |
| Activation | `true` | `null` | User |
| Reinstate | `true` | `null` | Admin |

### Impact

- User-initiated deactivation is indistinguishable from admin takedown in the database
- Firehose events (if they were emitted) would show wrong status
- Account recovery flows may behave differently for deactivation vs takedown

### Remediation

1. Add `deactivateAccount:reason:error:` to `PDSAdminController` protocol
2. Set a distinct `"deactivated"` status in the database
3. Update `deactivateAccount` handler to call the new method
4. Ensure firehose `#account` event emits correct status

---

## H4: Account migration flow absent

### Spec Reference

https://atproto.com/guides/account-migration — The AT Protocol requires account migration between PDS instances.

### Missing Endpoints

| Endpoint | Purpose | Status |
|----------|---------|--------|
| `com.atproto.identity.getRecommendedDidCredentials` | Returns recommended DID credentials for migration | Not implemented |
| `com.atproto.identity.requestPlcOperationSignature` | Requests signature for PLC operation | Not implemented |
| `com.atproto.server.prepareDeleteAccount` | Prepares account for deletion/migration | Not implemented |
| `com.atproto.identity.signPlcOperation` | Signs a PLC operation | Not implemented |

### Current State

- `activateAccount`/`deactivateAccount` exist but no migration-specific logic
- No DID rotation key update flow for migration
- No account data export for migration
- No "tombstone" or "moved" status in account model

### Remediation

This is a large scope item. See [[files/migration.md]] for a detailed implementation plan.

**Estimated scope**: 8-12 new endpoints, new account status model, data export/import, PLC operation signing.
