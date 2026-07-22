/**
 * Tests for {@link ./cache.ts} — InMemoryCache, DiskCache, and the three
 * caching port wrappers.
 *
 * @module lexicon_resolution
 */

import { assert, assertEquals, assertFalse } from "@std/assert";
import {
  CachingDidResolver,
  CachingDnsResolver,
  CachingRecordFetcher,
  DiskCache,
  InMemoryCache,
} from "./cache.ts";
import type { KeyValueCache } from "./cache.ts";
import type { DidResolver, DnsResolver, RecordFetcher } from "./ports.ts";
import type { Did, DidDocument, Domain, LexiconDoc, Result } from "./types.ts";
import { asDid, asDomain } from "./types.ts";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** A minimal lexicon doc for test fixtures. */
function testLexicon(id = "app.bsky.feed.post"): LexiconDoc {
  return { lexicon: 1, id, defs: { main: { type: "record" } } };
}

/** A minimal DID document for test fixtures. */
function testDidDoc(): DidDocument {
  return {
    id: "did:plc:test123",
    service: [{
      id: "#atproto_pds",
      type: "AtprotoPersonalDataServer",
      serviceEndpoint: "https://pds.example.com",
    }],
  };
}

/** Wait for the given duration in milliseconds. */
function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

// =============================================================================
// InMemoryCache
// =============================================================================

Deno.test("InMemoryCache: get returns undefined for a missing key", async () => {
  const cache = new InMemoryCache<string>();
  assertEquals(await cache.get("missing"), undefined);
});

Deno.test("InMemoryCache: set then get returns the stored value", async () => {
  const cache = new InMemoryCache<string>();
  await cache.set("key1", "value1");
  assertEquals(await cache.get("key1"), "value1");
});

Deno.test("InMemoryCache: overwriting a key returns the new value", async () => {
  const cache = new InMemoryCache<string>();
  await cache.set("key1", "old");
  await cache.set("key1", "new");
  assertEquals(await cache.get("key1"), "new");
});

Deno.test("InMemoryCache: TTL expiry — get returns undefined after TTL", async () => {
  const cache = new InMemoryCache<string>({ ttlMs: 1 }); // 1 ms TTL
  await cache.set("key1", "value1");
  await sleep(5); // Wait for TTL to expire.
  assertEquals(await cache.get("key1"), undefined);
});

Deno.test("InMemoryCache: set with explicit TTL overrides default", async () => {
  const cache = new InMemoryCache<string>({ ttlMs: 60_000 }); // long default
  await cache.set("key1", "ephemeral", 1); // 1 ms explicit TTL
  await sleep(5);
  assertEquals(await cache.get("key1"), undefined);
});

Deno.test("InMemoryCache: no default TTL — entry never expires", async () => {
  const cache = new InMemoryCache<string>(); // no default TTL
  await cache.set("key1", "immortal");
  assertEquals(await cache.get("key1"), "immortal");
});

Deno.test("InMemoryCache: set with explicit TTL on no-default cache", async () => {
  const cache = new InMemoryCache<string>();
  await cache.set("key1", "temp", 1);
  await sleep(5);
  assertEquals(await cache.get("key1"), undefined);
});

Deno.test("InMemoryCache: evictExpired removes stale entries", async () => {
  const cache = new InMemoryCache<string>({ ttlMs: 1 });
  await cache.set("key1", "v1");
  await cache.set("key2", "v2");
  await sleep(5);
  await cache.evictExpired();
  assertEquals(await cache.get("key1"), undefined);
  assertEquals(await cache.get("key2"), undefined);
});

Deno.test("InMemoryCache: evictExpired keeps non-expired entries", async () => {
  const cache = new InMemoryCache<string>({ ttlMs: 60_000 });
  await cache.set("key1", "v1");
  await cache.evictExpired();
  assertEquals(await cache.get("key1"), "v1");
});

Deno.test("InMemoryCache: clear removes all entries", async () => {
  const cache = new InMemoryCache<string>();
  await cache.set("a", "1");
  await cache.set("b", "2");
  await cache.clear();
  assertEquals(await cache.get("a"), undefined);
  assertEquals(await cache.get("b"), undefined);
});

Deno.test("InMemoryCache: size reflects entry count", async () => {
  const cache = new InMemoryCache<string>();
  assertEquals(cache.size, 0);
  await cache.set("a", "1");
  assertEquals(cache.size, 1);
  await cache.set("b", "2");
  assertEquals(cache.size, 2);
});

Deno.test("InMemoryCache: lazy eviction on get — size drops after expired get", async () => {
  const cache = new InMemoryCache<string>({ ttlMs: 1 });
  await cache.set("a", "1");
  await sleep(5);
  // size still counts the (stale) entry before get.
  assertEquals(cache.size, 1);
  // get triggers lazy eviction and removes the stale entry.
  await cache.get("a");
  assertEquals(cache.size, 0);
});

Deno.test("InMemoryCache: cache stores complex objects", async () => {
  const cache = new InMemoryCache<LexiconDoc>();
  const doc = testLexicon();
  await cache.set("nsid", doc);
  const retrieved = await cache.get("nsid");
  assertEquals(retrieved, doc);
});

// =============================================================================
// DiskCache
// =============================================================================

let _diskCacheDir: string | undefined;
function getDiskCacheDir(): string {
  if (!_diskCacheDir) {
    _diskCacheDir = Deno.makeTempDirSync({
      prefix: "gruszka-disk-cache-test-",
    });
  }
  return _diskCacheDir;
}

function makeDiskCache<T>(ttlMs?: number): DiskCache<T> {
  const subdir = `${getDiskCacheDir()}/${crypto.randomUUID()}`;
  return new DiskCache<T>({ directory: subdir, ttlMs });
}

Deno.test("DiskCache: get returns undefined for a missing key", async () => {
  const cache = makeDiskCache<string>();
  assertEquals(await cache.get("nonexistent"), undefined);
});

Deno.test("DiskCache: set then get returns the stored value", async () => {
  const cache = makeDiskCache<string>();
  await cache.set("hello", "world");
  assertEquals(await cache.get("hello"), "world");
});

Deno.test("DiskCache: overwriting a key returns the new value", async () => {
  const cache = makeDiskCache<string>();
  await cache.set("k", "old");
  await cache.set("k", "new");
  assertEquals(await cache.get("k"), "new");
});

Deno.test("DiskCache: TTL expiry — get returns undefined after TTL", async () => {
  const cache = makeDiskCache<string>(1); // 1 ms TTL
  await cache.set("ephemeral", "value");
  await sleep(5);
  assertEquals(await cache.get("ephemeral"), undefined);
});

Deno.test("DiskCache: set with explicit TTL overrides default", async () => {
  const cache = makeDiskCache<string>(60_000); // long default
  await cache.set("key", "val", 1); // 1 ms explicit
  await sleep(5);
  assertEquals(await cache.get("key"), undefined);
});

Deno.test("DiskCache: default 24h TTL when not specified", async () => {
  const cache = new DiskCache<string>({
    directory: `${getDiskCacheDir()}/${crypto.randomUUID()}`,
  });
  await cache.set("persistent", "value");
  // Should still be present (TTL is 24h).
  assertEquals(await cache.get("persistent"), "value");
});

Deno.test("DiskCache: evictExpired removes stale files", async () => {
  const cache = makeDiskCache<string>(1);
  await cache.set("a", "1");
  await cache.set("b", "2");
  await sleep(5);
  await cache.evictExpired();
  assertEquals(await cache.get("a"), undefined);
  assertEquals(await cache.get("b"), undefined);
});

Deno.test("DiskCache: evictExpired keeps non-expired entries", async () => {
  const cache = makeDiskCache<string>(60_000);
  await cache.set("keep", "value");
  await cache.evictExpired();
  assertEquals(await cache.get("keep"), "value");
});

Deno.test("DiskCache: clear removes all files and directory", async () => {
  const cache = makeDiskCache<string>();
  await cache.set("a", "1");
  await cache.set("b", "2");
  await cache.clear();
  assertEquals(await cache.get("a"), undefined);
  assertEquals(await cache.get("b"), undefined);
});

Deno.test("DiskCache: handles special characters in keys", async () => {
  const cache = makeDiskCache<string>();
  const key =
    "https://pds.example.com/xrpc/com.atproto.repo.getRecord?repo=did:plc:test&rkey=app.bsky.feed.post";
  await cache.set(key, "lexicon data");
  assertEquals(await cache.get(key), "lexicon data");
});

Deno.test("DiskCache: stores complex objects", async () => {
  const cache = makeDiskCache<LexiconDoc>();
  const doc = testLexicon();
  await cache.set("lexicon", doc);
  const retrieved = await cache.get("lexicon");
  assertEquals(retrieved, doc);
});

// =============================================================================
// KeyValueCache interface compliance
// =============================================================================

Deno.test("InMemoryCache satisfies KeyValueCache", () => {
  // Compile-time check: assign to KeyValueCache variable.
  const _cache: KeyValueCache<string> = new InMemoryCache<string>();
  assert(_cache !== undefined);
});

Deno.test("DiskCache satisfies KeyValueCache", () => {
  const _cache: KeyValueCache<string> = new DiskCache<string>({
    directory: getDiskCacheDir(),
  });
  assert(_cache !== undefined);
});

// =============================================================================
// CachingRecordFetcher
// =============================================================================

/** A RecordFetcher stub that tracks calls. */
function stubRecordFetcher(
  result: Result<LexiconDoc, string>,
): { fetcher: RecordFetcher; calls: string[] } {
  const calls: string[] = [];
  return {
    calls,
    fetcher: {
      fetch: (endpoint: string) => {
        calls.push(endpoint);
        return Promise.resolve(result);
      },
    },
  };
}

Deno.test("CachingRecordFetcher: delegates on cache miss", async () => {
  const { fetcher, calls } = stubRecordFetcher({
    ok: true,
    value: testLexicon(),
  });
  const cache = new InMemoryCache<LexiconDoc>();
  const cached = new CachingRecordFetcher(fetcher, cache);

  const result = await cached.fetch("https://pds.example/endpoint");

  assert(result.ok);
  assertEquals(result.value.id, "app.bsky.feed.post");
  assertEquals(calls.length, 1, "inner fetcher should be called once");
  assertEquals(calls[0], "https://pds.example/endpoint");
});

Deno.test("CachingRecordFetcher: returns cached value on second call", async () => {
  const { fetcher, calls } = stubRecordFetcher({
    ok: true,
    value: testLexicon(),
  });
  const cache = new InMemoryCache<LexiconDoc>();
  const cached = new CachingRecordFetcher(fetcher, cache);

  await cached.fetch("https://pds.example/endpoint");
  assertEquals(calls.length, 1);

  // Second call — should hit the cache.
  const result = await cached.fetch("https://pds.example/endpoint");
  assert(result.ok);
  assertEquals(calls.length, 1, "inner fetcher should not be called again");
});

Deno.test("CachingRecordFetcher: errors are not cached", async () => {
  const { fetcher, calls } = stubRecordFetcher({
    ok: false,
    error: "HTTP 503",
  });
  const cache = new InMemoryCache<LexiconDoc>();
  const cached = new CachingRecordFetcher(fetcher, cache);

  // First call — error.
  const first = await cached.fetch("https://pds.example/endpoint");
  assertFalse(first.ok);
  assertEquals(calls.length, 1);

  // Second call — should retry (error not cached).
  const second = await cached.fetch("https://pds.example/endpoint");
  assertFalse(second.ok);
  assertEquals(calls.length, 2, "error path should retry inner fetcher");
});

Deno.test("CachingRecordFetcher: different endpoints have separate cache keys", async () => {
  const doc1 = testLexicon("app.bsky.feed.post");
  const { fetcher, calls } = stubRecordFetcher({ ok: true, value: doc1 });
  const cache = new InMemoryCache<LexiconDoc>();
  const cached = new CachingRecordFetcher(fetcher, cache);

  // First endpoint: delegates, cached.
  await cached.fetch("https://pds.example/ep1");
  assertEquals(calls.length, 1);

  // Cache hit on same endpoint.
  const result = await cached.fetch("https://pds.example/ep1");
  assert(result.ok && result.value.id === "app.bsky.feed.post");
  assertEquals(calls.length, 1, "second call to same endpoint hits cache");

  // Different endpoint: must delegate again.
  await cached.fetch("https://pds.example/ep2");
  assertEquals(calls.length, 2, "different endpoint misses cache");
});

// =============================================================================
// CachingDnsResolver
// =============================================================================

/** A DnsResolver stub that tracks calls. */
function stubDnsResolver(
  result: Result<string[][], string>,
): { resolver: DnsResolver; calls: Domain[] } {
  const calls: Domain[] = [];
  return {
    calls,
    resolver: {
      resolveTxt: (domain: Domain) => {
        calls.push(domain);
        return Promise.resolve(result);
      },
    },
  };
}

Deno.test("CachingDnsResolver: delegates on cache miss", async () => {
  const domain = asDomain("feed.bsky.app");
  const records = [["did=did:plc:test123"]];
  const { resolver, calls } = stubDnsResolver({ ok: true, value: records });
  const cache = new InMemoryCache<string[][]>();
  const cached = new CachingDnsResolver(resolver, cache);

  const result = await cached.resolveTxt(domain);

  assert(result.ok);
  assertEquals(result.value, records);
  assertEquals(calls.length, 1);
  assertEquals(calls[0], domain);
});

Deno.test("CachingDnsResolver: returns cached value on second call", async () => {
  const domain = asDomain("feed.bsky.app");
  const { resolver, calls } = stubDnsResolver({
    ok: true,
    value: [["did=did:plc:test"]],
  });
  const cache = new InMemoryCache<string[][]>();
  const cached = new CachingDnsResolver(resolver, cache);

  await cached.resolveTxt(domain);
  assertEquals(calls.length, 1);

  await cached.resolveTxt(domain);
  assertEquals(calls.length, 1, "second call should hit cache");
});

Deno.test("CachingDnsResolver: errors are not cached", async () => {
  const domain = asDomain("nonexistent.example");
  const { resolver, calls } = stubDnsResolver({
    ok: false,
    error: "NXDOMAIN",
  });
  const cache = new InMemoryCache<string[][]>();
  const cached = new CachingDnsResolver(resolver, cache);

  await cached.resolveTxt(domain);
  await cached.resolveTxt(domain);
  assertEquals(calls.length, 2, "errors should not be cached");
});

Deno.test("CachingDnsResolver: different domains have separate cache keys", async () => {
  const domain1 = asDomain("feed.bsky.app");
  const domain2 = asDomain("repo.atproto.com");
  const { resolver, calls } = stubDnsResolver({
    ok: true,
    value: [["did=did:plc:test"]],
  });
  const cache = new InMemoryCache<string[][]>();
  const cached = new CachingDnsResolver(resolver, cache);

  await cached.resolveTxt(domain1);
  assertEquals(calls.length, 1);

  await cached.resolveTxt(domain2);
  assertEquals(calls.length, 2, "different domain should miss cache");
});

// =============================================================================
// CachingDidResolver
// =============================================================================

/** A DidResolver stub that tracks calls. */
function stubDidResolver(
  result: Result<DidDocument, string>,
): { resolver: DidResolver; calls: Did[] } {
  const calls: Did[] = [];
  return {
    calls,
    resolver: {
      resolve: (did: Did) => {
        calls.push(did);
        return Promise.resolve(result);
      },
    },
  };
}

Deno.test("CachingDidResolver: delegates on cache miss", async () => {
  const did = asDid("did:plc:test123");
  const doc = testDidDoc();
  const { resolver, calls } = stubDidResolver({ ok: true, value: doc });
  const cache = new InMemoryCache<DidDocument>();
  const cached = new CachingDidResolver(resolver, cache);

  const result = await cached.resolve(did);

  assert(result.ok);
  assertEquals(result.value, doc);
  assertEquals(calls.length, 1);
  assertEquals(calls[0], did);
});

Deno.test("CachingDidResolver: returns cached value on second call", async () => {
  const did = asDid("did:plc:test123");
  const { resolver, calls } = stubDidResolver({
    ok: true,
    value: testDidDoc(),
  });
  const cache = new InMemoryCache<DidDocument>();
  const cached = new CachingDidResolver(resolver, cache);

  await cached.resolve(did);
  assertEquals(calls.length, 1);

  await cached.resolve(did);
  assertEquals(calls.length, 1, "second call should hit cache");
});

Deno.test("CachingDidResolver: errors are not cached", async () => {
  const did = asDid("did:plc:test123");
  const { resolver, calls } = stubDidResolver({
    ok: false,
    error: "HTTP 404",
  });
  const cache = new InMemoryCache<DidDocument>();
  const cached = new CachingDidResolver(resolver, cache);

  await cached.resolve(did);
  await cached.resolve(did);
  assertEquals(calls.length, 2, "errors should not be cached");
});

// =============================================================================
// Composite: all three caching wrappers together
// =============================================================================

Deno.test("Caching wrappers compose: cache across all three layers", async () => {
  // Set up stubs with call tracking for each port.
  const dnsRecords: string[][] = [["did=did:plc:test123"]];
  const didDoc = testDidDoc();
  const lexicon = testLexicon();

  let dnsCalls = 0;
  let didCalls = 0;
  let recordCalls = 0;

  const dnsResolver: DnsResolver = {
    resolveTxt: (_domain: Domain) => {
      dnsCalls++;
      return Promise.resolve({ ok: true, value: dnsRecords });
    },
  };
  const didResolver: DidResolver = {
    resolve: (_did: Did) => {
      didCalls++;
      return Promise.resolve({ ok: true, value: didDoc });
    },
  };
  const recordFetcher: RecordFetcher = {
    fetch: (_endpoint: string) => {
      recordCalls++;
      return Promise.resolve({ ok: true, value: lexicon });
    },
  };

  const dnsCache = new InMemoryCache<string[][]>();
  const didCache = new InMemoryCache<DidDocument>();
  const recordCache = new InMemoryCache<LexiconDoc>();

  const cachedDns = new CachingDnsResolver(dnsResolver, dnsCache);
  const cachedDid = new CachingDidResolver(didResolver, didCache);
  const cachedRecord = new CachingRecordFetcher(recordFetcher, recordCache);

  const domain = asDomain("feed.bsky.app");
  const did = asDid("did:plc:test123");

  // First round: all delegates.
  await cachedDns.resolveTxt(domain);
  assertEquals(dnsCalls, 1);
  await cachedDid.resolve(did);
  assertEquals(didCalls, 1);
  await cachedRecord.fetch("https://pds.example/endpoint");
  assertEquals(recordCalls, 1);

  // Second round: all hits.
  await cachedDns.resolveTxt(domain);
  assertEquals(dnsCalls, 1, "DNS should hit cache");
  await cachedDid.resolve(did);
  assertEquals(didCalls, 1, "DID should hit cache");
  await cachedRecord.fetch("https://pds.example/endpoint");
  assertEquals(recordCalls, 1, "Record should hit cache");
});
