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

- **Documentation Validation**: Validates cross-document links and ensures TSDoc
  coverage.
- **Module Boundary Enforcement**: Ensures strict separation between packages in
  the Garazyk workspace.
- **SPDX Header Management**: Automates license header updates across source
  files.
- **VitePress Migration**: Helpers for evolving documentation into modern
  web-ready formats.

## Usage

Most tools in this package are designed for use via `deno run` or as part of the
Garazyk development workflow.

```bash
# Check module boundaries
deno run -A jsr:@garazyk/narzedzia/boundary_check

# Validate TSDoc coverage
deno run -A jsr:@garazyk/narzedzia/tsdoc_coverage packages/gruszka
```
