# Relay Phase 4: CLI & REPL

## Overview
Build command-line interface for the BGS relay similar to kaszlak PDS CLI.

---

## Commands

### 4.1 serve
```bash
bgs serve [options]

Options:
  --port, -p          Port for downstream consumers (default: 2584)
  --upstream, -u       Upstream relay URL (can be specified multiple times)
  --retention-hours    Event retention window (default: 24)
  --data-dir           Data directory for state persistence
  --config             Config file path
  --foreground          Run in foreground
  --help               Show help
```

### 4.2 repl
```bash
bgs repl [options]
# Interactive mode similar to kaszlak CLI
```

### 4.3 upstream management
```bash
# Add upstream relay
bgs upstream add wss://bsky.network

# Remove upstream
bgs upstream remove wss://bsky.network

# List upstreams with status
bgs upstream list
```

### 4.4 status
```bash
bgs status

Output:
  Uptime: 2h 34m
  Upstreams: 2 connected, 1 reconnecting
  Downstreams: 1547 connected
  Events (1h): 1.2M received, 1.2M validated, 1.2M forwarded
  Events (24h): 28.5M received
  Storage: 4.2GB used (events), 150MB used (state)
```

### 4.5 metrics
```bash
bgs metrics
# Output Prometheus-format metrics at /metrics endpoint
```

---

## Implementation

**Base on existing PLC/PDS CLI pattern:**

1. Create `BGSCLICommand` classes:
   - `BGSServeCommand` - Start relay server
   - `BGSUpstreamCommand` - Manage upstream connections
   - `BGSStatusCommand` - Show relay status
   - `BGSReplCommand` - Interactive REPL

2. Add to `main.m` similar to PLC server:
   - Parse commands: serve, repl, upstream, status, version, help
   - Options: --port, --upstream, --retention-hours, --data-dir
   - REPL with readline (same as kaszlak/plc)

3. Integrate with existing components:
   - `BGSConfiguration` for settings
   - `BGSMetrics` for status output

---

## Aliases

| Command | Aliases |
|---------|---------|
| serve | s, start, run |
| upstream | u, up |
| status | stats, info |
| repl | shell, interactive |

---

## Linked Deciduous Nodes
- Node 77: Goal - Implement ATProto Relay
- Node 82: Phase 4 Action

## Status: Pending