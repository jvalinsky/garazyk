# ATProto Relay Implementation - Master Plan

## Overview
Implement a full BGS (Big Graph Service) / Relay in Objective-C for the AT Protocol network.

## Background
Based on Sync v1.1 specification, relays can handle ~2000 msg/sec on 2 vCPU, 12GB RAM. The relay is "non-archival" - it doesn't store full repo data, just forwards events.

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  PDS Instances  │────▶│   BGS Relay    │────▶│  AppViews/     │
│  (upstream)      │     │  (this impl)    │     │  Consumers     │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │ Event Buffer    │
                    │ (24hr retention)│
                    └─────────────────┘
```

## Deciduous Nodes

| Node | Type | Description |
|------|------|-------------|
| 77 | goal | Implement ATProto Relay (BGS) in Objective-C |
| 78 | action | Research existing relay components |
| 79 | action | Phase 1: Core Infrastructure |
| 80 | action | Phase 2: Event Processing |
| 81 | action | Phase 3: XRPC Endpoints |
| 82 | action | Phase 4: CLI/REPL |
| 83 | action | Phase 5: Testing & Validation |

## Scratchpads

| Phase | File | Description |
|-------|------|-------------|
| 1 | `relay-phase1.md` | Core Infrastructure - BGSUpstreamManager, BGSConfiguration, RelayEventValidator, BGSMetrics |
| 2 | `relay-phase2.md` | Event Processing - EventFilter, EventBuffer, RepoStateManager, CrawlRequestHandler |
| 3 | `relay-phase3.md` | XRPC Endpoints - getHead, getRepo, requestCrawl, listHosts |
| 4 | `relay-phase4.md` | CLI/REPL - serve, repl, upstream, status commands |
| 5 | `relay-phase5.md` | Testing - Unit, Integration, Interop, Performance |

## Existing Components (Node 78)

The codebase already has:
- `RelayClient` - Client for subscribing to relay feeds
- `Firehose` - Firehose subscription with DAG-CBOR decoding  
- `WebSocketServer` - Server-side WebSocket handling
- `EventFormatter` - XRPC stream frame encoding
- `SubscribeReposHandler` - Full implementation of subscribeRepos endpoint

## Key Dependencies

1. **Networking**: Network.framework (already in use)
2. **Database**: SQLite for state persistence (already in use)
3. **Cryptography**: Secp256k1 for signature verification (already in use)
4. **MST**: Existing MST implementation for proof validation

## Questions to Resolve Before Implementation

1. **Scope**: Full-network relay or partial/community?
2. **Upstream**: Connect to official bsky.network or other PDS?
3. **Retention**: Default 24hr backfill?
4. **Validation**: Lenient vs strict MST verification?

## Next Steps

Decide on scope and begin Phase 1 implementation.

## Last Updated
2026-04-09