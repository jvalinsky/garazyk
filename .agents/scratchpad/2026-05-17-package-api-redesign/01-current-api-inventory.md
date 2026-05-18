# Current API Inventory

Date: 2026-05-17

## Package Roots

- `@garazyk/laweta` root currently exports every Docker module plus `docker.ts`, which pulls in `@garazyk/schemat` and `@garazyk/hamownia`.
- `@garazyk/gruszka` root currently exports `client.ts`, `transport.ts`, `firehose.ts`, `lexicons.ts`, and all hand-written namespace clients.
- `@garazyk/schemat` root currently exports topology models, schemas, registry helpers, compiler helpers, list helpers, and `docker_config.ts` runtime helpers.
- `@garazyk/hamownia` root currently exports scenario authoring APIs, runner/orchestration helpers, diagnostics, progress, instrumentation, OTel, mutable config globals, and mock Twilio.

## Findings

- Root barrels use broad `export *`, which expands JSR public docs beyond stable package APIs.
- `laweta` root is not generic because it re-exports ATProto topology and hamownia diagnostics.
- `gruszka` has a strong generated API but also exposes hand-written clients with `Promise<any>` returns.
- `schemat` mixes pure topology parsing/resolution with filesystem/env/git helpers.
- `hamownia` root imports mutable env/topology config at module load.

## Verification Baseline

- `deno check packages/*/mod.ts`: passed during review.
- `deno task boundaries`: passed with known baseline violations.
- `deno doc --lint packages/laweta/mod.ts packages/gruszka/mod.ts packages/schemat/mod.ts packages/hamownia/mod.ts`: failed with 1036 documentation lint errors during review.

## Boundary Baseline

Current known baseline includes laweta dependencies on schemat/hamownia and a schemat test dependency on hamownia. The redesign should eliminate laweta root violations and only keep intentional orchestration dependencies behind explicit subpaths.

## Final API Inventory After Implementation

- `@garazyk/laweta` root exports generic Docker API, Compose, event watcher, health, stats sampler, and Docker runner utilities. `laweta` no longer imports `schemat` or `hamownia`.
- `@garazyk/laweta/atproto-runtime` exports dependency-free local ATProto runtime compatibility helpers.
- `@garazyk/gruszka` root exports `XrpcClient`, transport/errors, `RawClient`, firehose primitives, and compact generated proxy aliases. Full generated Lexicon definitions are on `@garazyk/gruszka/lexicons`; hand-written clients are on `@garazyk/gruszka/legacy-clients`.
- `@garazyk/schemat` root exports pure topology registry, resolver, manifest, and compiler APIs. Filesystem/env/git helpers are on `@garazyk/schemat/runtime`; raw Zod schema utilities are on `@garazyk/schemat/topology-schema`.
- `@garazyk/hamownia` root exports scenario authoring primitives, assertions, metadata, selector helpers, and selected runner types. Mutable config globals and character registry compatibility APIs are on `@garazyk/hamownia/config`; network orchestration is on `@garazyk/hamownia/atproto-network`.
