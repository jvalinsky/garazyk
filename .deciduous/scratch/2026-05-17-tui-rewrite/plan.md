# TUI Rewrite Plan — Garazyk Scenario Dashboard

## Problem
Current `tui.ts` (267 lines) is a bare-minimum status printer:
- No alternate screen (pollutes scrollback)
- No SIGWINCH/SIGTSTP/panic-safe terminal restore
- No real interactivity (only q/ctrl-c/r)
- No layout (flat vertical list)
- Doesn't use existing TEA state machine (DashboardState + Msg + update + Cmd)
- No diffing (full redraw every frame)
- Single-byte key reading (breaks arrow keys, escape sequences)

## Architecture Decision: Custom Immediate-Mode Renderer
- **No framework** (Ink adds React; TEA state machine already exists)
- Reuse `DashboardState` + `Msg` + `update()` unchanged
- New TUI runtime interprets Cmds as direct service calls (not HTTP)
- Custom ScreenBuffer with diff-based rendering
- btop/bottom-style widget dashboard layout

## Layout: Widget Dashboard (2x2 grid)
```
┌─ Garazyk Scenario Dashboard ──────────────────────────────── time ─┐
│ ┌─ Network ──────────────┐ ┌─ Active Run ───────────────────────┐ │
│ │ service table + actions │ │ progress bar + current scenario    │ │
│ └────────────────────────┘ └────────────────────────────────────┘ │
│ ┌─ Scenarios ────────────┐ ┌─ Run History ─────────────────────┐ │
│ │ categories + coverage   │ │ recent runs + metrics              │ │
│ └────────────────────────┘ └────────────────────────────────────┘ │
│ 1 Network  2 Scenarios  3 Run  4 History  q Quit  Tab Switch   │
└───────────────────────────────────────────────────────────────────┘
```

## File Structure
```
scripts/scenario-dashboard/
├── tui.ts                    ← rewritten entry (alt screen, event loop, cleanup)
├── tui/
│   ├── mod.ts                ← re-exports
│   ├── renderer.ts           ← ScreenBuffer + diff + ANSI output
│   ├── layout.ts             ← panel sizing, responsive breakpoints
│   ├── input.ts              ← key parser (escape sequences, multi-byte)
│   ├── focus.ts              ← focus ring (panels 1-4, Tab cycling)
│   ├── view.ts               ← render DashboardState → ScreenBuffer
│   ├── panels/
│   │   ├── network.ts        ← network services panel
│   │   ├── scenarios.ts      ← scenario list + coverage panel
│   │   ├── run.ts            ← active run + progress panel
│   │   └── history.ts        ← run history + metrics panel
│   └── runtime.ts            ← TEA runtime for TUI (direct service calls)
├── tui_test.ts               ← updated tests
```

## Phases (dependency-ordered)

### Phase 1: Terminal Hygiene (renderer.ts + input.ts)
- ScreenBuffer class: 2D cell array, sized to Deno.consoleSize()
- diff(previous, next) → minimal ANSI escape sequence
- Alternate screen enter/exit, cursor hide/show
- Color helpers: rgb(), ansi16(), dim(), bold(), reverse(), reset()
- Key parser: escape sequences, multi-byte, modifiers
- SIGWINCH → resize + re-render
- SIGTSTP → restore terminal, suspend, re-enter on resume
- finally block → always restore terminal state

### Phase 2: Layout Engine (layout.ts + focus.ts)
- computeLayout(cols, rows) → PanelLayout[]
- Wide (≥100 cols): 2x2 grid
- Narrow (<100 cols): vertical stack
- FocusRing: Tab/Shift+Tab cycling, 1-4 numeric jump

### Phase 3: TUI Runtime (tui/runtime.ts)
- Interprets Cmd.fetch as direct service method calls
- URL → service method mapping:
  /api/network/health → networkManager.healthCheck()
  /api/runs/active → runManager.getActiveRun()
  /api/scenarios → scenarioDiscovery.getScenarios()
  /api/topologies → topologyService.listTopologies()
  /api/runs/:id/progress → runManager.getProgress(runId)
  /api/runs/:id/logs → runManager.getLogs(runId)
  /api/runs/active/metrics → networkManager.getContainerStats()
  /api/network/start → networkManager.startAll(opts)
  /api/network/stop → networkManager.stopAll()
  /api/runs/start → runManager.startRun(config)
  /api/runs/:id/stop → runManager.stopRun(id)
  /api/runs/:id/restart → runManager.restartRun(id)
- Reuses DashboardState + Msg + update() unchanged
- schedule cmd: same as web runtime (setTimeout)
- navigate cmd: no-op in TUI

### Phase 4: View Layer (view.ts + panels/)
- renderView(state, layout, focus) → paint ScreenBuffer
- Status bar (title + time)
- Hint bar (keybindings)
- Panel renderers:
  - network.ts: service table + start/stop actions
  - scenarios.ts: category groups + coverage + filter
  - run.ts: progress bar + current scenario + elapsed
  - history.ts: recent runs table + metrics

### Phase 5: Event Loop (tui.ts rewrite)
- Enter alternate screen, hide cursor, set raw mode
- Create TUI runtime (state + dispatch)
- Compute initial layout
- Event loop: key input → dispatch Msg → state change → render → diff → write
- On quit: exit alternate screen, show cursor, restore raw mode

### Phase 6: Keybinding Design
Global: q/Ctrl+C quit, 1-4 jump panel, Tab cycle, ? help, r refresh
Network: s start, p pds2, x stop, ↑↓ scroll
Scenarios: ↑↓ navigate, Enter run, / filter, Esc clear, Space toggle category
Run: Ctrl+C stop, R restart
History: ↑↓ navigate, Enter view logs, R restart

### Phase 7: Tests + Integration
- renderer_test.ts: buffer diffing, resize, ANSI output
- input_test.ts: key parsing
- layout_test.ts: panel sizing
- focus_test.ts: Tab cycling
- tui_test.ts: update existing test
- cli.ts: minimal update
- deno.json: update check task

## What Stays Unchanged
- dashboard_state.ts (entire TEA state machine)
- services/types.ts
- services/network_manager.ts, run_manager.ts, scenario_discovery.ts, topology_service.ts
- db/
- cli.ts (minimal change)
- Web dashboard (routes/, islands/, components/)

## Estimated Scope
~1,350 lines total (replacing 267-line tui.ts)
