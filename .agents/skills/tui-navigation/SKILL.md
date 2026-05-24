---
name: tui-navigation
description: Guide an agent to navigate a TUI application using semantic snapshots, with error detection and recovery. Use when an agent needs to drive a terminal UI through the MCP-PTY tools, follow a multi-step navigation plan, or recover from unexpected TUI states.
---

# TUI Navigation

Navigate a terminal UI application programmatically using the MCP-PTY tool
suite. This skill provides the **observe-decide-act-verify** loop, error
taxonomy, and recovery strategies that turn semantic snapshots into reliable
agent-driven navigation.

## When to Use

- You need an agent to drive a TUI application (start services, select
  items, trigger runs, dismiss modals).
- You are writing an automation script that interacts with a TUI via
  `pty_action` and `pty_semantic_snapshot`.
- A TUI interaction failed or produced an unexpected state and you need to
  diagnose and recover.

## Prerequisites

- The `garazyk-pty` MCP server must be running and connected.
- Available MCP tools: `pty_start`, `pty_semantic_snapshot`, `pty_action`,
  `pty_resize`, `pty_stop`, `pty_list`.
- The target TUI must be on the allowlist (or `GARAZYK_PTY_MCP_ALLOW` must
  include it).

---

## The Navigation Loop

Every TUI interaction follows this cycle. Never skip a step.

```
  ┌──────────────────────────────────────────────────┐
  │  1. OBSERVE  — pty_semantic_snapshot              │
  │  2. DECIDE   — match state to goal, pick action   │
  │  3. ACT      — pty_action                         │
  │  4. VERIFY   — pty_semantic_snapshot, compare     │
  │  5. CORRECT  — if state ≠ expected, recover       │
  └──────────────────────────────────────────────────┘
```

### 1. Observe

Call `pty_semantic_snapshot` with `detail: "compact"`. The response contains:

| Field | Use |
|-------|-----|
| `snapshot.app` | Which application is running (for app-specific heuristics) |
| `snapshot.confidence` | 0–1 confidence in the app guess |
| `snapshot.framework` | Detected framework: `ratatui`, `textual`, `ncurses`, `unknown` |
| `snapshot.altScreen` | `true` if app is in alternate screen buffer (full-screen TUI) |
| `snapshot.cursor` | `{x, y}` — hardware cursor position, often indicates focus |
| `snapshot.facts` | Mode/status facts (e.g., `Mode: Insert`, `TerminalMode: alt_screen`) |
| `snapshot.tables` | Detected tables with columns and row bounds |
| `snapshot.regions` | Containers, panels, empty-space regions |
| `snapshot.controls` | Checkboxes, buttons, input fields with positions |
| `snapshot.tabs` | Tab bars with tab labels, indices, and active state |
| `snapshot.panes` | Split panes (vertical/horizontal) with titles and bounds |
| `snapshot.lists` | List items with markers (▾, ▸, nerd icons), labels, and selection state |
| `snapshot.statusBars` | Status bars with keybinding hints and background colors |
| `snapshot.popups` | Popup overlays with titles, centered flag, and bounds |
| `snapshot.gameElements` | Game-specific elements: gameBoard, player, gameEntity, cardGame, cardFace |
| `snapshot.charts` | Data visualizations: brailleChart, blockBar, pipeMeter |
| `snapshot.vdomViz` | Tree-formatted element hierarchy for quick scanning |

Use `detail: "full"` only when you need the raw text lines for
content-level assertions (e.g., checking a specific value in a table cell).

#### New Methods

**`waitForStable({ maxMs, stableMs, pollMs })`** — Wait for the screen to
stop changing before observing. Replaces fixed `setTimeout` with adaptive
polling. The screen is considered stable when content hasn't changed for
`stableMs` (default 300ms). Polls every `pollMs` (default 100ms). Gives up
after `maxMs` (default 5000ms).

**`actAndVerify(keyName, { maxWaitMs, stableMs })`** — Combines the
ACT + VERIFY steps into one call. Takes a before snapshot, sends the key,
waits for stable, takes an after snapshot, and returns a diff:

```javascript
const result = await session.actAndVerify("j");
// result.diff.cursorMoved      — did the cursor position change?
// result.diff.changedLineCount — how many lines changed content?
// result.diff.tabsChanged      — did the active tab change?
// result.diff.activeTabAfter   — which tab is now active?
// result.diff.popupsChanged    — did a popup appear/disappear?
// result.diff.selectionChanged — did the selected list item change?
// result.diff.selectedAfter    — which item is now selected?
```

**`diffSnapshots(before, after)`** — Compare two semantic snapshots and
return what changed. Used internally by `actAndVerify` but also available
for manual comparison.

### 2. Decide

Compare the observed state against the **navigation goal**. A goal is a
structured description of the desired state:

```
Goal: { panel: "Scenarios", selectedItem: "01_account_lifecycle" }
```

**Read the capability map first.** `snapshot.capabilities` tells you what
actions are available without needing to know the app:

```javascript
caps = snapshot.capabilities;
// caps.navigate.keys     → ["j", "k"] or ["up", "down"]
// caps.tabs.keys        → ["1", "2", "3", "4", "5"]
// caps.tabs.activeTab   → "Status"
// caps.quit.keys        → ["q"]
// caps.dismiss.keys     → ["escape"]
// caps.help.keys        → ["?", "F1"]
// caps.actions          → [{ key: "s", action: "Save" }, ...]
```

**Decision priority (element-driven, not app-driven):**

1. **Status bar key hints first** — If `caps.actions` has a key→action
   mapping that matches your goal, use it directly. The TUI is telling you
   how to interact with it.
2. **Tab/panel navigation** — If `caps.tabs.available`, use the listed
   keys to switch to the target panel.
3. **List navigation** — Use `caps.navigate.keys` to move within lists.
4. **Dismiss overlays** — If a popup is blocking, use `caps.dismiss.keys`.
5. **Framework defaults** — If no status bar hints are available, fall
   back to framework conventions from the strategy table below.

**Framework strategy table** (from [[reference/tui-navigation/competence.md]]):

| Framework | Navigate | Tabs | Quit | Help | Dismiss |
|-----------|----------|------|------|------|---------|
| ratatui | j/k | number keys | q | ? | escape |
| textual | up/down | Tab key | Ctrl+C | ? | escape |
| ncurses | j/k (never arrows) | number keys | q | ? | escape |
| unknown | j/k first | try numbers then Tab | q then Ctrl+C | ? then F1 | escape |

**Decision rules:**

1. If the goal panel is not focused → navigate to it using `caps.tabs.keys`.
2. If the goal item is not selected → navigate to it using `caps.navigate.keys`.
3. If the goal item is selected → trigger the action (Enter, letter key from `caps.actions`).
4. If a modal or overlay is blocking → dismiss it first using `caps.dismiss.keys`.

**Discovery protocol for unknown TUIs:**

When `caps.actions` is empty and the framework is unknown, use this
systematic approach to discover the TUI's interaction model:

1. **Check status bar** — Read the bottom 1-2 lines for key hints.
2. **Try help** — Press `?` or `F1`. If a help overlay appears, parse it
   with `parseHelpOverlay()` to get the full keybinding table.
3. **Try navigation** — Press `j` then `k`. If `cursorMoved` is true,
   the app supports vim-style navigation. If not, try `down`/`up`.
4. **Try tab switch** — Press `1` or `Tab`. If `tabsChanged` is true,
   the app supports panel switching.
5. **Try quit** — Press `q`. If `processExited` is true, done.
   If not, try `Ctrl+C`.
6. **Record findings** — Update [[reference/tui-navigation/competence.md]]
   with the discovered patterns.

### 3. Act

Call `pty_action` with the chosen key:

```json
{ "sessionId": "s1", "action": "press_key", "value": "tab" }
```

For text input:

```json
{ "sessionId": "s1", "action": "type", "value": "search term" }
```

**Key name reference** (maps to terminal escape sequences):

| Key | Name | Notes |
|-----|------|-------|
| Enter | `enter` | |
| Tab | `tab` | |
| Space | `space` | Select card, start game, confirm |
| Shift+Tab | Use `pty_action` with `write` and `\\x1b[Z` | |
| Escape | `escape` | Universal dismiss |
| Up/Down/Left/Right | `up`, `down`, `left`, `right` | |
| Ctrl+C | `ctrl-c` | Interrupt |
| Ctrl+D | `ctrl-d` | EOF |
| Ctrl+L | `ctrl-l` | Redraw |
| Backspace | `backspace` | |
| Page Up/Down | Use `write` with `\x1b[5~` / `\x1b[6~` | |
| Home/End | Use `write` with `\x1b[H` / `\x1b[F` | |

### 4. Verify

After every action, call `pty_semantic_snapshot` again. Compare the new state
to the pre-action state. **Prefer `actAndVerify()`** which combines ACT + VERIFY
into one call and returns a structured diff.

**What the diff tells you:**

| Diff Field | What It Detects | Example |
|------------|----------------|---------|
| `cursorMoved` | Cursor position changed | Navigation in yazi, ncdu |
| `changedLineCount` | Lines with different content | Scroll, content refresh |
| `tabsChanged` | Active tab changed | Tab switch in gitui |
| `activeTabAfter` | Which tab is now active | "Status" → "Files" |
| `popupsChanged` | Popup appeared or disappeared | Dialog open/close |
| `selectionChanged` | Selected list item changed | Item highlight in ncdu |
| `selectedAfter` | Which item is now selected | "plc" → "scripts" |
| `statusBarChanged` | Status bar content changed | Mode change |

**Manual verification** (if not using `actAndVerify`):

- **Panel focus changed?** — Look at `facts` or cursor position.
- **Selection moved?** — Look at `inverse` styling in controls or cursor `y`.
- **Modal appeared/disappeared?** — New regions or controls that weren't there
  before.
- **Content changed?** — Compare `vdomViz` trees or specific line content.
- **Process still running?** — Check `snapshot.running` (if using
  `pty_snapshot` instead).

**Verification outcomes:**

| Outcome | Meaning | Next step |
|---------|---------|-----------|
| State matches expected | Action succeeded | Continue to next goal |
| State unchanged | No-op (action had no effect) | Diagnose: wrong focus? wrong key? |
| State changed unexpectedly | Side-effect or error | Enter recovery |
| Process exited | Crash or intentional exit | Check exit code, restart if needed |

### 5. Correct

When verification fails, do **not** blindly retry the same action. Diagnose
first, then apply the appropriate recovery strategy (see below).

---

## Error Taxonomy

### E1: No-Op (action had no visible effect)

**Symptoms:** Post-action snapshot is identical to pre-action snapshot.

**Causes:**
- Wrong panel has focus (key was consumed by a different panel).
- Key is not bound in the current mode/context.
- App is in a modal state that swallows the key.

**Recovery:**
1. Check which panel has focus (cursor position, inverse styling).
2. Navigate to the correct panel first (Tab, number key).
3. Check for blocking modals/overlays in `regions` or `controls`.
4. Dismiss any overlay (Escape, `?`, `q`).
5. Retry the action.

### E2: Wrong State (unexpected transition)

**Symptoms:** Post-action snapshot shows a different state than expected (e.g.,
modal appeared, error message visible, wrong panel focused).

**Causes:**
- Key was interpreted differently in the current context.
- App has mode-dependent key bindings.
- Race condition (app was still rendering when action was sent).

**Recovery:**
1. Read the new state carefully — what changed?
2. Look for error messages in the snapshot lines (use `detail: "full"`).
3. If a modal appeared: read its content, then dismiss (Escape, `q`).
4. If the app entered a different mode: check `facts` for mode indicators.
5. Return to the expected state before retrying (Escape, mode-toggle key).
6. If a race condition is suspected: add a longer settle time by waiting
   before the next `pty_semantic_snapshot` call.

### E3: Crash (process exited)

**Symptoms:** `pty_snapshot` shows `running: false` with an exit code.

**Causes:**
- Bug in the TUI application.
- Invalid input caused an assertion failure.
- OOM or signal from outside.

**Recovery:**
1. Record the exit code and any error output in the last snapshot lines.
2. Restart the session with `pty_start` using the same parameters.
3. Replay navigation steps to return to the point before the crash.
4. If the crash is reproducible, avoid the triggering action and find an
   alternative path.

### E4: Stuck (app is unresponsive)

**Symptoms:** Multiple actions produce no change; cursor doesn't move; no
new output.

**Causes:**
- App is waiting for input that wasn't sent.
- App is blocked on I/O (network, file).
- Terminal is in a weird state (alternate screen, raw mode).

**Recovery:**
1. Try Ctrl+L (`ctrl-l`) to force a redraw.
2. Try Escape to break out of any pending input.
3. Try Ctrl+C (`ctrl-c`) to interrupt.
4. If still stuck: stop the session (`pty_stop`) and restart.
5. Consider resizing (`pty_resize`) to force a redraw event.

### E5: Ambiguity (multiple controls match)

**Symptoms:** The semantic snapshot shows multiple controls of the same type
and the agent can't determine which one is the target.

**Causes:**
- Multiple buttons/checkboxes with similar labels.
- List items with identical prefixes.

**Recovery:**
1. Use `detail: "full"` to read the actual text content around each control.
2. Use cursor position (`snapshot.cursor`) to determine which element has
   focus.
3. Navigate step-by-step (Up/Down) and verify after each step rather than
   trying to jump directly.
4. If the TUI supports search/filter, use that to narrow the list.

### E6: Parse Failure (semantic extractor returns empty VDOM)

**Symptoms:** `pty_semantic_snapshot` returns an empty or near-empty VDOM
tree even though the TUI is clearly rendering content.

**Causes:**
- The TUI uses Unicode characters not recognized by the generic detector
  (rounded box-drawing, Braille, custom symbols).
- The TUI uses variable-width columns where fields are separated by only 1
  space, breaking `\s{2,}` regex assumptions.
- The TUI renders content in a way the heuristic detectors don't cover.

**Recovery:**
1. Fall back to parsing raw lines (`pty_snapshot` or `detail: "full"`)
   with app-specific regex patterns.
2. Use the header line to determine column positions, then extract fields
   by position rather than by regex.
3. For variable-width columns, parse from the end of the line backwards
   (the trailing fields like memory, CPU% are usually fixed-width).
4. Consider extending `semantic.mjs` with app-specific detectors for
   commonly used TUIs.

---

## Navigation Patterns

### Panel Navigation

Most multi-panel TUIs use one of these patterns:

| Pattern | Keys | Example |
|---------|------|---------|
| Tab ring | `tab` / `shift+tab` | Garazyk Dashboard, htop |
| Number jump | `1`–`9` | Garazyk Dashboard (panels 1–4) |
| Arrow between panes | `left`/`right` | tmux-like layouts |
| Prefix + target | `g` then panel id | vim-style |

**Strategy:** Prefer number-key jumps (deterministic, one step) over Tab
cycles (may require multiple presses and counting).

### List Navigation

| Pattern | Keys | Notes |
|---------|------|-------|
| Arrow keys | `up`, `down` | One item at a time |
| Page keys | Page Up/Down | Jump by page |
| Home/End | Home, End | Jump to first/last |
| Search/filter | `/`, then type | If supported |
| Prefix type | Type first chars | Some TUIs jump to matching item |

**Strategy:** For short lists (< 10 items), arrow keys are fine. For long
lists, use search or page jumps. Always verify position after each navigation
step.

### Modal and Overlay Handling

| Situation | Dismiss key | Verify |
|-----------|-------------|--------|
| Help overlay | `?`, `escape` | Overlay region disappears from snapshot |
| Confirmation dialog | `y`/`n`, `enter` | Dialog region disappears |
| Error popup | `enter`, `escape` | Error message gone |
| Input prompt | Type value + `enter` | Prompt replaced by result |

**Strategy:** Always check for blocking overlays before attempting
goal-directed navigation. An overlay will swallow keys meant for the main
interface.

### Scrolling

| Pattern | Keys |
|---------|------|
| Line scroll | `up`, `down` |
| Page scroll | Page Up/Down, or `space`/`b` in viewers |
| Jump to top/bottom | `g`/`G`, Home/End |
| Follow mode | `F` (in tail/less-like viewers) |

---

## Navigation Plans

A navigation plan is a sequence of steps that achieves a goal. Write the plan
**before** executing it, so you can detect deviations.

### Plan Format

```yaml
goal: "Run the account_lifecycle scenario"
steps:
  - id: focus-scenarios
    action: press_key "1"
    expect: panel "Scenarios" focused
  - id: select-scenario
    action: press_key "down" (repeat until target highlighted)
    expect: "01_account_lifecycle" selected (inverse styling)
  - id: trigger-run
    action: press_key "enter"
    expect: "Active Run" panel shows running state
  - id: verify-complete
    action: wait + pty_semantic_snapshot
    expect: run status = "passed" or "failed"
```

### Execution Rules

1. **Execute steps in order.** Do not skip ahead.
2. **Verify after every step.** If verification fails, enter recovery.
3. **Track position.** After each step, record the current state (panel,
   selected item, mode) so you can backtrack.
4. **Timeout each step.** If a step doesn't produce the expected state within
   3 verification attempts, enter recovery.
5. **Never assume state.** Always observe; never act based on a stale
   snapshot.

### Backtracking

If a step fails and recovery puts you in a different state than the plan
expects:

1. Re-observe from the current state.
2. Determine the nearest plan step that matches the current state.
3. Resume from that step.
4. If no plan step matches, create an ad-hoc recovery plan to return to a
   known state.

---

## Garazyk Dashboard — Concrete Reference

The Garazyk Scenario Dashboard is the primary TUI target. Here is its
semantic model and navigation map.

### Semantic Layout

```
Container "screen" [0..23]
├── Region "header" [0..0]        — Title + service count
├── Region "panel-network" [1..11] — Service list + controls
├── Region "panel-scenarios" [1..11] — Scenario tree + metrics
├── Region "panel-active-run" [12..17] — Running scenario details
├── Region "panel-history" [18..22] — Past run results
└── Region "footer" [23..23]       — Key legend
```

### Key Map

| Key | Context | Effect |
|-----|---------|--------|
| `tab` | Any | Cycle focus to next panel |
| `shift+tab` | Any | Cycle focus to previous panel |
| `1` | Any | Jump to Network panel |
| `2` | Any | Jump to Scenarios panel |
| `3` | Any | Jump to Active Run panel |
| `4` | Any | Jump to Run History panel |
| `up`/`down` | Panel with list | Move selection cursor |
| `s` | Network panel | Start selected service |
| `p` | Network panel | Start PDS2 |
| `x` | Network panel | Stop selected service |
| `enter` | Scenarios panel | Start run for selected scenario |
| `?` | Any | Toggle help overlay |
| `q` | Any | Quit dashboard |

### Common Navigation Sequences

**Start a service and run a scenario:**

```
1. press_key "1"          → focus Network panel
2. press_key "down"        → select target service
3. press_key "s"           → start service
4. verify: service status changes from ○ to ●
5. press_key "2"           → jump to Scenarios panel
6. press_key "down" (×N)   → navigate to target scenario
7. press_key "enter"       → start the run
8. verify: Active Run panel shows progress
```

**Check run results:**

```
1. press_key "4"           → jump to Run History panel
2. pty_semantic_snapshot detail=full → read pass/fail counts
```

**Dismiss help overlay:**

```
1. press_key "?"           → toggle help on
2. press_key "?"           → toggle help off
   OR press_key "escape"   → dismiss
```

### Error Scenarios Specific to Dashboard

| Error | Detection | Recovery |
|-------|-----------|----------|
| Service won't start | Network panel still shows `○` after `s` | Check service logs; try `x` then `s` again |
| Scenario run stuck at 0% | Active Run panel progress unchanged across 3 snapshots | Press `escape` to cancel; retry |
| Help overlay blocking | `regions` contains overlay; footer keys not responding | Press `?` or `escape` to dismiss |
| Dashboard crashed | `pty_snapshot` shows `running: false` | Restart with `pty_start` |

---

## btop — Concrete Reference

btop is a system monitor TUI that shows CPU, memory, network, disks, and
processes simultaneously. It is a valuable test case because it uses rich
Unicode (rounded box-drawing, Braille bar graphs) that the generic semantic
extractor cannot handle.

### Key Map

| Key | Context | Effect |
|-----|---------|--------|
| `1` | Any | Toggle CPU full-screen view |
| `2` | Any | Toggle MEM full-screen view |
| `3` | Any | Toggle NET full-screen view |
| `4` | Any | Toggle PROC full-screen view |
| `q` | Any | Quit btop |
| `up`/`down` | Process list | Scroll process list |
| `left`/`right` | Process list | Sort by different column |
| `f` | Process list | Filter processes |
| `F` | Any | Toggle freeze |

### Navigation Notes

- **Default view shows all panels simultaneously.** No panel switching is
  needed for overview extraction — just parse the raw lines.
- **Number keys toggle full-screen.** Pressing `1` expands CPU to full screen;
  pressing `1` again returns to the default multi-panel view.
- **Settle time:** btop needs 1500–2000ms for initial render; 300ms is
  sufficient for subsequent key responses.
- **Quit key (`q`) works reliably.** Always verify `running: false` after
  sending `q`.

### Semantic Extraction Limitations

The generic `pty_semantic_snapshot` (Layer 2) returns empty VDOM for btop
because:

1. **Rounded box-drawing characters** (`╭`, `╰`, `├`, `─`, `│`) are not
   recognized by `detectContainers`, which only looks for `~` lines (vim).
2. **Braille bar graphs** (`⣀`, `⣿`, `⠈`, `⣠`, `⣤`) are not recognized as
   progress indicators or data visualizations.
3. **Variable-width columns** in the process list mean field boundaries
   cannot be determined by simple `\s{2,}` regex — some fields are separated
   by only 1 space.

**Workaround:** Parse raw lines directly with btop-specific regex patterns.
See `scripts/mcp-pty/navigate_btop.mjs` for a working implementation that
extracts CPU cores, memory, network, and processes from the raw snapshot.

**Long-term fix:** Extend `semantic.mjs` with:
- Rounded box-drawing character recognition in `detectContainers`
- Braille pattern recognition for bar graphs
- Column-position-based field extraction (using header line as template)

### Error Scenarios Specific to btop

| Error | Detection | Recovery |
|-------|-----------|----------|
| btop not rendering | Snapshot lines are empty after 2s | Increase settle time; check TERM env |
| Wrong panel in full-screen | Expected data not in snapshot | Press same number key to toggle back |
| Process list scrolled | PID numbers don't start from top | Press `Home` or `g` to jump to top |
| btop not quitting | `running: true` after `q` | Force stop with `pty_stop` |

---

## vim — Concrete Reference

vim is the canonical **modal** TUI. The same key produces different effects
depending on the current mode (NORMAL, INSERT, VISUAL, COMMAND, REPLACE).
This makes it the primary test case for E2 (Wrong State) error recovery.

### Mode Detection

The semantic extractor's `detectStatusLines` correctly identifies INSERT
and VISUAL modes via the `-- INSERT --` and `-- VISUAL --` strings on the
last line. However, NORMAL mode has no explicit indicator — it is the
**absence** of a mode string.

**Mode detection rules:**

| Status line content | Mode | Confidence |
|---------------------|------|------------|
| `-- INSERT --` | INSERT | 0.95 |
| `-- VISUAL --` | VISUAL | 0.95 |
| `-- REPLACE --` | REPLACE | 0.95 |
| Starts with `:` | COMMAND | 0.85 |
| Starts with `/` | COMMAND (search) | 0.80 |
| Empty or filename + line count | NORMAL | 0.70 |
| Contains `E\d\d\d:` | ERROR (in NORMAL) | 0.90 |

**Critical rule:** ALWAYS verify mode before acting. A key that deletes a
line in NORMAL mode (`dd`) types literal text in INSERT mode.

### Mode Transition Map

```
                    ┌──────────┐
              i,I,a,A,o,O ──▶│  INSERT  │
         ┌─────────────────── │         │ ◀── Escape
         │                    └──────────┘
         │
    ┌────┴───┐     v,V,Ctrl+V    ┌──────────┐
    │ NORMAL │───────────────────▶│  VISUAL  │
    │        │◀────────────────── │         │
    └────┬───┘     Escape         └──────────┘
         │
         │ :     ┌──────────┐
         └──────▶│ COMMAND  │
       ◀─────────│         │
         Enter    └──────────┘
```

**Universal recovery:** Escape always returns to NORMAL mode from any
other mode. When in doubt, press Escape first.

### Key Map (NORMAL mode only)

| Key | Effect |
|-----|--------|
| `h`/`j`/`k`/`l` | Move left/down/up/right |
| `i` | Enter INSERT mode (before cursor) |
| `a` | Enter INSERT mode (after cursor) |
| `o` | Open new line below, enter INSERT |
| `v` | Enter VISUAL mode (character) |
| `V` | Enter VISUAL mode (line) |
| `:` | Enter COMMAND mode |
| `dd` | Delete current line |
| `yy` | Yank (copy) current line |
| `p` | Paste after cursor |
| `u` | Undo last change |
| `Ctrl+r` | Redo |
| `gg` | Go to first line |
| `G` | Go to last line |
| `/pattern` | Search forward |
| `n` | Next search match |

### Navigation Plan Template

```yaml
goal: "Open file, add text, save, quit"
steps:
  - id: verify-normal
    action: press_key "escape"
    expect: status line shows filename (no mode indicator)
  - id: enter-insert
    action: press_key "i"
    expect: status line shows "-- INSERT --"
  - id: type-text
    action: type "new content"
    expect: text appears at cursor position
  - id: exit-insert
    action: press_key "escape"
    expect: status line no longer shows "-- INSERT --"
  - id: save
    action: type ":w" then press_key "enter"
    expect: status line shows "written"
  - id: quit
    action: type ":q" then press_key "enter"
    expect: running = false
```

### Error Scenarios Specific to vim

| Error | Detection | Recovery |
|-------|-----------|----------|
| Modal confusion | Key produces unexpected result (e.g., `dd` typed as text) | Press Escape → verify NORMAL → `u` to undo |
| Stuck in INSERT | Agent thinks it's in NORMAL but is in INSERT | Press Escape, re-observe |
| Invalid command | Status line shows `E492: Not an editor command` | Press Enter to dismiss, back to NORMAL |
| File modified, can't quit | Status line shows `E37: No write since last change` | Use `:q!` to force quit, or `:w` to save first |
| Search not found | Status line shows `E486: Pattern not found` | Press Enter to dismiss |
| Mode transition lag | Status line still shows old mode after keypress | Increase settle time to 300ms; re-observe |

### Semantic Extraction Notes

The generic `pty_semantic_snapshot` works well for vim:

- **App detection:** `guessApplication` correctly identifies vim (0.9
  confidence) from the command name.
- **Container detection:** `detectContainers` finds the `filler` region
  (vim `~` lines) correctly.
- **Status line detection:** `detectStatusLines` correctly identifies
  `-- INSERT --` and `-- VISUAL --` modes.
- **Missing:** NORMAL mode detection (no indicator), COMMAND mode prompt
  detection, and error message detection (`E492`, `E37`, etc.).

**Recommendation:** Extend `detectStatusLines` to also detect:
- NORMAL mode (absence of mode indicator + filename in status line)
- COMMAND mode (status line starts with `:`)
- Error messages (status line matches `E\d\d\d:`)

---

## Anti-Patterns

### Blind Retry
**Bad:** Send the same key 5 times hoping it works.
**Good:** Observe after each keypress. If no change, diagnose before retrying.

### Assumed State
**Bad:** "I pressed Tab twice so I must be on the Scenarios panel."
**Good:** Take a snapshot and verify which panel has focus.

### Ignoring Modals
**Bad:** Keep pressing arrow keys when a dialog is showing.
**Good:** Check for overlay regions in every snapshot. Dismiss before
navigating.

### Skipping Verify
**Bad:** Send a sequence of keys without checking intermediate states.
**Good:** Verify after every action, or at minimum after every logically
grouped action sequence.

### Over-Reliance on Timing
**Bad:** `setTimeout(1000)` then assume the app has finished rendering.
**Good:** Use `pty_semantic_snapshot` as the synchronization primitive. It
calls `settle()` internally, which drains the PTY output queue.

### Assuming Mode (for modal TUIs like vim)
**Bad:** "I pressed `i` so I must be in INSERT mode now — let me type text."
**Good:** After every mode-changing keypress, take a snapshot and verify the
mode indicator on the status line. Mode transitions can fail or lag.

### Acting Without Mode Verification
**Bad:** Send `dd` to delete a line without checking if you're in NORMAL mode.
**Good:** Check the status line first. If in INSERT mode, `dd` types literal
text. Press Escape to return to NORMAL, then act.

### Using Arrow Keys with ncurses Apps
**Bad:** Press `pressKey("down")` to navigate in an ncurses app and watch
it crash or exit.
**Good:** Many ncurses apps (nudoku, nethack) interpret arrow key escape
sequences (`\x1b[A`) incorrectly when sent via PTY — the `\x1b` (ESC) may
be processed as a standalone Escape before the `[A` arrives. Use the app's
native movement keys instead (hjkl for vim-style, or WASD). If arrow keys
are required, try sending the full sequence atomically or increasing the
inter-key delay.

### Assuming Tab Key Switches Tabs
**Bad:** Press Tab to switch between tabs in a TUI app.
**Good:** Many apps (gitui, yazi) use number keys for tab switching, not
the Tab key. Tab is often reserved for field-level focus cycling within a
panel. Always check the app's keybinding help first.

### Insufficient Settle Time for Textual Apps
**Bad:** `await settle(300)` then observe a Textual (Python) app and see
an empty screen.
**Good:** Textual apps need 5+ seconds to fully render. If the first
snapshot shows empty lines but `running: true`, wait longer and re-observe.
Use 5000ms minimum settle time for Textual apps.

### Ignoring Terminal Size Requirements
**Bad:** Launch tty-solitaire in an 80×24 terminal and wonder why it
shows an error message.
**Good:** Check minimum terminal size requirements before launching. Some
apps (tty-solitaire: 57×28, btop: 80×24) have hard minimums. Set `cols`
and `rows` appropriately when creating the PTY session.

---

## TUI Games — Concrete References

TUI games exercise navigation patterns not found in productivity apps:
real-time input, multi-step character creation, score tracking, and varied
quit sequences.

### Common Patterns Across Games

| Pattern | Games | Key Insight |
|---------|-------|-------------|
| Menu → Game → Play → Quit | nsnake, nethack | Each transition needs verification |
| Real-time input | nsnake | Direction changes, not position changes |
| Multi-step creation | nethack | Role → Race → Gender → Alignment → Confirm |
| Score/status line | nsnake, greed, nethack | Most parseable part of any game TUI |
| Quit confirmation | greed, nethack | `q` may show "Really quit? [y/n]" |
| hjkl movement | nethack, nudoku | Arrow keys may crash ncurses apps via PTY |

### Quit Sequence Reference

| Game | Quit Sequence | Notes |
|------|--------------|-------|
| nsnake | `q` | Clean, immediate |
| greed | `q` → `y` | Two-step: quit + confirm |
| nethack | `#quit` → Enter → `y` → `y` | Multi-step; may need Escape first |
| nudoku | `Q` | Uppercase Q; `q` does nothing; arrow keys crash via PTY |
| btop | `q` | Clean, immediate |
| vim | `:q!` → Enter | From NORMAL mode only |
| gitui | `q` | Clean, immediate |
| yazi | `q` | Clean; may need multiple `q` for multiple tabs |
| csvlens | `q` | Clean, immediate |
| ncdu | `q` | May need multiple presses; ncdu 2.x exits on error |
| trippy | `q` | Clean, immediate |
| posting | `Ctrl+C` | Textual standard quit |
| tty-solitaire | `q` | Clean, immediate; must `space` past welcome first |

### Arrow Key Escape Sequence Issue

When sending arrow keys via PTY (`\x1b[A` for Up, `\x1b[B` for Down, etc.),
ncurses-based applications may interpret the `\x1b` (ESC) as a standalone
Escape keypress before the `[A` part arrives. This causes:

- **nudoku**: Exits immediately (treats ESC as quit signal)
- **Other ncurses apps**: May show unexpected behavior

**Workaround:** Use the app's native movement keys (hjkl, WASD) instead of
arrow keys. If arrow keys are required, consider:
1. Setting `TERM=xterm-256color` (more compatible escape sequences)
2. Sending the full escape sequence atomically
3. Adding a small delay between `\x1b` and `[A`

### Error Scenarios Specific to Games

| Error | Detection | Recovery |
|-------|-----------|----------|
| Game exited unexpectedly | `running: false` with exitCode=0 | Check if arrow key caused it; restart with hjkl |
| Character creation loop | Same prompt repeated | Read prompt carefully; respond with specific key, not Enter |
| Stuck in multi-step quit | `running: true` after quit sequence | Continue confirming; check for "Really" prompts |
| Real-time game too fast | Snake dies immediately | Use shorter settle times; send direction before observing |
| Score not changing | Same score across snapshots | Check if moves are valid (greed: can't move to eaten squares) |

---

## Productivity/Utility TUIs — Concrete References

These apps exercise navigation patterns not found in games: split panes,
tabbed interfaces, popup overlays, form input, tabular data, and tree
navigation.

### Framework-Specific Behaviors

| Framework | Apps Tested | PTY Compatibility | Key Findings |
|-----------|-------------|-------------------|--------------|
| Bubbletea (Go) | lazygit, posting | ⚠️ lazygit fails (`/dev/tty` error) | Bubbletea apps may need real TTY; posting works fine |
| Ratatui (Rust) | gitui, yazi, csvlens, trippy | ✓ All work | Excellent PTY compatibility; crossterm backend handles PTY well |
| Textual (Python) | harlequin, posting | ✓ Works but slow render | Need 5+ second settle time; Ctrl+C to quit |
| ncurses (C) | ncdu, tty-solitaire | ✓ Works | Arrow keys may crash; use hjkl; ncdu 2.x exits on error |

### Navigation Patterns by App

#### gitui (Ratatui) — Split-pane + Popup Overlays
- **Tab switching**: Number keys (1-4), not Tab key
- **Panels**: Left (files/staging) + Right (diff view)
- **Commit popup**: `c` key opens commit dialog (only when files are staged)
- **Quit**: `q` — clean, immediate
- **Key insight**: Tab key is NOT for tab switching; apps use number keys

#### yazi (Ratatui) — Dual-pane File Manager
- **Navigation**: hjkl (vim-style), not arrow keys
- **Enter directory**: `l` or Enter
- **Parent directory**: `h`
- **New tab**: `t` (creates new tab at current path)
- **Tab switching**: Number keys (1-9)
- **Warning**: Shows "Terminal response timeout" on first start in PTY
- **Quit**: `q` — may need multiple presses for multiple tabs
- **Key insight**: Terminal timeout warning is benign; app still works

#### csvlens (Ratatui) — Tabular Data Viewer
- **Vertical scroll**: j/k (line by line)
- **Horizontal scroll**: h/l (column by column)
- **Search**: `/` followed by search term, then Enter
- **Go to bottom**: `G` (capital G)
- **Go to top**: `g`
- **Sort**: `s` cycles through sort columns
- **Filter**: `&` followed by column=value
- **Quit**: `q`
- **Key insight**: Horizontal scrolling is unique to tabular data viewers

#### ncdu (ncurses) — Disk Usage Tree Navigator
- **Navigation**: j/k or hjkl (both work)
- **Enter directory**: Enter or `l`
- **Parent directory**: `h`
- **Delete prompt**: `d` shows confirmation; Escape to cancel
- **Sort**: `s` cycles sort mode
- **Quit**: `q` (may need multiple presses)
- **Key insight**: ncdu 2.x exits immediately on error (e.g., missing dir)
  instead of showing a prompt. Always validate the path before launching.

#### posting (Textual) — HTTP API Client
- **Layout**: Method selector + URL input + Collection panel + Request tabs
- **Tabs**: Headers/Body/Path/Query/Auth/Info (within request panel)
- **Method switching**: Ctrl+T
- **Send request**: Ctrl+J
- **Quit**: Ctrl+C (Textual standard)
- **Key insight**: Textual apps need 5+ second settle time for full render.
  The footer shows available keybindings (^c, ^j, ^t, ^o, ^s, ^n, ^P).

#### trippy (Ratatui) — Network Traceroute
- **Tab switching**: Tab key cycles through views (hops, charts, details)
- **Scroll hops**: j/k
- **Start/stop**: `s` toggles tracing
- **Retrace**: `r`
- **Quit**: `q`
- **Requires**: `-u` flag for unprivileged mode (no root needed)
- **Key insight**: Real-time data updates continuously; snapshots may
  show different data each time. Use `s` to pause before observing.

#### tty-solitaire (ncurses) — Card Game
- **Minimum size**: 57×28 terminal (exits with error if too small)
- **Welcome screen**: Shows instructions; press `space` to start
- **Navigation**: hjkl (vim-style) to move cursor between cards
- **Select card**: Space (first press selects, second press places)
- **Select more/fewer**: `m`/`n` after selecting; `M` selects all
- **New game**: `N` (Shift+N)
- **Quit**: `q`
- **Card rendering**: Face-up cards show rank+suit (K♥, 5♦) or suit+rank (♥K, ♦5)
  in cascade; face-down cards show as green-bordered boxes (┌─────┐)
- **Semantic detection**: detectGameElements() identifies cardGame (card count,
  face-down count, tableau columns), individual cardFace elements (rank, suit,
  suitColor), and card backs
- **Framework**: ncurses (correctly detected via frameworkByApp mapping)
- **Key insight**: The welcome screen must be dismissed with `space` before
  the game renders. Card faces use two formats: rank+suit for top of cascade,
  suit+rank for cards below.

### /dev/tty Limitation (Bubbletea Apps)

Some Bubbletea (Go) apps like lazygit directly open `/dev/tty` instead
of using the PTY's stdin/stdout. This causes an immediate crash:

```
*fs.PathError open /dev/tty: device not configured
```

**Affected apps**: lazygit (confirmed), potentially other Go TUI apps
that use `tcell` or direct TTY access.

**Workaround**: This is a fundamental limitation — these apps cannot be
driven via PTY. Use alternative apps built with the same framework that
don't have this issue (e.g., posting works fine with Bubbletea/Textual).

### Textual App Rendering Delay

Textual (Python) apps like harlequin and posting use a different rendering
pipeline that takes significantly longer to produce visible output:

- **posting**: ~3-5 seconds to full render
- **harlequin**: ~5+ seconds (may show empty screen initially)
- **Settle time**: Use 5000ms minimum for Textual apps

**Detection**: If the first snapshot shows all empty lines but
`running: true`, the app is still rendering. Wait longer and re-observe.

### Terminal Size Requirements

Some TUI apps have minimum terminal size requirements:

| App | Minimum Size | Behavior If Too Small |
|-----|-------------|----------------------|
| tty-solitaire | 57×28 | Shows error message, exits |
| btop | 80×24 | May render incorrectly |
| nethack | 80×24 | Works but cramped |
| csvlens | 80×24 | Works; horizontal scroll for wide data |

Always set `cols` and `rows` appropriately when creating a PTY session.

---

## Integration with Other Skills

| Skill | Relationship |
|-------|-------------|
| [[tui-semantic-recognition]] | Provides the perception layer — how to extract semantics from raw grids |
| [[tui-capture-replay]] | Record navigation sequences for replay and regression testing |
| [[garazyk-tui]] | Underlying TUI primitives (ScreenBuffer, FocusRing, layout) |
| [[garazyk-scenario-dashboard]] | Dashboard-specific domain knowledge |
| [[agent-scenario-testing]] | Running scenarios programmatically (alternative to TUI navigation) |

## Semantic Detector Reference

The semantic parser (`semantic.mjs`) extracts structured information from
xterm.js cell data. Each detector produces a list of elements with `id`,
`role`, `bounds`, `confidence`, and `evidence`.

### detectTabs()
Finds tab bars with numbered tabs `[1]`, `[2]`, etc. separated by `|`.
Detects the active tab via underline/bold styling. Returns tab labels,
indices, and active state.

### detectPanes()
Finds box-drawing borders (`┌─┐│└─┘`) and vertical split rules (`│`).
Detects pane titles from `┌Title───` patterns. Identifies vertical splits
by finding columns where `│` appears consistently across multiple rows.

### detectLists()
Finds list items via three patterns:
1. **Tree markers**: `▾`, `▸`, `►`, `•` (handles box-border prefix)
2. **Nerd Font icons**: PUA range characters (U+E000–U+F8FF) used by
   file managers like yazi
3. **Cursor indicators**: `>` prefix or inverse/bold first character
   (selection highlight)

### detectStatusBar()
Finds bottom rows with distinct background colors (e.g., white-on-blue)
or keybinding hints like `[s]`, `[q]`, `↑↓→←`. Extracts keybinding
labels for the DECIDE step.

### detectPopups()
Finds centered bordered boxes that don't span the full width. Detects
popup titles from `┌Title───` patterns. Skips full-width borders
(which are panes, not popups).

### guessApplication()
Identifies the running app via:
1. **Command name** from the session (highest confidence)
2. **Screen content heuristics** (gitui tab pattern, btop header, etc.)
3. **Framework detection** (Textual: `[Esc]` key hints; Ratatui: fast
   rendering; ncurses: `~` tildes on empty lines)

### diffSnapshots(before, after)
Compares two semantic snapshots and returns:
- `cursorMoved`: cursor position changed
- `changedLineCount`: number of lines with different content
- `tabsChanged` / `activeTabBefore` / `activeTabAfter`: tab state
- `popupsChanged`: popup appeared or disappeared
- `selectionChanged` / `selectedAfter`: list selection state
- `statusBarChanged`: status bar content changed
- `processExited`: the process exited after the action

### parseKeyHints(text)
Parses status bar text into structured `{ key, action, raw }` objects.
Handles five formats:
- `Action [key]` — gitui: `Save [s]`
- `[key] Action` — bare: `[s] start`
- `Action: <key>` — lazygit: `Confirm: <enter>`
- `key: Action` — colon: `q: quit`
- `Action: <c-x>` — ctrl: `Copy: <c-o>`

### parseHelpOverlay(lines)
Parses a help overlay (triggered by `?`, `F1`, or `~`) into a full
keybinding table `{ key, command, description }`. Columns are separated
by 2+ spaces. Handles angle-bracket notation (`<C-c>`, `<Space>`).

### detectGameElements(grid, lines)
Detects game-specific elements not covered by standard UI detectors:
- **gameBoard**: Bordered area with wall chars (▒░█), with interior bounds
- **player**: `@` character with smart heuristics (single vs multi-@)
- **gameEntity**: Body segments (o), food ($), bonus (*) with positions
- **scoreBar**: Lines with Score/Level/Speed/Lives + parsed key-value pairs
- **titleBar**: First line with app name + mode suffix
- **cardGame**: Card game summary (card count, face-down count, tableau columns,
  foundations, waste, stock)
- **cardFace**: Individual card face (rank, suit, suitColor, position)

### detectCharts(grid, lines)
Detects data visualizations in TUI apps:
- **brailleChart**: Braille dot charts (U+2800–U+28FF) — two subtypes:
  - `sparkline`: 2D chart with few chars per line, multiple aligned rows
    (e.g., btop network graph: ⢀⣸ / ⠈⢹)
  - `barChart`: Inline Braille bars next to labels/values
    (e.g., btop CPU cores: "C0 ⣀⣀⣀⣀⢠⢠ 40%")
- **blockBar**: Horizontal bars with ■/█ block elements
  (e.g., btop CPU summary: "CPU ■■■■■■■■■■ 24%")
- **pipeMeter**: Pipe-character meters with brackets
  (e.g., htop: "0[|||||||||| 26.2%]")

Filtering: Braille inline bars in process tables are excluded by checking
x-position alignment variance across lines. Card backs require 5+ char width
to exclude UI buttons.

### buildCapabilityMap(snapshot)
Builds a navigation capability map from the semantic snapshot. This is
the core of the generalization: instead of app-specific logic, the
DECIDE step reads `snapshot.capabilities` to know what actions are
available. Sources (in priority order):

1. **Status bar key hints** — parsed from `[key] Action` patterns
2. **Tab bar detection** — number keys from tab indices
3. **Popup inference** — escape key for dismiss
4. **Framework defaults** — j/k, q, ? for ratatui; up/down, Ctrl+C for textual
5. **Universal fallbacks** — escape, ?, F1
