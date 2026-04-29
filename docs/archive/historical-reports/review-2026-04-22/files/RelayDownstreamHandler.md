# RelayDownstreamHandler.m — Per-File Analysis

**File**: `Garazyk/Sources/Sync/Relay/RelayDownstreamHandler.m`

## Findings

### M3: Only `#identity` events are forwarded

**Location**: Line 90

```objc
[self broadcastIdentityEvent:identityEvent];
```

The relay subscribes to PDS firehose streams and processes incoming events. Currently only `#identity` events are forwarded to relay subscribers. `#account` events from upstream PDS instances are dropped.

This means even after fixing C1 (PDS emitting `#account` events), relay consumers still won't see them.

### Remediation

Add `#account` event handling:
1. Parse incoming `#account` events from PDS firehose
2. Forward them to relay subscribers via `broadcastAccountEvent:`
3. Persist them in relay event store for replay

## Cross-references

- [[../medium.md#M3]] — Relay #account forwarding
- [[../critical.md#C1]] — Missing #account events on PDS
