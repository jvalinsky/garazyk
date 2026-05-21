# Sub-plan: 33 — Firehose Backpressure (Tortoise Consumer)

## Problem
Firehose disconnect test timed out — connection stayed open when it was expected to close due to backpressure.

## Investigation

### Expected behavior
- Tortoise consumer subscribes to firehose
- Consumer is deliberately slow (or it's the firehose being slow)
- After some threshold, the firehose should disconnect the consumer (backpressure signal)

### Root cause candidates
1. **Subscription timeout not configured**: The firehose may not have a consumer timeout/disconnect threshold set
2. **Backpressure not implemented**: The subscription relay may not track consumer processing speed
3. **Timeout too long**: Scenario may not wait long enough for the disconnect
4. **Wrong disconnect mechanism**: The firehose may use cursor-based disconnect instead of timeout

## Work

### 1. Find firehose subscription implementation
- Search for WebSocket subscription relay code in `Garazyk/Sources/`
- Look for `com.atproto.sync.subscribeRepos` handler
- Find how consumers are tracked and disconnected

### 2. Check backpressure/disconnect logic
- Does the relay track consumer message queue depth?
- Is there a maximum queue size or timeout?
- Are slow consumers ever disconnected?

### 3. Scenario vs. implementation mismatch
- Check what the scenario expects vs. what the implementation does
- May need to adjust the scenario timeout or implement the disconnect mechanism

## Files
- `Garazyk/Sources/Network/` (WebSocket/subscription handler)
- `Garazyk/Sources/Relay/` or `Garazyk/Sources/Sync/` (firehose relay)
- `scripts/scenarios/scenarios/33_tortoise_consumer.ts` (scenario)

## Verification
```bash
nix develop -c bash -c "cd scripts/scenarios && deno run -A e2e_runner.ts --scenario 33"
```
