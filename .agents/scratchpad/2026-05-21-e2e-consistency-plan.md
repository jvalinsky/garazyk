# Ensure E2E Test Execution Consistency

Ensures that no matter how we run E2E scenarios—via direct CLI, terminal TUI, or Web Dashboard—they run and report with absolute consistency. It aligns output folders, maps execution options, guards against redundant Docker container recreation, and captures direct CLI runs in the central SQLite dashboard database.

## User Review Required

We are modifying the central E2E execution loop and DB schema. Please review the following highlights:

> [!IMPORTANT]
> **Database Schema Migration (v4):**
> We are adding migration `v4` to the central `dashboard.db` SQLite database to track the expanded options (`allow_hybrid_network`, `otel`, `verbose`, `timeout`, `no_setup`). This runs safely and backward-compatibly using SQLite's dynamic `addColumns` helper.

> [!IMPORTANT]
> **Unified Execution Output Directory:**
> Direct CLI runs will now default to storing reports/logs inside the workspace at `scripts/scenarios/reports/runs/<runId>` (under the repo root) instead of `/tmp/garazyk-atproto-e2e`. This unifies file outputs across CLI/TUI/Web DB. If run outside the repository, it cleanly falls back to `/tmp/garazyk-atproto-e2e`.

> [!TIP]
> **Automatic Network Reuse:**
> Spawning scenarios via Dashboard or TUI will check if the ATProto compose network is currently active (using `networkManager.getStatus()`). If it is running, it dynamically appends `--no-setup` to prevent the subprocess from tearing down and restarting the active environment.

## Proposed Changes

---

### Central E2E Runner CLI

#### [MODIFY] [run_command.ts](file:///Users/jack/Software/garazyk/packages/hamownia/run_command.ts)
- Modify the default `runDir` construction: if the repository contains `scripts/scenarios/reports`, the direct CLI runner will output directly to `<repoRoot>/scripts/scenarios/reports/runs/<runId>`.
- Gracefully detect the presence of `scripts/scenarios/reports/dashboard.db`. If available, use a dynamic import of the Deno `sqlite3` module to record direct CLI runs and scenario results directly into the central SQLite database. This makes direct CLI runs immediately discoverable and dynamically updated inside the TUI/Web dashboards!

---

### Dashboard SQLite Database

#### [MODIFY] [schema.ts](file:///Users/jack/Software/garazyk/scripts/scenario-dashboard/db/schema.ts)
- Extend the `runs` table schema definition with new option columns:
  - `allow_hybrid_network INTEGER DEFAULT 0`
  - `otel INTEGER DEFAULT 0`
  - `verbose INTEGER DEFAULT 0`
  - `timeout INTEGER DEFAULT 120`
  - `no_setup INTEGER DEFAULT 0`

#### [MODIFY] [migrations.ts](file:///Users/jack/Software/garazyk/scripts/scenario-dashboard/db/migrations.ts)
- Implement `Migration v4` to dynamically add these five option columns to the existing `runs` table.

---

### Dashboard Types & Run Manager

#### [MODIFY] [types.ts](file:///Users/jack/Software/garazyk/scripts/scenario-dashboard/services/types.ts)
- Update `RunConfig` and `Run` interfaces with:
  - `allowHybridNetwork?: boolean`
  - `otel?: boolean`
  - `verbose?: boolean`
  - `timeout?: number`
  - `noSetup?: boolean`

#### [MODIFY] [run_manager.ts](file:///Users/jack/Software/garazyk/scripts/scenario-dashboard/services/run_manager.ts)
- Map new options in `RunConfig` and `Run` to SQL parameter insertion inside `saveRunToDb` and `updateRunInDb`.
- In `spawnRunner`, dynamically check the status of the local ATProto network using `networkManager` (dynamic import to avoid circular dependency). If active, automatically append `--no-setup` to the subprocess arguments.
- Pass `--allow-hybrid-network`, `--otel`, `--verbose`, `--timeout`, and `--no-setup` flags to the spawned CLI subprocess according to the run's configurations.
- Fix a bug in `restartRun` where it drops/loses the `scenarioParams` field, ensuring it properly carries overrides over on restarts.

## Verification Plan

### Automated Tests
- Run existing and new unit tests for argument parsing and DB handling:
  - `deno test -A packages/hamownia/run_command_test.ts`
  - `deno test -A scripts/scenario-dashboard/services/run_manager.test.ts`

### Manual Verification
- Start the ATProto compose stack from the Web/TUI dashboard.
- Run a direct CLI scenario: `deno run -A scripts/run_scenarios.ts --topology garazyk-default 01`.
- Verify that the CLI run reuses the running network without tearing it down.
- Verify that the CLI run immediately shows up in the TUI / Web Dashboard history database.
