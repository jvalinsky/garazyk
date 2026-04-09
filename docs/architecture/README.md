---
title: Architecture Documentation
---

# Architecture Documentation

This directory is deep reference for architecture analysis, diagram sources, and longer-form design notes. It is not the primary onboarding path.

Start with the current contributor pages if you need the shortest route into the codebase:

- [Architecture Overview](../01-getting-started/architecture-overview)
- [Codebase Map](../01-getting-started/codebase-map)
- [Request Lifecycle](../01-getting-started/request-lifecycle)
- [Services Overview](../03-application-layer/services-overview)

Use this directory when you need extra diagrams, historical analysis, or more exhaustive architecture notes.

## Documents

| File | Focus |
| --- | --- |
| [ARCHITECTURE_ANALYSIS.md](ARCHITECTURE_ANALYSIS) | deep code analysis and design discussion |
| [ARCHITECTURE_DIAGRAMS.md](ARCHITECTURE_DIAGRAMS) | Mermaid architecture diagrams |
| [DIAGRAMS_MERMAID.md](DIAGRAMS_MERMAID) | protocol and component diagrams |
| [DIAGRAM_QUICK_REFERENCE.md](DIAGRAM_QUICK_REFERENCE) | diagram lookup guide |
| [atproto_data_models.md](atproto_data_models) | ATProto data model notes |
| [atproto_pds_architecture.md](atproto_pds_architecture) | PDS architecture and protocol notes |
| [XRPC_PROTOCOL_REFERENCE.md](XRPC_PROTOCOL_REFERENCE) | older XRPC reference material |
| [DEVELOPMENT_WORKFLOWS.md](DEVELOPMENT_WORKFLOWS) | workflow diagrams |
| [2026-01-10-integration-test-findings.md](2026-01-10-integration-test-findings) | historical findings document |

## Diagram Sources

The `.dot` files in this directory are source material for Graphviz diagrams:

- `high_level_architecture.dot`
- `request_flow.dot`
- `database_schema.dot`
- `authentication_flow.dot`
- `repository_engine.dot`
- `firehose_sync.dot`
- `module_dependencies.dot`

## Notes On Currency

Some documents here predate the numbered contributor docs and may use older framing or terminology. When a note here conflicts with the current onboarding docs or the code, trust the code and update the docs.

## Related Collections

- [Guides](../guides/README)
- [Security Reference](../security/README)
- [Test Catalog](../tests/README)
- [Plans](../plans/README)
- [Examples](../examples/README)
