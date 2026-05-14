---
title: Script Development and Quality Standards
---

# Script Development and Quality Standards

Garazyk uses two script families:

- **Bash** for process boundaries, local service orchestration, CI wrappers, and operator glue.
- **Deno/TypeScript** for structured repository tooling, XRPC clients, scenario logic, JSON validation, and report generation.

Avoid adding maintained Python scripts under `scripts/`. Use Python only when a third-party toolchain is inherently Python-based and document that exception next to the entrypoint.

## Choosing Bash Or Deno

Use **Bash** when the script mainly:

- starts or stops processes
- wires environment variables into existing tools
- checks for local dependencies
- delegates to `docker`, `xcodebuild`, `cmake`, `deno`, `curl`, or another CLI
- acts as a thin compatibility wrapper around an existing command

Use **Deno** when the script needs:

- HTTP/XRPC client logic
- JSON parsing, validation, or transformation
- multi-step scenario state
- structured reports or diagnostics
- filesystem traversal with non-trivial filtering
- shared libraries and type checking

If a Bash script grows parsing logic, embedded JSON manipulation, or large functions, move the logic into a Deno script and leave Bash as a small launcher if a shell boundary is still useful.

## Bash Standards

Repository Bash scripts should follow the patterns from the `professional-bash-scripting` skill and the existing scripts in `scripts/`.

- Use `#!/usr/bin/env bash`.
- Use `set -euo pipefail`.
- Resolve paths relative to the script directory, not the caller's current directory.
- Validate required tools and input paths before doing work.
- Keep cleanup paths explicit with traps where the script owns temporary files or processes.
- Keep functions small and prefer direct delegation to repo tools.
- Use `scripts/lib/common.sh` for shared service ports, run directories, diagnostics, and logging.
- Keep secrets out of command traces and logs.

Recommended checks:

```bash
bash -n scripts/path/to/script.sh
shellcheck scripts/path/to/script.sh
```

## Deno Standards

Repository Deno scripts are TypeScript entrypoints rooted at `deno.json`.

- Use `#!/usr/bin/env -S deno run -A` for executable repo tools.
- Put reusable helpers in `scripts/lib/deno/`.
- Import Deno standard modules through aliases defined in `deno.json`.
- Prefer typed helper clients over hand-built fetch calls when an XRPC client already exists.
- Keep scenario files in `scripts/scenarios/scenarios/*.ts` and export `run(): Promise<ScenarioResult>`.
- Use `ScenarioResult`, `timedCall`, and the assertion helpers for scenario reporting.
- Keep generated reports under the run directory or a caller-provided `--reports-dir`; do not commit generated reports.

Recommended checks:

```bash
deno fmt --config deno.json --check scripts/path/to/script.ts
deno check --config deno.json scripts/path/to/script.ts
```

## Current Script Map

| Area | Primary language | Notes |
| --- | --- | --- |
| `scripts/run_scenarios.ts` | Deno | Discovers, selects, runs, and reports scenario tests. |
| `scripts/scenarios/scenarios/*.ts` | Deno | Narrative full-stack scenarios. |
| `scripts/lib/deno/` | Deno | Shared XRPC clients, scenario runner primitives, diagnostics, seed data, and Docker helpers. |
| `scripts/docs/*.ts` | Deno | Documentation coverage, registry, link graph, and validation tooling. |
| `scripts/test/*.ts` | Deno | Structured docs and guide validation checks. |
| `scripts/dev/*.ts` | Deno | Developer utilities that parse source or call local XRPC services. |
| `scripts/**/*.sh` | Bash | Thin orchestration, service lifecycle, CI, validation, and operator wrappers. |

## Scenario Commands

```bash
# List auto-discovered scenarios
./scripts/run_scenarios.ts --list

# Run a focused scenario against an already-running local network
./scripts/run_scenarios.ts --no-setup 01

# Start the local network, run scenarios, then stop it
./scripts/run_scenarios.ts --setup --teardown

# Include the optional second PDS on port 2587
./scripts/run_scenarios.ts --pds2
```

See [Deno Scenario Framework](../11-reference/deno-scenario-framework.md) and [Test Selection Workflow](../11-reference/test-selection-workflow.md) for testing guidance.

## Documentation Tooling

Documentation scripts live in `scripts/docs/` and use the root Deno configuration for TypeScript tooling.

```bash
deno run -A scripts/docs/doc-coverage.ts Garazyk/Sources
deno run -A scripts/docs/repo_docs.ts sync
deno run -A scripts/docs/repo_docs.ts validate --internal-strict
```

See [Documentation Tooling](../../scripts/docs/README.md) for the docs workspace commands.

## Adding Or Changing A Script

1. Pick Bash or Deno using the boundary above.
2. Reuse existing helpers before creating a new framework.
3. Add a short usage header or `--help` output for human-invoked tools.
4. Update docs when the command is contributor-facing.
5. Run the narrow syntax/type checks before broader workflows.

## Related Documentation

- [Development Workflows](DEVELOPMENT_WORKFLOWS.md)
- [Deno Scenario Framework](../11-reference/deno-scenario-framework.md)
- [End-to-End Testing](../11-reference/e2e-testing.md)
- [Documentation Tooling](../../scripts/docs/README.md)
