# Firehose Ordering and Backpressure Checklist

Use this checklist while validating candidates from `scan_firehose_backpressure.sh`.

## Ordering invariants
- Verify sequence or cursor is monotonic for all emitted events.
- Verify reconnect replay starts from the expected cursor boundary.
- Verify no branch can emit an older event after a newer one.

## Backpressure behavior
- Verify per-connection buffers are bounded.
- Verify overflow behavior is explicit (drop, disconnect, or block).
- Verify slow-consumer behavior does not impact global producer latency.

## Recovery and reliability
- Verify dropped/disconnected consumers can recover deterministically.
- Verify retry logic does not duplicate or skip events silently.
- Verify metrics/logging expose queue depth and drop counts.
