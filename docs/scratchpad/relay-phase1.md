# Relay Phase 1: Core Infrastructure

## Overview
Build the foundational components for the BGS relay implementation.

## Research Findings (Node 78)

### Existing Components
- **RelayClient** (`ATProtoPDS/Sources/Sync/RelayClient.m`): Client for subscribing to relay feeds
- **Firehose** (`ATProtoPDS/Sources/Sync/Firehose.m`): Firehose subscription with DAG-CBOR decoding
- **WebSocketServer** (`ATProtoPDS/Sources/Sync/WebSocketServer.m`): Server-side WebSocket handling
- **EventFormatter** (`ATProtoPDS/Sources/Sync/EventFormatter.m`): XRPC stream frame encoding

### Gaps Identified
- No multi-upstream support (need to subscribe to multiple PDS/relays)
- No relay-specific metrics
- No event validation component
- No BGS configuration class

---

## Tasks

### 1.1 Extend RelayClient for Multi-Upstream
```
New class: BGSUpstreamManager
- Maintains array of RelayClient instances
- Tracks upstream health/reliability
- Automatic failover to healthy upstream
- Load balancing across upstreams
```

**Files to create:**
- `ATProtoPDS/Sources/Sync/BGSUpstreamManager.h`
- `ATProtoPDS/Sources/Sync/BGSUpstreamManager.m`

### 1.2 Create BGSConfiguration
```
Configuration options:
- upstream_relays: []string - List of upstream relay URLs
- downstream_port: uint16 - Port for downstream consumers
- retention_hours: int - Event retention window
- validation_mode: "strict" | "lenient" - MST verification level
- max_connections: int - Max downstream connections
- data_dir: string - Local storage path
```

**Files to create:**
- `ATProtoPDS/Sources/Sync/BGSConfiguration.h`
- `ATProtoPDS/Sources/Sync/BGSConfiguration.m`

### 1.3 Implement RelayEventValidator
```
Responsibilities:
- Verify repo signatures (secp256k1)
- Validate MST proofs
- Check operation validity
- Reject malformed events

Implementation:
- Use existing Secp256k1.m for signature verification
- Use MST.m for proof validation
- Track validation metrics (success/failure counts)
```

**Files to create:**
- `ATProtoPDS/Sources/Sync/RelayEventValidator.h`
- `ATProtoPDS/Sources/Sync/RelayEventValidator.m`

### 1.4 Create BGSMetrics
```
Metrics to track:
- upstream_connections: gauge
- downstream_connections: gauge  
- events_received_total: counter
- events_validated_total: counter
- events_invalid_total: counter
- events_forwarded_total: counter
- validation_duration_ms: histogram
- reconnection_count: counter

Prometheus-compatible output at /metrics
```

**Files to create:**
- `ATProtoPDS/Sources/Sync/BGSMetrics.h`
- `ATProtoPDS/Sources/Sync/BGSMetrics.m`

---

## Notes

- Sync v1.1 spec: relay can handle ~2000 msg/sec on 2 vCPU, 12GB RAM
- Start with lenient mode for MST validation, enable strict later
- Use dispatch queues for concurrent event processing

## Linked Deciduous Nodes
- Node 77: Goal - Implement ATProto Relay
- Node 79: Phase 1 Action

## Status: Pending