---
title: Garazyk Contributor Guide
---

# Garazyk Contributor Guide

If documentation and implementation disagree, trust the implementation and update the docs.

## Start Here

1. [Setup](01-getting-started/setup) — Build and local runtime workflow.
2. [Codebase Map](01-getting-started/codebase-map) — Major subsystems and their locations.
3. [Request Lifecycle](01-getting-started/request-lifecycle) — Flow of requests through the stack.
4. [Tutorials Overview](10-tutorials/index) — Guided walkthroughs.

## Principles

We prioritize:
- Descriptive technical writing.
- Explaining subsystem purpose and invariants.
- Repo-grounded examples.

Development happens at the seams between configuration, routing, service composition, storage, and protocol rules.

## Paths

### Server Boot
[Setup](01-getting-started/setup), [Tutorial 1: Hello PDS](10-tutorials/tutorial-1-hello-pds), [Request Lifecycle](01-getting-started/request-lifecycle).

### Protocol Features
[Tutorial 8: Endpoint Workflow](10-tutorials/tutorial-8-endpoint-workflow), [API Reference](11-reference/api-reference), [Testing Map](11-reference/testing-map).

### Tooling
[Explorer, OpenAPI & UI](11-reference/explorer-openapi-ui), [Tutorial 7b: Admin UI Architecture](10-tutorials/tutorial-7b-admin-ui).

### Deployment
[Tutorial 6: Deployment](10-tutorials/tutorial-6-deployment), [Config Reference](11-reference/config-reference).

## Organization

- `01-09`: Runtime layers and subsystems.
- `10`: Tutorials.
- `11`: Operational and contributor reference.
- `12`: Diagrams.

## Verification

Before committing behavioral changes, identify:
1. The file owning the behavior.
2. Existing tests protecting it.
3. The specific command to verify the change.

## Related

- [Overview](01-getting-started/overview)
- [Architecture Overview](01-getting-started/architecture-overview)
- [Documentation Map](11-reference/documentation-map.md)
- [Repository Documentation Index](repo-index/index.md)

