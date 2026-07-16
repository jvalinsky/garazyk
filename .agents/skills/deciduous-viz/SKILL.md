# Skill: deciduous-viz

Generate a standalone interactive HTML document from the deciduous decision
graph.  The output visualises goals, decisions, actions, outcomes, and their
relationships alongside narratives, ADRs, and recent git history — all in a
single self-contained file with syntax-highlighted code references.

## When to Use

- "Visualise the decision graph"
- "Generate the graph HTML"
- "Show me the repo progress"
- "Dump deciduous to HTML"
- After significant graph updates, to produce a refreshable snapshot

## Usage

```bash
# Default output: docs/decision-graph.html
deno run -A .agents/skills/deciduous-viz/scripts/generate-html.ts

# Custom output path
deno run -A .agents/skills/deciduous-viz/scripts/generate-html.ts /tmp/graph.html
```

The script reads:
- `docs/graph-data.json` — exported deciduous graph (nodes + edges)
- `.deciduous/narratives.md` — evolution stories
- `docs/adr/*.md` — Architecture Decision Records
- `git log --oneline -30` — recent commit history

Output is a single HTML file with no external dependencies.  Open it in any
browser.  The file can be committed to the repo or hosted statically.

## Design Principles

Follows impeccable.style product register:
- Dark theme (OKLCH), no warm-neutral AI defaults
- ≥4.5:1 body contrast, ≥3:1 large text
- System font stack, 65–75ch line length for prose
- No gradient text, no side-stripe borders, no glassmorphism
- Purposeful motion with `prefers-reduced-motion` fallback
- Semantic z-index scale

## Views

| View | Content |
|------|---------|
| Graph | Force-directed node-link diagram, colour-coded by type, clickable |
| Timeline | Chronological node creation, grouped by day |
| ADRs | Rendered Architecture Decision Records |
| Narratives | Evolution stories from `.deciduous/narratives.md` |
| Stats | Summary metrics, status breakdown, top contributors |
