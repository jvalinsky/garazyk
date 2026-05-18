# Laweta ATProto Ownership Map

Post-split status for the `laweta` to `hamownia` ATProto orchestration move. The
split is complete; this document now tracks ownership, remaining hardening work,
and release-readiness checks.

## Current Status

Reviewed on 2026-05-18.

| Package              | Current responsibility                                                                                                                                           | Status                                                                                                                                  |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `@garazyk/laweta`    | Generic Docker Engine API, Compose wrappers, health probes, container events, container stats                                                                    | Target state. No ATProto runtime, binary orchestration, stale cleanup, scenario Docker runner, or local-network lifecycle code remains. |
| `@garazyk/hamownia`  | Scenario authoring, host/Docker scenario execution, local ATProto network orchestration, binary services, stale cleanup, diagnostics, demo/service/test commands | Target owner for orchestration. PR A restored type health for `binary_services.ts`.                                                     |
| `@garazyk/schemat`   | Topology/runtime schemas, service role metadata, role/env registries, compose rendering, topology manifests                                                      | Target owner for topology data and runtime path helpers.                                                                                |
| `@garazyk/dashboard` | Web/TUI dashboard over local runs and network health                                                                                                             | Uses `@garazyk/hamownia/atproto-network` for orchestration and `@garazyk/laweta` only for generic Docker primitives.                    |
| `scripts/`           | Thin CLI wrappers                                                                                                                                                | Scenario, demo, service, topology, and test commands delegate to package-owned modules.                                                 |

## Active Work

### PR A: Restore Post-Split Type Health

Status: complete.

- `packages/hamownia/binary_services.ts` now accepts `StartBinaryOptions` while
  preserving `startBinaryServices(ctx)` as the default binary-network call.
- Default binary services are PLC, PDS, Relay, and AppView.
- Per-service args/env overrides are resolved through a typed launch plan.
- PID-file status handling returns
  `Record<BinaryServiceName, BinaryServiceStatus>` without `any`.
- Log output from spawned binaries is piped to append-mode log files with
  stream-owned file lifetime.
- Unit coverage lives in `packages/hamownia/binary_services_test.ts`.

Verification completed:

```bash
deno check packages/hamownia/binary_services.ts packages/hamownia/atproto_network.ts
deno check packages/*/mod.ts scripts/*.ts
deno test -A packages/hamownia/
```

### PR B: Refresh Split Documentation

Status: in progress.

- Keep this file as the current post-split status document.
- Treat old PR 1-7 notes as archaeology only.
- Package docs must state the current ownership:
  - `laweta`: generic Docker primitives.
  - `hamownia`: scenario execution and ATProto orchestration.
  - `schemat`: topology/runtime schemas and role metadata.
- Active docs must not point users to:
  - `@garazyk/laweta/atproto-runtime`
  - deleted `packages/laweta/*` orchestration files
  - `@garazyk/laweta` as the scenario Docker runner owner

Verification:

```bash
deno task boundaries
deno check packages/*/mod.ts scripts/*.ts
```

### PR C: Harden Hamownia Orchestration APIs

Status: complete.

Added public API and characterization coverage for the new orchestration
surfaces:

- `@garazyk/hamownia/atproto-network`
- `@garazyk/hamownia/binary-services`
- `@garazyk/hamownia/stale-cleanup`
- `@garazyk/hamownia/docker-runner`
- `@garazyk/hamownia/run-command`

Covered behaviors:

- `scenario_runner.ts` applies `roleEnvKey` mapping.
- Scenario paths cannot escape the repo root.
- Docker-runner timeout returns `124` and force-removes the container.
- Binary mode starts binary services with defaults.
- Topology mode sets `ATPROTO_TOPOLOGY` and `ATPROTO_TOPOLOGY_MANIFEST`.
- Diagnostics collection remains in `hamownia`.

Verification completed:

```bash
deno test -A packages/hamownia/
deno check packages/*/mod.ts scripts/*.ts
```

### PR D: Final Boundary And Release Cleanup

Status: boundary cleanup complete; full lint remains blocked by existing
repo-wide lint debt.

- Confirm `packages/laweta/deno.json` exports only `.` and `./compose`.
- Confirm `packages/laweta/mod.ts` exports only Docker Engine, Compose, health,
  event, stats, and telemetry utilities.
- Confirm no ATProto names remain in `packages/laweta`.
- Remove stale doc-tooling paths that still reference legacy `lib/deno/*`
  entrypoints.
- Release gate status:
  - `deno task check`: pass.
  - `deno task test`: pass.
  - Scoped lint/format for touched files: pass.
  - `deno task lint`: fail on pre-existing repo-wide lint debt in generated
    lexicons, dashboard JSX/type imports, old scenario scripts, and docs
    migration scripts.

```bash
deno task check
deno task test
deno task lint
deno task fmt -- --check
```

## Current Imports

Expected cross-package dependency direction:

```text
hamownia -> laweta   generic Docker primitives only
hamownia -> schemat  topology manifests, runtime paths, service URLs, role metadata
dashboard -> hamownia/schemat/laweta through package subpaths
scripts -> package command modules
laweta -> no Garazyk package dependencies
```

Expected current examples:

```typescript
import { createDockerClient } from "@garazyk/laweta";
import { startLocalNetwork } from "@garazyk/hamownia/atproto-network";
import { roleEnvKey } from "@garazyk/schemat";
import { serviceUrl } from "@garazyk/schemat/runtime";
```

## Historical Appendix

The original PR 1-7 split plan is preserved here as a summary, not as active
guidance.

1. Runtime config moved from `laweta` to `@garazyk/schemat/runtime`.
2. `hamownia` stopped importing runtime types from the former laweta ATProto
   compatibility surface.
3. Binary services moved to `packages/hamownia/binary_services.ts`.
4. Stale cleanup moved to `packages/hamownia/stale_cleanup.ts`.
5. Scenario Docker execution moved to `packages/hamownia/docker_runner.ts`.
6. Dashboard package imports were aligned with workspace package resolution.
7. Deprecated laweta orchestration files were removed: `atproto_runtime.ts`,
   `docker.ts`, `docker_binary.ts`, `docker_cleanup.ts`, `docker_runner.ts`,
   `docker_types.ts`, and `runtime_config.ts`.

Result: `@garazyk/laweta` is now a generic Docker package. ATProto orchestration
belongs to `@garazyk/hamownia`; topology schemas and service role metadata
belong to `@garazyk/schemat`.
