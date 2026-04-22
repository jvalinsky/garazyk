# Critical Findings

## C1: Firehose `#account` event only emitted on takedown

### Spec Requirement

Per https://atproto.com/specs/sync, the `#account` event type in `com.atproto.sync.subscribeRepos` must be emitted for **all** account lifecycle transitions:

- Account creation → `active=true, status=null`
- Account activation → `active=true, status=null`
- Account deactivation → `active=false, status="deactivated"`
- Account takedown → `active=false, status="takendown"`
- Account deletion → `active=false, status="deleted"`

### Current Implementation

**SubscribeReposHandler.m** has exactly ONE method for account events:

```objc
// Line 482-514
- (void)broadcastAccountTakedown:(NSString *)did {
    // ...
    FirehoseAccountEvent *event = [[FirehoseAccountEvent alloc] init];
    event.did = did;
    event.active = NO;
    event.status = @"takendown";
    event.time = [SubscribeReposHandler rfc3339Timestamp];
    // ...
}
```

This is the ONLY call site that produces a `#account` firehose event. The method name itself reveals the gap — it's specifically for takedowns, not a generic account status broadcast.

**PDSAccountService.m** account creation (line 261-270):

```objc
if (self.serviceDatabases) {
    NSDictionary *details = @{
        @"handle": handle ?: @"",
        @"email": email ?: @""
    };
    [self.serviceDatabases logHostingEvent:resolvedDid
                                      type:@"account_created"
                                   details:details
                                 createdBy:resolvedDid
                                     error:nil];
}
```

This logs a hosting event (internal audit trail) but does NOT broadcast a firehose `#account` event. The relay and AppView never learn about the new account.

**XrpcServerMethods.m** activateAccount (line 1277-1298):

```objc
BOOL success = [adminController reinstateAccount:did error:&error];
// No firehose broadcast follows
```

**XrpcServerMethods.m** deactivateAccount (line 1300-1324):

```objc
BOOL success = [adminController takeDownAccount:did reason:reason ?: @"User deactivation" error:&error];
// No firehose broadcast follows
```

### Reference Implementation Comparison

The Bluesky reference PDS (TypeScript) emits `#account` events on:
- `createAccount` → `{active: true}`
- `activateAccount` → `{active: true}`
- `deactivateAccount` → `{active: false, status: 'deactivated'}`
- `takedownAccount` → `{active: false, status: 'takendown'}`

### Impact

1. **Relay consumers** miss account creation, activation, and deactivation events
2. **AppView** cannot track account status for indexing
3. **Spec-mandated event ordering** (`#identity` → `#account` → `#commit`) is broken
4. **Account status queries** from relay subscribers return stale data

### Remediation Plan

1. Add generic method to `SubscribeReposHandler`:
   ```objc
   - (void)broadcastAccountStatus:(NSString *)did
                           active:(BOOL)active
                           status:(nullable NSString *)status;
   ```

2. Update `broadcastAccountTakedown:` to call the new method:
   ```objc
   - (void)broadcastAccountTakedown:(NSString *)did {
       [self broadcastAccountStatus:did active:NO status:@"takendown"];
   }
   ```

3. Add calls from account lifecycle points:
   - `PDSAccountService.createAccountForEmail` → `broadcastAccountStatus:did active:YES status:nil`
   - `XrpcServerMethods.activateAccount` → `broadcastAccountStatus:did active:YES status:nil`
   - `XrpcServerMethods.deactivateAccount` → `broadcastAccountStatus:did active:NO status:@"deactivated"`

4. Update `SubscribeReposHandler.h` to declare the new method

5. Add tests for each lifecycle transition

---

## C2: Account creation does not emit `#identity` event

### Spec Requirement

Per https://atproto.com/guides/account-lifecycle, when a new account is created, the PDS must emit:
1. `#identity` event (so relays discover the new DID)
2. `#account` event (so relays know the account is active)
3. `#commit` event (for the initial profile record, if any)

### Current Implementation

Account creation in `PDSAccountService.m`:
- Generates DID via PLC
- Saves account to database
- Mints access/refresh tokens
- Logs hosting event (internal only)
- Sends welcome email
- **Does NOT call `broadcastIdentityChange:handle:`**
- **Does NOT call any `#account` broadcast**

The `broadcastIdentityChange:handle:` method exists and works correctly (called from `XrpcIdentityMethods.m:856` for handle updates), but is never invoked from the account creation path.

### Impact

New accounts are completely invisible on the firehose until:
- The user updates their handle (triggers `#identity`)
- The user creates their first record (triggers `#commit`)
- An admin takes action (triggers `#account`)

This means relays and AppViews will not discover new accounts in real-time.

### Remediation Plan

1. After successful account creation in `PDSAccountService.createAccountForEmail`, call:
   ```objc
   [subscribeReposHandler broadcastIdentityChange:resolvedDid handle:handle];
   [subscribeReposHandler broadcastAccountStatus:resolvedDid active:YES status:nil];
   ```

2. This requires passing a reference to `SubscribeReposHandler` to `PDSAccountService`, or using a notification pattern similar to `PDSRecordDidChangeNotification`.

3. Consider adding a `PDSAccountLifecycleNotification` that the `SubscribeReposHandler` observes, similar to how it observes `PDSRecordDidChangeNotification` for commit events.
