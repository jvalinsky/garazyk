---
title: Deno Packages
---

# Deno Packages

| Package              | Purpose                                                 |
| -------------------- | ------------------------------------------------------- |
| `@garazyk/gruszka`   | XRPC clients, firehose handling, and lexicon resolution |
| `@garazyk/schemat`   | Topology schemas and compilation                        |
| `@garazyk/laweta`    | Docker Engine access and service control                |
| `@garazyk/hamownia`  | Scenario execution                                      |
| `@garazyk/narzedzia` | Repository checks                                       |
| `@garazyk/tui`       | Terminal UI components                                  |
| `dashboard`          | Scenario dashboard                                      |

Each package lives under `packages/`. Its `mod.ts`, tests, and local README are
the package-level references.

See the [scenario framework](deno-scenario-framework.md) and
[lexicon resolution](lexicon-resolution.md) references for the two shared
workflows.
