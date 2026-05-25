# TUI Agent Protocol

A "Playwright for TUIs" — interactive, semantic, recordable.

## Problem

The original TUI capture approach used **blind replay scripts**: generate a
`ReplayStep[]` array upfront, play it back, export the result. This had
fundamental limitations:

- **No feedback loop**: the agent couldn't see the state after each action.
- **Fragile timing**: step timestamps were guesses that could drift.
- **No semantic understanding**: the agent worked with pixel positions and key
  names, not with structured concepts like "scenario 02" or "cursor on service
  PDS".
- **One-shot**: if the script diverged from reality, there was no recovery.

The TUI Agent Protocol replaces blind replay with an **interactive loop**: the
agent inspects structured state, decides what action to take, sends a keystroke,
sees the result, and records everything transparently.

## Theory: Three Layers of Semantic Extraction

A TUI has three levels of structure that an agent can observe:

### Layer 1: Layout (TDOM)

The `@garazyk/tui` framework produces a `ResolvedNode` tree from the layout
solver — each panel has an id, bounding box, and children. The
`VirtualTuiHarness` holds a `ScreenBuffer` (a cell grid) that captures every
character and its style.

`serializeTdom(buf, layout)` walks the layout tree and reads cell content from
the buffer, producing a `TdomElement` tree:

```ts
{ id: "network", x: 0, y: 1, width: 30, height: 10,
  text: "PDS  ● running  http://...",
  children: [] }
```

**Limitation**: TDOM knows position and text, but not meaning. It sees `●` not
`status=running`. It sees `02_social_graph` but not
`scenario with id=02, status=failed, category=core`.

### Layer 2: Application State (Semantic Model)

The real dashboard maintains a `DashboardState` object that holds every piece of
semantic information:

```ts
interface DashboardState {
  network: { services: ServiceStatus[] };
  scenarios: { all: ScenarioMeta[] };
  runs: { active: Run | null; recentRuns: Run[]; progressByRunId: ... };
  ux: { collapsedCategories: Set<string>; searchTerm: string };
  // ...
}
```

Each panel's render function reads from this model. The cursor position, scroll
offset, and focus are tracked in `PanelStates` and `FocusRing`.

**Key insight**: the semantic state already exists in the application model. The
agent should read it directly — not parse it from the rendered buffer.

### Layer 3: Combined Snapshot (Agent Protocol)

Layout + State = a structured YAML tree that the agent can reason about:

```yaml
- panel "Network" [id=network] [ref=p1] [focused]
  - service "PDS" [status=running] [healthy] [cursor] [ref=e1]
  - service "Relay" [status=starting] [ref=e2]
- panel "Scenarios" [id=scenarios] [ref=p2]
  - heading "Core ATProto" [count=4] [collapsed=false]
  - scenario "01_account_lifecycle" [status=passed] [ref=e3]
  - scenario "02_social_graph" [status=failed] [cursor] [ref=e4]
- panel "Active Run" [id=run] [ref=p3]
  - state "idle"
- panel "Run History" [id=history] [ref=p4]
  - run "run-20260524-001" [status=completed] [passed=11] [failed=1] [ref=e5]
```

The agent sees **semantic roles** (`panel`, `service`, `scenario`, `run`),
**attributes** (`focused`, `cursor`, `status=running`), and **stable refs**
(`ref=e1`) that persist across snapshot updates.

## Architecture

```
┌─────────────────────────────────────┐
│         MCP Client (opencode)       │
│  tui_snapshot  tui_action           │
│  tui_rec_start  tui_rec_stop        │
└──────────┬──────────────────────────┘
           │ JSON-RPC 2.0 (stdin/stdout)
           ▼
┌─────────────────────────────────────┐
│ garazyk-tui-mcp (scripts/mcp-tui)   │
│                                     │
│  ┌──────────┐  ┌──────────────────┐ │
│  │ session  │  │ harness          │ │
│  │ Dashboard│  │ VirtualTuiHarness│ │
│  │ State    │  │ + ScreenBuffer   │ │
│  │ PanelSt. │  │ + CastRecorder   │ │
│  │ FocusRing│  └──────────────────┘ │
│  └──────────┘                       │
│  ┌──────────┐  ┌──────────────────┐ │
│  │ snapshot │  │ recording        │ │
│  │ state →  │  │ start/stop/export│ │
│  │ YAML     │  │ asciicast+HTML   │ │
│  └──────────┘  └──────────────────┘ │
└─────────────────────────────────────┘
```

The server is a **Deno process** that communicates via **stdin/stdout JSON-RPC
2.0**. It:

1. Creates a `VirtualTuiHarness` with the real dashboard render function.
2. Wires the same `handleHeadlessKey` state machine from the dashboard.
3. Provides a `CastRecorder` that captures every frame as asciicast v2.
4. Exports recordings as standalone HTML pages with Asciinema Player.

### Server Files

| File                           | Purpose                                             |
| ------------------------------ | --------------------------------------------------- |
| `scripts/mcp-tui/server.ts`    | JSON-RPC stdin/stdout loop, tool dispatch           |
| `scripts/mcp-tui/session.ts`   | Session lifecycle: harness creation, key dispatch   |
| `scripts/mcp-tui/snapshot.ts`  | `buildSnapshot()` reads state → YAML string         |
| `scripts/mcp-tui/refs.ts`      | Stable `ref=eN` assignment per semantic key         |
| `scripts/mcp-tui/recording.ts` | `startRecording()`, `stopRecording()` → cast + HTML |

## YAML Snapshot Format

Follows Playwright's `ariaSnapshot()` conventions:

### Rules

| Rule                        | Example                                                       |
| --------------------------- | ------------------------------------------------------------- |
| Semantic tag as first token | `- panel "Network"`, `- scenario "..."`                       |
| Label in quotes             | Human-readable display text                                   |
| `[key=val]` attributes      | Structured properties: `status=running`, `count=4`            |
| `[flag]` boolean attributes | `[focused]`, `[cursor]`, `[healthy]`, `[collapsed]`           |
| `[ref=eN]`                  | Stable handle for interaction (like Playwright's `[ref=...]`) |
| `[box=x,y,w,h]`             | Optional positional grounding                                 |
| Indentation for hierarchy   | Children indented under parents                               |

### Tags

| Tag        | Represents                       | Attributes                                             |
| ---------- | -------------------------------- | ------------------------------------------------------ |
| `panel`    | A dashboard panel                | `id`, `ref`, `focused`, `box`                          |
| `service`  | A network service                | `status`, `healthy`, `cursor`, `ref`                   |
| `heading`  | A category header in scenarios   | `count`, `collapsed`, `cursor`                         |
| `scenario` | A runnable scenario              | `status`, `cursor`, `ref`                              |
| `run`      | A past or current run            | `status`, `passed`, `failed`, `total`, `cursor`, `ref` |
| `state`    | A status indicator (e.g. `idle`) | none                                                   |
| `search`   | Current search filter            | none                                                   |

### Example

```yaml
- panel "Network" [id=network] [ref=p1] [focused] [box=0,1,40,10]
  - service "PDS" [status=running] [healthy] [cursor] [ref=e1]
  - service "Relay" [status=starting] [ref=e2]
  - service "PLC" [status=stopped] [ref=e3]
- panel "Scenarios" [id=scenarios] [ref=p2] [box=40,1,80,10]
  - search "02"
  - heading "Core ATProto" [count=2] [collapsed=false]
  - scenario "02_social_graph 02_social_graph" [status=failed] [cursor] [ref=e5]
- panel "Active Run" [id=run] [ref=p3] [box=0,11,120,6]
  - run "run-1740000000" [status=running] [passed=0] [failed=0] [total=1] [completed=0/1] [running=true]
- panel "Run History" [id=history] [ref=p4] [box=0,17,120,8]
  - run "run-20260524-001" [status=completed] [passed=11] [failed=1] [total=12] [ref=e6]
```

## MCP Tools

### `tui_snapshot`

Returns the current TUI state as structured YAML.

**Parameters:**

| Name    | Type                                     | Description                                       |
| ------- | ---------------------------------------- | ------------------------------------------------- |
| `boxes` | boolean                                  | Include `[box=x,y,w,h]` bounding boxes (optional) |
| `panel` | "network"\|"scenarios"\|"run"\|"history" | Scope to a single panel (optional)                |

**Returns:** `content[].text` containing YAML string.

### `tui_action`

Send a keystroke or type text. Returns updated YAML snapshot.

**Parameters:**

| Name     | Type                  | Description                                                                |
| -------- | --------------------- | -------------------------------------------------------------------------- |
| `action` | "press_key" \| "type" | `press_key` for control keys, `type` for characters                        |
| `value`  | string                | Key name (e.g. `"down"`, `"tab"`, `"enter"`, `"?"`, `"c"`) or text to type |

**Available keys:** `down`, `up`, `tab`, `shift+tab`, `enter`, `escape`,
`backspace`, `?`, `1`-`4` (panel jump), `c` (complete active run), arrow keys
for cursor navigation.

**Returns:** Updated YAML snapshot.

### `tui_world_snapshot`

Returns the current dashboard state as a normalized `TuiWorld` graph. This is
the preferred reasoning surface for agents that need strict role/name lookup,
relations, actions, evidence, and diagnostics. The YAML snapshot remains
available for human-readable compatibility.

**Returns:** `content[].text` containing JSON and `_meta.structuredContent`
containing the same `TuiWorld` object.

### `tui_world_query`

Runs one deterministic query against the current dashboard `TuiWorld`.

**Parameters:**

| Name        | Type   | Description                                      |
| ----------- | ------ | ------------------------------------------------ |
| `op`        | string | `getByRole`, `find`, `related`, `nearest`, etc. |
| `role`      | string | Role filter for lookup operations                |
| `name`      | string | Case-insensitive label filter                    |
| `ref`       | string | Stable node reference for ref-based operations   |
| `kind`      | string | Relation or action kind filter                   |
| `direction` | string | Relation or spatial direction                    |
| `strict`    | bool   | Defaults to strict lookup                        |

**Returns:** JSON query result in `content[].text` and
`_meta.structuredContent`.

### `tui_rec_start`

Start recording the session as an asciicast.

**Parameters:**

| Name        | Type   | Description                              |
| ----------- | ------ | ---------------------------------------- |
| `title`     | string | Recording title for HTML page (optional) |
| `outputDir` | string | Output directory (optional)              |

### `tui_rec_stop`

Stop recording and export as HTML.

**Returns:** `{ castPath: "...", htmlPath: "..." }`

## Agent Workflow

### Interactive Capture

```
1. tui_rec_start(title: "Scenario 02 demo")
   → "Recording started."

2. tui_snapshot()
   → Agent sees: Network focused, cursor on PDS

3. tui_action(press_key, "tab")
   → Agent sees: Scenarios focused, cursor on "Core ATProto" heading

4. tui_action(press_key, "down")
   → Agent sees: cursor on "01_account_lifecycle" [ref=e5]

5. tui_action(press_key, "down")
   → Agent sees: cursor on "02_social_graph" [ref=e6]

6. tui_action(press_key, "enter")
   → Agent sees: Active Run panel shows [status=running]

7. tui_action(press_key, "c")
   → Agent sees: Active Run shows [status=completed] [passed=1]

8. tui_rec_stop()
   → "Cast: .../dashboard.cast\nHTML: .../index.html"
```

### Verification

```
1. tui_snapshot()
2. Assert [cursor] is on expected element
3. tui_action(press_key, "enter")
4. tui_snapshot() → verify result
```

## Design Decisions

### Why MCP, not a Custom Tool or Plugin

| Approach                         | Scope          | Reusability                                   | State Model          |
| -------------------------------- | -------------- | --------------------------------------------- | -------------------- |
| Custom tool (.opencode/tools/)   | opencode only  | Low                                           | Stateless (one-shot) |
| Full plugin (.opencode/plugins/) | opencode only  | Low                                           | Stateful             |
| MCP server                       | Any MCP client | High — works with Claude Code, opencode, etc. | Stateful process     |

MCP servers are spawned as subprocesses, communicate via stdin/stdout JSON-RPC,
and can maintain long-lived state. This is the natural fit for the interactive
loop pattern.

### Why State Model, not Screen-Scraping

Reading `DashboardState` directly gives us:

- **Perfect accuracy**: no text-parsing bugs or truncation issues.
- **Rich semantics**: `status=running`, `passed=11`, `collapsed=true` — not just
  `●` or `▶` characters.
- **Cursor mapping**: we know the cursor is on `02_social_graph` because we
  track the cursor index against the flat item list — not because we parse
  `> 02_social_graph` from the buffer.
- **Decoupled from rendering**: the snapshot works even if the render layout
  changes.

### Why YAML, not JSON

Following Playwright's `ariaSnapshot()` format:

- **Token-efficient**: YAML uses 30-50% fewer tokens than equivalent JSON.
- **Hierarchy via indentation**: tree structure is implicit, no closing brackets
  or braces.
- **Reader-friendly**: a human can scan YAML at a glance.

### Why `ref=eN`, not Positional Selectors

`ref=eN` survives list reordering, insertion, and deletion — within a stable
data set, the same semantic element gets the same ref across snapshots. The ref
is derived from the element's semantic key (e.g. `network.pds`,
`scenario.02_social_graph`), not its position.

## opencode Integration

Add to `opencode.json` or `~/.config/opencode/opencode.json`:

```jsonc
{
  "mcp": {
    "garazyk-tui": {
      "type": "local",
      "command": ["deno", "run", "-A", "scripts/mcp-tui/server.ts"],
      "enabled": true
    }
  }
}
```

After restarting opencode, the tools `tui_snapshot`, `tui_action`,
`tui_rec_start`, and `tui_rec_stop` are available to the agent.

## Comparison to Playwright

| Concept         | Playwright (Web)                      | TUI Agent Protocol                      |
| --------------- | ------------------------------------- | --------------------------------------- |
| State source    | Browser accessibility tree            | DashboardState + PanelStates            |
| Snapshot format | YAML `ariaSnapshot()`                 | YAML semantic tree                      |
| Element refs    | `[ref=eN]`                            | `[ref=eN]` (same pattern)               |
| Interaction     | `element.click()`, `keyboard.press()` | `tui_action(press_key, "...")`          |
| Recording       | `page.video.saveAs()`                 | `tui_rec_start/stop` → asciicast + HTML |
| Locator         | `page.locator('aria-ref=e5')`         | `tui_action` on ref (agent decides)     |
| Assertion       | `expect(element).toHaveText()`        | Agent reads snapshot YAML               |

## References

Related documentation in this directory:

- [Semantic Extraction Theory](semantic-extraction.md) — Two-layer TUI vdom
  model, TuiElement interface, framework comparison across 6 libraries
- [Extraction Pipeline](extraction-pipeline.md) — Unicode classification →
  region detection → semantic labeling → interaction detection
- [Unicode UI Element Reference](unicode-ui-elements.md) — Complete catalog of
  Unicode characters used in TUIs with their structural semantics

Deciduous nodes 880-897 track the research, observations, and decisions behind
this model.
