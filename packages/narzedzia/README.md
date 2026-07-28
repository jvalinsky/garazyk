# @garazyk/narzedzia

Repository-level static analysis and code generation tooling for the Garazyk
workspace.

## Name

_Narzędzia_ is the Polish word for tools.

## Installation

```bash
deno add jsr:@garazyk/narzedzia
```

## Features

- Cross-document link validation: checks internal cross-references and surrogate
  mention links, and reports orphan docs. `@garazyk/narzedzia/doc-coverage`
- TSDoc coverage on exported APIs. `@garazyk/narzedzia/tsdoc-coverage`
- Module boundary enforcement between packages in the workspace.
  `@garazyk/narzedzia/boundary-check`
- SPDX header management across source files. `@garazyk/narzedzia/spdx-headers`
- Repo-docs registry: generates repo metadata, the link graph, and the
  orphan/orphan-back report pages. `@garazyk/narzedzia/repo-docs`
- VitePress migration helpers for converting documentation to web-ready formats.
  `@garazyk/narzedzia/vitepress-migration`
- Ops commands for DNS, certificates, and backups.
  `@garazyk/narzedzia/ops-command`

## Usage

Run these through `deno run`, or as part of the Garazyk development workflow.

```bash
# Check module boundaries
deno run -A jsr:@garazyk/narzedzia/boundary-check

# Validate TSDoc coverage
deno run -A jsr:@garazyk/narzedzia/tsdoc-coverage packages/gruszka
```
