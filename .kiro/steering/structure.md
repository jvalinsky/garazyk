# Project Structure

## Runtime Source Tree

```text
Garazyk/Sources/
  Admin/          - admin endpoints and moderation flows
  App/            - application composition, configuration, explorer, UI, helper services
  AppView/        - read-model and browser-facing data helpers
  Auth/           - JWT, OAuth, DPoP, TOTP, WebAuthn
  Auth/Crypto/    - crypto helpers used by auth flows
  Auth/Verifier/  - verification helpers and request checks
  Auth/OAuthProvider/ - OAuth provider support code
  Auth/PDS/       - PDS auth integration points
  Blob/           - blob storage and blob-specific operations
  CLI/            - `kaszlak` command-line surface
  Compat/         - macOS and GNUstep compatibility code
  Core/           - CBOR, CAR, CID, MST, DID, shared primitives
  Database/       - service DBs, actor stores, migrations, pools, monitoring
  Email/          - provider integrations and secret resolution
  Federation/     - cross-PDS and federation behavior
  Identity/       - handle and DID resolution, PLC client logic
  Lexicon/        - lexicon and schema helpers
  Media/          - media helpers and processing
  Metrics/        - runtime metrics
  Network/        - HTTP server, route registration, XRPC dispatch
  PLC/            - `campagnola` PLC server code
  Relay/          - standalone relay server entrypoints
  Repository/     - repository state, commits, blob and MST interactions
  Security/       - security-sensitive helpers
  Services/       - shared service-layer abstractions
  Sync/           - firehose, relay, and subscribeRepos behavior
```

## Key Entry Points

- `Garazyk/Sources/CLI/main.m` - CLI entrypoint
- `Garazyk/Sources/PLC/main.m` - PLC server entrypoint
- `Garazyk/Sources/App/PDSApplication.m` - application startup and service composition
- `Garazyk/Sources/Network/PDSHttpServerBuilder.m` - route registration

## Route Ownership

- `/xrpc/*` - `XrpcDispatcher`, `XrpcMethodRegistry`, and domain method modules
- `/api/pds/*` - `PDSHttpServerBuilder` plus `ExploreHandler`
- `/ui` - `PDSHttpServerBuilder` plus `CappuccinoUIHandler`
- `/api/mst/*`, `/api/relay/*`, `/metrics`, `/.well-known/*`, and admin routes - server builder plus their specific route packs and handlers

## Tests

`Garazyk/Tests/` broadly mirrors the runtime structure. New test classes must be registered in `Garazyk/Tests/test_main.m`.

## Supporting Directories

```text
docs/                - canonical contributor docs (VitePress)
docs/guides/         - specialized and older deep-reference guides
docs/architecture/   - diagrams, analyses, and architecture notes
docs/security/       - security reports and hardening notes
docs/tests/          - detailed test catalog
docker/              - deployment assets
scripts/             - utility scripts
skills/              - audit and helper skills
lexicons/            - AT Protocol lexicons
fuzzing/             - fuzz infrastructure
examples/            - example and tutorial assets
```

## Deployment

Production Compose lives under `docker/pds/`. Do not run deployment Compose commands from the repo root.
