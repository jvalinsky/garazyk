# Scenario Dashboard UI/UX Audit

Date: 2026-05-24

Target: `scripts/scenario-dashboard`

Scope: code-level UI audit for accessibility, performance, theming, responsive behavior, and product anti-patterns. This report is intentionally fix-oriented and does not modify runtime code.

## Audit Health Score

| # | Dimension | Score | Key Finding |
|---|---:|---:|---|
| 1 | Accessibility | 2/4 | Settings modal and sidebar toggles are not accessible interaction patterns. |
| 2 | Performance | 2/4 | Log auto-scroll and width transitions can interrupt or degrade live debugging. |
| 3 | Theming | 2/4 | Tokens exist, but hardcoded colors and undefined tokens break consistency. |
| 4 | Responsive Design | 1/4 | Toolbar, hidden sidebar, small controls, and fixed log height make mobile rough. |
| 5 | Anti-Patterns | 2/4 | Card-heavy dashboard, modal-first settings, and unclear control scope are visible. |
| **Total** | | **9/20** | **Poor: major UX pass needed before this feels like a trustworthy test control surface.** |

## Anti-Patterns Verdict

The dashboard does not look like a generic marketing page, which is good. It does, however, show several tool-UI slop patterns: a card-heavy overview, scattered state vocabulary, a modal-first settings flow, ambiguous control scope, and hardcoded visual overrides inside otherwise tokenized CSS.

The biggest product issue is not visual polish. It is information architecture: the user cannot quickly answer what network is under test, what action each control will affect, and where a failure began.

## Executive Summary

- Audit Health Score: **9/20** (Poor)
- Issues found: **0 P0, 7 P1, 8 P2, 3 P3**
- Highest priority: fix modal accessibility, sidebar keyboard access, run/network control scope, failure triage flow, and mobile structure.
- Best next command: `impeccable shape ./scripts/scenario-dashboard` to reshape the dashboard layout and control model before implementation.

## Detailed Findings

### [P1] Settings modal lacks dialog semantics and focus management

- **Location:** `islands/Toolbar.tsx:185`
- **Category:** Accessibility
- **Impact:** Screen reader and keyboard users are not told that a dialog opened. Focus is not trapped, Escape is not handled, and focus is not restored to the Settings button on close.
- **Standard:** WCAG 2.1 AA, keyboard and name/role/value expectations.
- **Recommendation:** Add `role="dialog"`, `aria-modal="true"`, `aria-labelledby`, Escape handling, initial focus, focus trap, and focus restoration. Consider replacing the modal with an inspector or inline run-setup panel.
- **Suggested command:** `impeccable harden ./scripts/scenario-dashboard`

### [P1] Scenario setting inputs are not programmatically labeled

- **Location:** `islands/Toolbar.tsx:207`
- **Category:** Accessibility
- **Impact:** The visible setting name is a `div`, not a label associated with the input. Assistive tech users may hear unlabeled number, text, or checkbox controls.
- **Standard:** WCAG 2.1 AA, form labels.
- **Recommendation:** Generate stable IDs, use `<label for>`, connect descriptions via `aria-describedby`, and expose parameter defaults and units where available.
- **Suggested command:** `impeccable harden ./scripts/scenario-dashboard`

### [P1] Sidebar category toggles are clickable divs

- **Location:** `islands/Sidebar.tsx:81`
- **Category:** Accessibility
- **Impact:** Keyboard users cannot reliably collapse or expand categories. Screen readers do not receive button semantics or expanded/collapsed state.
- **Standard:** WCAG 2.1 AA, keyboard operability and name/role/value.
- **Recommendation:** Use `<button type="button">` with `aria-expanded`, `aria-controls`, and keyboard-visible focus styling.
- **Suggested command:** `impeccable harden ./scripts/scenario-dashboard`

### [P1] Control scope is ambiguous across network and run actions

- **Location:** `islands/Toolbar.tsx:98`, `islands/Toolbar.tsx:130`, `islands/NetworkStatus.tsx:24`
- **Category:** Product UX
- **Impact:** Topology, runner, agent mode, run actions, and service lifecycle controls are split across areas without a clear preview of what each action affects. This is risky for a local network control surface.
- **Recommendation:** Separate "Network setup" from "Run scenarios"; show selected topology, runner, service count, PDS2 requirement, and target scenario count next to the action that uses them.
- **Suggested command:** `impeccable shape ./scripts/scenario-dashboard`

### [P1] Failure triage starts from counts, not cause

- **Location:** `routes/index.tsx:102`, `components/SummaryCards.tsx:14`, `routes/scenario/[id].tsx:144`, `islands/LogViewer.tsx:55`
- **Category:** Product UX
- **Impact:** A failed run shows red counts and cards, but the user has to click around to find the first failed step, related service, and log excerpt.
- **Recommendation:** Add a failure-first triage panel: first failing scenario, failed step, service context, log jump link, and topology compatibility context.
- **Suggested command:** `impeccable shape ./scripts/scenario-dashboard`

### [P1] Mobile hides the primary navigation without replacement

- **Location:** `static/app.css:1041`, `islands/Sidebar.tsx:53`
- **Category:** Responsive Design
- **Impact:** At narrow widths the sidebar disappears, which removes scenario search, category navigation, network summary, and topology inspector from the interface.
- **Recommendation:** Replace hidden sidebar with an accessible drawer, segmented view switcher, or top-level tab model. Preserve search and topology context on mobile.
- **Suggested command:** `impeccable adapt ./scripts/scenario-dashboard`

### [P1] Log rendering uses trusted HTML insertion for service output

- **Location:** `islands/LogViewer.tsx:40`, `islands/LogViewer.tsx:67`
- **Category:** Frontend Security
- **Impact:** Logs can include data from services, scenario output, and protocol payloads. Rendering converted HTML through `dangerouslySetInnerHTML` needs a clear sanitization boundary and tests.
- **Standard:** XSS prevention.
- **Recommendation:** Confirm `ansi_up` escapes all non-ANSI HTML, add a focused test for hostile log lines, and consider a sanitizer or safer token renderer.
- **Suggested command:** `impeccable harden ./scripts/scenario-dashboard`

### [P2] Log viewer overrides the token system with hardcoded colors

- **Location:** `islands/LogViewer.tsx:66`
- **Category:** Theming
- **Impact:** Inline `#000`, `#eee`, and `#333` bypass OKLCH tokens, dark-mode behavior, and the new `Log Well` design rule.
- **Recommendation:** Move height, border, padding, and colors to `.log-viewer`; use `--color-log-bg`, `--color-log-text`, and tokenized borders.
- **Suggested command:** `impeccable colorize ./scripts/scenario-dashboard`

### [P2] Undefined token breaks scenario settings title styling

- **Location:** `static/app.css:281`
- **Category:** Theming
- **Impact:** `var(--color-primary)` is not defined in `tokens.css`, so the title underline silently fails.
- **Recommendation:** Use `--color-accent` or add a real token with documented purpose.
- **Suggested command:** `impeccable colorize ./scripts/scenario-dashboard`

### [P2] Primary button uses literal white

- **Location:** `static/app.css:625`
- **Category:** Theming
- **Impact:** The UI violates the tinted-neutral rule and may drift from the OKLCH palette in dark and light themes.
- **Recommendation:** Add an on-accent token or reuse a tinted light neutral instead of `white`.
- **Suggested command:** `impeccable colorize ./scripts/scenario-dashboard`

### [P2] Dashboard has no page-level heading

- **Location:** `routes/index.tsx:89`
- **Category:** Accessibility
- **Impact:** The dashboard main content starts with component sections and an `h2`, but no `h1`. Screen-reader users lose a clear page landmark.
- **Recommendation:** Add a visually appropriate `h1`, or an accessible-only heading if the toolbar title is the visual title.
- **Suggested command:** `impeccable harden ./scripts/scenario-dashboard`

### [P2] Log auto-scroll hijacks user reading position

- **Location:** `islands/LogViewer.tsx:33`
- **Category:** Product UX / Performance
- **Impact:** Every log update scrolls to the bottom. A user reading an earlier failure loses context during live runs.
- **Recommendation:** Auto-scroll only when the viewer is already near the bottom. Add a sticky "jump to latest" control and visible paused state.
- **Suggested command:** `impeccable harden ./scripts/scenario-dashboard`

### [P2] Motion does not respect reduced-motion preferences

- **Location:** `static/app.css:331`, `static/app.css:812`, `static/app.css:975`
- **Category:** Accessibility / Performance
- **Impact:** Pulsing indicators and width transitions continue for users who request reduced motion.
- **Recommendation:** Add a `prefers-reduced-motion: reduce` block that disables pulse animations, active transforms, and progress width animation.
- **Suggested command:** `impeccable animate ./scripts/scenario-dashboard`

### [P2] Touch targets are below common mobile size guidance

- **Location:** `static/app.css:56`, `static/app.css:587`, `static/app.css:645`, `static/app.css:846`
- **Category:** Responsive Design
- **Impact:** 24px to 28px buttons, selects, and inputs are efficient on desktop but difficult on touch devices.
- **Recommendation:** Keep compact desktop controls, but raise hit areas to at least 44px on coarse pointers or mobile breakpoints.
- **Suggested command:** `impeccable adapt ./scripts/scenario-dashboard`

### [P2] Implementation-specific labels leak into generic product surface

- **Location:** `islands/Toolbar.tsx:93`, `islands/Toolbar.tsx:20`, `islands/Toolbar.tsx:33`, `islands/Toolbar.tsx:46`
- **Category:** Product UX
- **Impact:** The dashboard is meant to be swappable for multiple ATProto implementations, but the visible title and persisted preference keys are Garazyk-specific.
- **Recommendation:** Rename the visible product surface around ATProto local-network testing, then scope Garazyk as an implementation or preset.
- **Suggested command:** `impeccable clarify ./scripts/scenario-dashboard`

### [P2] Inline styles make states hard to theme and audit

- **Location:** `routes/run/[runId].tsx:62`, `routes/scenario/[id].tsx:129`, `islands/NetworkStatus.tsx:24`, `components/RunHistory.tsx:14`, `islands/Sidebar.tsx:62`
- **Category:** Maintainability / Theming
- **Impact:** Layout, colors, and spacing are spread across JSX, making responsive and theme changes harder to reason about.
- **Recommendation:** Extract repeated page, panel, empty-state, metadata-row, and action-row classes.
- **Suggested command:** `impeccable extract ./scripts/scenario-dashboard`

### [P3] Progress bar animates width

- **Location:** `static/app.css:975`
- **Category:** Performance
- **Impact:** Width animation can trigger layout work. The impact is probably minor here, but it is avoidable.
- **Recommendation:** Animate a transform-scaled fill or disable the transition for frequent updates.
- **Suggested command:** `impeccable optimize ./scripts/scenario-dashboard`

### [P3] Tables lack captions

- **Location:** `islands/NetworkStatus.tsx:40`, `components/RunHistory.tsx:34`
- **Category:** Accessibility
- **Impact:** Table purpose is visually implied by the card header, but assistive tech benefits from explicit captions or `aria-labelledby`.
- **Recommendation:** Add captions or connect tables to their section headings.
- **Suggested command:** `impeccable harden ./scripts/scenario-dashboard`

### [P3] Browser tab state is not reflected in UI state

- **Location:** `islands/Toolbar.tsx:18`, `islands/Toolbar.tsx:31`, `islands/Toolbar.tsx:44`
- **Category:** Product UX
- **Impact:** Persisted agent mode, topology, and runner values are useful, but there is no visible "restored from last session" affordance. This can surprise users before a run.
- **Recommendation:** Show restored mode as normal editable state and make the run preview explicit before launch.
- **Suggested command:** `impeccable clarify ./scripts/scenario-dashboard`

## Patterns & Systemic Issues

- **Control scope problem:** Network lifecycle, run lifecycle, runner mode, topology, and parameter controls are physically close but conceptually mixed.
- **State language problem:** The same statuses appear as dots, badges, counts, cards, and text without one source of visual truth.
- **Token drift:** The app has a good token base, but inline styles and hardcoded colors bypass it.
- **Accessibility gap:** Native controls are used in many places, but dynamic UI patterns like dialogs, collapsible sections, and live logs need explicit keyboard and screen-reader behavior.
- **Responsive gap:** The mobile breakpoint removes information instead of restructuring it.

## Positive Findings

- The app already uses semantic landmarks: header, aside, main, and footer.
- Most controls are native buttons, inputs, and selects.
- The run progress component has a real `role="progressbar"` with value attributes.
- Service and run data use real tables where comparison matters.
- There is a clear state-machine/runtime architecture, which should make UI state fixes cleaner than ad hoc DOM patching.
- OKLCH tokens exist and already cover most semantic roles.

## Recommended Actions

1. **[P1] `impeccable shape ./scripts/scenario-dashboard`**: Redesign the dashboard information architecture around network setup, active run state, and failure-first triage.
2. **[P1] `impeccable harden ./scripts/scenario-dashboard`**: Fix modal semantics, form labels, collapsible sidebar buttons, log rendering safety, and auto-scroll behavior.
3. **[P1] `impeccable adapt ./scripts/scenario-dashboard`**: Replace the hidden mobile sidebar and increase touch hit areas on narrow or coarse-pointer viewports.
4. **[P2] `impeccable colorize ./scripts/scenario-dashboard`**: Remove hardcoded log colors, literal white, undefined tokens, and inconsistent focus hue.
5. **[P2] `impeccable extract ./scripts/scenario-dashboard`**: Pull repeated inline page and panel styles into reusable classes.
6. **[Final] `impeccable polish ./scripts/scenario-dashboard`**: Re-run visual QA after structural fixes.

Re-run `impeccable audit ./scripts/scenario-dashboard` after fixes to measure improvement.
