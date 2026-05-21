/**
 * Tests for {@link ./mod.ts} — the resolveLexicon orchestration function.
 *
 * Uses in-memory stub port implementations to exercise every path through
 * the DNS → DID → record pipeline without network access.
 *
 * @module lexicon_resolution
 */

import { assertEquals, assert, assertFalse } from "jsr:@std/assert";
import { resolveLexicon, type ResolutionPorts } from "./mod.ts";
import { InMemoryCache } from "./cache.ts";
import type {
  Did,
  DidDocument,
  Domain,
  LexiconDoc,
  Result,
} from "./types.ts";
import { asDid, asDomain, asNsid } from "./types.ts";

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

const testNsid = "app.bsky.feed.post";
const brandedTestNsid = asNsid(testNsid);
const testDid = asDid("did:plc:test123");
const testDomain = asDomain("feed.bsky.app");

/** A minimal valid DID document with an AtprotoPersonalDataServer service. */
function makeDidDoc(pdsEndpoint = "https://pds.example.com"): DidDocument {
  return {
    id: testDid,
    service: [
      {
        id: "#atproto_pds",
        type: "AtprotoPersonalDataServer",
        serviceEndpoint: pdsEndpoint,
      },
    ],
  };
}

/** A minimal valid lexicon document. */
function makeLexicon(id = testNsid): LexiconDoc {
  return {
    lexicon: 1,
    id,
    defs: {
      main: { type: "record" },
    },
  };
}

// ---------------------------------------------------------------------------
// Stub port helpers
// ---------------------------------------------------------------------------

/** Track calls to a DnsResolver stub. */
interface DnsStub {
  calls: Domain[];
  resolveTxt(domain: Domain): Promise<Result<string[][], string>>;
}

/** Track calls to a DidResolver stub. */
interface DidStub {
  calls: Did[];
  resolve(did: Did): Promise<Result<DidDocument, string>>;
}

/** Track calls to a RecordFetcher stub. */
interface RecordStub {
  calls: string[];
  fetch(endpoint: string): Promise<Result<LexiconDoc, string>>;
}

/** Create a DnsResolver stub that returns a pre-configured result. */
function stubDns(result: Result<string[][], string>): DnsStub {
  const calls: Domain[] = [];
  return {
    calls,
    resolveTxt: (domain: Domain) => {
      calls.push(domain);
      return Promise.resolve(result);
    },
  };
}

/** Create a DidResolver stub that returns a pre-configured result. */
function stubDid(result: Result<DidDocument, string>): DidStub {
  const calls: Did[] = [];
  return {
    calls,
    resolve: (did: Did) => {
      calls.push(did);
      return Promise.resolve(result);
    },
  };
}

/** Create a RecordFetcher stub that returns a pre-configured result. */
function stubRecord(result: Result<LexiconDoc, string>): RecordStub {
  const calls: string[] = [];
  return {
    calls,
    fetch: (endpoint: string) => {
      calls.push(endpoint);
      return Promise.resolve(result);
    },
  };
}

/** Assemble stubs into a ResolutionPorts value. */
function makePorts(
  dns: DnsStub,
  did: DidStub,
  record: RecordStub,
): ResolutionPorts {
  return {
    dns: { resolveTxt: dns.resolveTxt },
    did: { resolve: did.resolve },
    record: { fetch: record.fetch },
  };
}

// =============================================================================
// Happy path
// =============================================================================

Deno.test("resolveLexicon: happy path — resolves DNS → DID → record", async () => {
  const dns = stubDns({ ok: true, value: [["did=did:plc:test123"]] });
  const did = stubDid({ ok: true, value: makeDidDoc() });
  const record = stubRecord({ ok: true, value: makeLexicon() });

  const result = await resolveLexicon(testNsid, makePorts(dns, did, record));

  assert(result.ok);
  assertEquals(result.value.id, testNsid);
  assertEquals(result.value.lexicon, 1);
  assertEquals(Object.keys(result.value.defs), ["main"]);

  // DNS was called with the reversed domain.
  assertEquals(dns.calls.length, 1);
  assertEquals(dns.calls[0], testDomain);

  // DID was called with the DID extracted from DNS.
  assertEquals(did.calls.length, 1);
  assertEquals(did.calls[0], testDid);

  // Record was fetched from the PDS with a properly constructed XRPC URL.
  assertEquals(record.calls.length, 1);
  const url = record.calls[0];
  assert(url.startsWith("https://pds.example.com/xrpc/com.atproto.repo.getRecord?"));
  assert(url.includes("repo=did%3Aplc%3Atest123"));
  assert(url.includes("collection=com.atproto.lexicon.schema"));
  assert(url.includes("rkey=app.bsky.feed.post"));
});

Deno.test("resolveLexicon: happy path — handles deep NSID", async () => {
  const dns = stubDns({ ok: true, value: [["did=did:plc:test123"]] });
  const did = stubDid({ ok: true, value: makeDidDoc("https://pds.deep.example") });
  const record = stubRecord({ ok: true, value: makeLexicon("com.atproto.repo.createRecord") });

  const result = await resolveLexicon("com.atproto.repo.createRecord", makePorts(dns, did, record));

  assert(result.ok);
  assertEquals(result.value.id, "com.atproto.repo.createRecord");

  // Domain derived from the authority segment of the deep NSID.
  assertEquals(dns.calls[0], asDomain("repo.atproto.com"));
});

// =============================================================================
// Invalid NSID (immediate failure — no ports called)
// =============================================================================

Deno.test("resolveLexicon: invalid NSID — returns InvalidNsid error", async () => {
  const dns = stubDns({ ok: true, value: [] });
  const did = stubDid({ ok: true, value: makeDidDoc() });
  const record = stubRecord({ ok: true, value: makeLexicon() });

  const result = await resolveLexicon("xy", makePorts(dns, did, record));

  assertFalse(result.ok);
  if (!result.ok && result.error.type === "InvalidNsid") {
    assertEquals(result.error.nsid, "xy");
  }

  // No ports should have been touched.
  assertEquals(dns.calls.length, 0);
  assertEquals(did.calls.length, 0);
  assertEquals(record.calls.length, 0);
});

Deno.test("resolveLexicon: empty NSID — returns InvalidNsid error", async () => {
  const dns = stubDns({ ok: true, value: [] });
  const did = stubDid({ ok: true, value: makeDidDoc() });
  const record = stubRecord({ ok: true, value: makeLexicon() });

  const result = await resolveLexicon("", makePorts(dns, did, record));

  assertFalse(result.ok);
  if (!result.ok && result.error.type === "InvalidNsid") {
    assertEquals(result.error.nsid, "");
  }

  assertEquals(dns.calls.length, 0);
  assertEquals(did.calls.length, 0);
  assertEquals(record.calls.length, 0);
});

Deno.test("resolveLexicon: NSID with uppercase — validated correctly", async () => {
  // Uppercase is now valid per the fixed regex (allows a-zA-Z0-9.).
  const dns = stubDns({ ok: true, value: [["did=did:plc:test123"]] });
  const did = stubDid({ ok: true, value: makeDidDoc() });
  const record = stubRecord({ ok: true, value: makeLexicon("com.Atproto.Repo.CreateRecord") });

  const result = await resolveLexicon("com.Atproto.Repo.CreateRecord", makePorts(dns, did, record));

  assert(result.ok);
  assertEquals(dns.calls.length, 1);
});

// =============================================================================
// DNS failure
// =============================================================================

Deno.test("resolveLexicon: DNS fails — returns DnsQueryFailed error", async () => {
  const dns = stubDns({ ok: false, error: "NXDOMAIN: no such domain" });
  const did = stubDid({ ok: true, value: makeDidDoc() });
  const record = stubRecord({ ok: true, value: makeLexicon() });

  const result = await resolveLexicon(testNsid, makePorts(dns, did, record));

  assertFalse(result.ok);
  if (!result.ok && result.error.type === "DnsQueryFailed") {
    assertEquals(result.error.domain, testDomain);
    assertEquals(result.error.reason, "NXDOMAIN: no such domain");
  }

  // Only DNS was called.
  assertEquals(dns.calls.length, 1);
  assertEquals(did.calls.length, 0);
  assertEquals(record.calls.length, 0);
});

Deno.test("resolveLexicon: DNS fails with server error — reason is preserved", async () => {
  const dns = stubDns({ ok: false, error: "SERVFAIL: server failure" });
  const did = stubDid({ ok: true, value: makeDidDoc() });
  const record = stubRecord({ ok: true, value: makeLexicon() });

  const result = await resolveLexicon(testNsid, makePorts(dns, did, record));

  assertFalse(result.ok);
  if (!result.ok && result.error.type === "DnsQueryFailed") {
    assertEquals(result.error.reason, "SERVFAIL: server failure");
  }
});

// =============================================================================
// DNS succeeds but no DID found in TXT records
// =============================================================================

Deno.test("resolveLexicon: DNS succeeds but no DID — returns NoLexiconDnsRecord", async () => {
  const dns = stubDns({ ok: true, value: [["v=spf1 mx ~all", "some=other"]] });
  const did = stubDid({ ok: true, value: makeDidDoc() });
  const record = stubRecord({ ok: true, value: makeLexicon() });

  const result = await resolveLexicon(testNsid, makePorts(dns, did, record));

  assertFalse(result.ok);
  if (!result.ok && result.error.type === "NoLexiconDnsRecord") {
    assertEquals(result.error.domain, testDomain);
  }

  // DNS was called but DID resolution was never reached.
  assertEquals(dns.calls.length, 1);
  assertEquals(did.calls.length, 0);
  assertEquals(record.calls.length, 0);
});

Deno.test("resolveLexicon: DNS returns empty records — returns NoLexiconDnsRecord", async () => {
  const dns = stubDns({ ok: true, value: [] });
  const did = stubDid({ ok: true, value: makeDidDoc() });
  const record = stubRecord({ ok: true, value: makeLexicon() });

  const result = await resolveLexicon(testNsid, makePorts(dns, did, record));

  assertFalse(result.ok);
  if (!result.ok && result.error.type === "NoLexiconDnsRecord") {
    assertEquals(result.error.domain, testDomain);
  }
});

// =============================================================================
// DID resolution failure
// =============================================================================

Deno.test("resolveLexicon: DID resolution fails — returns DidResolutionFailed", async () => {
  const dns = stubDns({ ok: true, value: [["did=did:plc:test123"]] });
  const did = stubDid({ ok: false, error: "HTTP 404: not found" });
  const record = stubRecord({ ok: true, value: makeLexicon() });

  const result = await resolveLexicon(testNsid, makePorts(dns, did, record));

  assertFalse(result.ok);
  if (!result.ok && result.error.type === "DidResolutionFailed") {
    assertEquals(result.error.did, testDid);
    assertEquals(result.error.reason, "HTTP 404: not found");
  }

  // DNS and DID were called, but not record fetch.
  assertEquals(dns.calls.length, 1);
  assertEquals(did.calls.length, 1);
  assertEquals(record.calls.length, 0);
});

Deno.test("resolveLexicon: DID resolution network error", async () => {
  const dns = stubDns({ ok: true, value: [["did=did:plc:test123"]] });
  const did = stubDid({ ok: false, error: "Connection refused" });
  const record = stubRecord({ ok: true, value: makeLexicon() });

  const result = await resolveLexicon(testNsid, makePorts(dns, did, record));

  assertFalse(result.ok);
  if (!result.ok && result.error.type === "DidResolutionFailed") {
    assertEquals(result.error.reason, "Connection refused");
  }
});

// =============================================================================
// DID resolves but no PDS endpoint found
// =============================================================================

Deno.test("resolveLexicon: DID doc has no PDS service — returns PdsEndpointMissing", async () => {
  const dns = stubDns({ ok: true, value: [["did=did:plc:test123"]] });
  const did = stubDid({
    ok: true,
    value: {
      id: testDid,
      service: [
        {
          id: "#some_other",
          type: "SomeOtherService",
          serviceEndpoint: "https://other.example.com",
        },
      ],
    },
  });
  const record = stubRecord({ ok: true, value: makeLexicon() });

  const result = await resolveLexicon(testNsid, makePorts(dns, did, record));

  assertFalse(result.ok);
  if (!result.ok && result.error.type === "PdsEndpointMissing") {
    assertEquals(result.error.did, testDid);
  }

  assertEquals(dns.calls.length, 1);
  assertEquals(did.calls.length, 1);
  assertEquals(record.calls.length, 0);
});

Deno.test("resolveLexicon: DID doc has empty service array — returns PdsEndpointMissing", async () => {
  const dns = stubDns({ ok: true, value: [["did=did:plc:test123"]] });
  const did = stubDid({
    ok: true,
    value: { id: testDid, service: [] },
  });
  const record = stubRecord({ ok: true, value: makeLexicon() });

  const result = await resolveLexicon(testNsid, makePorts(dns, did, record));

  assertFalse(result.ok);
  if (!result.ok && result.error.type === "PdsEndpointMissing") {
    assertEquals(result.error.did, testDid);
  }
});

Deno.test("resolveLexicon: DID doc has no service array — returns PdsEndpointMissing", async () => {
  const dns = stubDns({ ok: true, value: [["did=did:plc:test123"]] });
  const did = stubDid({
    ok: true,
    value: { id: testDid },
  });
  const record = stubRecord({ ok: true, value: makeLexicon() });

  const result = await resolveLexicon(testNsid, makePorts(dns, did, record));

  assertFalse(result.ok);
  if (!result.ok && result.error.type === "PdsEndpointMissing") {
    assertEquals(result.error.did, testDid);
  }
});

// =============================================================================
// Record fetch failure
// =============================================================================

Deno.test("resolveLexicon: record fetch fails — returns RecordFetchFailed", async () => {
  const dns = stubDns({ ok: true, value: [["did=did:plc:test123"]] });
  const did = stubDid({ ok: true, value: makeDidDoc() });
  const record = stubRecord({ ok: false, error: "HTTP 503: service unavailable" });

  const result = await resolveLexicon(testNsid, makePorts(dns, did, record));

  assertFalse(result.ok);
  if (!result.ok && result.error.type === "RecordFetchFailed") {
    assertEquals(result.error.reason, "HTTP 503: service unavailable");
    // The endpoint field contains the full XRPC URL for diagnostics.
    assert(result.error.endpoint.includes("xrpc/com.atproto.repo.getRecord"));
    assert(result.error.endpoint.includes("did%3Aplc%3Atest123"));
  }

  // All three ports were called.
  assertEquals(dns.calls.length, 1);
  assertEquals(did.calls.length, 1);
  assertEquals(record.calls.length, 1);
});

Deno.test("resolveLexicon: record fetch network error", async () => {
  const dns = stubDns({ ok: true, value: [["did=did:plc:test123"]] });
  const did = stubDid({ ok: true, value: makeDidDoc() });
  const record = stubRecord({ ok: false, error: "Connection reset" });

  const result = await resolveLexicon(testNsid, makePorts(dns, did, record));

  assertFalse(result.ok);
  if (!result.ok && result.error.type === "RecordFetchFailed") {
    assertEquals(result.error.reason, "Connection reset");
  }
});

// =============================================================================
// Record verification failure
// =============================================================================

Deno.test("resolveLexicon: record id mismatch — returns RecordVerificationFailed", async () => {
  const dns = stubDns({ ok: true, value: [["did=did:plc:test123"]] });
  const did = stubDid({ ok: true, value: makeDidDoc() });
  // The PDS returns a lexicon for a different NSID than what was requested.
  const record = stubRecord({ ok: true, value: makeLexicon("com.atproto.other.method") });

  const result = await resolveLexicon(testNsid, makePorts(dns, did, record));

  assertFalse(result.ok);
  if (!result.ok && result.error.type === "RecordVerificationFailed") {
    assertEquals(result.error.nsid, brandedTestNsid);
    assert(result.error.reason.includes("does not match"));
    assert(result.error.reason.includes("com.atproto.other.method"));
  }
});

Deno.test("resolveLexicon: empty id in lexicon — returns RecordVerificationFailed", async () => {
  const dns = stubDns({ ok: true, value: [["did=did:plc:test123"]] });
  const did = stubDid({ ok: true, value: makeDidDoc() });
  const record = stubRecord({ ok: true, value: makeLexicon("") });

  const result = await resolveLexicon(testNsid, makePorts(dns, did, record));

  assertFalse(result.ok);
  if (!result.ok && result.error.type === "RecordVerificationFailed") {
    assertEquals(result.error.nsid, brandedTestNsid);
  }
});

// =============================================================================
// DID document with object-form serviceEndpoint
// =============================================================================

Deno.test("resolveLexicon: DID doc with object-form endpoint — resolves correctly", async () => {
  const dns = stubDns({ ok: true, value: [["did=did:plc:test123"]] });
  const did = stubDid({
    ok: true,
    value: {
      id: testDid,
      service: [
        {
          id: "#atproto_pds",
          type: "AtprotoPersonalDataServer",
          serviceEndpoint: { url: "https://pds-object.example.com" },
        },
      ],
    },
  });
  const record = stubRecord({ ok: true, value: makeLexicon() });

  const result = await resolveLexicon(testNsid, makePorts(dns, did, record));

  assert(result.ok);
  // The XRPC URL should use the unwrapped .url from the object-form endpoint.
  const url = record.calls[0];
  assert(url.startsWith("https://pds-object.example.com/xrpc/com.atproto.repo.getRecord?"));
});

// =============================================================================
// DnsQueryFailed error variant across multiple failure reasons
// =============================================================================

Deno.test("resolveLexicon: all DNS error reasons produce DnsQueryFailed variant", async () => {
  // Verify that different port error strings all produce the same error variant.
  for (const reason of ["NXDOMAIN", "timeout", "SERVFAIL"]) {
    const dns = stubDns({ ok: false, error: reason });
    const did = stubDid({ ok: true, value: makeDidDoc() });
    const record = stubRecord({ ok: true, value: makeLexicon() });

    const result = await resolveLexicon(testNsid, makePorts(dns, did, record));

    assertFalse(result.ok);
    if (!result.ok && result.error.type === "DnsQueryFailed") {
      assertEquals(result.error.reason, reason);
    }
  }
});

// =============================================================================
// Lexicon document with additional fields is passed through
// =============================================================================

Deno.test("resolveLexicon: extra fields on lexicon doc are preserved", async () => {
  const lexicon = {
    lexicon: 1,
    id: testNsid,
    revision: 42,
    description: "A test lexicon",
    defs: {
      main: { type: "record" as const, description: "Main record def" },
    },
  };
  const dns = stubDns({ ok: true, value: [["did=did:plc:test123"]] });
  const did = stubDid({ ok: true, value: makeDidDoc() });
  const record = stubRecord({ ok: true, value: lexicon });

  const result = await resolveLexicon(testNsid, makePorts(dns, did, record));

  assert(result.ok);
  assertEquals(result.value.revision, 42);
  assertEquals(result.value.description, "A test lexicon");
  assertEquals(result.value.defs.main.description, "Main record def");
});

// =============================================================================
// Caching behaviour
// =============================================================================

/**
 * Create a RecordFetcher stub that returns a lexicon whose `.id` matches
 * the NSID extracted from the endpoint URL's `rkey` query parameter.
 * Used by caching tests that resolve multiple NSIDs.
 */
function stubDynamicRecord(): {
  calls: string[];
  fetch(endpoint: string): Promise<Result<LexiconDoc, string>>;
} {
  const calls: string[] = [];
  return {
    calls,
    fetch: (endpoint: string) => {
      calls.push(endpoint);
      // Extract the rkey (NSID) from the URL to produce a matching lexicon.
      const match = endpoint.match(/rkey=([^&]+)/);
      const id = match ? decodeURIComponent(match[1]) : testNsid;
      return Promise.resolve({ ok: true, value: makeLexicon(id) });
    },
  };
}

Deno.test("resolveLexicon: cache hit — second resolution for same NSID does not call inner ports", async () => {
  const dns = stubDns({ ok: true, value: [["did=did:plc:test123"]] });
  const did = stubDid({ ok: true, value: makeDidDoc() });
  const record = stubDynamicRecord();

  const dnsCache = new InMemoryCache<string[][]>({ ttlMs: 60_000 });
  const didCache = new InMemoryCache<DidDocument>({ ttlMs: 60_000 });
  const recordCache = new InMemoryCache<LexiconDoc>({ ttlMs: 60_000 });

  const ports: ResolutionPorts = {
    dns: { resolveTxt: dns.resolveTxt },
    did: { resolve: did.resolve },
    record: { fetch: record.fetch },
    cache: { dns: dnsCache, did: didCache, record: recordCache },
  };

  // First resolution — populates all three caches.
  const r1 = await resolveLexicon(testNsid, ports);
  assert(r1.ok);
  assertEquals(r1.value.id, testNsid);
  assertEquals(dns.calls.length, 1);
  assertEquals(did.calls.length, 1);
  assertEquals(record.calls.length, 1);

  // Second resolution — all cached, no additional inner-port calls.
  const r2 = await resolveLexicon(testNsid, ports);
  assert(r2.ok);
  assertEquals(r2.value.id, testNsid);
  assertEquals(dns.calls.length, 1, "DNS should not be called again (cache hit)");
  assertEquals(did.calls.length, 1, "DID should not be called again (cache hit)");
  assertEquals(record.calls.length, 1, "record should not be called again (cache hit)");
});

Deno.test("resolveLexicon: cache miss — different NSID calls inner ports for each", async () => {
  const dns = stubDns({ ok: true, value: [["did=did:plc:test123"]] });
  const did = stubDid({ ok: true, value: makeDidDoc() });
  const record = stubDynamicRecord();

  const dnsCache = new InMemoryCache<string[][]>({ ttlMs: 60_000 });
  const didCache = new InMemoryCache<DidDocument>({ ttlMs: 60_000 });
  const recordCache = new InMemoryCache<LexiconDoc>({ ttlMs: 60_000 });

  const ports: ResolutionPorts = {
    dns: { resolveTxt: dns.resolveTxt },
    did: { resolve: did.resolve },
    record: { fetch: record.fetch },
    cache: { dns: dnsCache, did: didCache, record: recordCache },
  };

  // First NSID.
  const r1 = await resolveLexicon("app.bsky.feed.post", ports);
  assert(r1.ok);
  assertEquals(r1.value.id, "app.bsky.feed.post");
  assertEquals(dns.calls.length, 1);
  assertEquals(did.calls.length, 1);
  assertEquals(record.calls.length, 1);

  // Second NSID shares the same domain (feed.bsky.app) and DID,
  // so DNS and DID are cache hits, but the record endpoint has a
  // different rkey — a cache miss.
  const r2 = await resolveLexicon("app.bsky.feed.like", ports);
  assert(r2.ok);
  assertEquals(r2.value.id, "app.bsky.feed.like");
  // DNS and DID: same keys → cache hits.
  assertEquals(dns.calls.length, 1, "DNS cache hit — same domain");
  assertEquals(did.calls.length, 1, "DID cache hit — same DID");
  // Record: different rkey → cache miss.
  assertEquals(record.calls.length, 2, "record cache miss — different rkey");
});

Deno.test("resolveLexicon: partial cache — only record cache enabled", async () => {
  // When only some ports are cached, uncached ones are called every time.
  const dns = stubDns({ ok: true, value: [["did=did:plc:test123"]] });
  const did = stubDid({ ok: true, value: makeDidDoc() });
  const record = stubDynamicRecord();

  const recordCache = new InMemoryCache<LexiconDoc>({ ttlMs: 60_000 });

  const ports: ResolutionPorts = {
    dns: { resolveTxt: dns.resolveTxt },
    did: { resolve: did.resolve },
    record: { fetch: record.fetch },
    cache: { record: recordCache },
  };

  // First resolution.
  const r1 = await resolveLexicon(testNsid, ports);
  assert(r1.ok);
  assertEquals(dns.calls.length, 1);
  assertEquals(did.calls.length, 1);
  assertEquals(record.calls.length, 1);

  // Second resolution — record is cached, DNS and DID are not.
  const r2 = await resolveLexicon(testNsid, ports);
  assert(r2.ok);
  assertEquals(dns.calls.length, 2, "DNS not cached — called again");
  assertEquals(did.calls.length, 2, "DID not cached — called again");
  assertEquals(record.calls.length, 1, "record cached — not called again");
});

Deno.test("resolveLexicon: errors are not cached", async () => {
  // A failing DNS port should not cache the error — the next resolution
  // retries the inner port.
  const dns = stubDns({ ok: false, error: "NXDOMAIN" });
  const did = stubDid({ ok: true, value: makeDidDoc() });
  const record = stubRecord({ ok: true, value: makeLexicon() });

  const dnsCache = new InMemoryCache<string[][]>({ ttlMs: 60_000 });

  const ports: ResolutionPorts = {
    dns: { resolveTxt: dns.resolveTxt },
    did: { resolve: did.resolve },
    record: { fetch: record.fetch },
    cache: { dns: dnsCache },
  };

  // First attempt — DNS fails.
  const r1 = await resolveLexicon(testNsid, ports);
  assertFalse(r1.ok);
  assertEquals(dns.calls.length, 1);
  assertEquals(dnsCache.size, 0, "cache should be empty — errors are not stored");

  // Second attempt — DNS is called again because the error was not cached.
  const r2 = await resolveLexicon(testNsid, ports);
  assertFalse(r2.ok);
  assertEquals(dns.calls.length, 2, "DNS error not cached — retried");
  assertEquals(dnsCache.size, 0, "cache still empty — errors are never cached");
});

Deno.test("resolveLexicon: TTL expiry — inner port called again after entry expires", async () => {
  const dns = stubDns({ ok: true, value: [["did=did:plc:test123"]] });
  const did = stubDid({ ok: true, value: makeDidDoc() });
  const record = stubDynamicRecord();

  // Very short TTL — entry expires almost immediately.
  const recordCache = new InMemoryCache<LexiconDoc>({ ttlMs: 1 });

  const ports: ResolutionPorts = {
    dns: { resolveTxt: dns.resolveTxt },
    did: { resolve: did.resolve },
    record: { fetch: record.fetch },
    cache: { record: recordCache },
  };

  // First resolution — populates the record cache.
  const r1 = await resolveLexicon(testNsid, ports);
  assert(r1.ok);
  assertEquals(record.calls.length, 1);
  assertEquals(recordCache.size, 1, "record entry should be in cache");

  // Wait for the TTL to expire (1ms TTL + small buffer).
  await new Promise((resolve) => setTimeout(resolve, 10));

  // Second resolution — TTL has expired, so the inner port must be recalled.
  const r2 = await resolveLexicon(testNsid, ports);
  assert(r2.ok);
  assertEquals(record.calls.length, 2, "TTL expired — record port called again");
});
