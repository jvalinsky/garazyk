# Migrating to Garazyk Deno Monorepo

Garazyk has transitioned from a monolithic PDS implementation into a suite of
modular Deno packages. This guide helps you migrate your local testing workflows
and scenarios to the new structure.

## Overview of Changes

The core logic previously located in `scripts/lib/deno/` has been split into
five JSR packages:

1. **`@garazyk/laweta`**: Generic Docker Engine, Compose, health, event, and
   stats primitives.
2. **`@garazyk/gruszka`**: Strongly-typed XRPC client and protocol seed helpers.
3. **`@garazyk/schemat`**: Zod-validated topology/runtime schemas, service role
   metadata, and compose manifests.
4. **`@garazyk/hamownia`**: Scenario execution, ATProto network orchestration,
   diagnostics, and E2E test framework surfaces.
5. **`@garazyk/narzedzia`**: Repository tooling for boundaries, docs validation,
   code generation helpers, and operational command modules.

`packages/dashboard` remains a local workspace package for development checks
and checkout-local dashboard commands. It is not part of the JSR publish set.

## 1. Updating Scenario Imports

If you have custom scenarios, you must update your import statements. The
`../../lib/deno/` path no longer exists.

**Old Import (PDS Scripts):**

```typescript
import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { createAccountOrLogin } from "../../lib/deno/seed.ts";
```

**New Import (Monorepo):**

```typescript
import { ScenarioResult, timedCall } from "@garazyk/hamownia";
import { XrpcClient } from "@garazyk/gruszka";
import { createAccountOrLogin } from "@garazyk/gruszka/seed";
```

## 2. Using Root Tasks

We have introduced a set of `deno task` commands to simplify monorepo
management. You no longer need to navigate into `packages/` to run tests or
build lexicons.

| Command                     | Description                       |
| :-------------------------- | :-------------------------------- |
| `deno task scenarios`       | Run the full E2E scenario suite.  |
| `deno task test`            | Run all package unit tests.       |
| `deno task check`           | Type-check the entire monorepo.   |
| `deno task generate-client` | Rebuild typed lexicon interfaces. |

Local `@garazyk/*` imports resolve through Deno workspace package names. The
root config only keeps third-party import aliases used by scripts and packages.

## 3. Topology Registry

The `@garazyk/schemat` package now includes all standard topologies as embedded
code. You no longer need to point the runner at local JSON files in most cases.

**Old Command:**

```bash
deno task scenarios --topology garazyk-default
```

**New Command:**

```bash
deno task scenarios --topology garazyk-default
```

## 4. Portability

You can now use Garazyk components in standalone Deno projects without cloning
the full repository:

```bash
deno add jsr:@garazyk/gruszka
```

```typescript
import { XrpcClient } from "@garazyk/gruszka";
// ... use the strongly typed API
```

## 5. Publishing

CI publishes only the five libraries:

- `packages/laweta`
- `packages/gruszka`
- `packages/schemat`
- `packages/hamownia`
- `packages/narzedzia`

Do not run `deno publish` at the repository root while the local dashboard
workspace member is present.
