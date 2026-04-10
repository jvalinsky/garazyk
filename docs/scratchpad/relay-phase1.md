# Relay Phase 1: Core Infrastructure

## Overview
Build the foundational components for the ATProto Relay (Sync v1.1).

> Note: Using "Relay" not "BGS" - BGS is the old name from pre-Sync v1.1

## Implementation Status: Complete

### Files Created

| File | Status | Notes |
|------|--------|-------|
| `RelayConfiguration.h/.m` | ✅ | Config with validation modes, 72hr retention default |
| `RelayMetrics.h/.m` | ✅ | Prometheus metrics, connection/event counts |
| `RelayUpstreamManager.h/.m` | ✅ | Multi-PDS connections, auto-reconnect |
| `RelayEventValidator.h/.m` | ✅ | Strict/lenient/log-only validation modes |

### Implementation Notes

- **Validation Modes**: Implemented per Sync v1.1 spec:
  - `lenient`: forward all events regardless
  - `strict`: drop invalid events
  - `logOnly`: validate, log failures, forward anyway (default, matches bsky.network)

- **Retention**: Default 72 hours (per Sync v1.1 spec)

- **Auto-reconnect**: Exponential backoff with 10 max attempts

- **Metrics**: Prometheus format at `/metrics`

## Dependencies

- Existing `RelayClient` for upstream connections
- Existing `MST` for proof validation (stubbed for now)
- Existing `Secp256k1` for signature verification (stubbed for now)

## Linked Deciduous Nodes
- Node 77: Goal - Implement ATProto Relay
- Node 79: Phase 1 Action

## Status: Complete ✅