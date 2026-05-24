# TUI Capture & Replay

Record TUI interactions as asciicast v2 and export standalone HTML playback via
Asciinema Player.

## When to Use

- An agent or human describes a sequence of TUI interactions that should be
  recorded as a playable demo.
- You need to create offline HTML exports of TUI sessions for sharing or docs.
- You are testing or demonstrating a TUI built on `@garazyk/tui` primitives.

## Architecture

```
Interaction script (ReplayStep[])
         │
         ▼
┌─────────────────┐    ┌───────────────┐    ┌──────────────┐
│ VirtualTuiHarness│───▶│ CastRecorder  │───▶│ buildExportHtml│
│ (headless render)│    │ (asciicast v2)│    │ (standalone   │
│                 │    │               │    │  HTML player) │
└─────────────────┘    └───────────────┘    └──────────────┘
```

The harness wraps a `ScreenBuffer` and a render callback. Each keystroke or
resize triggers a re-render. The recorder captures every frame as an asciicast
v2 event. The HTML exporter inlines the cast with Asciinema Player v3.8.

## ReplayStep Format

```typescript
type ReplayStep =
  | { t: number; kind: "key"; key: string; ctrl?: boolean; alt?: boolean; shift?: boolean }
  | { t: number; kind: "resize"; cols: number; rows: number }
  | { t: number; kind: "marker"; label: string };
```

- `t` — script-time offset in seconds from start. At speed 1× this equals wall
  time; at speed 5× the wall delay is 1/5 of the gap.
- `key` — key name for the Key object (`"tab"`, `"?"`, `"1"`, `"down"`, etc)
- `marker` — labels appear as clickable timeline buttons in the HTML player

## Writing an Interaction Script (General)

Describe the desired interaction, then translate to a step sequence:

```
"Open dashboard, tab to the Scenarios panel, scroll down twice,
show the help overlay, then go back to the Network panel."
```

```typescript
function demoScript(): ReplayStep[] {
  return [
    { t: 0.5, kind: "marker", label: "Dashboard loaded" },
    { t: 1.0, kind: "key", key: "tab" },
    { t: 1.5, kind: "marker", label: "Focused: Scenarios" },
    { t: 2.0, kind: "key", key: "down" },
    { t: 2.5, kind: "key", key: "down" },
    { t: 3.0, kind: "key", key: "1" },
    { t: 3.5, kind: "marker", label: "Back to Network" },
    { t: 4.0, kind: "key", key: "?" },
    { t: 4.5, kind: "marker", label: "Help shown" },
    { t: 5.0, kind: "key", key: "?" },
  ];
}
```

**Key naming conventions:**
- Navigation: `"tab"`, `"up"`, `"down"`, `"left"`, `"right"`
- Modifiers: `{ key: "tab", shift: true }` for Shift+Tab
- Letters/numbers: their string value (`"a"`, `"1"`, `"?"`)
- Special: `"escape"`, `"enter"`, `" "` (space), `"backspace"`

## General Integration Pattern

To capture any TUI built with `@garazyk/tui`:

```typescript
import { VirtualTuiHarness, CastRecorder, replayScript } from "@garazyk/tui/testing";
import { ScreenBuffer } from "@garazyk/tui";

// 1. Build your render function
const render = (buf: ScreenBuffer) => { /* paint into buf */ };

// 2. Create harness
const harness = new VirtualTuiHarness(width, height, render);

// 3. Wire key handler
harness.onKey((key) => {
  /* update state / navigation from key */
  harness.render();
});

// 4. Record
const recorder = new CastRecorder(harness);
harness.render(); // initial frame

// 5. Replay
await replayScript(harness, steps, { speed: 2 });

// 6. Export
await recorder.close();
const cast = recorder.exportAsciicast();
// write cast + pass to buildExportHtml()
```

## Garazyk Dashboard — Quickstart

The dashboard has its own headless capture script with a pre-built agent API:

```bash
cd scripts/scenario-dashboard

# Capture with default demo (2x speed, ~3.5s)
deno run -A tui_headless_capture.ts

# Custom output dir and speed
deno run -A tui_headless_capture.ts /tmp/my-capture --speed=1

# Via deno task
deno task tui:capture
```

**Programmatic API (preferred for agents):**

```typescript
import { captureHeadlessReplay, demoScript } from "./tui_headless_capture.ts";

const result = await captureHeadlessReplay({
  outputDir: "/tmp/demo",
  steps: [
    { t: 0.5, kind: "marker", label: "Start" },
    { t: 1.0, kind: "key", key: "tab" },
    { t: 1.5, kind: "key", key: "down" },
    { t: 2.0, kind: "marker", label: "Done" },
  ],
  speed: 1,
  title: "My Demo",
});
// result.castPath → /tmp/demo/dashboard.cast
// result.htmlPath → /tmp/demo/index.html
```

### Key handling

The capture script handles these keys out of the box:

| Key | Action |
|-----|--------|
| Tab / Shift+Tab | Cycle panels forward/backward |
| 1–4 | Jump directly to panel |
| Up / Down | Navigate cursor in focused panel |
| `?` | Toggle help overlay |
| Enter (scenarios panel) | Start a simulated run for the selected scenario |

Enter in the scenarios panel uses `getScenariosItemAt()` to resolve the flat
item at the cursor. If it's a scenario (not a category header), the handler
mutates `state.runs.active` and `state.runs.progressByRunId` to simulate a run
starting — no real service calls needed. Extend for other panels by adding
cases to the `onEnter` callback.

### E2E test capture

A dedicated script is available:

```bash
# Capture running the first e2e test (01_account_lifecycle)
deno run -A tui_headless_capture.ts /tmp/capture --e2e --speed=1

# Via deno task (with speed override):
deno task tui:capture -- --e2e --speed=1
```

```typescript
import { e2eTestScript } from "./tui_headless_capture.ts";

const result = await captureHeadlessReplay({
  outputDir: "/tmp/capture",
  steps: e2eTestScript(),
  speed: 1,
});
```

The `e2eTestScript()` sequence: show dashboard → Tab to Scenarios → Down to
first scenario → Enter to start run → Tab through Active Run / History panels
→ back to Network.

### Seed state

`seedDefaultState()` in `tui_headless_capture.ts` pre-populates 4 services, 4
scenarios, and 3 runs. Override by passing `state` to `captureHeadlessReplay`:

```typescript
import { createInitialState } from "./dashboard_state.ts";

const state = createInitialState();
state.network.services = [ /* custom services */ ];
state.scenarios.all = [ /* custom scenarios */ ];

const result = await captureHeadlessReplay({
  outputDir: "/tmp/custom",
  state,
  steps: myScript(),
});
```

## Output

| Path | Format | Use |
|------|--------|-----|
| `{outputDir}/dashboard.cast` | asciicast v2 | Raw recording |
| `{outputDir}/index.html` | Standalone HTML | Open in browser |

The HTML embeds Asciinema Player v3.8 loaded from CDN. Markers render as
clickable timeline buttons.

## Related

- `@garazyk/tui/testing` — VirtualTuiHarness, CastRecorder, replayScript,
  replay_types (the core primitives)
- `scripts/scenario-dashboard/tui_headless_capture.ts` — project-specific
  capture script
- `scripts/scenario-dashboard/tui.ts` — live interactive TUI with recording
  support
- `scripts/scenario-dashboard/lib/export_html.ts` — `buildExportHtml()`
