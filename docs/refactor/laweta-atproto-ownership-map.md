# Laweta ATProto Ownership Map

PR 1 inventory for splitting Garazyk-specific ATProto orchestration out of
`@garazyk/laweta` while preserving alpha compatibility paths.

## Current State

The split is already partially in place:

- `@garazyk/laweta` root exports generic Docker Engine, Compose, health,
  events, stats, and one scenario Docker runner helper.
- `@garazyk/hamownia/atproto-network` is the active local ATProto network
  orchestrator used by scripts and the dashboard.
- `@garazyk/schemat/runtime` already owns duplicated runtime path and service
  URL helpers through `packages/schemat/docker_config.ts`.
- `@garazyk/laweta/atproto-runtime` remains as an alpha compatibility subpath
  for binary-service helpers, stale cleanup helpers, and legacy runtime types.

## Import Inventory

| Surface | Current consumers | Notes |
| --- | --- | --- |
| `packages/laweta/atproto_runtime.ts` | `packages/hamownia/atproto_network.ts`, `packages/hamownia/docker_diagnostics.ts` for `RunContext`, `packages/laweta/public_api_test.ts` | Exported as `@garazyk/laweta/atproto-runtime`. Compatibility surface only. |
| `packages/laweta/docker_binary.ts` | `packages/laweta/atproto_runtime.ts`, `packages/laweta/docker.ts` | ATProto binary names, config files, env vars, and health probes are all Garazyk-specific. |
| `packages/laweta/runtime_config.ts` | `packages/laweta/atproto_runtime.ts`, `packages/laweta/docker_binary.ts`, `packages/laweta/docker_cleanup.ts`, `packages/laweta/docker.ts` | Duplicated by `packages/schemat/docker_config.ts` and exported as `@garazyk/schemat/runtime`. |
| `packages/laweta/docker_runner.ts` | `packages/laweta/mod.ts`, `packages/laweta/docker_runner_test.ts`, `packages/laweta/public_api_test.ts`, `packages/hamownia/scenario_runner.ts` | Runs scenario files inside `denoland/deno:alpine`; the path-safety and timeout mechanics are generic, but env mapping and scenario semantics are not. |
| `packages/laweta/docker.ts` | No active package-subpath export in `packages/laweta/deno.json`; no current repo imports found | Legacy local-network API file. Throws for topology-aware orchestration and points users to `@garazyk/hamownia/atproto-network`. |
| `packages/laweta/mod.ts` | `packages/hamownia/atproto_network.ts`, `packages/hamownia/run_loop.ts`, `packages/hamownia/scenario_runner.ts`, `packages/dashboard/services/network_manager.ts`, `scripts/scenarios/wait_topology.ts`, tests/docs | Root API is mostly generic, but still exports `docker_runner.ts`. |
| `packages/laweta/deno.json` | Workspace package metadata | Exports only `.`, `./atproto-runtime`, and `./compose`; `./docker` is not exported. |

## Symbol Classification

| Symbol or file | Classification | Target owner | Compatibility plan | Tests required |
| --- | --- | --- | --- | --- |
| `SERVICE_PORTS` | ATProto topology/runtime config | `@garazyk/schemat/runtime` | Re-export from `@garazyk/laweta/atproto-runtime` with `@deprecated`; stop using `laweta/runtime_config.ts` internally | `packages/schemat/public_api_test.ts`, `packages/laweta/public_api_test.ts` |
| `serviceUrl()` | ATProto topology/runtime config | `@garazyk/schemat/runtime` | Re-export from `@garazyk/laweta/atproto-runtime` with `@deprecated` | `packages/schemat/public_api_test.ts`, `packages/laweta/public_api_test.ts` |
| `neededPorts()` | ATProto topology/runtime config | `@garazyk/schemat/runtime` | Re-export from `@garazyk/laweta/atproto-runtime`; update `docker_cleanup.ts` or move cleanup first | `packages/schemat/public_api_test.ts`, cleanup tests if added |
| `initRunDir()` | Scenario/topology runtime behavior | `@garazyk/hamownia/atproto-network` facade over `@garazyk/schemat/runtime` | Keep `@garazyk/laweta/atproto-runtime` compatibility export temporarily | `packages/hamownia/public_api_test.ts`, `packages/laweta/public_api_test.ts` |
| `repoRoot()` | Runtime helper coupled to local topology execution | `@garazyk/schemat/runtime` | Keep compatibility re-export only | `packages/schemat/public_api_test.ts` |
| `LocalNetworkOptions` | Scenario/network orchestration config | `@garazyk/hamownia/atproto-network`, possibly backed by `@garazyk/schemat` config types | Keep type alias export from `@garazyk/laweta/atproto-runtime` until all consumers move | `deno check packages/*/mod.ts scripts/*.ts` |
| `RunContext` | Scenario/network runtime context | `@garazyk/hamownia/atproto-network`, compatible with `@garazyk/schemat/runtime` `TopologyRunContext` | Keep type alias export from `@garazyk/laweta/atproto-runtime`; move `docker_diagnostics.ts` off laweta type | `deno check packages/*/mod.ts scripts/*.ts` |
| `startBinaryServices()` | ATProto binary orchestration | `@garazyk/hamownia/atproto-network` or `@garazyk/hamownia/atproto-network/binary` | Keep deprecated export from `@garazyk/laweta/atproto-runtime`; old implementation can delegate to hamownia only if boundary rules allow it, otherwise leave wrapper until removal | Binary-mode smoke/characterization test, `deno test -A packages/hamownia/ packages/laweta/` |
| `stopBinaryServices()` | ATProto binary orchestration | `@garazyk/hamownia/atproto-network` or `@garazyk/hamownia/atproto-network/binary` | Same as `startBinaryServices()` | Unit test for PID-file parsing and cleanup behavior |
| `appendPid()` | Internal implementation detail | New hamownia binary module | No public compatibility needed | Covered through `stopBinaryServices()` characterization |
| `stopStaleDockerE2e()` | Scenario-network cleanup | `@garazyk/hamownia/atproto-network` or diagnostics/cleanup submodule | Keep deprecated export from `@garazyk/laweta/atproto-runtime`; this currently depends on ATProto port sets | Cleanup unit test using mocked Docker client boundaries, or keep existing behavior under check-only PR |
| `stopStaleHostProcesses()` | ATProto host-binary cleanup | `@garazyk/hamownia/atproto-network` | Keep deprecated export from `@garazyk/laweta/atproto-runtime` | Characterization around known binary names and port list |
| `DockerRunnerOptions` | Mixed: generic container runner plus scenario semantics | Split: generic primitive stays in `laweta`; scenario runner config moves to `hamownia` | Keep root `@garazyk/laweta` export until hamownia wrapper is in place, then deprecate if public | `packages/laweta/docker_runner_test.ts`, `packages/hamownia/scenario_runner_test.ts` |
| `DOCKER_RUNNER_TIMEOUT_EXIT_CODE` | Generic process/container runner convention | `@garazyk/laweta` if generic runner stays; otherwise `@garazyk/hamownia/scenario-runner` | Keep root export while `runScenarioInDocker()` remains exported | `packages/laweta/docker_runner_test.ts` |
| `buildDockerRunnerArgs()` | Mixed | Split helper: generic Docker `run` builder can stay in `laweta`; scenario env derivation moves to `hamownia` | Keep current root export temporarily; deprecate if the remaining API is scenario-specific | `packages/laweta/docker_runner_test.ts` |
| `runScenarioInDocker()` | Scenario execution behavior | `@garazyk/hamownia/scenario-runner` | Move behind hamownia API; leave laweta wrapper only if external alpha users require it | `packages/hamownia/scenario_runner_test.ts`, timeout behavior test |
| `roleToEnvKey()` in `docker_runner.ts` | ATProto topology env mapping | `@garazyk/schemat` already has `roleEnvKey`/`ROLE_ENV_REGISTRY` | Replace with `@garazyk/schemat` mapping when moving runner semantics | Tests for `pds2`, `ui`, and unknown role behavior |
| `startLocalNetwork()` in `docker.ts` | Legacy ATProto orchestration | `@garazyk/hamownia/atproto-network` | Do not export from `laweta` root. If `./docker` is restored as a compatibility subpath, mark deprecated and delegate/throw consistently. | Compatibility check only if subpath is exported |
| `stopLocalNetwork()` in `docker.ts` | Legacy ATProto orchestration | `@garazyk/hamownia/atproto-network` | Same as `startLocalNetwork()` | Compatibility check only if subpath is exported |
| `composeDown()`, `composeUp()` | Generic Docker Compose primitive | `@garazyk/laweta` | Keep root export | Existing checks |
| `waitForHttp()`, `waitForService()`, `waitForServiceCLI()` | Generic health/check primitives | `@garazyk/laweta` | Keep root export | Existing checks |
| `ContainerEventWatcher`, `DockerEventParser`, Docker API/stat helpers | Generic Docker primitives | `@garazyk/laweta` | Keep root export | Existing laweta API/tests |

## Migration Matrix

| Current import path | New import path | Owning package | Compatibility plan | Tests required |
| --- | --- | --- | --- | --- |
| `@garazyk/laweta` for Docker API, Compose, health, events, stats | unchanged | `@garazyk/laweta` | Keep stable | `deno check packages/*/mod.ts`; laweta Docker tests |
| `@garazyk/laweta` for `runScenarioInDocker`, `buildDockerRunnerArgs`, `DockerRunnerOptions` | `@garazyk/hamownia/scenario-runner` for scenario execution; optional low-level container primitive can remain in `@garazyk/laweta` | `@garazyk/hamownia` for scenario semantics | Keep current root export for alpha compatibility until hamownia no longer imports it | `packages/laweta/docker_runner_test.ts`, `packages/hamownia/scenario_runner_test.ts` |
| `@garazyk/laweta/atproto-runtime` for `SERVICE_PORTS`, `serviceUrl`, `neededPorts`, `repoRoot` | `@garazyk/schemat/runtime` | `@garazyk/schemat` | Deprecated re-export from laweta subpath | `packages/schemat/public_api_test.ts`, `packages/laweta/public_api_test.ts` |
| `@garazyk/laweta/atproto-runtime` for `initRunDir`, `LocalNetworkOptions`, `RunContext` | `@garazyk/hamownia/atproto-network` | `@garazyk/hamownia` | Deprecated re-export/type alias from laweta subpath | `packages/hamownia/public_api_test.ts`, `deno check packages/*/mod.ts scripts/*.ts` |
| `@garazyk/laweta/atproto-runtime` for `startBinaryServices`, `stopBinaryServices` | `@garazyk/hamownia/atproto-network` or a new `@garazyk/hamownia/atproto-network/binary` subpath | `@garazyk/hamownia` | Deprecated laweta subpath export until compatibility removal | Binary-mode characterization test |
| `@garazyk/laweta/atproto-runtime` for `stopStaleDockerE2e`, `stopStaleHostProcesses` | `@garazyk/hamownia/atproto-network` cleanup module | `@garazyk/hamownia` | Deprecated laweta subpath export until compatibility removal | Cleanup characterization tests |
| `packages/laweta/runtime_config.ts` relative imports | `@garazyk/schemat/runtime` or local hamownia imports after file move | `@garazyk/schemat` | Keep file only as compatibility implementation detail until deleted | `deno task boundaries` |
| `packages/laweta/docker_binary.ts` relative imports | `@garazyk/hamownia/atproto-network` implementation module using `@garazyk/laweta` generic health helpers and `@garazyk/schemat/runtime` | `@garazyk/hamownia` | Leave old laweta subpath wrapper while alpha consumers migrate | `deno test -A packages/hamownia/ packages/laweta/` |
| `packages/laweta/docker.ts` direct file use | `@garazyk/hamownia/atproto-network` | `@garazyk/hamownia` | No current package export; either remove in final cleanup or explicitly export as deprecated compatibility if external alpha users depend on it | `deno check packages/*/mod.ts` |

## Cross-Package Dependency Graph

```
laweta (root) ← hamownia/atproto_network.ts  [generic Docker primitives]
laweta (root) ← hamownia/run_loop.ts          [ContainerEventWatcher, ContainerStatsSampler, createDockerClient]
laweta (root) ← hamownia/scenario_runner.ts   [runScenarioInDocker]
laweta (root) ← dashboard/network_manager.ts  [composeServiceName, cpuPercent, createDockerClient, formatMemory, ContainerEventWatcher]
laweta (root) ← scripts/scenarios/wait_topology.ts [ContainerEventWatcher]

laweta/atproto-runtime ← hamownia/atproto_network.ts  [LocalNetworkOptions, RunContext, start/stopBinaryServices, stale cleanup]
laweta/atproto-runtime ← hamownia/docker_diagnostics.ts [RunContext type only]

schemat/runtime ← hamownia/atproto_network.ts  [initRunDir, repoRoot, SERVICE_PORTS, serviceUrl, neededPorts]
schemat/runtime ← hamownia/docker_diagnostics.ts [repoRoot, serviceUrl]
schemat (root)  ← hamownia/atproto_network.ts  [compileTopology, loadTopologyManifest]
```

### Key Observations

1. **`docker_diagnostics.ts` has a split dependency**: ~~it imports `RunContext` from
   `@garazyk/laweta/atproto-runtime` but `repoRoot`/`serviceUrl` from
   `@garazyk/schemat/runtime`. This is the single file that straddles both
   old and new ownership boundaries. Moving it to use only schemat/hamownia
   types is a prerequisite for PR 2.~~
   **Fixed in PR 2**: `docker_diagnostics.ts` now imports `TopologyRunContext`
   from `@garazyk/schemat/runtime` exclusively. No more laweta dependency.

2. **`RunContext` vs `TopologyRunContext` type divergence**:
   ~~- `laweta/docker_types.ts` defines `RunContext` with `statsSampler?: ContainerStatsSampler`
   - `schemat/docker_config.ts` defines `TopologyRunContext` with `statsSampler?: { start(); stop() }`
   (a structural interface, not the concrete class).
   - `hamownia/atproto_network.ts` bridges via `initTopologyRunDir(requestedId) as RunContext`.
   The structural typing works at runtime but the explicit cast is a code smell.
   PR 2 should unify on `TopologyRunContext` or a shared interface.~~
   **Fixed in PR 2**: `laweta/docker_types.ts` now defines a `StatsSampler` structural
   interface and `RunContext.statsSampler` uses it instead of the concrete class.
   `hamownia/atproto_network.ts` uses `TopologyRunContext` from schemat directly
   and exports a deprecated `RunContext` type alias. The `as RunContext` cast is gone.

3. **`roleToEnvKey` is duplicated**:
   ~~- `laweta/docker_runner.ts` has a private `roleToEnvKey()` with a hardcoded
     ATProto-specific mapping (`pds→PDS_URL`, `pds2→PDS2_URL`, etc.).
   - `schemat/topology_registry.ts` has `roleEnvKey()` backed by `ROLE_ENV_REGISTRY`
     which is the canonical, extensible version.
   - When `docker_runner.ts` scenario semantics move to hamownia, the private
     `roleToEnvKey()` should be replaced by `roleEnvKey()` from `@garazyk/schemat`.~~
   **Fixed in PR 4**: Removed the private `roleToEnvKey()` from
   `laweta/docker_runner.ts`. Added `roleEnvMapper` option to
   `DockerRunnerOptions` so callers inject the ATProto mapping from
   `@garazyk/schemat`. The generic fallback is `role.toUpperCase() + "_URL"`.
   `hamownia/scenario_runner.ts` now passes `roleEnvKey` from schemat.

4. **Dashboard uses JSR import, not workspace alias**:
   ~~`packages/dashboard/deno.json` maps `@garazyk/laweta` to
   `jsr:@garazyk/laweta@0.1.0-alpha.1` rather than the workspace path.
   This means the dashboard does not see local laweta changes until a new
   version is published to JSR. This is a known alpha constraint but should
   be noted: dashboard import path updates will need a JSR publish or a
   switch to the workspace alias.~~
   **Fixed in PR 6**: Removed the JSR import overrides from the dashboard's
   `deno.json`. The dashboard now resolves `@garazyk/laweta`,
   `@garazyk/hamownia`, and `@garazyk/schemat` through the workspace root
   import map, which correctly handles both root and subpath imports.

5. **`laweta/docker.ts` is dead code**:
   ~~Not exported in `deno.json`, not imported by any package or script.
   Its `startLocalNetwork()` throws for topology-aware orchestration.
   It can be removed in PR 3 or PR 7 without compatibility concerns.~~
   **Removed in PR 7**.

## PR Sequencing Notes

1. ~~Move runtime config consumers first because `@garazyk/schemat/runtime`
   already exists and matches the laweta helper behavior.~~ **Done in PR 2.**
2. ~~Move `RunContext` users in `hamownia/docker_diagnostics.ts` to a hamownia
   or schemat-owned type before moving binary orchestration.~~ **Done in PR 2.**
3. ~~Move binary orchestration as implementation code into hamownia, with laweta
   compatibility wrappers kept thin. Avoid having laweta import hamownia if the
   boundary checker treats that as an inversion.~~ **Done in PR 3.**
4. ~~Split `docker_runner.ts` by behavior: keep only reusable Docker container
   execution in laweta if needed, and put scenario env mapping plus topology
   semantics in hamownia.~~ **Done in PR 4.**
5. Leave `@garazyk/laweta` root generic throughout. The only questionable root
   export today is the scenario Docker runner surface.

## PR 2 Changes Summary

- `hamownia/docker_diagnostics.ts`: Switched from `RunContext` (laweta) to
  `TopologyRunContext` (schemat/runtime). No longer depends on laweta.
- `hamownia/atproto_network.ts`: Defined `LocalNetworkOptions` locally (no
  longer imported from laweta). Uses `TopologyRunContext` from schemat/runtime
  directly. Exports deprecated `RunContext` type alias for backward compat.
  Removed type imports from `@garazyk/laweta/atproto-runtime`.
- `laweta/docker_types.ts`: Introduced `StatsSampler` structural interface.
  `RunContext.statsSampler` now uses the structural type instead of the
  concrete `ContainerStatsSampler` class, making it compatible with
  `TopologyRunContext`. Added `@deprecated` to both `LocalNetworkOptions`
  and `RunContext`.
- `laweta/atproto_runtime.ts`: Added `@deprecated` TSDoc to every re-export,
  pointing to the correct owning package.
- `laweta/runtime_config.ts`: Added `@deprecated` module header.
- `laweta/docker.ts`: Added `@deprecated` module header.

## PR 3 Changes Summary

- `hamownia/binary_services.ts` (new): Moved `startBinaryServices` and
  `stopBinaryServices` from `laweta/docker_binary.ts`. Uses
  `TopologyRunContext` from `@garazyk/schemat/runtime` instead of
  `RunContext`. Drops unused `LocalNetworkOptions` parameter from
  `startBinaryServices`. Imports `repoRoot`, `SERVICE_PORTS`, `serviceUrl`
  from `@garazyk/schemat/runtime` and `waitForHttp` from `@garazyk/laweta`.
- `hamownia/stale_cleanup.ts` (new): Moved `stopStaleDockerE2e` and
  `stopStaleHostProcesses` from `laweta/docker_cleanup.ts`. Imports
  `createDockerClient`, `findStaleProjectsOnPorts`, `composeDown` from
  `@garazyk/laweta` and `neededPorts` from `@garazyk/schemat/runtime`.
- `hamownia/atproto_network.ts`: Now imports from `./binary_services.ts` and
  `./stale_cleanup.ts` instead of `@garazyk/laweta/atproto-runtime`. No more
  laweta/atproto-runtime dependency.
- `hamownia/deno.json`: Added `./binary-services` and `./stale-cleanup`
  subpath exports.
- `laweta/docker_binary.ts`: Added `@deprecated` module header pointing to
  `@garazyk/hamownia/binary-services`. Kept for internal use by dead code
  (`docker.ts`) until PR 7.
- `laweta/docker_cleanup.ts`: Added `@deprecated` module header pointing to
  `@garazyk/hamownia/stale-cleanup`. Kept for internal use by dead code
  (`docker.ts`) until PR 7.
- `laweta/atproto_runtime.ts`: Updated deprecation pointers for binary and
  cleanup helpers to point to the new hamownia subpaths.

## PR 4 Changes Summary

- `laweta/docker_runner.ts`: Removed private `roleToEnvKey()` (ATProto-specific
  hardcoded mapping). Added `roleEnvMapper?: (role: string) => string` to
  `DockerRunnerOptions` so callers inject the mapping. Generic fallback is
  `role.toUpperCase() + "_URL"`. The module is now fully generic — no
  ATProto-specific knowledge.
- `hamownia/scenario_runner.ts`: Now imports `roleEnvKey` from `@garazyk/schemat`
  and passes it as `roleEnvMapper` to `runScenarioInDocker`.
- `laweta/docker_runner_test.ts`: Updated to pass explicit `roleEnvMapper`.
  Added a new test for the generic fallback behavior.

## PR 5 Changes Summary

- `hamownia/docker_runner.ts` (new): Moved from `laweta/docker_runner.ts`.
  Scenario Docker execution is orchestration, not generic Docker infrastructure.
  Identical implementation; only the module header changed.
- `hamownia/docker_runner_test.ts` (new): Moved from `laweta/docker_runner_test.ts`.
  Updated import path from `./docker_runner.ts` (still local within hamownia).
- `hamownia/scenario_runner.ts`: Now imports `runScenarioInDocker` from
  `./docker_runner.ts` instead of `@garazyk/laweta`. No more laweta dependency
  for the Docker runner.
- `hamownia/deno.json`: Added `./docker-runner` subpath export.
- `laweta/mod.ts`: Removed `buildDockerRunnerArgs`, `runScenarioInDocker`,
  `DOCKER_RUNNER_TIMEOUT_EXIT_CODE`, and `DockerRunnerOptions` from the root
  export. Updated module docstring to reflect that laweta is now purely
  generic Docker infrastructure (Engine, Compose, health, event, stats).
- `laweta/docker_runner.ts`: Added `@deprecated` module header pointing to
  `@garazyk/hamownia/docker-runner`. File kept but no longer exported from
  `laweta/mod.ts`.
- `laweta/docker_runner_test.ts`: Deleted (moved to hamownia).
- `laweta/public_api_test.ts`: Removed `buildDockerRunnerArgs` assertion from
  the root-export test, since the Docker runner is no longer on laweta's root.

## PR 6 Changes Summary

- `dashboard/deno.json`: Removed the three JSR import overrides
  (`@garazyk/hamownia`, `@garazyk/laweta`, `@garazyk/schemat`).
  The dashboard now resolves all garazyk package imports through the
  workspace root import map, which correctly handles both root imports
  (e.g. `@garazyk/laweta`) and subpath imports
  (e.g. `@garazyk/hamownia/atproto-network`).
- No source code changes needed — the dashboard only imports generic
  Docker primitives from `@garazyk/laweta` (still on root export) and
  orchestration from `@garazyk/hamownia/atproto-network`.

## PR 7 Changes Summary

**Deleted files (7):**
- `laweta/docker.ts` — dead code, not exported, not imported
- `laweta/docker_runner.ts` — moved to `hamownia/docker_runner.ts` in PR 5
- `laweta/atproto_runtime.ts` — deprecated compatibility subpath, no external consumers
- `laweta/docker_binary.ts` — moved to `hamownia/binary_services.ts` in PR 3
- `laweta/docker_cleanup.ts` — moved to `hamownia/stale_cleanup.ts` in PR 3
- `laweta/docker_types.ts` — types moved to hamownia/schemat in PRs 2-3
- `laweta/runtime_config.ts` — duplicated by `schemat/docker_config.ts`

**Updated files:**
- `laweta/deno.json`: Removed `./atproto-runtime` subpath export. Laweta now
  exports only `.` (root) and `./compose`.
- `laweta/public_api_test.ts`: Removed the `atproto_runtime` import and the
  "ATProto runtime helpers are off the root export" test (the subpath no
  longer exists).

**Result:** `@garazyk/laweta` is now a pure generic Docker package with
zero ATProto-specific code. Its root export contains only Docker Engine API,
Compose, health, event, stats, and telemetry utilities.

## Verification

Run after PR 1 and after every later import migration:

```bash
deno task boundaries
deno check packages/*/mod.ts
```

Broader follow-up gates for movement PRs:

```bash
deno check packages/*/mod.ts scripts/*.ts
deno test -A packages/schemat/ packages/hamownia/ packages/laweta/
```
