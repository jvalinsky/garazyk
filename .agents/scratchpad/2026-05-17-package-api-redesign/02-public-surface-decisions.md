# Public Surface Decisions

Date: 2026-05-17

## Decisions

### Root exports are curated stable APIs

Package root exports should be the smallest useful public API for ordinary Deno/JSR consumers. Internal tooling, compatibility shims, and side-effectful modules move to explicit subpaths.

### Legacy orchestration moves to explicit subpaths

ATProto network orchestration stays available, but not from generic package roots. Consumers should import orchestration from `@garazyk/laweta/atproto-network` or hamownia runner subpaths.

Implementation decision: orchestration moved to `@garazyk/hamownia/atproto-network`, not a `laweta` subpath, because it legitimately composes topology compilation, diagnostics, OTel, and scenario run context. `laweta` keeps only generic Docker primitives on root plus a narrow `@garazyk/laweta/atproto-runtime` compatibility subpath for runtime helpers that do not import `schemat` or `hamownia`.

### Generated lexicon types are documented or hidden from root docs

The generated `lexicons.ts` file is useful but too large for root documentation linting in its current form. Root exports should expose only the stable generated helper types needed by `XrpcClient`, while the full generated surface remains on an explicit `./lexicons` subpath.

Implementation decision: root `GeneratedClient` and helper aliases are compact documentation-safe proxy types. Exact generated Lexicon types remain on `@garazyk/gruszka/lexicons`, and internal test helpers cast to that exact type where needed.

### Scenario globals remain compatibility-only

Mutable scenario globals such as `PDS1` and `SERVICE_URLS` are retained on `@garazyk/hamownia/config` for existing scenarios. New code should prefer explicit `createScenarioConfig(...)` and `createCharacterRegistry(...)`.

## Deprecation Policy

Because the packages are still `0.1.0-alpha.1`, breaking root export cleanup is acceptable. Compatibility paths should be documented for one alpha cycle where internal scripts still depend on old imports.
