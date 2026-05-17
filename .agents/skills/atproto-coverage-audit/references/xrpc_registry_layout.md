# XRPC Client Layout

Garazyk's current Deno workspace does not keep a native XRPC route registry in this repository. Coverage is evaluated from:

- lexicon JSON under `lexicons/`,
- generated client metadata in `packages/gruszka/lexicons.ts`,
- dynamic dispatch in `packages/gruszka/client.ts`,
- raw transport helpers in `packages/gruszka/transport.ts`,
- scenario endpoint usage under `scripts/scenarios/scenarios/`.

When auditing a missing endpoint, determine whether the gap is in lexicon generation, typed client surface, raw scenario usage, or the external service being exercised by the topology.
