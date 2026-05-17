---
name: garazyk-testing
description: "Garazyk Deno workspace testing patterns for packages, scenario scripts, topology validation, and quality gates. Use when adding or reviewing TypeScript tests, scenario coverage, or package-level checks."
---

# Garazyk Testing Patterns

This repository is a Deno monorepo. Tests live beside the code they cover, and scenario coverage is driven from `scripts/run_scenarios.ts`.

## Core Quality Gates

Run these from the repository root before finishing package or scenario changes:

```bash
deno check packages/*/mod.ts scripts/*.ts
deno test -A packages/
deno lint packages/ scripts/
deno fmt --check packages/ scripts/
```

The `deno.json` tasks mirror those commands:

```bash
deno task check
deno task test
deno task lint
deno task fmt -- --check
```

## Package Test Layout

Package tests use Deno's native `*_test.ts` convention. Keep tests close to the module they cover:

```text
packages/laweta/docker_api.ts
packages/laweta/docker_api_test.ts
packages/hamownia/runner.ts
packages/hamownia/runner_test.ts
```

Use `@std/assert` assertions and import package APIs through workspace aliases when crossing package boundaries:

```ts
import { assertEquals } from "@std/assert";
import { runScenario } from "@garazyk/hamownia";
```

Do not use direct `../` imports between packages. The workspace aliases in the root `deno.json` are the package boundary.

## Scenario Tests

End-to-end scenarios live in `scripts/scenarios/scenarios/NN_name.ts` and are run through:

```bash
deno run -A scripts/run_scenarios.ts
```

For scenario authoring details, use the `adding-scenario` skill. For running and debugging scenarios against local services, use `atproto-scenario-testing`.

## Test Selection

Run a single package test file during iteration:

```bash
deno test -A packages/hamownia/runner_test.ts
```

Run a specific Deno test by name:

```bash
deno test -A packages/hamownia/runner_test.ts --filter "selects scenarios"
```

Run a specific scenario by passing the scenario selector supported by `scripts/run_scenarios.ts`.

## Test Data And Side Effects

- Prefer temporary directories from `Deno.makeTempDir()` for filesystem tests.
- Clean up Docker containers, networks, and volumes through the helper APIs in `@garazyk/laweta`.
- Keep network-dependent tests explicit. Local ATProto stack tests should be scenarios rather than hidden package-test side effects.
- Avoid sleeps in assertions. Prefer polling helpers, health checks, or hamownia timing utilities.

## Public API Checks

When changing exports under `packages/`, verify:

- `deno check packages/*/mod.ts` passes.
- Exported functions, methods, and classes have explicit return types, except exported Zod schemas in `packages/schemat`.
- Cross-package imports use `@garazyk/*` aliases.
- Generated XRPC client files are regenerated after lexicon changes:

```bash
deno run -A packages/gruszka/scripts/generate.ts
```

## Review Checklist

Before landing a test change, check:

- The test exercises public behavior rather than implementation details where practical.
- Assertions include enough context to diagnose failures.
- Docker or filesystem resources are cleaned up on failure.
- Scenario changes keep reports machine-readable through `ScenarioResult` and `timedCall`.
- Package changes do not introduce new cross-package relative imports.
