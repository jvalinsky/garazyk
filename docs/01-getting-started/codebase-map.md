---
title: Codebase Map
---

# Codebase Map

## Main directories

| Path                | Contents                                                 |
| ------------------- | -------------------------------------------------------- |
| `Garazyk/Sources/`  | Objective-C services and shared libraries                |
| `Garazyk/Tests/`    | Objective-C tests                                        |
| `Garazyk/Binaries/` | Service and command-line entry points                    |
| `packages/`         | Deno and TypeScript packages                             |
| `scripts/`          | Development, test, documentation, and operations scripts |
| `docker/`           | Container builds and local topologies                    |
| `config/`           | Example service configuration                            |
| `ops/`              | Deployment examples                                      |
| `docs/`             | Project documentation                                    |
| `lexicons/`         | AT Protocol lexicons                                     |

Notable Docker topologies:

| Path | Purpose |
| --- | --- |
| `docker/local-network/` | Full local ATProto network (PLC, PDS, relay, AppView, jelcz, …) |
| `docker/streamplace-peership/` | Streamplace + 3× jelcz HTTPS peership lab (joins local-network) |
| `docker/pds/` | Standalone PDS compose |

Demo entrypoints: `scripts/demo/streamplace_peership_*.sh`,
`scripts/demo/jelcz_*_demo.sh`. Guide:
[Streamplace and jelcz peership lab](../20-explanation/guides/streamplace-jelcz-peership-lab.md).

## Objective-C source

The main source areas are:

| Path                                | Contents                                         |
| ----------------------------------- | ------------------------------------------------ |
| `App/` and `CLI/`                   | PDS startup and command handling                 |
| `Network/`                          | HTTP, XRPC, routing, and transport code          |
| `Database/` and `Repository/`       | SQLite storage, actor stores, MST, CAR, and CBOR |
| `Sync/`                             | Firehose, WebSocket, and relay code              |
| `PLC/` and `Identity/`              | DID operations and resolution                    |
| `AppView/`                          | AppView ingestion and queries                    |
| `Admin/` and `AdminUIServer/`       | Administration APIs and web UI                   |
| `Auth/` and `Security/`             | Sessions, OAuth, DPoP, and security checks       |
| `Compat/`                           | Linux compatibility code                         |
| `Chat/`, `Video/`, and `MediaCore/` | Optional service implementations                 |

`Garazyk/Binaries/` contains the executable entry points. The main ones are
`kaszlak` for the PDS, `zuk` for the relay, `campagnola` for PLC, and `syrena`
for AppView. Other binaries cover administration, chat, media processing,
indexing, and caches.

## Deno packages

| Package     | Purpose                           |
| ----------- | --------------------------------- |
| `gruszka`   | XRPC clients and lexicon handling |
| `hamownia`  | Scenario runner                   |
| `laweta`    | Docker control                    |
| `schemat`   | Topology definitions              |
| `narzedzia` | Repository checks                 |
| `tui`       | Terminal UI components            |
| `dashboard` | Scenario dashboard code           |

The [documentation index](../index.md) links to the subsystem references.
