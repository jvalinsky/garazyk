# Scenario Dashboard Run State And Network Health

Date: 2026-05-24
Primary node: 825
Commit: b27b3982

## User Report

The dashboard showed stale run state, 2016/2017 timestamps for 2026 run IDs, huge elapsed durations, empty network service status, and noisy connection-refused stack traces during expected binary-service startup probes.

## Implemented

- Normalized dashboard network API responses to arrays so web and TUI runtimes receive the same service shape.
- Added recent-run polling support and made completed runs refresh promptly after terminal events.
- Normalized run timestamps from run IDs when persisted DB epochs are bogus, avoiding 2016/2017 display for 2026 run IDs.
- Updated run progress rendering to use polled progress state and finished timestamps instead of stale active-row state.
- Seeded host-mode network service cache from topology defaults so the dashboard does not show `0/0 services` before Docker discovery succeeds.
- Reworked host/docker start and stop paths to use runner mode explicitly and avoid passive Docker discovery blocking normal host-mode dashboard use.
- Reconciled stale running rows at dashboard startup by importing reports or marking old runs complete/error.
- Filtered non-scenario JSON artifacts out of report scanning.
- Reduced expected startup probe noise by hiding retry stack traces unless `LAWETA_HEALTH_DEBUG=1`.
- Added persistence and TUI/run-detail coverage around topology, runner, agent mode, and run summaries.

## Verification

- `deno check scripts/scenario-dashboard/main.ts`
- `deno test -A scripts/scenario-dashboard`
- `deno test -A packages/laweta/docker_health_test.ts`

## Follow-Up

- Re-run a real browser smoke test after the next dashboard polish pass to confirm the latest cache-seeding behavior against the live UI.
- If Docker-mode failures remain, collect `docker ps`, `docker logs`, and `/api/network/health` output from a Docker runner session before changing service health semantics again.
