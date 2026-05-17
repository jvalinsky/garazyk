# Lexicon Paths

- Lexicon JSON files are stored under `lexicons/`.
- Generated TypeScript is written to `packages/gruszka/lexicons.ts`.
- The generator is `packages/gruszka/scripts/generate.ts`.
- Method IDs come from each lexicon JSON `id` field.
- Method definitions are lexicon `defs.main` entries with `type` of `query`, `procedure`, or `subscription`.

Regenerate after lexicon changes:

```bash
deno run -A packages/gruszka/scripts/generate.ts
```
