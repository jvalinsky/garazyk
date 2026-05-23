---
title: Documentation Map
---

# Documentation Map

Every document in the repository, organized by subsystem and type.

## Root Entrypoints

| Path | Type | Description |
|---|---|---|
| `README.md` | Entrypoint | Project overview, build instructions, licensing |
| `AGENTS.md` | Entrypoint | AI assistant operational guidance |
| `AGENTS_QUICKREF.md` | Entrypoint | Quick reference for AI assistants |

## Core PDS Documentation

| Path | Type | Description |
|---|---|---|
| `Garazyk/docs-site/src/content/docs/fundamentals/at-protocol.md` | Explanation | AT Protocol fundamentals |
| `Garazyk/docs-site/src/content/docs/fundamentals/objective-c-env.md` | Explanation | Objective-C environment setup |
| `Garazyk/docs-site/src/content/docs/core-server/http-server.md` | Reference | HTTP server architecture |
| `Garazyk/docs-site/src/content/docs/core-server/sqlite-persistence.md` | Reference | SQLite persistence layer |
| `Garazyk/docs-site/src/content/docs/core-server/gcd-threading.md` | Reference | GCD threading model |
| `Garazyk/docs-site/src/content/docs/advanced-parsing/fast-parsing.md` | Explanation | Fast parsing techniques |
| `Garazyk/docs-site/src/content/docs/advanced-parsing/sans-io-architecture.md` | Explanation | Sans-I/O architecture |
| `Garazyk/docs-site/src/content/docs/advanced-parsing/db-pool-concurrency.md` | Reference | Database pool concurrency |
| `Garazyk/Sources/Database/ARCHITECTURE.md` | Explanation | Database layer architecture |
| `Garazyk/Sources/Database/README.md` | Reference | Database layer overview |

## AT Protocol

| Path | Type | Description |
|---|---|---|
| `Garazyk/docs-site/src/content/docs/atproto/cryptography.md` | Reference | Cryptographic operations |
| `Garazyk/docs-site/src/content/docs/atproto/data-modeling.md` | Explanation | Data modeling patterns |
| `Garazyk/docs-site/src/content/docs/atproto/merkle-search-trees.md` | Reference | Merkle Search Tree implementation |

## Auth & Federation

| Path | Type | Description |
|---|---|---|
| `Garazyk/docs-site/src/content/docs/auth/oauth-dpop.md` | Reference | OAuth DPoP implementation |
| `Garazyk/docs-site/src/content/docs/auth/hardware-security.md` | Reference | Hardware security integration |
| `Garazyk/docs-site/src/content/docs/federation/firehose.md` | Explanation | Firehose protocol |
| `Garazyk/docs-site/src/content/docs/federation/websockets.md` | Reference | WebSocket handling |

## Admin UI

| Path | Type | Description |
|---|---|---|
| `Garazyk/Sources/Admin/ADMINUI_ARCHITECTURE.md` | Explanation | AdminUI architecture |
| `Garazyk/Sources/Admin/ADMINUI_DELIVERY_SUMMARY.md` | Reference | Delivery summary |
| `Garazyk/Sources/Admin/ADMINUI_IMPLEMENTATION_STATUS.md` | Reference | Implementation status |
| `Garazyk/Sources/Admin/ADMINUI_INTEGRATION_COMPLETE.md` | Reference | Integration complete |
| `Garazyk/Sources/Admin/ADMINUI_INTEGRATION.md` | Reference | Integration guide |
| `Garazyk/Sources/Admin/Diagnostics/README.md` | Reference | Diagnostics module |
| `Garazyk/Sources/AdminUIServer/Assets/DESIGN_SYSTEM.md` | Reference | Design system |
| `Garazyk/Sources/AdminUIServer/Assets/QUICK_REFERENCE.md` | Reference | Quick reference |
| `Garazyk/Sources/AdminUIServer/Assets/README.md` | Reference | Assets README |

## Testing

| Path | Type | Description |
|---|---|---|
| `Garazyk/Tests/fixtures/atproto-interop-tests/README.md` | Reference | Interop test fixtures |
| `Garazyk/Tests/plc_e2e/README.md` | Reference | PLC end-to-end tests |

## Guides & Other

| Path | Type | Description |
|---|---|---|
| `docs/10-tutorials/germ-mailbox-setup.md` | Guide | Germ E2EE Mailbox setup guide |
| `Garazyk/docs/guides/objective_c_research_guide.md` | Guide | ObjC research guide |
| `Garazyk/docs/guides/objective_c_tips.md` | Guide | ObjC development tips |
| `Garazyk/Frameworks/README.md` | Reference | Framework dependencies |

## TUI (Historical Reference)

| Path | Type | Description |
|---|---|---|
| `docs/tui/README.md` | Explanation | TUI overview (deprecated) |
| `docs/tui/architecture.md` | Explanation | Event loop architecture |
| `docs/tui/core-primitives.md` | Reference | Renderer, input, focus |
| `docs/tui/components.md` | Reference | Layout & components |
| `docs/tui/theme-architecture.md` | Reference | Theme system design |
| `docs/tui/runtime.md` | Reference | TEA state bridge |
