# Garazyk `tui` Research Findings

I searched for layout engines, Elm/TEA-style architecture, ANSI theming, screen-buffer rendering, key parsing, and Unicode width handling. Most of the evidence came from active issue/PR discussions in adjacent TUI ecosystems, so the findings below reflect practical implementation tradeoffs rather than formal specs.

## 1) TUI layout engines: tree solver vs. flex/grid-style engines

The layout discussion in terminal UI projects consistently points toward a richer constraint model than a simple split-tree solver. Ratatui’s layout work, for example, has evolved around constraint priorities such as `Min`, `Max`, `Length`, `Percentage`, `Ratio`, and `Fill`, and the community has repeatedly discussed moving layout logic to a dedicated engine like Taffy rather than growing the solver inside the TUI crate itself. The recurring reason is that once you want stability across edge cases, the algorithm stops being “just split a rect” and starts needing explicit tie-breaking, min/max bounds, and deterministic rounding rules.

Compared with a basic tree solver, flexbox/grid-oriented approaches expose features that matter in real UIs: wrap, gap, grow/shrink, minmax bounds, and aspect ratio. That matters because terminal layouts often need more than division into rows/columns; they need nested, adaptive regions that can overflow gracefully, wrap text or panes, and preserve proportions under resize. The likely gap for Garazyk’s `solveLayout()` is not just “more features,” but whether it has a principled story for constraint satisfaction when the parent size is too small or when several children all want the remainder.

**Code review implication:** if `solveLayout()` is currently a tree splitter, verify whether it has explicit min/max validation, overflow behavior, wrap semantics, and deterministic rounding. The implementation should be compared against the kinds of constraint priority systems used by Ratatui/Taffy-like engines, not only against simpler TUI libraries.

## 2) Sans-IO TUI architecture: how close is it to TEA?

The strongest TEA/sans-IO examples in TypeScript and Rust all use a very sharp boundary: pure state update and pure view rendering, with commands/subscriptions or runtime services handling all side effects outside the model. In practice, the cleanest implementations keep `update()` free of terminal I/O, keep `view()` as a pure render of state, and model input as events/messages that come in through a runtime layer. That separation is what makes tests and replayability straightforward.

Where things get blurry is when a library claims to be reusable primitives but still leaks environment state, mutable globals, or IO decisions into the rendering path. Theme selection is a common place for that leak, as is keyboard parsing if it depends on terminal mode, current environment variables, or one-time detection at import. If Garazyk’s `tui` package is meant to be reusable, the boundary should stay “renderer consumes a snapshot of state and a theme; runtime owns terminal setup, input parsing, and environment detection.”

**Code review implication:** verify that the `tui` primitives are sans-IO in the TEA sense. The package should not read environment or mutate terminal state as a side effect of ordinary rendering calls, and it should not require the consumer to coordinate hidden global state to get correct output.

## 3) ANSI 16-color theme design: palette semantics, light themes, and `COLORFGBG`

The theme discussions in the ecosystem point to one consistent rule: a 16-color ANSI palette is workable, but only if the palette is treated as semantic and contrast-aware. Base16-style systems work because they define named roles and provide both dark and light variants, while ANSI16-focused themes work best when they keep foreground colors legible across terminals rather than assuming a single dark-background default. A recurring pitfall is using bright-black as a generic “dim” token; that is often fine on dark terminals and often unreadable on light ones.

`COLORFGBG` is useful for auto-detecting background brightness, but it is not universal and should not be the sole source of truth. The best practice in the wild is usually: detect if you can, allow user override, and fall back to a safe default. Another practical lesson is that “theme selection” should not be a hidden global mutable choice; it should ideally be explicit configuration that can be injected into renderers and components. The report also reinforces that low-contrast surface colors, especially blue surfaces on dark terminals, can be brittle because many users’ terminal blue is already visually loud.

**Code review implication:** the current `lightTheme`, `classicTheme`, and `COLORS` exports should be checked for semantic correctness and accessibility. In particular, verify whether `textSecondary` and `textMuted` are actually distinguishable beyond a comment, whether surface-elevated blue remains legible on dark terminals, and whether theme detection is unnecessarily frozen at import time.

## 4) Terminal screen-buffer rendering: diffing, double buffering, and resize behavior

The rendering pattern used by mature TUIs is almost always some form of virtual buffer + diff + ANSI emission. The goal is to compute a minimal set of cell changes, not to clear the whole screen every frame. That reduces flicker, improves throughput, and avoids wasting terminal bandwidth. Adjacent projects also highlight that frame timing matters: clearing and redrawing a full screen can be visibly unstable, while diff-based rendering and synchronized update strategies produce smoother output.

The crucial implementation detail is that the screen buffer becomes stateful geometry, not just a string builder. Once you have a cached cell grid, resize becomes a real concern: the buffer must either be recreated, resized, or invalidated when the terminal size changes. Otherwise the renderer can compute diffs against the wrong geometry, which leads to stale cells, clipping artifacts, or misaligned output. The same pattern applies to environment-controlled rendering decisions like `NO_COLOR`: if the renderer reads it once at import time, later changes in the process environment will never be seen.

**Code review implication:** confirm whether `ScreenBuffer` is explicitly resize-aware and whether its diff baseline is invalidated on terminal size changes. Also verify that `NO_COLOR` is not locked in at module import if runtime reconfiguration or test overrides are expected.

## 5) Terminal key event parsing: legacy escapes, Kitty protocol, and paste handling

The input side of modern terminal UIs is messy. There is the old world of ambiguous escape sequences, where many keys collapse into the same bytes, and there is the modern world of Kitty-style CSI-u reporting with press/repeat/release semantics and richer modifier data. Real implementations increasingly parse both: legacy CSI/SS3 for compatibility, Kitty protocol for fidelity, and bracketed paste for safety. The consistent warning from the ecosystem is that `Esc` is ambiguous, many control keys collide, and pasted text needs to be distinguished from actual keystrokes or it will accidentally trigger commands.

That means a `parseKey()` implementation should be judged by coverage, not just by a few happy-path examples. It should recognize the common legacy sequences, gracefully handle ambiguous prefixes, preserve printable text where possible, and optionally understand bracketed paste and focus events. The presence of Kitty protocol support in neighboring projects is a good indicator that “good enough” parsing in 2026 usually means support for CSI-u plus a compatibility fallback rather than a small handwritten switch over a dozen keys.

**Code review implication:** treat `parseKey()` as a compatibility surface. Check whether it covers CSI/SS3 legacy keys, Kitty CSI-u, modifier combinations, release/repeat events, paste events, and ambiguous escape timing. If bracketed paste is not handled, pasted commands may be interpreted as live input.

## 6) Wide character handling: CJK, emoji, ZWJ, combining marks, and graphemes

Unicode width handling is one of the most common sources of TUI corruption. The ecosystem broadly agrees that simple per-codepoint width rules are not enough for modern text. CJK wide/fullwidth characters, emoji, ZWJ sequences, variation selectors, and combining marks all complicate the notion of “how many terminal cells does this occupy?” Libraries that treat width as a fixed property of a single codepoint often drift as soon as they encounter real-world text.

There is also a tension between “Unicode theory” and “terminal reality.” Some tools lean on grapheme-aware segmentation; others intentionally sum codepoint widths because that better matches common terminal behavior. The safest practical stance for a TUI library is to use a width engine that knows about emoji, CJK ambiguity, combining marks, and zero-width joiners, and to back it with tests in multiple terminals. Text wrapping is another danger zone: if spacing is collapsed or ANSI preservation is partial, the renderer may destroy layout even if width measurement is otherwise correct.

**Code review implication:** check whether `getCharWidth()` and any wrapping/truncation helpers are grapheme-aware enough for emoji and ZWJ sequences. Also verify that ANSI escape sequences are preserved faithfully during wrapping, since partial ANSI preservation can break styling and make width calculations drift.

---

## Review Checklist

| Concern | What the research suggests | What to verify in Garazyk `tui` |
|---|---|---|
| `solveLayout()` gives remainder pixels to the last growing child | Many engines treat remainder allocation and rounding as a deliberate policy, not an accident | Ensure the bias is intentional, documented, and visually stable; consider round-robin or balanced remainder distribution if needed |
| `ScreenBuffer` resize handling | Diff buffers must be invalidated or resized when geometry changes | Confirm there is a resize path, or that callers are required to recreate the buffer explicitly |
| `COLORS` getter-based re-export is deprecated but exported | Re-export shortcuts often become maintenance debt once theming stabilizes | Decide whether it should remain part of the public API or be removed in a compatibility window |
| `lightTheme` uses `textSecondary` and `textMuted` both as `BRIGHT_BLACK` | Bright-black is often unreadable on light themes, and “dim” usually needs a semantic rather than literal palette slot | Verify there is an actual visual distinction, not just a comment; consider faint/dim styling or a different token mapping |
| `classicTheme` surface elevated is `BLUE` | Blue surfaces can become harsh or unreadable on dark terminals with blue-dominant palettes | Test whether this choice has sufficient contrast across common terminal themes |
| `parseKey()` coverage | Modern TUI parsers typically support legacy CSI/SS3, Kitty CSI-u, and bracketed paste | Check for coverage of ambiguous escape sequences, modifiers, repeat/release, paste, and focus events |
| `command.ts` `BoxCommand.clip` ignored by `rasterize()` | Clipping needs to be honored by the rasterizer or nested content will bleed | Verify clipping is enforced at render time for nested and overflowing content |
| `focus.ts` `jump(index)` is 0-based but comments describe 1-based keys | Input-model mismatches are a classic off-by-one trap | Align comments, UI labels, and runtime indexing semantics; add tests for bounds and wrap behavior |
| `layout_tree.ts` lacks validation that fixed sizes fit within bounds | Layout solvers usually need explicit overflow/underflow behavior | Add validation or graceful degradation when fixed sizes exceed the available rectangle |
| `renderer.ts` reads `NO_COLOR` at import time | Import-time env reads freeze behavior and make tests/runtime changes impossible | Move environment detection to initialization or allow explicit config injection |
| `text.ts` ANSI preservation is partial; `wrapWord()` can collapse spacing; width logic is not grapheme-aware | Text measurement and styling preservation must be aligned | Add tests for ANSI round-tripping, spacing preservation, emoji/ZWJ sequences, and mixed-width text |
| `theme.ts` global mutable state and one-time environment detection | Global theme state is hard to reason about and leaks across consumers | Prefer injected theme objects or explicit initialization; avoid hidden process-wide mutation |

## Cross-Cutting Concerns

1. **Layout, wrapping, and width must agree.** If the layout solver, text wrapper, and renderer use different width rules, the UI will drift under CJK, emoji, and ANSI-styled text.
2. **Resize is a first-class event.** Any cached screen buffer, focus index, or layout tree needs a clear resize/update story.
3. **Avoid import-time environment decisions.** Theme selection and color disabling should be configurable and testable, not fixed when the module loads.
4. **Global mutable theme state will leak across packages.** If `tui` is reused by multiple consumers in the same process, a process-wide mutable theme can create surprising cross-app effects.
5. **Input parsing needs a compatibility matrix.** Legacy terminals, Kitty protocol terminals, tmux, and bracketed paste all behave differently; test coverage should reflect that reality.
6. **Accessibility and readability are not optional.** Terminal palettes that look fine on a developer’s preferred dark terminal may fail on light themes, high-contrast terminals, or color-deficient setups.
7. **The same primitives likely affect other packages.** Any fix to width handling, buffering, theming, or key parsing will probably cascade into higher-level packages that rely on `tui` as a rendering or input foundation.

## Bottom line

The strongest theme across all six searches is that mature TUIs treat layout, rendering, input, and text measurement as separate but tightly coordinated subsystems. For Garazyk’s `tui` package, the likely risks are not just missing features; they are mismatched assumptions between subsystems: layout rounding versus rendering, theme semantics versus terminal palette reality, and width calculation versus actual grapheme behavior. The highest-value review work is therefore to check the boundaries between these subsystems, not just the individual functions in isolation.
