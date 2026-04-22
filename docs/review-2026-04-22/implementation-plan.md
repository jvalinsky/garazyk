# AT Protocol Spec Compliance — Implementation Plan

**Date**: 2026-04-22
**Git**: e4507906
**Decision Graph**: Node #99 (AT Protocol Spec Compliance Remediation)
**Review**: docs/review-2026-04-22/

---

## Phase 1: Fix Firehose Event Emission (Critical) — 1-2 days

**Why**: The PDS is invisible on the firehose for account lifecycle events. Relays and AppViews cannot discover new accounts, track activation/deactivation, or distinguish takedown from deactivation. This is the single highest-impact spec gap.

**Decision Graph**: #100 → #101, #102, #103, #104, #105

### Step 1.1: Add generic `broadcastAccountStatus:active:status:` to SubscribeReposHandler

**Files to modify**:
- [ ] `Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.h` — Declare new method
- [ ] `Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m` — Implement method, refactor `broadcastAccountTakedown:`
- [ ] `Garazyk/Tests/Sync/SubscribeReposHandlerTests.m` — Add tests

**Implementation**:

```objc
// SubscribeReposHandler.h — add after broadcastAccountTakedown:
- (void)broadcastAccountStatus:(NSString *)did
                        active:(BOOL)active
                        status:(nullable NSString *)status;

// SubscribeReposHandler.m — implement
- (void)broadcastAccountStatus:(NSString *)did
                        active:(BOOL)active
                        status:(nullable NSString *)status {
  if (self.stopping) return;
  dispatch_async(self.eventQueue, ^{
    [self ensureSequenceInitialized];
    FirehoseAccountEvent *event = [[FirehoseAccountEvent alloc] init];
    event.did = did;
    event.active = active;
    event.status = status;
    event.time = [SubscribeReposHandler rfc3339Timestamp];
    NSData *eventData = [self.session encodeAccountEvent:event];
    if (!eventData) return;
    NSError *persistError = nil;
    [self.serviceDatabases persistEvent:self.session.sequenceNumber
                                    type:@"account"
                                    data:eventData
                                   error:&persistError];
    [self broadcastEventData:eventData];
    [[PDSMetrics sharedMetrics] incrementFirehoseEvent:@"account"];
    [[PDSMetrics sharedMetrics] setFirehoseSeq:(int64_t)self.session.sequenceNumber];
  });
}

// Refactor broadcastAccountTakedown: to use generic method
- (void)broadcastAccountTakedown:(NSString *)did {
  [self broadcastAccountStatus:did active:NO status:@"takendown"];
}
```

**Tests**:
- Test `broadcastAccountStatus:active:YES status:nil` (creation)
- Test `broadcastAccountStatus:active:NO status:@"deactivated"` (deactivation)
- Test `broadcastAccountStatus:active:NO status:@"takendown"` (takedown, backward compat)
- Test `broadcastAccountTakedown:` still works (regression)

### Step 1.2: Add PDSAccountLifecycleNotification pattern

**Why**: `PDSAccountService` has no reference to `SubscribeReposHandler`. Following the existing pattern of `PDSRecordDidChangeNotification`, add notifications for account lifecycle events.

**Files to create/modify**:
- [ ] `Garazyk/Sources/Core/PDSAccountEvents.h` — Define notification names and user info keys
- [ ] `Garazyk/Sources/Services/PDS/PDSAccountService.m` — Post notifications
- [ ] `Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m` — Observe notifications

**Implementation**:

```objc
// PDSAccountEvents.h
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const PDSAccountCreatedNotification;
extern NSString * const PDSAccountActivatedNotification;
extern NSString * const PDSAccountDeactivatedNotification;

// User info keys
extern NSString * const PDSAccountEventDidKey;
extern NSString * const PDSAccountEventHandleKey;
extern NSString * const PDSAccountEventStatusKey;

NS_ASSUME_NONNULL_END

// PDSAccountEvents.m
#import "Core/PDSAccountEvents.h"

NSString * const PDSAccountCreatedNotification = @"PDSAccountCreatedNotification";
NSString * const PDSAccountActivatedNotification = @"PDSAccountActivatedNotification";
NSString * const PDSAccountDeactivatedNotification = @"PDSAccountDeactivatedNotification";

NSString * const PDSAccountEventDidKey = @"did";
NSString * const PDSAccountEventHandleKey = @"handle";
NSString * const PDSAccountEventStatusKey = @"status";
```

**SubscribeReposHandler.m** — add observer in init:
```objc
[[NSNotificationCenter defaultCenter]
    addObserver:self
       selector:@selector(handleAccountLifecycleEvent:)
           name:PDSAccountCreatedNotification
         object:nil];
[[NSNotificationCenter defaultCenter]
    addObserver:self
       selector:@selector(handleAccountLifecycleEvent:)
           name:PDSAccountActivatedNotification
         object:nil];
[[NSNotificationCenter defaultCenter]
    addObserver:self
       selector:@selector(handleAccountLifecycleEvent:)
           name:PDSAccountDeactivatedNotification
         object:nil];
```

**Handler method**:
```objc
- (void)handleAccountLifecycleEvent:(NSNotification *)notification {
  NSDictionary *info = notification.userInfo;
  NSString *did = info[PDSAccountEventDidKey];
  NSString *handle = info[PDSAccountEventHandleKey];
  if (!did) return;

  if ([notification.name isEqualToString:PDSAccountCreatedNotification]) {
    [self broadcastIdentityChange:did handle:handle];
    [self broadcastAccountStatus:did active:YES status:nil];
  } else if ([notification.name isEqualToString:PDSAccountActivatedNotification]) {
    [self broadcastAccountStatus:did active:YES status:nil];
  } else if ([notification.name isEqualToString:PDSAccountDeactivatedNotification]) {
    NSString *status = info[PDSAccountEventStatusKey] ?: @"deactivated";
    [self broadcastAccountStatus:did active:NO status:status];
  }
}
```

### Step 1.3: Wire account creation to emit notifications

**File**: `Garazyk/Sources/Services/PDS/PDSAccountService.m`

After line 270 (after `logHostingEvent`), add:
```objc
[[NSNotificationCenter defaultCenter]
    postNotificationName:PDSAccountCreatedNotification
                  object:self
                userInfo:@{
                    PDSAccountEventDidKey: resolvedDid,
                    PDSAccountEventHandleKey: handle ?: @""
                }];
```

### Step 1.4: Wire activate/deactivate to emit notifications

**File**: `Garazyk/Sources/Network/XrpcServerMethods.m`

After `activateAccount` success (line ~1297):
```objc
[[NSNotificationCenter defaultCenter]
    postNotificationName:PDSAccountActivatedNotification
                  object:self
                userInfo:@{PDSAccountEventDidKey: did}];
```

After `deactivateAccount` success (line ~1323):
```objc
[[NSNotificationCenter defaultCenter]
    postNotificationName:PDSAccountDeactivatedNotification
                  object:self
                userInfo:@{
                    PDSAccountEventDidKey: did,
                    PDSAccountEventStatusKey: @"deactivated"
                }];
```

### Step 1.5: Add #account event forwarding in RelayDownstreamHandler

**File**: `Garazyk/Sources/Sync/Relay/RelayDownstreamHandler.m`

Add `#account` event handling alongside existing `#identity` handling (line ~90):
```objc
// Forward #account events from upstream PDS
- (void)handleAccountEvent:(FirehoseAccountEvent *)accountEvent {
    [self broadcastAccountEvent:accountEvent];
}
```

Add `broadcastAccountEvent:` method and observer registration.

---

## Phase 2: Account Lifecycle Semantics (High) — 2-3 days

**Why**: Deactivation and takedown are semantically different but use the same code path. `getAccount` is declared but not wired. Email leaks through `getAccount`.

**Decision Graph**: #106 → #107, #108, #109

### Step 2.1: Separate deactivation from takedown

**Files to modify**:
- [ ] `Garazyk/Sources/Admin/PDSAdminController.h` — Add `deactivateAccount:reason:error:` to protocol
- [ ] `Garazyk/Sources/Admin/PDSAdminController.m` — Implement with distinct `"deactivated"` status
- [ ] `Garazyk/Sources/Network/XrpcServerMethods.m` — Call new method from deactivateAccount handler

**PDSAdminController.h** — add to protocol:
```objc
- (BOOL)deactivateAccount:(NSString *)did reason:(NSString *)reason error:(NSError **)error;
```

**PDSAdminController.m** — implement:
```objc
- (BOOL)deactivateAccount:(NSString *)did reason:(NSString *)reason error:(NSError **)error {
    // Set account status to "deactivated" (distinct from "takendown")
    // This is a user-initiated, reversible action
    return [self setAccountStatus:did
                           active:NO
                           status:@"deactivated"
                           reason:reason
                            error:error];
}
```

**XrpcServerMethods.m** — update deactivateAccount handler:
```objc
// Change from:
BOOL success = [adminController takeDownAccount:did reason:reason ?: @"User deactivation" error:&error];
// To:
BOOL success = [adminController deactivateAccount:did reason:reason ?: @"User deactivation" error:&error];
```

### Step 2.2: Wire com.atproto.server.getAccount handler

**File**: `Garazyk/Sources/Network/XrpcServerMethods.m`

Add in `registerAccountLifecycleEndpoints:`:
```objc
[dispatcher registerComAtprotoServerGetAccount:^(HttpRequest *request, HttpResponse *response) {
    NSString *authHeader = [request headerForKey:@"Authorization"];
    NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                   jwtMinter:jwtMinter
                                              adminController:adminController
                                                     request:request
                                                    response:response];
    if (!did) {
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{@"error": @"AuthRequired"}];
        return;
    }

    NSError *error = nil;
    NSDictionary *account = [accountService getAccountForDid:did error:&error];
    if (!account) {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"AccountNotFound"}];
        return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:account];
}];
```

### Step 2.3: Remove email from getAccountForDid: response

**File**: `Garazyk/Sources/Services/PDS/PDSAccountService.m`

Change:
```objc
return @{
    @"did": account.did ?: @"",
    @"handle": account.handle ?: @"",
    @"email": account.email ?: @""  // REMOVE
};
```
To:
```objc
return @{
    @"did": account.did ?: @"",
    @"handle": account.handle ?: @""
};
```

---

## Phase 3: PLC Improvements (High) — 3-5 days

**Why**: PLC export will OOM at scale. Validation is too lenient. No recovery window for key rotation.

**Decision Graph**: #110 → #111, #112, #113

### Step 3.1: Implement streaming /export endpoint

**Files to modify**:
- [ ] `Garazyk/Sources/Network/HttpResponse.h` — Add chunked transfer encoding support
- [ ] `Garazyk/Sources/Network/HttpResponse.m` — Implement streaming write methods
- [ ] `Garazyk/Sources/PLC/PLCServer.m` — Rewrite `handleExport:` to stream
- [ ] `Garazyk/Sources/PLC/PLCPersistentStore.m` — Add batched export method with cursor

**HttpResponse** — add streaming support:
```objc
// HttpResponse.h
@property (nonatomic, assign) BOOL chunkedTransferEncoding;
- (void)beginChunkedResponse;
- (void)writeChunk:(NSData *)data;
- (void)endChunkedResponse;
```

**PLCServer.m** — rewrite handleExport:
```objc
- (void)handleExport:(HttpRequest *)req response:(HttpResponse *)resp {
    // Parse count/after params (same as before)
    // ...
    resp.statusCode = HttpStatusOK;
    resp.contentType = @"application/jsonlines; charset=utf-8";
    [resp beginChunkedResponse];

    NSDate *cursorDate = afterDate;
    NSInteger remaining = count;

    while (remaining > 0) {
        NSInteger batchSize = MIN(remaining, 100);
        NSError *error = nil;
        NSArray<PLCOperation *> *ops = [self.store exportOperationsAfter:cursorDate count:batchSize error:&error];
        if (error || !ops || ops.count == 0) break;

        for (PLCOperation *op in ops) {
            // Build entry dict and serialize
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:entry options:0 error:nil];
            if (jsonData) {
                NSMutableData *lineData = [jsonData mutableCopy];
                [lineData appendBytes:"\n" length:1];
                [resp writeChunk:lineData];
            }
            cursorDate = op.createdAt;
        }

        remaining -= ops.count;
        if (ops.count < batchSize) break;
    }

    [resp endChunkedResponse];
}
```

### Step 3.2: Add stricter PLC validation

**File**: `Garazyk/Sources/PLC/PLCServer.m`

In `PLCValidateIncomingOperation`, after alsoKnownAs length check:
```objc
for (NSString *aka in alsoKnownAs) {
    // ... existing length check ...
    if (![aka hasPrefix:@"at://"]) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCValidationErrorDomain"
                                         code:25
                                     userInfo:@{NSLocalizedDescriptionKey: @"alsoKnownAs entry must start with at://"}];
        }
        return NO;
    }
}
```

For service endpoints:
```objc
NSString *endpoint = service[@"endpoint"];
if (![endpoint hasPrefix:@"https://"] && ![endpoint hasPrefix:@"http://localhost"]) {
    // Reject non-HTTPS endpoints (allow localhost for testing)
}
```

### Step 3.3: Implement PLC recovery window

**Files to modify**:
- [ ] `Garazyk/Sources/PLC/PLCPersistentStore.m` — Add pending_operations table
- [ ] `Garazyk/Sources/PLC/PLCServer.m` — Implement recovery window logic
- [ ] `Garazyk/Sources/PLC/PLCAuditor.m` — Check recovery window during verification

This is the most complex PLC change. The recovery window means:
1. When a rotation key change is submitted, store it as "pending" with a timestamp
2. The previous rotation key can revert the change within 72 hours
3. After the window expires, the change becomes permanent
4. During the window, both the old and new keys are valid for signing

---

## Phase 4: Testnet Improvements (Medium) — 1-2 days

**Decision Graph**: #114 → #115, #116

### Step 4.1: Fix Docker key persistence

**File**: `docker/local-network/docker-compose.yml`

Replace `/tmp` host mounts with named volumes:
```yaml
volumes:
  plc-data:
  pds-data:

services:
  plc:
    volumes:
      - plc-data:/data
  pds:
    volumes:
      - pds-data:/data
```

### Step 4.2: Add AppView to E2E stack

**File**: `docker/e2e/docker-compose.yml`

Add syrena service:
```yaml
  appview:
    build:
      context: ../..
      dockerfile: docker/Dockerfile.gnustep
      target: runtime
    entrypoint: ["./syrena"]
    command: ["--port", "3200", "--relay-url", "ws://relay:2584", "--plc-url", "http://plc:2582"]
    ports:
      - "3200:3200"
    depends_on:
      relay:
        condition: service_healthy
```

---

## Phase 5: Account Migration (Deferred — 6-10 weeks)

**Decision Graph**: #117 (depends on #100, #106)

See `docs/review-2026-04-22/files/migration.md` for detailed plan.

This phase requires Phases 1-2 to be complete first because:
- Migration needs the generic `broadcastAccountStatus:` method
- Migration needs distinct deactivation/takedown semantics
- Migration needs `getAccount` endpoint to be working

---

## Build & Test Checklist

After each phase, verify:

- [ ] `cmake --build build --target AllTests` passes
- [ ] `./scripts/check_module_boundaries.sh` passes
- [ ] New tests added for each feature
- [ ] No regressions in existing tests
- [ ] Docker testnet starts successfully
- [ ] Firehose events visible in relay subscription

## Git Commit Strategy

After each step:
1. Stage specific files by name (never `git add -A`)
2. Commit with conventional commit format:
   - `feat(sync): add generic broadcastAccountStatus method`
   - `fix(sync): emit #account events on account creation`
   - `fix(xrpc): wire com.atproto.server.getAccount handler`
   - `fix(pds): separate deactivation from takedown semantics`
   - `feat(plc): implement streaming /export endpoint`
3. Push to remote after each phase is complete
