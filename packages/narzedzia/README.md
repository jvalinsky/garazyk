# @garazyk/narzedzia

Repository-level static analysis and code generation tooling for the Garazyk
workspace.

## Why Narzedzia?

**Narzedzia** is the Polish word for **tools**. This package contains the
essential infrastructure and development-time tools needed to maintain the
Garazyk codebase, from documentation validation to project-wide architectural
checks.

## Installation

```bash
deno add jsr:@garazyk/narzedzia
```

## Features

- **Cross-Document Link Validation**: Validates internal cross-references and
  surrogate mention links, and surfaces orphan docs via
  `@garazyk/narzedzia/doc-coverage`.
- **TSDoc Coverage**: Validates TSDoc coverage on exported APIs via
  `@garazyk/narzedzia/tsdoc-coverage`.
- **Module Boundary Enforcement**: Ensures strict separation between packages
  in the Garazyk workspace via `@garazyk/narzedzia/boundary-check`.
- **SPDX Header Management**: Automates license header updates across source
  files via `@garazyk/narzedzia/spdx-headers`.
- **Repo-Docs Registry**: Generates the canonical repo metadata, link graph,
  and orphan/orphan-back report pages via `@garazyk/narzedzia/repo-docs`.
- **VitePress Migration**: Helpers for evolving documentation into modern
  web-ready formats via `@garazyk/narzedzia/vitepress-migration`.
- **Ops Commands**: Operational tasks (DNS, certificates, backups) via
  `@garazyk/narzedzia/ops-command`.

## Usage

Most tools in this package are designed for use via `deno run` or as part of the
Garazyk development workflow.

```bash
# Check module boundaries
deno run -A jsr:@garazyk/narzedzia/boundary-check

# Validate TSDoc coverage
deno run -A jsr:@garazyk/narzedzia/tsdoc-coverage packages/gruszka
```
