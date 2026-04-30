# Context Map

This repo is organized by service. Each service has its own domain language documented in a per-service `CONTEXT.md`.

| Service | Context file | Description |
|---------|-------------|-------------|
| PDS | `Garazyk/Sources/PDS/CONTEXT.md` | Personal Data Server — the main ATProto PDS implementation |
| AppView | `Garazyk/Sources/AppView/CONTEXT.md` | App View — indexed view of the network |
| Chat | `Garazyk/Sources/Chat/CONTEXT.md` | Chat service — DMs and conversation management |
| PLC | `Garazyk/Sources/PLC/CONTEXT.md` | PLC directory — DID-to-handle resolution |
| Relay | `Garazyk/Sources/Relay/CONTEXT.md` | Relay — firehose aggregation and crawling |
| Video | `Garazyk/Sources/Video/CONTEXT.md` | Video processing — transcoding and thumbnail generation |

System-wide architectural decisions live in `docs/adr/`. Service-scoped decisions live in `Garazyk/Sources/<Service>/docs/adr/`.
