---
title: Garazyk Contributor Guide
---

# Garazyk Contributor Guide

This site is the canonical documentation set for contributors working on Garazyk. It is written to explain how the repository actually works today, not to preserve every historical note or every large example inline.

If the docs and the code disagree, trust the code and fix the docs.

## Start Here

New contributors should usually begin with this sequence:

1. [Setup](01-getting-started/setup) for the real build and local runtime workflow.
2. [Codebase Map](01-getting-started/codebase-map) to learn where the major subsystems live.
3. [Request Lifecycle](01-getting-started/request-lifecycle) to understand how a request moves through the stack.
4. [Tutorials Overview](10-tutorials/index) to pick the right repo-grounded walkthrough.
5. [Documentation Map](11-reference/documentation-map) to navigate canonical and non-canonical doc collections.

That path is intentionally short. The goal is to get you from clone to confident navigation without forcing you through large reference dumps first.

## What This Site Optimizes For

The contributor docs favor:

- descriptive technical writing over long code listings,
- explanations of why a subsystem exists and what invariant it protects,
- repo-grounded tutorials instead of toy standalone labs,
- and small inline examples, with longer material moved to appendices.

That is especially important in a codebase like Garazyk, where the interesting work usually happens at the seam between configuration, routing, service composition, storage, and protocol rules.

## Recommended Learning Paths

### Understand the Server Boot Path

Start with [Setup](01-getting-started/setup), then [Tutorial 1: Hello PDS](10-tutorials/tutorial-1-hello-pds), and keep [Request Lifecycle](01-getting-started/request-lifecycle) open beside it.

### Change a Protocol Feature

Use [Tutorial 8: Endpoint Workflow](10-tutorials/tutorial-8-endpoint-workflow), then jump between:

- [API Reference](11-reference/api-reference),
- [Config Reference](11-reference/config-reference),
- [CLI Reference](11-reference/cli-reference),
- [Testing Map](11-reference/testing-map).

### Work on Contributor Tooling

Start with [Explorer, OpenAPI & UI](11-reference/explorer-openapi-ui), then [Tutorial 7: Objective-J UI](10-tutorials/tutorial-7-objective-j-ui).

### Prepare or Review a Deployment Change

Read [Tutorial 6: Deployment](10-tutorials/tutorial-6-deployment) with [Config Reference](11-reference/config-reference) and [Email & Verification](06-authentication/email-and-verification).

### Update Contributor Docs

Use the repository [Documentation and Comment Style Guide](../DOCUMENTATION.md), then verify command names against [CLI Reference](11-reference/cli-reference), config keys against [Config Reference](11-reference/config-reference), and test guidance against [Testing Map](11-reference/testing-map).

## The Main Sections

The numbered sections are the primary contributor journey:

- `01-09` explain the runtime by layer and subsystem,
- `10` contains the tutorial track,
- `11` contains operational and contributor reference pages,
- `12` is reserved for diagrams and visual references.

The sidebar reflects that path. Use it as the primary navigation surface.

## Deep Reference and Archival Material

Some material remains intentionally outside the main newcomer path:

- [`docs/tests/README`](tests/README) is the detailed test catalog.
- [`docs/oauth2/README`](oauth2/README) is the deeper OAuth implementation set.
- [`docs/security/README`](security/README) is the security and audit collection.

Those directories remain useful, but they are deeper reference or historical material. The contributor-facing guidance lives in the numbered VitePress sections first.

Repository-wide secondary docs are also indexed in [Repository Documentation Index](repo-index/index), with dedicated hubs for [Admin UI](11-reference/admin-ui-documentation), [Source-Adjacent](11-reference/source-adjacent-documentation), and [Tooling/Skills](11-reference/tooling-and-skills-documentation).

## Reading Style

The tutorials and reference pages no longer assume that every example should be pasted into a fresh file and run unchanged. Instead, they are written to help you answer questions like:

- Which file actually owns this behavior?
- Which tests protect it?
- What breaks if I change it?
- How do I verify the change without cargo-culting an old snippet?

That is the right mental model for a production codebase.

## Useful Entry Points

- [Overview](01-getting-started/overview)
- [Architecture Overview](01-getting-started/architecture-overview)
- [Tutorials Overview](10-tutorials/index)
- [Documentation Map](11-reference/documentation-map)
- [Objective-C Research Map](11-reference/objective-c-research-map)
- [Objective-C Research Appendices](guides/objective-c-appendices/)
- [Explorer, OpenAPI & UI](11-reference/explorer-openapi-ui)
- [Testing Map](11-reference/testing-map)
- [Troubleshooting](11-reference/troubleshooting)
- [Documentation and Comment Style Guide](../DOCUMENTATION.md)\n\n## Related\n\n- [Documentation Map](11-reference/documentation-map.md)\n- [Contributor Guide](index.md)\n- [Repository Documentation Index](repo-index/index.md)\n\n