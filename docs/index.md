---
title: Garazyk Contributor Guide
---

# Garazyk Contributor Guide

This documentation explains how the repository works today. If the docs and code disagree, trust the code and fix the docs.

## Start Here

1. [Setup](01-getting-started/setup) for the build and local runtime workflow.
2. [Codebase Map](01-getting-started/codebase-map) to learn where major subsystems live.
3. [Request Lifecycle](01-getting-started/request-lifecycle) to understand how requests move through the stack.
4. [Tutorials Overview](10-tutorials/index) for guided walkthroughs.
5. [Documentation Map](11-reference/documentation-map) to navigate doc collections.

## Design Goals

These docs favor:
- Descriptive technical writing.
- Explanations of subsystem purpose and invariants.
- Repo-grounded tutorials.
- Small inline examples with details in appendices.

Most work happens at the seam between configuration, routing, service composition, storage, and protocol rules.

## Learning Paths

### Understand the Server Boot Path
Start with [Setup](01-getting-started/setup), then [Tutorial 1: Hello PDS](10-tutorials/tutorial-1-hello-pds), and [Request Lifecycle](01-getting-started/request-lifecycle).

### Change a Protocol Feature
Use [Tutorial 8: Endpoint Workflow](10-tutorials/tutorial-8-endpoint-workflow), then consult the [API Reference](11-reference/api-reference) and [Testing Map](11-reference/testing-map).

### Work on Contributor Tooling
See [Explorer, OpenAPI & UI](11-reference/explorer-openapi-ui) and [Tutorial 7b: Admin UI Architecture](10-tutorials/tutorial-7b-admin-ui).

### Prepare a Deployment Change
Read [Tutorial 6: Deployment](10-tutorials/tutorial-6-deployment) and [Config Reference](11-reference/config-reference).

## Sections

- `01-09`: Runtime layers and subsystems.
- `10`: Tutorials.
- `11`: Operational and contributor reference.
- `12`: Diagrams.

## Secondary Material

The following directories contain deep reference or historical context:
- [`docs/tests/`](tests/README)
- [`docs/oauth2/`](oauth2/README)
- [`docs/security/`](security/README)

Repository-wide indices: [Repository Documentation Index](repo-index/index), [Admin UI](11-reference/admin-ui-documentation), [Source-Adjacent](11-reference/source-adjacent-documentation), and [Tooling/Skills](11-reference/tooling-and-skills-documentation).

## Verification

When changing behavior, identify:
- Which file owns the behavior.
- Which tests protect it.
- How to verify the change.

## Entry Points

- [Overview](01-getting-started/overview)
- [Architecture Overview](01-getting-started/architecture-overview)
- [Objective-C Research Map](11-reference/objective-c-research-map)
- [Troubleshooting](11-reference/troubleshooting)
- [Documentation and Style Guide](../DOCUMENTATION.md)

## Related

- [Documentation Map](11-reference/documentation-map.md)
- [Contributor Guide](index.md)
- [Repository Documentation Index](repo-index/index.md)

