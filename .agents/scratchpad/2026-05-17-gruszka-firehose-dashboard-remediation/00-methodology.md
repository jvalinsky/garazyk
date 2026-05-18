# Methodology

## Prompt

Fix the four review findings covering generated Gruszka XRPC typing, generated binary XRPC transport, subscribeRepos DAG-CBOR frame decoding, and dashboard report JSON validation.

## Skills

- `using-deciduous`: create goal, decision, action, outcome, and scratchpad links.
- `garazyk-testing`: Deno workspace verification and package quality gates.
- `atproto-lexicon`: XRPC body encoding and subscription frame wire-format rules.
- `zod`: boundary validation guidance; repository uses Zod v3 in dashboard.

## Deciduous Nodes

- Goal: 47, Fix generated XRPC typing, firehose decoding, and report import validation.
- Decision: 48, Use exact generated gruszka types at root.
- Decision: 49, Route generated binary XRPC methods by lexicon encoding metadata.
- Decision: 51, Decode subscribeRepos as two concatenated DAG-CBOR objects.
- Decision: 50, Validate dashboard report JSON with Zod v3 safeParse.
- Action: 52, Phase 1: Gruszka generated contract and binary transport.
- Action: 55, Phase 2: Firehose frame parser and scenarios.
- Action: 54, Phase 3: Dashboard report validation.
- Action: 53, Final integration verification.

## Working Rules

- Do not hand-edit generated `packages/gruszka/lexicons.ts`; update `packages/gruszka/scripts/generate.ts` and run `deno task generate-client`.
- Preserve `FirehoseEvent.payload` as the raw frame for compatibility while adding decoded `header` and `body`.
- Validate dashboard report JSON at the file boundary and skip invalid files with diagnostics.
- Leave unrelated existing worktree changes untouched.
- Main agent owns Deciduous, scratchpads, integration, and final verification.
