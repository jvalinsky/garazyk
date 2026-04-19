---
title: Tutorials Overview
---

# Tutorials Overview

## Overview

The tutorial track is for contributors who want to understand how Garazyk is put together, not for readers who want a sequence of standalone toy projects.

That distinction is deliberate. Earlier tutorial drafts implied "copy this code and it compiles as written," but the repository itself is a richer, more interconnected system than that framing allowed. The tutorials now focus on:

- why a subsystem exists,
- where it lives in the repo,
- how to verify it,
- and which failure modes matter when you change it.

Long code and shell material belongs in appendices so the main narrative can stay technical and readable.

## Recommended Order

1. [Tutorial 1: Hello PDS](./tutorial-1-hello-pds)
2. [Tutorial 2: Accounts](./tutorial-2-accounts)
3. [Tutorial 3: Records](./tutorial-3-records)
4. [Tutorial 4: Authentication](./tutorial-4-auth)
5. [Tutorial 5: Firehose](./tutorial-5-firehose)
6. [Subguide: HTTP + WebSocket from Scratch](./network-from-scratch/)
7. [Tutorial 6: Deployment](./tutorial-6-deployment)
8. [Tutorial 7: Objective-J UI](./tutorial-7-objective-j-ui)
9. [Tutorial 8: Endpoint Workflow](./tutorial-8-endpoint-workflow)

The first five tutorials plus the network subguide teach the production server from the inside out. Tutorial 6 then shifts to deployment. Tutorial 7 covers contributor tooling in the browser. Tutorial 8 ties together the end-to-end workflow for adding or changing a feature.

If you want the network internals immediately after the firehose walkthrough, take the advanced track next:

- [Subguide: HTTP + WebSocket from Scratch](./network-from-scratch/)

That subguide sits between [Tutorial 5: Firehose](./tutorial-5-firehose) and [Tutorial 6: Deployment](./tutorial-6-deployment). It is the place to study how Garazyk actually accepts sockets, parses HTTP/1.1, upgrades to WebSocket, and hands the connection to `subscribeRepos`.

## What the Tutorials Optimize For

These tutorials are written for new contributors. They assume you want to answer questions like:

- Which files matter?
- What invariant is this subsystem protecting?
- How do I prove a change is correct?
- Where do protocol concerns stop and repo-specific concerns start?

They do not assume you need a giant code listing on every page. Where exact commands or samples are still useful, they live in `## Appendix` sections.

## What Is Runnable and What Is Illustrative

The main docs now use three different levels of example material:

| Level | How to treat it |
| --- | --- |
| Main tutorial prose | Contributor explanation and repo walkthrough |
| Inline short snippets | Illustrative, small enough to explain one idea clearly |
| Appendix code and shell blocks | The longer material you may run, adapt, or compare to the repo |

If you need literal source truth, always prefer the runtime files under `Garazyk/Sources/` and the deployment assets under `docker/pds/`.

## Supporting Reference Pages

Before or during the tutorial track, these pages usually pay off:

- [Codebase Map](../01-getting-started/codebase-map)
- [Request Lifecycle](../01-getting-started/request-lifecycle)
- [Config Reference](../11-reference/config-reference)
- [CLI Reference](../11-reference/cli-reference)
- [Testing Map](../11-reference/testing-map)
- [Explorer, OpenAPI & UI](../11-reference/explorer-openapi-ui)

## Related Reading

- [Overview](../01-getting-started/overview)
- [Architecture Overview](../01-getting-started/architecture-overview)\n\n## Related\n\n- [Documentation Map](../11-reference/documentation-map.md)\n- [Contributor Guide](../index.md)\n- [Repository Documentation Index](../repo-index/index.md)\n\n