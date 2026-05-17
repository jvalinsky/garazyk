# Refactor Plan: Extract TypeScript from `scripts/` into JSR Packages

## Current State

**4 packages** in `packages/`:
| Package | Purpose |
|---------|---------|
| `@garazyk/gruszka` | XRPC client, lexicons, firehose, seed helpers |
| `@garazyk/hamownia` | Scenario runner, diagnostics, process lifecycle, mock-twilio client, OTel |
| `@garazyk/laweta` | Docker Engine/Compose client, container stats, health |
| `@garazyk/schemat` | Topology compiler, presets, manifest, web-client configs |

**1 quasi-package** in `scripts/`:
| Package | Purpose |
|---------|---------|
| `@garazyk/scenario-dashboard` | Fresh web dashboard + TUI (already has `deno.json`, already in workspace) |

**~30 TypeScript files** still in `scripts/` that contain extractable logic.

---

## Phase 0: New Package — `@garazyk/narzedzia` (tooling)

**Rationale:** Several scripts are dev-tooling (doc coverage, boundary checks, SPDX headers, TSDoc coverage) that don't belong in any existing package. They share a common theme: repo-level static analysis and codegen. A new `@garazyk/narzedzia` ("tools" in Polish) package gives them a proper home.

### 0.1 Create `packages/narzedzia/`

```
packages/narzedzia/
  deno.json
  mod.ts
  doc_coverage.ts        ← from scripts/docs/doc-coverage.ts
  tsdoc_coverage.ts      ← from scripts/docs/tsdoc-coverage.ts
  repo_docs.ts           ← from scripts/docs/repo_docs.ts
  boundary_check.ts      ← from scripts/dev/check_module_boundaries.ts
  spdx_headers.ts        ← from scripts/add-spdx-headers.ts
  vitepress_migration.ts ← from scripts/docs/migrate-to-vitepress.ts
```

**`deno.json` exports:**
```json
{
  "name": "@garazyk/narzedzia",
  "exports": {
    ".": "./mod.ts",
    "./doc-coverage": "./doc_coverage.ts",
    "./tsdoc-coverage": "./tsdoc_coverage.ts",
    "./repo-docs": "./repo_docs.ts",
    "./boundary-check": "./boundary_check.ts",
    "./spdx-headers": "./spdx_headers.ts",
    "./vitepress-migration": "./vitepress_migration.ts"
  }
}
```

**Changes per file:**

| Source | Changes |
|--------|---------|
| `doc-coverage.ts` (594 lines) | Extract `buildReport()`, `countDocumentation()`, `walkHeaders()`, `summarize()` as exported functions. CLI `main()` stays as `if (import.meta.main)` entry. Remove hardcoded `Garazyk/Sources` default — make it a parameter. |
| `tsdoc-coverage.ts` (627 lines) | Extract `buildReport()`, `collectSourceFiles()`, `loadDocJson()`, `addTopLevelNode()`, `addClassMembers()`, `addInterfaceMembers()` as exported functions. Replace hand-rolled `dirname`/`basename`/`joinPath` with `@std/path`. CLI `main()` stays as entry. |
| `repo_docs.ts` (886 lines) | Extract `buildRegistry()`, `analyzeLinks()`, `computeOrphans()`, `generateIndexPages()`, `checkExternalLinks()`, `resolveInternalTarget()` as exported functions. Replace hardcoded `ROOT`/`DOCS` paths with parameters. CLI `main()` stays as entry. |
| `check_module_boundaries.ts` (160 lines) | Extract `walkTypeScriptFiles()`, `lineStartOffsets()`, `lineForOffset()`, and the violation-checking loop as `checkBoundaries(root, rules, baseline)`. CLI becomes thin wrapper. |
| `add-spdx-headers.ts` (87 lines) | Extract `processFile()`, `walk()`, `hasSpdx()` as exported functions. Currently ObjC-only — generalize file extension list to be configurable. |
| `migrate-to-vitepress.ts` (549 lines) | Rewrite from Node.js `fs`/`path` to Deno APIs (`Deno.readTextFile`, `@std/path`). Extract `MigrationTool` class as-is (it's already well-structured). Remove `process.exit` / `process.argv` — use `Deno.args`. |

**After extraction**, each `scripts/docs/*.ts` and `scripts/dev/check_module_boundaries.ts` and `scripts/add-spdx-headers.ts` becomes a thin CLI wrapper:
```typescript
#!/usr/bin/env -S deno run -A
import { main } from "@garazyk/narzedzia/doc-coverage";
await main();
```

---

## Phase 1: Expand `@garazyk/gruszka` — Chat Viewer & Account Creation

### 1.1 Add `gruszka/chat-viewer` sub-export

**Source:** `scripts/show_chat.ts` (362 lines)

Extract the TUI rendering layer into `packages/gruszka/chat_viewer.ts`:

```
packages/gruszka/chat_viewer.ts
```

**Exported functions:**
- `getTermWidth(): number`
- `boxTop(title)`, `boxBot()`, `boxMid()`, `boxRow(content)`
- `printMsg(msg, selfDid)`, `printConvo(convo, idx, total, selfDid, messages)`
- `fmtTs(ts)`, `fmtSender(sender, selfDid)`, `wrap(text, max)`
- ANSI helper: `c(s, ...codes)`, `vis(s)`, `padR(s, w)`, `padL(s, w)`

**Rewrite `show_chat.ts`** to import from `@garazyk/gruszka/seed` (for XRPC/chat) and `@garazyk/gruszka/chat-viewer` (for rendering). The script becomes ~30 lines.

### 1.2 Add `gruszka/account-ops` sub-export

**Source:** `scripts/create_account.ts` (355 lines)

The XRPC operations (`createAccount`, `createSession`, `updateProfile`, `createPost`, `requestCrawl`) are already in `gruszka/seed` or trivially expressible via `XrpcClient`. The unique logic is:

- `generateInviteCode()` — random invite code generation
- `insertInviteCodeViaSsh()` — SSH-based invite code insertion into PDS SQLite
- `getExistingInviteCodeViaSsh()` — SSH-based invite code query

Add to `packages/gruszka/account_ops.ts`:

```
packages/gruszka/account_ops.ts
```

**Exported functions:**
- `generateInviteCode(groups?, length?): string`
- `generatePassword(length?): string`
- `randomString(alphabet, length): string`

The SSH-based invite code operations are infrastructure-specific (they shell out to `ssh` + `sqlite3`). These belong in `@garazyk/hamownia` — see Phase 2.

**Rewrite `create_account.ts`** to use `XrpcClient` + `gruszka/seed` + `gruszka/account-ops`. The script becomes ~50 lines.

### 1.3 Update `gruszka/deno.json` exports

```json
{
  "exports": {
    ".": "./mod.ts",
    "./doc-links": "./doc_links.ts",
    "./legacy-clients": "./legacy_clients.ts",
    "./lexicons": "./lexicons.ts",
    "./seed": "./seed.ts",
    "./chat-viewer": "./chat_viewer.ts",
    "./account-ops": "./account_ops.ts"
  }
}
```

---

## Phase 2: Expand `@garazyk/hamownia` — Mock Twilio Server, Account Discovery, PDS CLI

### 2.1 Move mock-twilio server into `hamownia/mock-twilio`

**Source:** `scripts/mock-twilio-server.ts` (217 lines)

The client class (`MockTwilioServer`) is already in `packages/hamownia/mock_twilio.ts`. The server implementation is still in `scripts/`. Unify them.

**Add to `packages/hamownia/mock_twilio.ts`:**
- Export `MockTwilioServerConfig` interface (port, accountSid, authToken, alwaysApprove, latency, failRate)
- Export `serveMockTwilio(config): void` — the `Deno.serve()` call with `handleRequest`
- Export `handleRequest(req, config): Promise<Response>` — the request handler
- Keep existing `MockTwilioServer` class (client)

**Rewrite `scripts/mock-twilio-server.ts`** to:
```typescript
#!/usr/bin/env -S deno run -A
import { serveMockTwilio, parseMockTwilioConfig } from "@garazyk/hamownia/mock-twilio";
const cfg = parseMockTwilioConfig(Deno.args);
serveMockTwilio(cfg);
```

**Move `scripts/mock-twilio-server.test.ts`** to `packages/hamownia/mock_twilio_server_test.ts` (or keep as-is if it tests the CLI entry point).

### 2.2 Add `hamownia/account-discovery` sub-export

**Source:** `scripts/create_chat_convos.ts` lines 198–316 (SSH-based PDS DB querying, admin API fallback, local SQLite discovery)

Add `packages/hamownia/account_discovery.ts`:

```
packages/hamownia/account_discovery.ts
```

**Exported functions:**
- `discoverLocalDidTargets(dbPath, limit?): Promise<TargetIdentity[]>`
- `discoverRemoteAccountsViaSsh(sshHost, dbPath, limit?): Promise<TargetIdentity[]>`
- `discoverRemoteAccountsViaAdminApi(pdsUrl, accessJwt, limit?): Promise<TargetIdentity[]>`
- `resolveTargets(pdsUrl, selfDid, accessJwt?, options?): Promise<TargetIdentity[]>`
- `firstExistingServiceDbPath(): Promise<string | undefined>`

**Exported types:**
- `TargetIdentity { input: string; did: string; handle?: string }`

### 2.3 Add `hamownia/invite-code` sub-export

**Source:** `scripts/create_account.ts` lines 153–183 (SSH-based invite code insertion/query)

Add `packages/hamownia/invite_code.ts`:

```
packages/hamownia/invite_code.ts
```

**Exported functions:**
- `insertInviteCodeViaSsh(sshHost, dbPath, code, accountDid, maxUses?): Promise<void>`
- `getExistingInviteCodeViaSsh(sshHost, dbPath): Promise<string | null>`

### 2.4 Add `hamownia/pds-cli` sub-export

**Source:** `scripts/dev/pds_cli.ts` (282 lines)

This is a multi-command CLI. The `runKaszlak` (binary execution) part is unique to the native PDS. The XRPC operations should use `gruszka`.

Add `packages/hamownia/pds_cli.ts`:

```
packages/hamownia/pds_cli.ts
```

**Exported functions:**
- `runKaszlak(binPath, dataDir, args): Promise<number>` — binary execution
- `handleAccountCreate(argv, config): Promise<number>`
- `handlePostCreate(argv, config): Promise<number>`
- `handleProfileUpdate(argv, config): Promise<number>`

**Rewrite `scripts/dev/pds_cli.ts`** to import from `@garazyk/hamownia/pds-cli` and `@garazyk/gruszka`.

### 2.5 Update `hamownia/deno.json` exports

```json
{
  "exports": {
    ".": "./mod.ts",
    "./account-discovery": "./account_discovery.ts",
    "./atproto-network": "./atproto_network.ts",
    "./browser-flow": "./browser_flow.ts",
    "./config": "./config.ts",
    "./diagnostics": "./diagnostics.ts",
    "./docker-diagnostics": "./docker_diagnostics.ts",
    "./format": "./format.ts",
    "./instrumentation": "./instrumentation.ts",
    "./invite-code": "./invite_code.ts",
    "./mock-twilio": "./mock_twilio.ts",
    "./otel": "./otel.ts",
    "./pds-cli": "./pds_cli.ts",
    "./process-lifecycle": "./process_lifecycle.ts",
    "./progress": "./progress.ts",
    "./report-writer": "./report_writer.ts",
    "./run-loop": "./run_loop.ts",
    "./run-scenarios-types": "./run_scenarios_types.ts",
    "./scenario-runner": "./scenario_runner.ts",
    "./scenario-selector": "./scenario_selector.ts"
  }
}
```

---

## Phase 3: Rewrite chat scripts to use `gruszka/seed`

### 3.1 Rewrite `scripts/create_chat_convos.ts`

**Current:** 634 lines with inline `xrpcGet`, `xrpcPost`, `chatServiceDidForUrl`, `serviceAuthForChatMethod`, `createSession`, `resolveHandle`, `asRecord`, `memberName`, `senderName`, `nowIso`, `short`, `appendParams`.

**After:** Import from `@garazyk/gruszka/seed` and `@garazyk/hamownia/account-discovery`. The script becomes ~150 lines (the mode-dispatch logic and CLI arg parsing are the only unique parts).

**Remove all duplicated functions:**
- `xrpcGet` / `xrpcPost` → `XrpcClient` from `gruszka`
- `chatServiceDidForUrl` → `chatServiceDidForUrl` from `gruszka/seed`
- `serviceAuthForChatMethod` → `chatServiceAuthForMethod` from `gruszka/seed`
- `createSession` → `XrpcClient.accounts.createSession`
- `resolveHandle` → `XrpcClient.identity.resolveHandle`
- `asRecord` / `memberName` / `senderName` / `nowIso` / `short` / `appendParams` → inline or small local helpers

### 3.2 Rewrite `scripts/check_chat_messages.ts`

**Current:** 183 lines with duplicated XRPC/chat layer.

**After:** Import from `@garazyk/gruszka/seed`. The script becomes ~40 lines.

### 3.3 Rewrite `scripts/show_chat.ts`

**Current:** 362 lines with duplicated XRPC/chat layer + TUI rendering.

**After:** Import from `@garazyk/gruszka/seed` (XRPC/chat) and `@garazyk/gruszka/chat-viewer` (TUI). The script becomes ~30 lines.

---

## Phase 4: Move `scenario-dashboard` to `packages/`

### 4.1 Move `scripts/scenario-dashboard/` → `packages/dashboard/`

**Current state:** Already has its own `deno.json`, already in workspace as `@garazyk/scenario-dashboard`, already has proper exports. The only problem is it lives in `scripts/`.

**Steps:**
1. `mv scripts/scenario-dashboard packages/dashboard`
2. Update `deno.json` workspace: `"./scripts/scenario-dashboard"` → `"./packages/dashboard"`
3. Update root `deno.json` imports: `"@garazyk/scenario-dashboard"` path
4. Update all references in `deno task` entries
5. Update `packages/dashboard/deno.json` name to `@garazyk/dashboard` (drop "scenario-" prefix for consistency with other packages)

---

## Phase 5: Expand `@garazyk/schemat` — Web Client Compose Rendering

### 5.1 Move compose rendering into `schemat`

**Source:** `scripts/scenarios/render_web_client_compose.ts` (254 lines)

The YAML rendering, Dockerfile generation, and git clone orchestration are topology-related logic that belongs in `schemat`.

Add `packages/schemat/web_client_compose.ts`:

```
packages/schemat/web_client_compose.ts
```

**Exported functions:**
- `renderWebClientCompose(client, options): Promise<string>` — the `render()` function
- `writeSourceDockerfile(client, runDir): Promise<string>` — Dockerfile generation
- `prepareSourceBuildContext(client, buildDir): Promise<void>` — git clone orchestration

**Rewrite `scripts/scenarios/render_web_client_compose.ts`** to:
```typescript
#!/usr/bin/env -S deno run -A
import { renderWebClientCompose } from "@garazyk/schemat/web-client-compose";
import { WEB_CLIENT_PRESETS } from "@garazyk/schemat";
// ... parse args, call renderWebClientCompose, write output
```

### 5.2 Update `schemat/deno.json` exports

```json
{
  "exports": {
    ".": "./mod.ts",
    "./runtime": "./runtime.ts",
    "./topology-schema": "./topology_schema.ts",
    "./web-client-compose": "./web_client_compose.ts"
  }
}
```

---

## Phase 6: Clean up remaining scripts

### 6.1 Scripts that become thin wrappers (already mostly done)

These scripts are already thin CLI wrappers over package logic. They stay in `scripts/` but become even thinner:

| Script | Current | After |
|--------|---------|-------|
| `run_scenarios.ts` | Thin wrapper over `hamownia` | No change needed |
| `run_scenarios_test.ts` | Tests for above | No change needed |
| `run_topology_matrix.ts` | CLI wrapper | No change needed |
| `manage_local_network.ts` | Thin wrapper over `hamownia/atproto-network` | No change needed |
| `seed_chat.ts` | Already uses `gruszka/seed` | No change needed |
| `seed_full_suite.ts` | Already uses `gruszka/seed` | No change needed |
| `dev/demo_seed.ts` | Already uses `gruszka/seed` | No change needed |
| `dev/seed_demo_via_xrpc.ts` | Already uses `gruszka/seed` | No change needed |
| `scenarios/compile_topology.ts` | Thin wrapper over `schemat` | No change needed |
| `scenarios/wait_topology.ts` | Thin wrapper over `schemat` + `laweta` | No change needed |
| `test/test-doc-links.ts` | Uses `gruszka` | No change needed |
| `test/test-pds-guide-links.ts` | Uses `gruszka` | No change needed |

### 6.2 Scripts that get rewritten to use packages

| Script | Package(s) used | Estimated new size |
|--------|----------------|-------------------|
| `create_chat_convos.ts` | `gruszka/seed`, `hamownia/account-discovery` | ~150 lines |
| `check_chat_messages.ts` | `gruszka/seed` | ~40 lines |
| `show_chat.ts` | `gruszka/seed`, `gruszka/chat-viewer` | ~30 lines |
| `create_account.ts` | `gruszka/seed`, `gruszka/account-ops`, `hamownia/invite-code` | ~50 lines |
| `mock-twilio-server.ts` | `hamownia/mock-twilio` | ~10 lines |
| `dev/pds_cli.ts` | `hamownia/pds-cli`, `gruszka` | ~30 lines |
| `scenarios/render_web_client_compose.ts` | `schemat/web-client-compose` | ~20 lines |

### 6.3 Scripts that get deleted (logic moves to packages, CLI wrapper stays)

| Script | Logic moves to | CLI wrapper |
|--------|---------------|-------------|
| `docs/doc-coverage.ts` | `@garazyk/narzedzia/doc-coverage` | `scripts/docs/doc-coverage.ts` (5 lines) |
| `docs/tsdoc-coverage.ts` | `@garazyk/narzedzia/tsdoc-coverage` | `scripts/docs/tsdoc-coverage.ts` (5 lines) |
| `docs/repo_docs.ts` | `@garazyk/narzedzia/repo-docs` | `scripts/docs/repo_docs.ts` (5 lines) |
| `docs/migrate-to-vitepress.ts` | `@garazyk/narzedzia/vitepress-migration` | `scripts/docs/migrate-to-vitepress.ts` (5 lines) |
| `dev/check_module_boundaries.ts` | `@garazyk/narzedzia/boundary-check` | `scripts/dev/check_module_boundaries.ts` (5 lines) |
| `add-spdx-headers.ts` | `@garazyk/narzedzia/spdx-headers` | `scripts/add-spdx-headers.ts` (5 lines) |

### 6.4 Scripts that stay as-is (one-off or legacy)

| Script | Reason to keep |
|--------|---------------|
| `diagnose25.ts` | 15-line one-off debug script |
| `dev/generate_characterization_tests.ts` | Legacy ObjC codegen — deprecated, ObjC-specific |

---

## Phase 7: Update workspace, boundary checks, and CI

### 7.1 Update root `deno.json`

```json
{
  "workspace": [
    "./packages/laweta",
    "./packages/gruszka",
    "./packages/schemat",
    "./packages/hamownia",
    "./packages/narzedzia",
    "./packages/dashboard"
  ],
  "imports": {
    "@garazyk/narzedzia": "./packages/narzedzia/mod.ts",
    "@garazyk/dashboard": "./packages/dashboard/mod.ts"
  }
}
```

### 7.2 Update `check_module_boundaries.ts`

Add `narzedzia` and `dashboard` to the package list and boundary rules:

```typescript
type PackageName = "gruszka" | "schemat" | "laweta" | "hamownia" | "narzedzia" | "dashboard";

const rules: readonly BoundaryRule[] = [
  {
    packageName: "gruszka",
    denied: new Set(["gruszka", "schemat", "laweta", "hamownia", "narzedzia", "dashboard"]),
    description: "packages/gruszka must remain standalone",
  },
  {
    packageName: "schemat",
    denied: new Set(["laweta", "hamownia", "narzedzia", "dashboard"]),
    description: "packages/schemat must not depend on laweta, hamownia, narzedzia, or dashboard",
  },
  {
    packageName: "laweta",
    denied: new Set(["schemat", "hamownia", "narzedzia", "dashboard"]),
    description: "packages/laweta must not depend on schemat, hamownia, narzedzia, or dashboard",
  },
  {
    packageName: "narzedzia",
    denied: new Set(["hamownia", "laweta", "dashboard"]),
    description: "packages/narzedzia must not depend on hamownia, laweta, or dashboard",
  },
  {
    packageName: "dashboard",
    denied: new Set(["narzedzia"]),
    description: "packages/dashboard must not depend on narzedzia",
  },
];
```

### 7.3 Update `deno task` entries

```json
{
  "tasks": {
    "check": "deno task boundaries && deno check packages/*/mod.ts scripts/*.ts && deno task dashboard:check",
    "dashboard:check": "deno check --config packages/dashboard/deno.json packages/dashboard/mod.ts packages/dashboard/cli.ts packages/dashboard/server.ts packages/dashboard/tui.ts",
    "dashboard": "cd packages/dashboard && deno task dev",
    "dashboard:tui": "cd packages/dashboard && deno task tui"
  }
}
```

---

## Execution Order

The phases are ordered by dependency: earlier phases produce exports that later phases consume.

| Step | Phase | What | Depends on |
|------|-------|------|-----------|
| 1 | 0 | Create `@garazyk/narzedzia` package, move doc/boundary/SPDX tooling | Nothing |
| 2 | 1.1 | Add `gruszka/chat-viewer` | Nothing |
| 1 | 1.2 | Add `gruszka/account-ops` | Nothing |
| 4 | 1.3 | Update `gruszka/deno.json` | Steps 2–3 |
| 5 | 2.1 | Move mock-twilio server into `hamownia/mock-twilio` | Nothing |
| 6 | 2.2 | Add `hamownia/account-discovery` | Nothing |
| 7 | 2.3 | Add `hamownia/invite-code` | Nothing |
| 8 | 2.4 | Add `hamownia/pds-cli` | `gruszka` |
| 9 | 2.5 | Update `hamownia/deno.json` | Steps 5–8 |
| 10 | 3.1 | Rewrite `create_chat_convos.ts` | Steps 4, 6 |
| 11 | 3.2 | Rewrite `check_chat_messages.ts` | Step 4 |
| 12 | 3.3 | Rewrite `show_chat.ts` | Steps 2, 4 |
| 13 | 4 | Move `scenario-dashboard` → `packages/dashboard` | Nothing |
| 14 | 5 | Add `schemat/web-client-compose` | Nothing |
| 15 | 6 | Rewrite remaining scripts to use packages | Steps 1–14 |
| 16 | 7 | Update workspace, boundary checks, CI | Steps 1–15 |

**Steps 1, 2, 3, 5, 6, 7, 13, 14** are independent and can be done in parallel.

---

## Final Package Map

```
packages/
  gruszka/          # XRPC client, lexicons, firehose, seed, chat-viewer, account-ops
  hamownia/         # Scenario runner, diagnostics, mock-twilio (server+client),
                    # account-discovery, invite-code, pds-cli
  laweta/           # Docker Engine/Compose client
  schemat/          # Topology compiler, presets, web-client-compose
  narzedzia/        # Doc coverage, TSDoc coverage, repo docs, boundary check,
                    # SPDX headers, VitePress migration
  dashboard/        # Fresh web dashboard + TUI for scenario runs
```

**`scripts/` after refactor** contains only:
- Thin CLI wrappers (5–30 lines each) that import from packages
- Shell scripts (`.sh` files — not in scope)
- Scenario files (`scenarios/scenarios/*.ts` — these are test data, not library code)
- One-off debug scripts (`diagnose25.ts`)
- Legacy ObjC codegen (`dev/generate_characterization_tests.ts`)
- Test runner scripts (`test/*.sh`, `test/test-doc-links.ts`, `test/test-pds-guide-links.ts`)
