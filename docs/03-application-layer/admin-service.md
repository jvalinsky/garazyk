# Admin Service

## Overview

The `PDSAdminService` provides administrative operations for PDS management including account moderation, takedowns, labeling, and system administration. It handles privileged operations that require admin authentication.

## Responsibilities

- Account suspension and deletion
- Record takedowns
- Label management
- Moderation actions
- Admin audit logging
- System configuration
- User management

## Architecture

```
┌──────────────────────────────────────────┐
│   XRPC Admin Endpoints                   │
│  (com.atproto.admin.*)                   │
└────────────────┬─────────────────────────┘
                 │
┌────────────────▼─────────────────────────┐
│   PDSAdminService                        │
│  - suspendAccount()                      │
│  - deleteAccount()                       │
│  - takedownRecord()                      │
│  - addLabel()                            │
│  - removeLabel()                         │
│  - getModeration()                       │
└────────────────┬─────────────────────────┘
                 │
        ┌────────┴────────┐
        │                 │
┌───────▼──────────┐  ┌──▼──────────────┐
│ Audit Logging    │  │ Moderation DB   │
│ (Admin Actions)  │  │ (Labels/Status) │
└──────────────────┘  └──────────────────┘
        │
        └────────┬────────┘
                 │
        ┌────────▼────────────┐
        │ PDSServiceDatabases │
        │ (Admin Data)        │
        └─────────────────────┘
```

## Key Operations

### Account Suspension

Temporarily disables an account while preserving data:

```objc
- (BOOL)suspendAccount:(NSString *)did 
              reason:(NSString *)reason 
             error:(NSError **)error;
```

**Effects:**
- Account cannot login
- Records are hidden from search
- Blobs are inaccessible
- Data is preserved for restoration

**Example:**
```objc
NSError *error = nil;
BOOL success = [adminService suspendAccount:@"did:plc:user123"
                                     reason:@"Violation of terms of service"
                                      error:&error];
```

### Account Deletion

Permanently removes an account and all associated data:

```objc
- (BOOL)deleteAccount:(NSString *)did 
             reason:(NSString *)reason 
            error:(NSError **)error;
```

**Effects:**
- Account is permanently deleted
- All records are removed
- All blobs are deleted
- Data cannot be recovered

**Example:**
```objc
NSError *error = nil;
BOOL success = [adminService deleteAccount:@"did:plc:user123"
                                    reason:@"User requested deletion"
                                     error:&error];
```

### Record Takedown

Removes a specific record from the repository:

```objc
- (BOOL)takedownRecord:(NSString *)uri 
              reason:(NSString *)reason 
             error:(NSError **)error;
```

**Parameters:**
- `uri`: AT URI of record to remove
- `reason`: Takedown reason
- `error`: Error pointer

**Example:**
```objc
NSError *error = nil;
BOOL success = [adminService takedownRecord:@"at://did:plc:user123/app.bsky.feed.post/abc123"
                                     reason:@"Illegal content"
                                      error:&error];
```

### Label Management

Adds labels to accounts or records for moderation:

```objc
- (BOOL)addLabel:(NSString *)label 
        toTarget:(NSString *)target 
         reason:(NSString *)reason 
        error:(NSError **)error;

- (BOOL)removeLabel:(NSString *)label 
          fromTarget:(NSString *)target 
             error:(NSError **)error;
```

**Common Labels:**
- `!no-unauthenticated`: Hide from unauthenticated users
- `!no-unknown`: Hide from unknown users
- `!warn`: Show warning before viewing
- `!impersonation`: Impersonation warning
- `!spam`: Spam label

**Example:**
```objc
NSError *error = nil;

// Add warning label
BOOL success = [adminService addLabel:@"!warn"
                             toTarget:@"did:plc:user123"
                               reason:@"Potentially sensitive content"
                                error:&error];

// Remove label
success = [adminService removeLabel:@"!warn"
                         fromTarget:@"did:plc:user123"
                              error:&error];
```

### Get Moderation Status

Retrieves moderation information for an account or record:

```objc
- (nullable NSDictionary *)getModerationForTarget:(NSString *)target 
                                            error:(NSError **)error;
```

**Returns:** Dictionary with:
- `labels`: Array of applied labels
- `suspended`: Boolean suspension status
- `reason`: Moderation reason
- `actionedAt`: Timestamp of last action

**Example:**
```objc
NSError *error = nil;
NSDictionary *moderation = [adminService getModerationForTarget:@"did:plc:user123"
                                                          error:&error];

if (moderation) {
    NSArray *labels = moderation[@"labels"];
    BOOL suspended = [moderation[@"suspended"] boolValue];
}
```

## Audit Logging

All admin actions are logged with:

- Admin DID who performed action
- Action type (suspend, delete, label, etc.)
- Target (account or record)
- Reason provided
- Timestamp
- Result (success/failure)

**Example log entry:**
```
{
  "admin": "did:plc:admin123",
  "action": "suspend",
  "target": "did:plc:user123",
  "reason": "Violation of terms of service",
  "timestamp": "2025-01-15T10:30:00Z",
  "result": "success"
}
```

## Moderation Workflow

### Typical Moderation Process

```
1. Report received
   ↓
2. Admin reviews content
   ↓
3. Admin applies label (if warning needed)
   ↓
4. If severe: takedown record or suspend account
   ↓
5. Log action in audit trail
   ↓
6. Notify user (if applicable)
   ↓
7. Monitor for appeals
```

## Error Handling

Common error scenarios:

| Error | Cause | Handling |
|-------|-------|----------|
| Not found | Target doesn't exist | Return 404 |
| Unauthorized | Not admin | Return 403 |
| Invalid label | Unknown label | Return 400 |
| Already suspended | Account already suspended | Return 409 |
| Invalid reason | Reason too short/long | Return 400 |

## Best Practices

1. **Moderation Actions**
   - Always provide clear reason
   - Use appropriate labels before takedown
   - Document all actions
   - Follow due process

2. **Account Suspension**
   - Suspend before delete to allow appeals
   - Preserve data for investigation
   - Notify user of suspension
   - Set appeal deadline

3. **Audit Trail**
   - Log all admin actions
   - Include admin identity
   - Timestamp all actions
   - Retain logs for compliance

4. **Escalation**
   - Have clear escalation procedures
   - Multiple admins for serious actions
   - Review high-impact decisions
   - Document reasoning

## Common Patterns

### Handling a Reported Post

```objc
// 1. Get moderation status
NSError *error = nil;
NSDictionary *moderation = [adminService getModerationForTarget:reportedUri
                                                          error:&error];

// 2. Review content (admin UI)
// ...

// 3. Apply label if warning needed
[adminService addLabel:@"!warn"
             toTarget:reportedUri
               reason:@"Potentially sensitive content"
                error:&error];

// 4. If severe, takedown
[adminService takedownRecord:reportedUri
                      reason:@"Illegal content"
                       error:&error];
```

### Suspending a Problematic Account

```objc
// 1. Get account moderation status
NSError *error = nil;
NSDictionary *moderation = [adminService getModerationForTarget:userDid
                                                          error:&error];

// 2. Review account history
// ...

// 3. Suspend account
BOOL success = [adminService suspendAccount:userDid
                                     reason:@"Multiple violations of terms"
                                      error:&error];

// 4. Notify user
[self notifyUserOfSuspension:userDid reason:@"Multiple violations"];

// 5. Set appeal deadline
[self setAppealDeadline:userDid days:30];
```

### Bulk Moderation Action

```objc
// Apply label to multiple accounts
NSArray *violatingAccounts = @[
    @"did:plc:user1",
    @"did:plc:user2",
    @"did:plc:user3"
];

for (NSString *did in violatingAccounts) {
    NSError *error = nil;
    [adminService addLabel:@"!spam"
                 toTarget:did
                   reason:@"Spam network detected"
                    error:&error];
}
```

## See Also

- [Services Overview](./services-overview)
- [PDSApplication](./pds-application)
- [Authentication](../06-authentication/jwt-tokens)
