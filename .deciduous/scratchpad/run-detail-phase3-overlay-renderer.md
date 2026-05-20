# Phase 3: Overlay Renderer — renderRunDetailOverlay

## Goal
Build the full-screen overlay that shows scenario results for a run.

## Design

```
┌─ Run 2026-05-19T23-12-36-564 ─ [fail] ──────────────────────────┐
│ topology: garazyk-default  runner: host  pds2: no  binary: no  │
│ 3 passed  2 failed  1 skipped  duration: 45.2s                 │
│                                                                 │
│ ● 01_account_lifecycle                              passed  2.1s│
│ ● 02_profile_update                                 passed  1.8s│
│ ✖ 03_repo_creation                                  failed  3.2s│
│   └ Error: Repository creation returned 500                     │
│ ● 04_follow_graph                                   passed  4.1s│
│ ✖ 05_message_send                                   failed  0.8s│
│   └ AssertionError: Expected message to be delivered            │
│ ○ 06_labeler_setup                                 skipped  0.1s│
│                                                                 │
│ ↑↓ scroll  Enter step detail  Esc close                        │
└─────────────────────────────────────────────────────────────────┘
```

## Changes

### 1. `tui/panels/run_detail.ts` — New file

`renderRunDetailOverlay(buf, run, results, cursor, scrollOffset)`:
- Full-screen reverse-video background (same as help overlay)
- Header: run ID, status badge, topology/runner/pds2/binary metadata
- Summary line: passed/failed/skipped counts + duration
- Scenario list: scrollable, cursor-highlighted
  - Passed: `●` green
  - Failed: `✖` red + indented error detail line
  - Skipped: `○` muted
- Footer: keybinding hints (↑↓ scroll, Esc close)
- Uses `buf.writeClipped()` for all content
- Cursor row gets reverse-video highlight

### 2. `tui/view.ts` — Call overlay from renderView

When `state.runs.detailRunId !== null`, render the overlay after rasterize().
Pass the needed state to `renderRunDetailOverlay`.

## Verification
- `deno check` on new and modified files
