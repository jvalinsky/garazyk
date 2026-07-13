# TUI Edge Case Library

Curated test scenarios that exercise terminal rendering edge cases for semantic
recognition training.

## Edge Case Taxonomy

| Scenario             | What It Tests                                  | App Used            | Test File                                              |
| -------------------- | ---------------------------------------------- | ------------------- | ------------------------------------------------------ |
| CJK Fullwidth        | 中文/日本語/한국어 width calculation, wrapping | glow, less          | [cjk_fullwidth.yaml](cjk_fullwidth.yaml)               |
| Emoji ZWJ            | Zero-width joiners, skin tones, flags          | glow, less          | [emoji_zwj.yaml](emoji_zwj.yaml)                       |
| RTL Text             | Bidirectional layout, cursor placement         | glow, less, vim     | [rtl_text.yaml](rtl_text.yaml)                         |
| Combining Marks      | Precomposed vs decomposed equivalence          | less, vim           | [combining_marks.yaml](combining_marks.yaml)           |
| Wide Terminal        | 200+ column layout, horizontal scroll          | htop, btop, lazygit | [wide_terminal.yaml](wide_terminal.yaml)               |
| Tiny Terminal        | Layout collapse, text truncation (20×10)       | htop, btop          | [tiny_terminal.yaml](tiny_terminal.yaml)               |
| Resize During Render | Diff buffer invalidation                       | btop                | [resize_during_render.yaml](resize_during_render.yaml) |
| ANSI Torture         | Nested SGR, OSC, DCS sequences                 | cat (crafted file)  | [ansi_torture.yaml](ansi_torture.yaml)                 |
| Sixel Graphics       | Image data in terminal                         | notcurses-demo      | [sixel_graphics.yaml](sixel_graphics.yaml)             |
| Long Lines           | 1000+ char line wrapping                       | less, glow          | [long_lines.yaml](long_lines.yaml)                     |
| Zero-Width Chars     | U+200B invisible width                         | crafted file        | [zero_width.yaml](zero_width.yaml)                     |
| Escape Flooding      | PTY buffer overflow, CPU spike                 | flood harness       | [escape_flood.yaml](escape_flood.yaml)                 |
| Bracketed Paste      | Paste vs typed input distinction               | vim, nano           | [bracketed_paste.yaml](bracketed_paste.yaml)           |

## Usage

```bash
# Run a single edge case scenario
node corpus/runner.mjs edge_cases/cjk_fullwidth.yaml --report reports/cjk.json

# Run all edge cases
for f in edge_cases/*.yaml; do
  node corpus/runner.mjs "$f" --report "reports/$(basename $f .yaml).json"
done
```

## Expected Behavior

Each edge case scenario documents expected semantic detection behavior:

- **PASS**: Semantic detectors correctly identify elements despite edge case
- **SKIP**: Edge case not applicable to current terminal/app combination
- **FAIL**: Semantic detection regression — file a bug
