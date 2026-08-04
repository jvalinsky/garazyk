# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Garazyk is an Objective-C implementation of AT Protocol services (PDS, relay, PLC directory,
AppView, admin UI). It builds with CMake on macOS (Apple frameworks) and Linux (GNUstep), stores
state in SQLite, and is driven in tests by a Deno-based scenario framework.

`AGENTS.md` is the operational companion to this file: it lists the project skills in
`.agents/skills/` (e.g. `garazyk-testing`, `garazyk-database`, `gnustep-compat`,
`sqlite-sql-best-practices`) and the plan-governance loop in `docs/plans/`.

## Commands

### Build and test

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug
```

```bash
cmake --build build --target AllTests --parallel 4
```

```bash
./build/tests/AllTests --gated=run
```

Keep `--parallel` bounded (4). Unbounded parallel builds exhaust memory on 16 GB machines. Full
test runs also need free disk — SQLite tests fail with `SQLITE_FULL` when the disk is near
capacity.

Run `xcodegen generate` (from `project.yml`) before using `Garazyk.xcodeproj` on macOS.

### Running a subset of tests

`AllTests` is a single binary with its own filter layer (`./build/tests/AllTests --help`):

```bash
./build/tests/AllTests --filter 'PDSAccountServiceTests' --gated=run
```

```bash
./build/tests/AllTests -XCTest 'MSTInteropTests/testEmptyTree' --gated=run
```

Other useful flags: `--list [-v]` (enumerate classes/methods with gate tags), `--category Sync`,
`--exclude PATTERN`, `--timeout SECS`, `--shuffle --seed N`, `--json`.

**Gated tests.** Classes needing sockets or external services are tagged `integration` or `socket`
and are *skipped by default*. `--gated=run` runs everything (this is what `ctest` and CI use);
`--gated=include` runs them but marks them in the output. A green default run is not a green run.

`ctest --test-dir build --output-on-failure` runs `AllTests --gated=run` plus the admin-UI asset
sync check. `scripts/test/run-tests.sh` wraps the same thing with the UI design-system gate.

Standalone test executables exist for a few suites excluded from `AllTests`: `migration_tests`,
`connection_pool_tests`, `record_cache_tests` (and `SecItemLinuxStoreTests` on Linux only).

### Deno checks

```bash
deno task check && deno task lint && deno task test
```

`deno task fmt` formats `packages/`. `deno install` fetches dependencies.

### Scenarios (integration against a live local network)

```bash
deno task hamownia run --setup 01_account_lifecycle
```

Requires Docker. `--no-setup` runs against already-running services, `--keep-running` leaves them
up, `--teardown-only` stops them, `--list` enumerates scenarios. `./scripts/scenarios/setup_local_network.sh`
brings up the Docker topology directly. See `docs/11-reference/deno-scenario-framework.md`.

### Pre-push gates (these mirror CI)

Beyond the build/test/lint commands above, CI enforces:

```bash
./scripts/dev/check_module_boundaries.sh .
```

```bash
./scripts/check-recursive-setters.sh
```

```bash
deno run -A scripts/generate_nsid_constants.ts --check
```

```bash
deno run --allow-read packages/narzedzia/nsid_registration_literal_check.ts .
```

```bash
node scripts/docs/generate_xrpc_coverage_report.cjs --source-only --fail-on-duplicates
```

Doc coverage is also gated: Objective-C ≥90% overall (`scripts/docs/doc-coverage.ts`), and repo
docs must pass `scripts/docs/repo_docs.ts validate --internal-strict`.

## Architecture

### Services and binaries

Each binary in `Garazyk/Binaries/` is a separate process with its own config and routes. The
names are Polish-vehicle codenames, so the mapping is not guessable:

| Binary | Role |
| --- | --- |
| `kaszlak` | PDS server + CLI |
| `zuk` | Relay |
| `campagnola` | PLC directory |
| `syrena` | AppView |
| `syrena-chat` | Chat service |
| `garazyk-ui` | Administration UI |
| `jelcz` | Video processing |
| `beskid`, `mikrus`, `germ` | Supporting services (indexing, caches) |

Flow: client → PDS → PLC for identity; PDS emits `com.atproto.sync.subscribeRepos` → relay →
AppView ingest → indexers → AppView query handlers.

### Library layering

Shared code lives in static libraries whose public dependency DAG is enforced by
`scripts/dev/check_module_boundaries.sh`:

```
ATProtoCore  ←  ATProtoStorage, ATProtoTransport
             ←  ATProtoServices (→ Storage)
             ←  ATProtoSync (→ Storage, Transport)
             ←  ATProtoXRPC (→ Services, Storage, Transport, Sync)
             ←  ATProtoPLC (→ Storage, Transport)
             ←  ATProtoRuntime (→ PLC, Services, Transport, XRPC, Sync, VideoService)
             ←  ATProtoMediaCore → ATProtoVideoService
```

Adding a `PUBLIC` link that is not in the allow-list in that script fails CI. The same script also
forbids `Sync/` importing `App/`, and `PLC/` importing App runtime types.

### Request path

`HttpServer` accepts → `Http1Parser` turns bytes into protocol events (parsing is separated from
socket I/O, which `HttpConnectionIOCoordinator` owns) → `HttpRouteTrie` picks an HTTP route →
`XrpcDispatcher` applies request policy → a *route pack* handler runs. XRPC methods are grouped by
namespace into route packs (`XrpcServerPack`, `XrpcRepoPack`, `XrpcSyncPack`,
`AppViewXRpcRoutePack+*`), typically split further into `+Category` categories. Size and timeout
limits are enforced before dispatch.

`ATProtoServiceContainer` registers shared services; route packs receive them via
`XrpcRoutePackServiceBag`.

### Storage

Service-level SQLite databases hold account, DID cache, and sequencing state; each actor
repository has its own store for records and blocks; blobs live outside SQLite. WAL mode, pooled
readers, serialized writers per store, migrations through `PDSMigrationManager`. Services depend on
repository protocols so tests can substitute in-memory implementations. See
`Garazyk/Sources/Database/ARCHITECTURE.md`.

### Platform split

macOS uses Apple frameworks directly; Linux uses GNUstep + libdispatch + OpenSSL plus the shims in
`Garazyk/Sources/Compat/` (including a `Compat/XCTest` reimplementation). Both build with ARC
enabled. Code under `Compat/` must not depend on `Database/` (ADR 0001).

## Conventions that will bite you

**Imports are absolute from `Garazyk/Sources/`.** Write `#import "Network/XrpcHandler.h"`, never
`#import "../Network/XrpcHandler.h"`. Relative imports in `Sources/` or `Frameworks/` fail the
boundary check.

**New test suites need two steps, not one.** Test sources are picked up by `file(GLOB_RECURSE ...)`,
so a new `.m` file requires re-running `cmake -S . -B build` — an incremental build alone will not
see it. The class name must *also* be added to the `testClasses` array in
`Garazyk/Tests/test_main.m` (~line 826). A registration audit compares that array against
runtime-discovered `XCTestCase` subclasses and fails the run on any mismatch in either direction —
so removing a suite means removing its entry too.

**XRPC method IDs come from generated constants.** Use the constants in
`Network/Generated/GZXrpcNSID.h`, generated from the lexicons in `Garazyk/Resources/lexicons/` by
`scripts/generate_nsid_constants.ts`. Raw `registerMethod:@"com.atproto...."` literals are rejected
by the `narzedzia` lint. Do not propose a typed NSID wrapper class — that was evaluated and
rejected in ADR 0003 for ObjC-specific reasons.

**Every source file carries SPDX headers.** `// SPDX-FileCopyrightText:` and
`// SPDX-License-Identifier: Unlicense OR CC0-1.0` at the top; licensing is declared in
`.reuse/dep5`. `scripts/add-spdx-headers.ts` adds them.

**Architecture decisions are recorded.** `docs/adr/` holds ~30 accepted ADRs covering things that
look like bugs but are deliberate (P-256 low-S, relay future-cursor handling, permissioned spaces,
DPoP replay cache durability, auth path architecture). Check there before "fixing" surprising
behavior, and add an ADR for new structural decisions.

**Match surrounding style; do not run clang-format over existing files.** `.clang-format` specifies
Allman braces, but the tree is uniformly K&R, and indentation varies between 2 and 4 spaces across
(and sometimes within) files. Reformatting produces large spurious diffs. Follow the file you are
editing.

**A secret-scanning pre-commit hook exists but is not installed by default** —
`cp scripts/git-hooks/pre-commit .git/hooks/pre-commit`.

## Deno packages

Workspace members under `packages/`: `gruszka` (XRPC clients, lexicon handling), `hamownia`
(scenario runner), `laweta` (Docker control), `schemat` (topology definitions), `narzedzia`
(repository lints), `tui` (terminal UI components), plus `scripts/scenario-dashboard`.

## Documentation map

`docs/index.md` is the entry point. Most useful: `docs/01-getting-started/codebase-map.md`,
`docs/20-explanation/architecture/atproto_pds_architecture.md`,
`docs/20-explanation/guides/DEPLOYMENT.md`, `docs/adr/`, and `docs/plans/` for in-flight work.
`DESIGN.md` is the design system for the scenario dashboard UI specifically, not the services.
