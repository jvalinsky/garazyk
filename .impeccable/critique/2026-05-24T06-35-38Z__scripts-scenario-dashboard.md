---
target: scripts/scenario-dashboard
total_score: 20
p0_count: 0
p1_count: 3
timestamp: 2026-05-24T06-35-38Z
slug: scripts-scenario-dashboard
---
# Impeccable Critique: `scripts/scenario-dashboard`

Target commit: `142181bf`

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|---:|---:|---|
| 1 | Visibility of System Status | 3 | Scope strip and failure triage now make run/network state visible, but mobile hides scope and sidebar context. |
| 2 | Match System / Real World | 2 | ATProto testing concepts are present, but visible identity is still Garazyk-first and `Agent` remains under-explained. |
| 3 | User Control and Freedom | 2 | Back, stop, restart, and log jump exist; settings and destructive actions still lack robust escape/confirmation behavior. |
| 4 | Consistency and Standards | 2 | New scope/triage vocabulary helps, but dots, badges, cards, inline styles, and token drift still split the system. |
| 5 | Error Prevention | 2 | Command scope reduces risk before `Run All`, but `Stop`, `Restart`, and service lifecycle actions still need clearer guardrails. |
| 6 | Recognition Rather Than Recall | 2 | Failure triage reduces hunting on run detail, but home still asks users to infer relationships among cards, tables, sidebar, and toolbar. |
| 7 | Flexibility and Efficiency | 2 | Search and direct scenario/run links exist; no failed-only view, log search, keyboard accelerators, or rerun-failed path. |
| 8 | Aesthetic and Minimalist Design | 2 | Tool-native foundation is credible, but the home page is still card-heavy and the scope strip becomes visually dense. |
| 9 | Error Recovery | 2 | Failed run page now identifies the first failed scenario/step, but empty logs leave users without the next recovery action. |
| 10 | Help and Documentation | 1 | No contextual help for topology, runner, Agent mode, PDS2, or scenario parameter decisions. |
| **Total** | | **20/40** | **Acceptable, but the core experience still needs focused UX hardening.** |

## Anti-Patterns Verdict

This no longer reads as a generic AI dashboard. The shell is dense, task-oriented, and domain-specific, and the new scope strip plus failure triage panel move it toward the "Network Flight Deck" direction in `DESIGN.md`.

The remaining slop tells are product-specific: repeated cards where comparison would be better, modal-first configuration, literal black/white log styling, hidden mobile context, and Garazyk-first naming in a tool meant to support swappable ATProto implementations.

### Deterministic Scan

The detector did not run successfully.

- Command: `node /Users/jack/.agents/skills/impeccable/scripts/detect.mjs --json scripts/scenario-dashboard`
- Exit code: `1`
- Failure: `Error: bundled detector not found.`
- Counts/rules/locations: unavailable

This is an unavailable scan, not a clean result.

### Browser Evidence

The in-app browser successfully loaded the current dashboard through a Fresh dev server at `http://localhost:3001/`.

Observed home page:
- Header: `Garazyk Scenarios`
- Scope strip: `Garazyk`, `garazyk-default`, `host`, `92 scenarios`, `0/11`, `PDS2 included`
- Controls: topology selector, runner selector, `Settings`, `Agent`, `Run All`
- Main content: `Network Status`, service table, summary cards, scenario grid, run history

Observed failed run page at `/run/2026-05-24t0512z-45109`:
- Failure triage is present and starts with `First failed scenario: 01 account lifecycle`
- Failed step is visible: `Scenario 01 timeout`
- Failure detail is visible: `Timed out after 5s; host child process was terminated`
- `Jump to logs` target exists, but logs show `No logs available.`

Overlay injection was not available because the browser evaluation scope is read-only. No visible `[Human]` overlay was created.

## Overall Impression

The last commit fixed the right first-order problems. The dashboard now tells the user what scope they are about to act on, and a failed run starts with a useful triage panel instead of only counts and cards. That is a real improvement.

The next level is making the tool resilient: accessible controls, mobile structure, safer logs, and a more generic ATProto framing. Right now it is a better Garazyk dashboard, but not yet a trustworthy swappable local-network test console.

## What's Working

- The command scope strip is the right idea. It surfaces topology, runner, target count, service count, and PDS2 before the primary action.
- The failure triage panel materially improves run detail. It answers the first failure and failed step before summary cards.
- The underlying shell still fits the product register: toolbar, sidebar, service table, progress panel, run history, and logs are the right primitives.

## Priority Issues

### [P1] Mobile removes the network model

**Why it matters:** The design principle says the network model must stay visible. At mobile width the scope strip is hidden and the sidebar is removed, which removes topology context, scenario navigation, network summary, and topology inspector.

**Evidence:** [app.css](/Users/jack/Software/garazyk/scripts/scenario-dashboard/static/app.css:1219), [app.css](/Users/jack/Software/garazyk/scripts/scenario-dashboard/static/app.css:1223)

**Fix:** Replace hidden context with a mobile structure: a top summary row for topology/runner/services, a drawer or tab for scenarios/topology, and touch-sized controls. Do not simply hide the command scope.

**Suggested command:** `impeccable adapt ./scripts/scenario-dashboard`

### [P1] Settings are still modal-first and not accessibility-ready

**Why it matters:** Scenario parameters affect the run, but the user edits them in a modal detached from the scope strip. The modal lacks dialog semantics, focus management, Escape behavior, and programmatic labels for parameter inputs.

**Evidence:** [Toolbar.tsx](/Users/jack/Software/garazyk/scripts/scenario-dashboard/islands/Toolbar.tsx:252), [Toolbar.tsx](/Users/jack/Software/garazyk/scripts/scenario-dashboard/islands/Toolbar.tsx:276)

**Fix:** Move scenario parameters into a run setup panel or inspector beside the scope strip. If a dialog remains, add `role="dialog"`, `aria-modal`, `aria-labelledby`, focus trap, Escape close, focus restoration, and real labels/descriptions for every input.

**Suggested command:** `impeccable harden ./scripts/scenario-dashboard`

### [P1] Logs are still the weakest triage link

**Why it matters:** The new failure triage panel sends users to logs, but the tested failed run shows `No logs available.` The viewer also force-scrolls, uses hardcoded colors, and renders converted ANSI HTML via `dangerouslySetInnerHTML`.

**Evidence:** [LogViewer.tsx](/Users/jack/Software/garazyk/scripts/scenario-dashboard/islands/LogViewer.tsx:33), [LogViewer.tsx](/Users/jack/Software/garazyk/scripts/scenario-dashboard/islands/LogViewer.tsx:66), [LogViewer.tsx](/Users/jack/Software/garazyk/scripts/scenario-dashboard/islands/LogViewer.tsx:67)

**Fix:** Show why logs are absent and where to look next. Add safe log rendering tests, tokenized log colors, search/filter, copy, "jump to latest", and auto-scroll only when already near the bottom.

**Suggested command:** `impeccable harden ./scripts/scenario-dashboard`

### [P2] Generic ATProto positioning is still not carried through

**Why it matters:** `PRODUCT.md` says this should work for anyone testing local ATProto network stacks. The visible product identity still starts with `Garazyk`, and browser evidence showed the first scope pill is `Garazyk`.

**Evidence:** [Toolbar.tsx](/Users/jack/Software/garazyk/scripts/scenario-dashboard/islands/Toolbar.tsx:106), [Toolbar.tsx](/Users/jack/Software/garazyk/scripts/scenario-dashboard/islands/Toolbar.tsx:110)

**Fix:** Rename the surface around the generic task, for example `ATProto Scenario Console`, and show `Garazyk` as the selected implementation/preset instead of the product identity.

**Suggested command:** `impeccable clarify ./scripts/scenario-dashboard`

### [P2] The home page remains card-heavy for diagnosis

**Why it matters:** The triage page improved, but the home page still leads with summary cards and a scenario card grid. For 92 scenarios, cards are weak for comparison, filtering, and failure-oriented scanning.

**Evidence:** Browser evidence confirmed summary cards and scenario grid remain on the home page; source renders them at [routes/index.tsx](/Users/jack/Software/garazyk/scripts/scenario-dashboard/routes/index.tsx:102) and [routes/index.tsx](/Users/jack/Software/garazyk/scripts/scenario-dashboard/routes/index.tsx:108).

**Fix:** Add a dense scenario table/list with status, compatibility, required roles, last result, last failure, and action. Keep cards only for compact summaries or empty states.

**Suggested command:** `impeccable layout ./scripts/scenario-dashboard`

## Cognitive Load

Current cognitive load is moderate-high. The scope strip reduced working-memory burden for run setup, and failure triage reduced hunting on run detail. Four checklist failures remain:

- **Single focus:** Home still has network actions, run actions, summary cards, scenario grid, sidebar, and run history competing at once.
- **Minimal choices:** The toolbar plus network panel still presents more than four decision points before a run.
- **Progressive disclosure:** Scenario settings reveal broad parameter lists in a modal instead of staged run setup.
- **Working memory:** Users still move between failure triage, scenario cards, and logs, especially when logs are empty.

Decision points over four options:
- Home toolbar: topology, runner, Settings, Agent, Run All, plus the scope strip.
- Network panel: Start, Start with PDS2, Stop, service table, runner/service status.
- Sidebar: search, network count, category toggles, many scenario links, topology inspector.
- Settings modal: all parameterized scenarios and fields in one surface.

## Emotional Journey

The peak is now the failed run detail. Seeing `First failed scenario`, `failed step`, topology, runner, and the timeout detail is exactly the kind of confidence this tool needs.

The valley is the handoff from triage to logs. `Jump to logs` is promising, but the observed failed run lands on `No logs available.` That breaks the recovery path at the exact moment the user expects evidence.

High-stakes reassurance improved before `Run All`, but not enough around `Stop`, `Restart`, `Start with PDS2`, and settings changes. Those controls still need clearer consequences and recovery affordances.

## Persona Red Flags

**Alex, power user:** The new failure panel helps, but there is still no failed-only scenario list, rerun-failed action, log search, copy affordance, keyboard shortcuts, or command palette. Alex can diagnose faster than before, but still has to click and scan too much.

**Sam, accessibility-dependent user:** Sidebar category headers are clickable `div`s, settings are modal-based without dialog semantics, parameter inputs are not labeled by real labels, status dots still carry meaning, and mobile hides navigation/context. Sam still hits core barriers.

**Priya, ATProto stack tester:** The scope strip helps Priya understand topology and runner, but the product still says `Garazyk Scenarios`. If she is testing another PDS/AppView/Relay implementation, she has to reinterpret Garazyk-specific identity as a generic ATProto testing tool.

## Minor Observations

- `var(--color-primary)` is still referenced but not defined.
- Primary buttons still use literal `white`.
- The log viewer still uses `#000`, `#eee`, and `#333`.
- The command scope hides later pills at medium widths and disappears entirely on mobile.
- Service URLs still use the system font instead of the exact-data mono rule.
- `Agent` is still too compressed for a mode that changes how runs stream events.

## Questions to Consider

- What should be the product name if Garazyk is only the default implementation preset?
- Should `Settings` be part of a staged `Prepare run` flow instead of a modal?
- When logs are absent, what is the next best evidence source: process exit, service diagnostics, run artifact, or scenario detail?
- Would the home page work better as a split view: network/run setup on top, scenario table below, history in a side rail?
