---
title: Source-Adjacent Documentation
---

# Source-Adjacent Documentation

Documentation that lives alongside source code rather than in `docs/`. These 32
files are co-located with the modules they describe and are updated alongside
code changes.

## Core Server

| File                                                                   | Module                |
| ---------------------------------------------------------------------- | --------------------- |
| `Garazyk/docs-site/src/content/docs/core-server/http-server.md`        | HTTP server           |
| `Garazyk/docs-site/src/content/docs/core-server/sqlite-persistence.md` | SQLite layer          |
| `Garazyk/docs-site/src/content/docs/core-server/gcd-threading.md`      | Concurrency           |
| `Garazyk/Sources/Database/ARCHITECTURE.md`                             | Database architecture |
| `Garazyk/Sources/Database/README.md`                                   | Database overview     |

## AT Protocol

| File                                                                | Module        |
| ------------------------------------------------------------------- | ------------- |
| `Garazyk/docs-site/src/content/docs/atproto/cryptography.md`        | Cryptography  |
| `Garazyk/docs-site/src/content/docs/atproto/data-modeling.md`       | Data modeling |
| `Garazyk/docs-site/src/content/docs/atproto/merkle-search-trees.md` | MST           |

## Federation

| File                                                          | Module    |
| ------------------------------------------------------------- | --------- |
| `Garazyk/docs-site/src/content/docs/federation/firehose.md`   | Firehose  |
| `Garazyk/docs-site/src/content/docs/federation/websockets.md` | WebSocket |

## Auth

| File                                                           | Module            |
| -------------------------------------------------------------- | ----------------- |
| `Garazyk/docs-site/src/content/docs/auth/oauth-dpop.md`        | OAuth/DPoP        |
| `Garazyk/docs-site/src/content/docs/auth/hardware-security.md` | Hardware security |

## Parsing

| File                                                                          | Module       |
| ----------------------------------------------------------------------------- | ------------ |
| `Garazyk/docs-site/src/content/docs/advanced-parsing/fast-parsing.md`         | Fast parsing |
| `Garazyk/docs-site/src/content/docs/advanced-parsing/sans-io-architecture.md` | Sans-I/O     |
| `Garazyk/docs-site/src/content/docs/advanced-parsing/db-pool-concurrency.md`  | DB pool      |

## Fundamentals

| File                                                                 | Module           |
| -------------------------------------------------------------------- | ---------------- |
| `Garazyk/docs-site/src/content/docs/fundamentals/at-protocol.md`     | AT Protocol      |
| `Garazyk/docs-site/src/content/docs/fundamentals/objective-c-env.md` | ObjC environment |

## Admin UI

| File                                                            | Module                    |
| --------------------------------------------------------------- | ------------------------- |
| `Garazyk/Sources/Admin/ADMINUI_ARCHITECTURE.md`                 | Legacy architecture input |
| `Garazyk/Sources/Admin/archive/ADMINUI_DELIVERY_SUMMARY.md`     | Archived delivery         |
| `Garazyk/Sources/Admin/archive/ADMINUI_INTEGRATION_COMPLETE.md` | Archived integration      |
| `Garazyk/Sources/Admin/Diagnostics/README.md`                   | Diagnostics               |
| `Garazyk/Sources/AdminUIServer/Assets/DESIGN_SYSTEM.md`         | Design system             |
| `Garazyk/Sources/AdminUIServer/Assets/QUICK_REFERENCE.md`       | Quick reference           |
| `Garazyk/Sources/AdminUIServer/Assets/README.md`                | Assets                    |

## Testing & Fixtures

| File                                                     | Module        |
| -------------------------------------------------------- | ------------- |
| `Garazyk/Tests/fixtures/atproto-interop-tests/README.md` | Interop tests |
| `Garazyk/Tests/plc_e2e/README.md`                        | PLC E2E       |

## Guides

| File                                                | Module     |
| --------------------------------------------------- | ---------- |
| `Garazyk/docs/guides/objective_c_research_guide.md` | Research   |
| `Garazyk/docs/guides/objective_c_tips.md`           | Tips       |
| `Garazyk/Frameworks/README.md`                      | Frameworks |
