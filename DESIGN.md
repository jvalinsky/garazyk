---
name: "ATProto Scenario Dashboard"
description: "A tool-native control surface for local ATProto network scenario runs and failure triage."
colors:
  bg-primary: "oklch(96% 0.004 15)"
  bg-secondary: "oklch(99% 0.003 15)"
  bg-tertiary: "oklch(93% 0.005 15)"
  text-primary: "oklch(13% 0.005 200)"
  text-secondary: "oklch(45% 0.005 200)"
  text-tertiary: "oklch(60% 0.003 200)"
  accent: "oklch(52% 0.18 15)"
  success: "oklch(60% 0.18 145)"
  warning: "oklch(75% 0.18 70)"
  destructive: "oklch(58% 0.22 25)"
  info: "oklch(60% 0.15 210)"
  separator: "oklch(85% 0.003 200)"
  separator-secondary: "oklch(91% 0.002 200)"
  log-bg: "oklch(12% 0.005 200)"
  log-text: "oklch(80% 0.01 200)"
  dark-bg-primary: "oklch(18% 0.008 15)"
  dark-bg-secondary: "oklch(24% 0.012 15)"
  dark-bg-tertiary: "oklch(30% 0.014 15)"
  dark-text-primary: "oklch(96% 0.003 200)"
  dark-text-secondary: "oklch(70% 0.005 200)"
typography:
  display:
    fontFamily: "-apple-system, BlinkMacSystemFont, SF Pro Text, Segoe UI, Roboto, Helvetica, Arial, sans-serif"
    fontSize: "30px"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "0"
  headline:
    fontFamily: "-apple-system, BlinkMacSystemFont, SF Pro Text, Segoe UI, Roboto, Helvetica, Arial, sans-serif"
    fontSize: "24px"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "0"
  title:
    fontFamily: "-apple-system, BlinkMacSystemFont, SF Pro Text, Segoe UI, Roboto, Helvetica, Arial, sans-serif"
    fontSize: "19px"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "0"
  body:
    fontFamily: "-apple-system, BlinkMacSystemFont, SF Pro Text, Segoe UI, Roboto, Helvetica, Arial, sans-serif"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.5
    letterSpacing: "0"
  label:
    fontFamily: "-apple-system, BlinkMacSystemFont, SF Pro Text, Segoe UI, Roboto, Helvetica, Arial, sans-serif"
    fontSize: "12px"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "0"
  mono:
    fontFamily: "SF Mono, Menlo, Monaco, Consolas, monospace"
    fontSize: "11px"
    fontWeight: 400
    lineHeight: 1.5
    letterSpacing: "0"
rounded:
  sm: "4px"
  md: "6px"
  lg: "8px"
  full: "50%"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
  2xl: "32px"
  3xl: "48px"
  4xl: "64px"
components:
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.bg-secondary}"
    rounded: "{rounded.md}"
    height: "28px"
    padding: "0 12px"
    typography: "{typography.label}"
  button-secondary:
    backgroundColor: "{colors.bg-secondary}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.md}"
    height: "28px"
    padding: "0 12px"
    typography: "{typography.label}"
  badge-success:
    backgroundColor: "oklch(60% 0.18 145 / 0.08)"
    textColor: "{colors.success}"
    rounded: "{rounded.sm}"
    padding: "2px 8px"
    typography: "{typography.mono}"
  card:
    backgroundColor: "{colors.bg-secondary}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.md}"
    padding: "16px"
  input:
    backgroundColor: "{colors.bg-secondary}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.md}"
    height: "28px"
    padding: "0 12px"
  run-progress:
    backgroundColor: "{colors.bg-secondary}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.md}"
    padding: "12px 16px"
---

# Design System: ATProto Scenario Dashboard

## 1. Overview

**Creative North Star: "Network Flight Deck"**

The dashboard is a dense, tool-native control surface for local ATProto network testing. It should feel like an engineering instrument that keeps topology, service health, run progress, logs, and failures in one readable operational field. Garazyk can be the best-supported implementation, but the design language should describe ATProto roles and capabilities before it describes project-specific names.

The current UI already has useful bones: a fixed toolbar, source-list sidebar, status bar, tabular service state, live progress, scenario cards, and log views. The next design direction should reduce ambiguity in controls, collapse scattered status into coherent state language, and move triage from summary counts into cause-first diagnostic flows.

The system explicitly rejects decorative AppKit imitation, a card-heavy overview that hides relationships, modal-first configuration, status that depends on color alone, and Garazyk-only framing.

**Key Characteristics:**

- Product register, task-first, and dense by design.
- System font, compact type scale, and small radii.
- Restrained OKLCH palette with semantic state colors.
- Split-pane and table patterns preferred over repeated cards when comparison matters.
- State language must be consistent across toolbar, sidebar, status bar, detail pages, logs, and run history.

## 2. Colors

The palette is a warm-neutral operational system with a restrained strawberry accent and explicit semantic colors for test and service state.

### Primary

- **Strawberry Command** (`oklch(52% 0.18 15)`): Primary action color for starting runs, focused controls, selected routes, and the smallest number of brand-bearing moments. It should not decorate inactive surfaces.

### Secondary

- **Transport Blue** (`oklch(60% 0.15 210)`): Live or informational state, including active run progress, topology metadata, runner mode, and service information.

### Tertiary

- **Healthy Green** (`oklch(60% 0.18 145)`): Passing scenarios and healthy services.
- **Fault Red** (`oklch(58% 0.22 25)`): Failed scenarios, unhealthy services, destructive controls, and explicit stop/error states.
- **Latency Amber** (`oklch(75% 0.18 70)`): Skipped scenarios, slow updates, starting/stopping state, compatibility warnings, and stale-but-not-failed conditions.

### Neutral

- **Warm Console Surface** (`oklch(96% 0.004 15)`): Main app background in light mode.
- **Panel Surface** (`oklch(99% 0.003 15)`): Toolbar, sidebar, cards, tables, buttons, and fields at rest.
- **Raised Row Surface** (`oklch(93% 0.005 15)`): Hover rows, table headers, selected sidebar items, and low-emphasis grouping.
- **Console Ink** (`oklch(13% 0.005 200)`): Primary text.
- **Secondary Ink** (`oklch(45% 0.005 200)`): Metadata, table labels, and secondary controls.
- **Tertiary Ink** (`oklch(60% 0.003 200)`): Empty states and low-importance helper text.
- **Log Well** (`oklch(12% 0.005 200)`): Log viewer background. Do not use hardcoded black.
- **Log Text** (`oklch(80% 0.01 200)`): Default log viewer text. ANSI colors may override it inside logs.

### Named Rules

**The State Color Rule.** Red, green, amber, and blue are state language first. Do not use them as decoration.

**The No Literal Black Or White Rule.** New UI must not use `#000`, `#fff`, `white`, or `black`; use tinted OKLCH neutrals.

## 3. Typography

**Display Font:** system UI stack with SF Pro Text on macOS and Segoe UI on Windows.

**Body Font:** the same system UI stack.

**Label/Mono Font:** SF Mono, Menlo, Monaco, Consolas, monospace for run IDs, metrics, logs, command output, and exact protocol values.

**Character:** compact, native, and functional. Type should make status and hierarchy scannable without becoming decorative.

### Hierarchy

- **Display** (700, 30px, 1.2): Rare. Use only for high-level empty states or future overview screens.
- **Headline** (700, 24px, 1.2): Page-level titles if a screen needs one. Avoid turning routine panels into hero sections.
- **Title** (700, 19px, 1.2): Active run title, panel titles, and major detail headings.
- **Body** (400, 15px, 1.5): Explanatory text and normal page content. Cap prose blocks at 65 to 75 characters.
- **Label** (600, 12px, 1.2): Toolbar labels, table headers, status labels, and compact control labels.
- **Mono** (400, 11px, 1.5): Run IDs, service URLs, logs, durations, metrics, and exact scenario identifiers.

### Named Rules

**The Exact Data Rule.** IDs, URLs, ports, roles, capabilities, logs, and durations use monospace or tabular numerals so users can compare them quickly.

**The No Tracked Labels Rule.** Keep new label letter spacing at `0`; density and clarity matter more than decorative uppercase spacing.

## 4. Elevation

The dashboard should be flat by default and use tonal layering before shadows. Borders and surface color communicate containment; shadows are reserved for transient overlays, drawers, and hover affordances that need to separate from scrollable content.

### Shadow Vocabulary

- **Low Interaction Shadow** (`0 1px 3px oklch(0% 0 0 / 0.08)`): Current hover shadow for scenario cards. Use sparingly and prefer row highlighting in dense lists.
- **Medium Overlay Shadow** (`0 2px 8px oklch(0% 0 0 / 0.12)`): Small floating surfaces if needed.
- **High Overlay Shadow** (`0 4px 16px oklch(0% 0 0 / 0.15)`): Drawers and settings surfaces.

### Named Rules

**The Flat-Until-Temporary Rule.** Persistent panels should use borders and tonal surfaces. Temporary overlays may use shadows.

## 5. Components

### Buttons

- **Shape:** compact rounded rectangle, 6px radius.
- **Primary:** strawberry command fill, 28px height, 12px horizontal padding, label typography. Primary action copy must name the scope when ambiguity is possible.
- **Hover / Focus:** hover shifts surface or brightness; focus uses a 2px visible outline with offset.
- **Secondary:** panel surface with border, used for reversible or lower-risk commands.
- **Destructive:** border and text in Fault Red unless the action is immediate and dangerous enough to require filled destructive treatment.

### Badges

- **Style:** full border, soft tinted background, semantic text color.
- **State:** badges must pair color with text, for example `running`, `failed`, `PDS2`, or `Agent`.
- **Scope:** badges communicate state or mode, not decoration.

### Cards / Containers

- **Corner Style:** 6px radius.
- **Background:** Panel Surface at rest, Raised Row Surface for row and hover states.
- **Shadow Strategy:** no shadow at rest.
- **Border:** 1px separator border.
- **Internal Padding:** 12px to 16px for dense panels, 24px only for empty states or explanatory blocks.
- **Use:** cards are acceptable for isolated panels, but scenario comparison, run results, and service health should prefer tables, split panes, or grouped lists.

### Inputs / Fields

- **Style:** 28px height, 6px radius, panel surface, separator border.
- **Focus:** accent border plus visible ring.
- **Error / Disabled:** disabled opacity must not hide the label or current value. Error states need text in addition to color.

### Navigation

- **Toolbar:** fixed top control rail for topology, runner mode, run control, and global state.
- **Sidebar:** source-list navigation for scenario discovery and topology context. It should not be the only place where network state appears.
- **Status Bar:** global footer for persistent, low-noise facts such as selected implementation, active run, service count, and primary endpoint.
- **Mobile:** sidebar collapses structurally. Primary run and triage actions must remain reachable without relying on hidden navigation.

### Run Progress

The run progress panel is the signature live component. It should show run state, elapsed time, total and remaining scenarios, current scenario, activity freshness, and mode badges in one compact area. Stale activity must be textual, not only color.

- **Layout & Structure:** Tinted background with a fine border (`var(--separator-color)`) and subtle shadow (`var(--shadow-sm)`). Features a segmented header and body separated by a hairline border (`var(--separator-color-secondary)`).
- **Progress Track:** A highly precise, fine progress track with a `4px` height and `var(--radius-sm)` curvature.
- **Progress Fill:** The bar fills with `var(--color-accent)` using a custom smooth decelerated easing (`width 0.6s cubic-bezier(0.25, 1, 0.5, 1)`).
- **Glowing Tip:** Features an overlay tip (`::after`) with a soft glow (`8px` width, `rgba(255, 255, 255, 0.4)` background, and `2px` blur) to emphasize incremental completion.
- **Activity Indicator:** Pairs color states (`var(--color-success)`, `var(--color-warning)`, `var(--color-destructive)`) with status text and active box-shadow glows (`0 0 6px`) to indicate update freshness dynamically.

### Log Viewer

The log viewer is a diagnostic surface, not a decoration. It should use Log Well and Log Text tokens, preserve ANSI rendering, expose copyable text, show source and freshness metadata, and avoid hardcoded black, white, or arbitrary inline borders.

## 6. Do's and Don'ts

### Do:

- **Do** keep topology, runner mode, implementation under test, and active run state visible while a run is active.
- **Do** place action scope next to controls, especially start, stop, restart, topology changes, runner selection, and scenario parameters.
- **Do** use tables, split panes, and grouped lists when users need to compare services, scenarios, steps, logs, or failures.
- **Do** pair every color-coded state with text or an icon label.
- **Do** make failed scenarios lead directly to the failed step, relevant service, log excerpt, and topology condition.
- **Do** keep Garazyk-specific labels as implementation details; first describe ATProto roles, capabilities, services, and runners.

### Don't:

- **Don't** make the dashboard feel Garazyk-only when the model should fit swappable ATProto service implementations.
- **Don't** use a card-heavy overview that hides relationships between topology, services, scenarios, logs, and failures.
- **Don't** leave controls with unclear scope, especially start, stop, restart, topology changes, runner selection, and scenario parameters.
- **Don't** rely on color alone for service health, scenario status, run state, compatibility, or stale activity.
- **Don't** use modal-first configuration when inline, staged, or panel-based controls would keep context visible.
- **Don't** use decorative AppKit imitation, hero metrics, gradient text, glass effects, ornamental motion, side-stripe accents, hardcoded black, or hardcoded white.
