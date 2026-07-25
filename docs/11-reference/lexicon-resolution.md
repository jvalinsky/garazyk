---
title: Lexicon Resolution
---

# Lexicon Resolution

`@garazyk/gruszka` resolves an NSID by looking up its domain, DID document, PDS
endpoint, and lexicon record. Network work is supplied through interfaces so the
resolver state machine can run without direct I/O.

## Files

| File          | Purpose                          |
| ------------- | -------------------------------- |
| `types.ts`    | Domain types and result values   |
| `core.ts`     | NSID, DID, and record validation |
| `resolver.ts` | Resolver state machine           |
| `ports.ts`    | DNS, DID, and record interfaces  |
| `adapters.ts` | Deno implementations             |
| `cache.ts`    | Memory and disk caches           |
| `mod.ts`      | Public orchestration API         |

These files are under `packages/gruszka/lexicon_resolution/`.

## Flow

1. Validate the NSID and derive its authority.
2. Read the lexicon TXT record.
3. Resolve the DID and find its PDS endpoint.
4. Fetch the lexicon record.
5. Check that the returned lexicon ID matches the requested NSID.

The resolver returns `Result<LexiconDoc, ResolutionError>`. Error variants
identify the failed stage and retain the relevant domain, DID, endpoint, or
NSID.

## Use

```ts
import {
  DenoDnsResolver,
  HttpDidResolver,
  HttpRecordFetcher,
} from "./packages/gruszka/lexicon_resolution/adapters.ts";
import { resolveLexicon } from "./packages/gruszka/lexicon_resolution/mod.ts";

const result = await resolveLexicon("app.bsky.feed.post", {
  dns: new DenoDnsResolver(),
  did: new HttpDidResolver(),
  record: new HttpRecordFetcher(),
});

if (!result.ok) {
  console.error(result.error);
}
```

Optional cache adapters wrap DNS, DID, and record ports. Only successful values
are cached, and each cache has its own TTL.

## Test

```sh
deno test \
  --allow-read \
  --allow-env \
  --allow-write \
  packages/gruszka/lexicon_resolution/ \
  --filter '!integration'
```

Integration tests require network access:

```sh
GARAZYK_INTEGRATION=1 deno test \
  --allow-net \
  --allow-read \
  --allow-env \
  packages/gruszka/lexicon_resolution/integration.test.ts
```
