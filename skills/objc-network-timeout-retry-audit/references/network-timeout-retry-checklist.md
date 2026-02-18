# Network Timeout and Retry Checklist

Use this checklist while validating candidates from `scan_network_timeout_retry.sh`.

## Timeout policy
- Verify connect/read/write operations have explicit timeout behavior.
- Verify timeout values are bounded and configurable where appropriate.
- Verify timeout errors are surfaced distinctly from generic failures.

## Retry policy
- Verify retries are bounded and include backoff (prefer jitter).
- Verify non-idempotent operations are not retried blindly.
- Verify terminal error conditions break retry loops.

## Cancellation and shutdown
- Verify cancellation interrupts pending IO promptly.
- Verify shutdown closes sockets and releases event sources safely.
- Verify no zombie retry tasks survive caller cancellation.
