# TUI Corpus 200: Detailed Plan

## Status
- **Created**: 2026-05-24
- **Current corpus**: 9 apps, 9 YAML scenarios
- **Target**: 200 apps with semantic coverage across 12+ frameworks
- **Dependencies**: `scripts/mcp-pty/server.mjs`, `semantic.mjs`, `world.mjs`, `navigate_tuis.mjs`, `recording.mjs`

---

## Phase 0: Foundation (Week 1-2)

### 0.1 — Language/Framework Installability Audit
Determine which frameworks can be tested on macOS (primary dev machine) vs Linux (CI/Docker).

| Framework | Language | macOS Install | Linux Install | Risk |
|-----------|----------|---------------|---------------|------|
| Ratatui | Rust | `cargo install` | `cargo install` | Low — most apps compile cleanly |
| Bubbletea | Go | `go install` or `brew` | `go install` | Low |
| Textual | Python | `pip install` | `pip install` | Low |
| ncurses | C | `brew` or source | `apt` | Medium — compilation varies |
| OpenTUI | TypeScript | `deno run` | `deno run` | Low — we own it |
| Ink | JS/TS | `npm i -g` | `npm i -g` | Low |
| FTXUI | C++ | `brew` or CMake | `apt` or CMake | High — compilation heavy |
| Notcurses | C | `brew` | `apt` | Medium |
| Rich | Python | `pip install` | `pip install` | Low |
| Blessed | JS | `npm i -g` | `npm i -g` | Low |
| charmbracelet/huh | Go | `go install` | `go install` | Low — forms library |
| Cursive | Rust | `cargo install` | `cargo install` | Medium |

**Deliverable**: Matrix of installability per framework, with known-broken apps documented.

### 0.2 — Corpus Manifest Schema & CLI Tool
Build `scripts/mcp-pty/corpus/cli.ts` — a Deno CLI for managing the corpus.

**Manifest file**: `scripts/mcp-pty/corpus/manifest.json`
- Each entry: id, name, framework, frameworkLang, category, installMethod, binary path, launch args, prerequisites, settle time, quit keys, UI patterns exercised, complexity, platforms
- Machine-local state: `scripts/mcp-pty/corpus/installed.json` (gitignored)

**CLI commands**:
```
deno task corpus scan        — scan $PATH + brew/cargo/npm for known TUIs
deno task corpus install     — install all or by filter
deno task corpus list        — list with --framework, --category, --installed, --missing, --tested
deno task corpus coverage    — coverage matrix: framework × UI pattern × category
deno task corpus launch <id> — launch in PTY harness for manual exploration
deno task corpus audit       — verify binaries exist, check versions
```

**Deliverable**: Working CLI with manifest for initial 50 apps.

### 0.3 — YAML Scenario Runner Enhancement
The current `navigate_tuis.mjs` hardcodes each app's navigation. Need a generic runner that:
1. Reads a YAML scenario file
2. Launches the app via PTY
3. Executes observe-decide-act-verify steps
4. Records asciicast + semantic overlay
5. Produces a pass/fail report

**Deliverable**: `scripts/mcp-pty/corpus/runner.ts` that replaces the hand-coded `navigate_tuis.mjs` per-app functions.

---

## Phase 1: Core Corpus (Week 3-5) — 80 Apps

Goal: Breadth across all major frameworks and UI patterns.

### 1.1 — Framework Assignment (80 apps)

**Ratatui (Rust) — 20 apps**
| App | Category | UI Patterns | Install |
|-----|----------|-------------|---------|
| gitui | git-client | split-pane, popup, tab | `cargo install gitui` |
| lazygit* | git-client | split-pane, list, tab, filter | `brew` |
| yazi | file-manager | dual-pane, tab, preview | `cargo install yazi-fm` |
| csvlens | data-browser | table, scroll, filter, sort | `cargo install csvlens` |
| trippy | network-tool | tab, real-time chart, table | `cargo install trippy` |
| btop | system-monitor | braille chart, tab, process-list | `brew` |
| bottom | system-monitor | chart, table, tab | `cargo install bottom` |
| bacon | dev-tool | list, status-bar, scroll | `cargo install bacon` |
| zellij | terminal-mux | split-pane, tab, status-bar | `cargo install zellij` |
| joshuto | file-manager | dual-pane, tab, preview | `cargo install joshuto` |
| gpg-tui | security | list, form, popup | `cargo install gpg-tui` |
| diskonaut | disk-analyzer | tree, chart, table | `cargo install diskonaut` |
| xplr | file-manager | tree, dual-pane, form | `cargo install xplr` |
| spotify-tui | music | list, search, status-bar | `cargo install spotify-tui` |
| bandwhich | network | table, real-time, chart | `cargo install bandwhich` |
| zenith | system-monitor | chart, table, braille | `cargo install zenith` |
| tickrs | stocks | chart, table, real-time | `cargo install tickrs` |
| dua-cli | disk-analyzer | tree, chart, scroll | `cargo install dua-cli` |
| oha | http-bench | table, chart, real-time | `cargo install oha` |
| zoxide | filesystem | list, search, fuzzy | `brew` |

**Bubbletea (Go) — 15 apps**
| App | Category | UI Patterns | Install |
|-----|----------|-------------|---------|
| lazygit* | git-client | split-pane, list, tab, filter | `brew` |
| glow | markdown-viewer | scroll, render, search | `brew` |
| soft-serve | git-server | list, form, status | `go install` |
| gum | form-tools | input, choose, confirm, filter | `brew` |
| huh | form-library | input, select, multiselect, confirm | `go install` |
| wishlist | ssh-directory | list, form, ssh | `go install` |
| mods | ai-chat | chat, scroll, input | `brew` |
| tz | timezone | table, search, list | `go install` |
| pty | terminal | embedded terminal, resize | built-in |
| vhs | terminal-recorder | form, status, record | `brew` |
| arttime | art | animation, color, timer | `brew` |
| charm | crypto | form, list, keygen | `go install` |
| skate | key-value | list, form, search | `go install` |
| pop | email | list, compose, search | `go install` |
| confetti | celebration | animation, overlay | `go install` |

**Textual (Python) — 15 apps**
| App | Category | UI Patterns | Install |
|-----|----------|-------------|---------|
| posting | api-client | tab, form, response-viewer | `pip install` |
| harlequin | database | schema-tree, editor, table | `pip install` |
| textual-paint | drawing | canvas, palette, tool-select | `pip install` |
| textual-fspicker | file-picker | tree, search, form | `pip install` |
| textual-dev | dev-tools | log-viewer, css-editor, repl | `pip install` |
| trogon | cli-builder | form, wizard, tab | `pip install` |
| elia | ai-chat | chat, scroll, markdown | `pip install` |
| posting-tui | api-client | tab, form, json-viewer | `pip install` |
| toolong | log-viewer | table, search, filter, scroll | `pip install` |
| textual-astview | dev-tool | tree, syntax-highlight | `pip install` |
| memray | profiler | chart, table, flame-graph | `pip install` |
| textual-markdown | markdown | render, scroll, link | `pip install` |
| rich-cli | renderer | table, panel, tree, markdown | `pip install` |
| dolphie | database | table, schema, query | `pip install` |
| posting-textual | http | form, tab, response | `pip install` |

**ncurses (C) — 12 apps**
| App | Category | UI Patterns | Install |
|-----|----------|-------------|---------|
| htop | system-monitor | table, pipe-meter, f-key-bar | `brew` |
| ncdu | disk-analyzer | tree, list, confirm-dialog | `brew` |
| tty-solitaire | game | card-grid, selection, movement | `brew` |
| nsnake | game | game-board, score, player | `brew` |
| nudoku | game | grid, selection, input | `brew` |
| nethack | game | roguelike, inventory, dungeon | `brew` |
| greed | game | grid, score, movement | `brew` |
| cmus | music | list, tree, status-bar, search | `brew` |
| mc | file-manager | dual-pane, menu, form, dialog | `brew` |
| ranger | file-manager | dual-pane, preview, tab, vim-keys | `brew` |
| alpine | email | list, compose, tree, search | `brew` |
| irssi | chat | split-pane, list, input, nicklist | `brew` |

**Ink (JS/TS) — 8 apps**
| App | Category | UI Patterns | Install |
|-----|----------|-------------|---------|
| pastel | color-tool | gradient, palette, picker | `npm i -g` |
| emoji-cli | emoji-tool | search, grid, copy | `npm i -g` |
| jira-cli | project-mgmt | list, form, tab, filter | `npm i -g` |
| speed-test | network | chart, real-time, meter | `npm i -g` |
| npms-cli | package-mgmt | search, list, detail | `npm i -g` |
| pageres-cli | screenshot | form, progress, list | `npm i -g` |
| clipboard-cli | clipboard | list, search, form | `npm i -g` |
| carbon-now-cli | image-gen | form, preview, select | `npm i -g` |

**Rich (Python) — 5 apps**
| App | Category | UI Patterns | Install |
|-----|----------|-------------|---------|
| rich | demo | table, panel, tree, markdown | `pip install` |
| textual-web | web | browser-based, proxy | `pip install` |
| inspect | debugger | tree, table, scroll | `pip install` |
| pytest-rich | testing | table, progress, status | `pip install` |
| cyclopts | cli-builder | form, panel, help | `pip install` |

**Blessed (JS) — 3 apps**
| App | Category | UI Patterns | Install |
|-----|----------|-------------|---------|
| blessed-contrib | dashboard | gauge, chart, table, map | `npm i -g` |
| vtop | system-monitor | chart, table, braille | `npm i -g` |
| ijavascript | notebook | editor, table, chart | `npm i -g` |

**FTXUI (C++) — 4 apps** (compile from source)
| App | Category | UI Patterns | Install |
|-----|----------|-------------|---------|
| ftxui-starter | demo | tab, menu, input, table | CMake build |
| ftxui-examples | demo | animation, color, gauges | CMake build |
| dom | tree | tree, render, scroll | CMake build |
| game-of-life | game | grid, animation, controls | CMake build |

**Notcurses (C) — 3 apps**
| App | Category | UI Patterns | Install |
|-----|----------|-------------|---------|
| notcurses-demo | demo | multimedia, sixel, rgb | `brew` |
| ncmpcpp | music | list, tree, status, search | `brew` |
| neomutt | email | list, compose, sidebar, search | `brew` |

### 1.2 — UI Pattern Coverage Grid

Target minimum counts per pattern across the corpus:

| UI Pattern | Min Apps | Strategy |
|-----------|---------|----------|
| Table/Data Grid | 25 | csvlens, htop, harlequin, dolphie, btop, bottom, bandwhich, trippy, zenith, lazygit (branches), cmus, ranger, mc, alpine, memray, dolphie, toolong, tz, etc. |
| List Selection | 25 | lazygit, gitui, ncdu, glow, ranger, yazi, dua-cli, diskonaut, cmus, alpine, zoxide, pastel, etc. |
| Tab Navigation | 20 | lazygit, gitui, btop, trippy, posting, harlequin, yazi, bottom, textual-paint, etc. |
| Split/Dual Pane | 15 | lazygit, gitui, yazi, joshuto, ranger, mc, zellij, irssi, neomutt, etc. |
| Form Input | 15 | posting, gum, huh, lazydocker, alpine, trogon, gpg-tui, etc. |
| Search/Filter | 20 | csvlens, lazygit, fzf, glow, ncdu, ranger, mc, cmus, etc. |
| Popup/Dialog | 12 | lazygit, gitui, ncdu (delete), mc, nethack, gpg-tui, etc. |
| Tree Navigation | 12 | ncdu, yazi, joshuto, harlequin (schema), dua-cli, diskonaut, xplr, etc. |
| Chart/Gauge | 12 | btop, bottom, trippy, bandwhich, zenith, tickrs, memray, oha, etc. |
| Game Board | 10 | tty-solitaire, nsnake, nudoku, nethack, greed, game-of-life, etc. |
| Real-time Data | 10 | btop, htop, bottom, trippy, bandwhich, zenith, tickrs, oha, etc. |
| Confirmation Dialog | 8 | ncdu, lazygit (commit), gitui (commit), mc, nethack, etc. |
| File Preview | 6 | yazi, joshuto, ranger, mc, xplr, etc. |
| Text Editor | 5 | hx, vim, nano, micro, ne | Already partially tested |
| Terminal Multiplexer | 3 | tmux, zellij, screen |

### 1.3 — YAML Scenario Template

Every app gets a YAML scenario following this structure:

```yaml
name: <app> Basic Navigation
description: <one-line purpose>
command: /path/to/binary
args: []
cols: 80
rows: 24
settleMs: 2000
framework: ratatui
category: git-client
patterns: [split-pane, list-selection, tab-navigation]

steps:
  # Phase 1: OBSERVE — verify app launched and semantic detection works
  - type: observe
    label: Initial snapshot
  - type: assert_semantic
    target: app
    expected: gitui
    label: Verify app detection

  # Phase 2: CAPABILITY — verify capability map
  - type: assert_capability
    target: navigate.keys
    contains: ["j", "k"]
    label: Navigate keys detected
  - type: assert_capability
    target: quit.keys
    contains: ["q"]
    label: Quit key detected

  # Phase 3: NAVIGATE — exercise basic movement
  - type: press_key
    value: j
    label: Scroll down
    times: 3
  - type: assert_cursor_moved
    label: Cursor moved after j

  # Phase 4: TABS — switch tabs if available
  - type: press_key
    value: "2"
    label: Switch to tab 2
  - type: assert_content_changed
    label: Content changed after tab switch

  # Phase 5: QUIT
  - type: press_key
    value: q
    label: Quit
  - type: assert_exited
    label: App exited cleanly

record: true
semantic_overlay: true
```

### 1.4 — Scenario Autogeneration (Minimal V1)

Build `scripts/mcp-pty/corpus/generator.ts` that:
1. Reads the manifest entry for an app
2. Launches the app via PTY
3. Takes one semantic snapshot
4. Generates a YAML scenario skeleton from:
   - Manifest metadata (framework → default keys)
   - Semantic snapshot (tabs detected → tab navigation steps, lists detected → scroll steps, popups detected → dismiss steps)
   - Capability map (quit keys, navigate keys, action keys)
5. Writes the skeleton to `corpus/tests/<app_id>.yaml`

This is NOT a fully automated runner — it generates a skeleton that a human can review and tune. But it eliminates the boilerplate of hand-writing 200 YAML files.

---

## Phase 2: Scenario Autogeneration (Week 6-8) — 200 Scenarios

### 2.1 — Full Autogeneration Pipeline

Build on the V1 skeleton generator with an LLM-assisted pipeline:

1. **Launch & Snapshot**: Start app, capture semantic snapshot + world graph
2. **Analyze**: Feed snapshot + capability map to an LLM (local or API)
3. **Generate Steps**: LLM produces observe-decide-act-verify steps
4. **Validate**: Dry-run the generated steps, retry up to 3 times with fixes
5. **Record**: Save passing scenario as YAML + asciicast + HTML overlay

**LLM prompt template**:
```
You are generating a TUI test scenario for {app_name} ({framework}).
The current semantic snapshot shows:
- Tabs: {tabs_summary}
- Lists: {lists_summary}
- Status bar keys: {key_actions}
- Popups: {popups_summary}
- Capability map: {capabilities}

Framework conventions for {framework}: {conventions}

Generate 10 observe-decide-act-verify steps that:
1. Verify the app launched correctly
2. Navigate through primary UI elements
3. Switch tabs if available
4. Scroll through lists if available  
5. Exercise one key action from the status bar
6. Cleanly quit the app

Output YAML as a code block.
```

### 2.2 — Quality Gates for Autogenerated Scenarios

Each autogenerated scenario must pass:
- **No crash**: App doesn't crash during scenario
- **Content change**: Each ACT step produces a measurable snapshot diff
- **Clean quit**: App exits after quit key sequence
- **Semantic detection**: App name and framework are correctly detected
- **No false steps**: Each step label accurately describes what happened

Scenarios that fail are flagged for manual review and stored in `corpus/failures/`.

---

## Phase 3: Framework Detection Training (Week 7-8)

### 3.1 — Detection Fingerprint Collection

For each of the 200 apps, after launch, collect:
- First 10 lines of terminal content (for content-based heuristics)
- Binary name and path (for command-based matching)
- Box-drawing character density
- Rounded vs sharp border usage
- Status bar pattern (bracketed keys, caret keys, F-key bar, descriptive phrases)
- Color palette analysis (16-color vs 256-color vs true-color)
- Key hint notation style

Store as `corpus/fingerprints/<app_id>.json`.

### 3.2 — Heuristic Expansion in `semantic.mjs`

Use the fingerprint collection to expand `guessApplication()`:

1. **Framework signatures**: Train regex/statistical patterns per framework
   - Ratatui: rounded borders + bracketed keys + box-count > 20
   - Bubbletea: `Press ESC / q to exit` pattern + no F-key bar
   - Textual: `^c` caret notation + no box drawing borders
   - ncurses: F-key bar + sharp corners + pipe meters
   - Ink: JS process name + sparse box drawing
   - FTXUI: double-line box drawing + C++ binary name
   - Notcurses: sixel sequences + true-color ANSI
   - Rich: `╭─` rounded borders + Python process + panel/tree keywords
   - Blessed: `[key]` bracketed notation + JS process

2. **App-specific signatures**: Expand from current ~25 to ~200 apps based on fingerprint data

3. **Unknown app fallback**: When app is unknown, use framework detection alone to provide navigation conventions

### 3.3 — Detection Accuracy Measurement

Build `scripts/mcp-pty/corpus/benchmark.ts` that:
1. Launches each app
2. Runs `guessApplication()` on the initial snapshot
3. Compares detected app + framework against manifest ground truth
4. Reports precision/recall per framework and overall

Target: 90%+ framework detection accuracy, 80%+ app detection accuracy.

---

## Phase 4: Edge Case Library (Week 8-9)

### 4.1 — Edge Case Taxonomy

| Edge Case | What Breaks | Test With |
|-----------|-------------|-----------|
| CJK fullwidth (中文, 日本語, 한국어) | Width calculation, wrapping, alignment | CJK filenames in yazi/ranger, CJK text in glow/moar |
| Emoji sequences (👨‍👩‍👧‍👦, 🏳️‍🌈) | ZWJ sequences counted as multiple cells | Emoji-rich text files in glow |
| RTL text (العربية, עברית) | Layout inversion, cursor placement | RTL files in less/moar/vim |
| Combining marks (é, ñ, ắ) | Precomposed vs decomposed equivalence | Unicode test files |
| Variation selectors (︎ vs ️) | Emoji presentation width changes | Emoji test grid |
| Zero-width characters (U+200B) | Invisible columns breaking grid alignment | Crafted test files |
| ANSI edge cases (nested SGR, OSC, DCS) | Parser state corruption | Generated ANSI torture tests |
| Wide terminals (200+ cols) | Horizontal scroll, layout overflow | Resize PTY to 200×50 |
| Tiny terminals (20×10) | Layout collapse, text truncation | Resize PTY to 20×10 |
| Resize during render | Diff buffer invalidation | Rapid resize during app startup |
| Long lines (1000+ chars) | Line wrapping, performance | Generated long-line files |
| Binary output | Garbage rendering, parser crash | Pipe binary through cat |
| NULL bytes | String termination in C apps | Crafted inputs |
| Escape flooding | PTY buffer overflow, CPU spike | Flood test harness |
| Combining box drawing | RTL box characters, mixed-width panels | Niche terminal emulators |
| Sixel graphics | Image data in terminal | Notcurses demo |
| Kitty keyboard protocol | Extended key sequences | Kitty terminal |
| Bracketed paste | Pasted text vs typed input distinction | Automated paste tests |

### 4.2 — Edge Case Test Harness

Build `scripts/mcp-pty/corpus/edge_cases.ts` that:
1. For each edge case, produces a specific app + input combination
2. Records the session with semantic overlay
3. Compares snapshot diffs before/after edge case trigger
4. Flags any semantic detection regressions

Stored in `corpus/edge_cases/` with expected outcomes.

---

## Phase 5: OpenTUI Dogfooding (Week 9-10)

### 5.1 — Build 8 Small OpenTUI Apps

Each app exercises one or two specific UI patterns that we want our semantic detectors to handle well:

| App | Pattern | Description |
|-----|---------|-------------|
| `tui-form-wizard` | Form, Input, Wizard | Multi-step form with text inputs, checkboxes, selects, progress bar. Submits and shows summary. |
| `tui-dashboard` | Dashboard, Charts, Panes | CPU/memory/disk gauges, status grid, alerts panel. Uses `@garazyk/tui` layout engine. |
| `tui-file-browser` | Tree, Dual-pane, Preview | Browse filesystem, preview text files, delete with confirmation. |
| `tui-kanban` | Board, Cards, Drag | Kanban board with columns, movable cards, tags, search. |
| `tui-inbox` | Inbox, List, Compose | Email-like interface: folder tree, message list, message viewer, compose form. |
| `tui-snake` | Game, Board, Score | Snake clone with game board detection, score tracking, game-over popup. |
| `tui-settings` | Settings, Tabs, Toggles | Settings panel with tabs, toggle switches, dropdowns, text inputs, save/cancel. |
| `tui-log-viewer` | Table, Filter, Scroll | Log viewer with table, real-time tail, filter, search, highlight. |

### 5.2 — Detect Our Own Framework

The OpenTUI apps give us a controlled environment to ensure `guessApplication()` correctly identifies `framework: "opentui"` and knows its conventions:
- Arrow keys for navigation by default
- Enter to activate/select
- Escape to dismiss
- Tab to cycle focus
- Ctrl+C to quit

This becomes the 13th framework in the detection matrix.

### 5.3 — Semantic Detector Validation

Run the full semantic pipeline against OpenTUI apps:
- Do `detectTabs()` correctly find OpenTUI tab bars?
- Does `detectLists()` find OpenTUI list items?
- Does `detectControls()` identify OpenTUI form controls?
- Does `buildCapabilityMap()` produce correct capabilities?

File bugs against either the semantic detectors or the OpenTUI apps themselves.

---

## Phase 6: Integration & Reporting (Week 10-11)

### 6.1 — Full Corpus Runner

`scripts/mcp-pty/corpus/run_all.ts`:
```
deno task corpus run-all          — run all 200 scenarios
deno task corpus run-all --framework ratatui  — filter by framework
deno task corpus run-all --category game      — filter by category
deno task corpus run-all --tag smoke          — smoke test subset
```

Produces `corpus/reports/<timestamp>/results.json` with per-app:
- Pass/fail status
- Semantic detection accuracy (app, framework)
- Capability map correctness
- Time to complete
- Any crashes or hangs
- Asciicast recording path

### 6.2 — Coverage Dashboard

Update the existing scenario dashboard (`scripts/scenario-dashboard/`) to include a TUI corpus panel showing:
- Framework coverage (bar chart)
- UI pattern coverage (radar/spider chart)
- Pass/fail heatmap
- Detection accuracy per framework
- Edge case regressions

### 6.3 — Decision Graph Integration

Log all corpus development decisions in the `deciduous` graph:
- Each app added = action node
- Framework detection changes = decision node
- Scenario generation improvements = outcome node
- Detection accuracy benchmarks = metric node

---

## Timeline Summary

```
Week 1-2:  Phase 0 — Foundation (manifest, CLI, runner)
Week 3-5:  Phase 1 — Core corpus (80 apps, YAML scenarios)
Week 6-8:  Phase 2 — Autogeneration (200 scenarios) + Phase 3 — Detection training
Week 8-9:  Phase 4 — Edge case library
Week 9-10: Phase 5 — OpenTUI dogfooding
Week 10-11: Phase 6 — Integration & reporting
```

## Success Metrics

| Metric | Current | Target |
|--------|---------|--------|
| Apps in corpus | 9 | 200 |
| YAML scenarios | 9 | 200+ |
| Frameworks detected | 4 (ratatui, bubbletea, textual, ncurses) | 12+ |
| Framework detection accuracy | ~85% (estimated) | 90%+ |
| App detection accuracy | ~70% (estimated) | 80%+ |
| UI patterns covered | ~6/15 | 15/15 |
| Edge cases covered | 0/20 | 20/20 |
| Autogenerated scenarios | 0 | 150+ |
| OpenTUI apps dogfooded | 0 | 8 |
| Corpus CI runtime | N/A | < 30 minutes |
