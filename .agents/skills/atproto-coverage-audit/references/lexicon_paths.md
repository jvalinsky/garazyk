# Lexicon Paths

- Lexicon JSON files are stored under `lexicons/`.
- Generated TypeScript is written to `packages/atproto-client/lexicons.ts`.
- The generator is `packages/atproto-client/scripts/generate.ts`.
- Method IDs come from each lexicon JSON `id` field.
- Method definitions are lexicon `defs.main` entries with `type` of `query`, `procedure`, or `subscription`.

Regenerate after lexicon changes:

```bash
deno run -A packages/atproto-client/scripts/generate.ts
```
