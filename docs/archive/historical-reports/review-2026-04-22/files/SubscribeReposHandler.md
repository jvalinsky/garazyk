# SubscribeReposHandler.m — Per-File Analysis

**File**: `Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m`
**Lines**: 960

## Findings

### C1: Only `broadcastAccountTakedown:` emits `#account` events

**Location**: Lines 482-514

The method is named specifically for takedowns and hardcodes `active=NO, status="takendown"`. No other method in the class emits `#account` events.

**Missing methods**:
- `broadcastAccountCreation:handle:` (active=YES, status=nil)
- `broadcastAccountActivation:handle:` (active=YES, status=nil)
- `broadcastAccountDeactivation:handle:` (active=NO, status="deactivated")

**Recommendation**: Replace with generic `broadcastAccountStatus:active:status:` method.

### C2: No `#identity` event on account creation

**Location**: Lines 447-480

`broadcastIdentityChange:handle:` exists and works correctly, but is never called from the account creation path. It's only called from `XrpcIdentityMethods.m:856` for handle updates.

### Event ordering is correct within existing methods

The implementation correctly sequences events on the serial `eventQueue`. The issue is not ordering but missing events entirely.

### Backpressure handling is good

Lines 914-933: `sendEventData:toConnectionWithBackpressureCheck:` properly checks pending send counts and bytes before sending. Connections are detached if they fall behind.

### Replay logic is spec-compliant

Lines 728-793: `replayEventsAfterCursor:toConnection:` correctly replays persisted events in batches, respects the max replay limit, and sends `#info` events for outdated cursors.

### `#sync` fallback is correctly implemented

Lines 407-426: When commit event encoding fails, the code falls back to `#sync` event type per the spec.

## Cross-references

- [[../critical.md#C1]] — Missing `#account` events
- [[../critical.md#C2]] — Missing `#identity` on creation
