---
title: Lexicon Resolution Pipeline
---

# Lexicon Resolution Pipeline (`@garazyk/gruszka`)

Resolves an AT Protocol lexicon from an NSID string to a fully-validated
`LexiconDoc` through the DNS → DID → record fetch pipeline. The entire
pipeline is implemented as a sans-IO state machine — all side effects
(DNS queries, HTTP requests) are injected through port interfaces.

## Package Structure

```
packages/gruszka/lexicon_resolution/
├── types.ts            Layer 1: Domain types, Result, ResolutionError
├── core.ts             Layer 2: Pure validation (NSID, domain derivation, DID parsing)
├── resolver.ts         Layer 2: Sans-IO state machine (init → update → terminal)
├── ports.ts            Layer 3: IO port interfaces (DnsResolver, DidResolver, RecordFetcher)
├── adapters.ts         Layer 3: Deno-specific port implementations
├── cache.ts            Layer 5: Transparent caching layer (InMemoryCache, DiskCache, wrappers)
├── mod.ts              Layer 4: Orchestration (resolveLexicon wires state machine + ports + cache)
```

Tests: `types.test.ts`, `core.test.ts`, `resolver.test.ts`, `adapters.test.ts`, `mod.test.ts`,
`cache.test.ts`, `integration.test.ts` — 236 unit + 6 integration tests.

## Five-Layer Architecture

### Layer 1: Domain Types (`types.ts`)

Branded primitive types (`Nsid`, `Did`, `Domain`) and the `Result<T, E>` discriminated
union used throughout the pipeline. No I/O, no logic — just type definitions and
branding helpers (`asNsid`, `asDid`, `asDomain`).

### Layer 2: Pure Logic (`core.ts`, `resolver.ts`)

- **`core.ts`** — Stateless validation and parsing: `isValidNsid()`,
  `deriveDomain()`, `parseDidFromTxt()`, `buildXrpcUrl()`, `verifyRecordId()`.
- **`resolver.ts`** — The sans-IO state machine: `init(nsid)` bootstraps the
  state, `update(state, msg)` advances through DNS → DID → record fetch → verify.
  The state machine emits commands (`ResolverCmd`) and consumes messages
  (`ResolverMsg`). Terminal states are `resolved` (success) or `failed` (error).

### Layer 3: IO Ports + Adapters (`ports.ts`, `adapters.ts`)

- **Port interfaces** — `DnsResolver.resolveTxt(domain)`, `DidResolver.resolve(did)`,
  `RecordFetcher.fetch(endpoint)`. Each returns `Result<T, string>`.
- **Deno adapters** — `DenoDnsResolver` (wraps `Deno.resolveDns`),
  `HttpDidResolver` (handles `did:plc` and `did:web`), `HttpRecordFetcher`
  (extracts `.value` from the AT Protocol `getRecord` envelope).

### Layer 4: Orchestration (`mod.ts`)

The `resolveLexicon(nsid, ports)` function wires everything together:

1. Bootstraps the state machine with `init(nsid)`
2. Optionally wraps ports with caching decorators via `applyCaches()`
3. Drives a `while(true)` loop: `executeCommand(cmd, ports)` → `update(state, msg)`
4. Returns `Result<LexiconDoc, ResolutionError>`

### Layer 5: Caching (`cache.ts`)

Transparent caching layer that wraps port implementations:

- **`KeyValueCache<T>`** — Generic interface with `get`, `set`, `evictExpired`, `clear`
- **`InMemoryCache<T>`** — `Map`-backed with lazy TTL eviction
- **`DiskCache<T>`** — Filesystem-backed with djb2-hashed filenames
- **`CachingDnsResolver`**, **`CachingDidResolver`**, **`CachingRecordFetcher`** —
  Decorator wrappers that cache successes and pass through errors

Caching is opt-in via `ResolutionPorts.cache` — each port can be cached independently.

## Usage

### Basic resolution

```ts
import { DenoDnsResolver, HttpDidResolver, HttpRecordFetcher } from "./adapters.ts";
import { resolveLexicon } from "./mod.ts";

const ports = {
  dns: new DenoDnsResolver(),
  did: new HttpDidResolver(),
  record: new HttpRecordFetcher(),
};

const result = await resolveLexicon("app.bsky.feed.post", ports);
if (result.ok) {
  console.log("Resolved:", result.value.id);
  // result.value is a fully-validated LexiconDoc ready for code generation
} else {
  console.error("Failed:", result.error.type, result.error);
}
```

### With caching

```ts
import { InMemoryCache, DiskCache } from "./cache.ts";

const ports = {
  dns: new DenoDnsResolver(),
  did: new HttpDidResolver(),
  record: new HttpRecordFetcher(),
  cache: {
    // Cache DNS results for 1 hour
    dns: new InMemoryCache<string[][]>({ ttlMs: 3600_000 }),
    // Cache DID documents for 24 hours on disk
    did: new DiskCache<DidDocument>({ directory: "/tmp/did-cache", ttlMs: 86_400_000 }),
    // Cache lexicon records in memory for 24 hours
    record: new InMemoryCache<LexiconDoc>({ ttlMs: 86_400_000 }),
  },
};

// Repeated calls for the same NSID hit the cache — no network requests.
const r1 = await resolveLexicon("app.bsky.feed.post", ports);
const r2 = await resolveLexicon("app.bsky.feed.post", ports);
// r2 returns instantly from cache.
```

## Error Handling

All errors are returned as `Result<T, ResolutionError>` — never thrown. The
`ResolutionError` discriminated union covers every failure mode:

| Variant | Stage | Example |
|---|---|---|
| `InvalidNsid` | Validation | `"xy"` — too short |
| `DnsQueryFailed` | DNS | NXDOMAIN, SERVFAIL, timeout |
| `NoLexiconDnsRecord` | DNS parsing | No `did=` in TXT records |
| `DidResolutionFailed` | DID | HTTP 404, network error |
| `PdsEndpointMissing` | PDS discovery | No `AtprotoPersonalDataServer` service |
| `RecordFetchFailed` | Record fetch | HTTP 503, connection reset |
| `RecordVerificationFailed` | Verification | Lexicon `id` doesn't match NSID |

Each error variant carries contextual fields (e.g. `domain`, `did`, `endpoint`,
`nsid`) for diagnostics.

## Testing

- **Unit tests** (236) — Each layer tested independently with stub ports
- **Integration tests** (6) — Full pipeline with real `DenoDnsResolver`,
  `HttpDidResolver`, `HttpRecordFetcher` against well-known NSIDs
  (`app.bsky.feed.post`, `com.atproto.repo.createRecord`,
  `com.atproto.repo.getRecord`). Gated behind `GARAZYK_INTEGRATION=1`.

Run unit tests:
```bash
deno test --allow-read --allow-env --allow-write packages/gruszka/lexicon_resolution/ --filter '!integration'
```

Run integration tests:
```bash
GARAZYK_INTEGRATION=1 deno test --allow-net --allow-read --allow-env packages/gruszka/lexicon_resolution/integration.test.ts
```

## Design Principles

1. **Sans-IO state machine** — Core logic has zero side effects. All I/O is
   injected through port interfaces, making the state machine fully testable
   with stubs.
2. **Dependency injection** — Ports are passed into `resolveLexicon`, not
   imported globally. Swap implementations for testing, caching, or
   platform portability (Deno, Node, browser).
3. **Result type, not exceptions** — All fallible operations return
   `Result<T, string>` or `Result<T, ResolutionError>`. No try/catch in
   the orchestration layer.
4. **Errors are not cached** — Only successful results populate the cache.
   Transient failures retry on the next call.
5. **Lazy TTL eviction** — Expired entries are removed on access or via
   explicit `evictExpired()`, avoiding background timers.
