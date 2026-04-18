---
title: Docs Workspace Guide
---

# Docs Workspace Guide

`docs/` is the canonical documentation workspace for Garazyk.

For contributor-facing guidance, start with the numbered VitePress sections and the site home page:

- [Home](index)
- [Getting Started](01-getting-started/overview)
- [Tutorials Overview](10-tutorials/index)
- [Reference](11-reference/api-reference)

## What Lives Here

The documentation tree has two different roles:

| Area | Role |
| --- | --- |
| numbered sections such as `01-getting-started/` and `11-reference/` | primary contributor documentation |
| `tests/`, `oauth2/`, `security/`, and similar folders | deep reference, audit, or historical material |

That split is intentional. The VitePress site should guide newcomers through the active contributor path first, while still keeping the denser background material available in-repo.

## Deep Reference Collections

- [tests/README](tests/README)
- [oauth2/README](oauth2/README)
- [security/README](security/README)

Use those when you need a catalog or historical detail that would be too dense for the main contributor flow.

## Repository Links

- [Main Project README](../README)
- [Build Guide](../BUILD)
- [Contributing Guide](../CONTRIBUTING)
- [Documentation and Comment Style Guide](../DOCUMENTATION)
- [Agent Instructions (AGENTS.md)](../AGENTS)
