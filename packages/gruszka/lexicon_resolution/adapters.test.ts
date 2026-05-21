/**
 * Unit tests for the Deno IO adapter implementations.
 *
 * These tests mock `Deno.resolveDns` and `globalThis.fetch` to exercise
 * every code path in the adapters without making real network calls.
 * Each mock is scoped to a single test via save/restore to avoid leaking
 * state between tests.
 *
 * @module lexicon_resolution
 */

import { assertEquals, assert } from "jsr:@std/assert";

import { DenoDnsResolver, HttpDidResolver, HttpRecordFetcher } from "./adapters.ts";
import { asDid, asDomain, type Did, type DidDocument, type Domain, type LexiconDoc } from "./types.ts";

// ===========================================================================
// Mock helpers
// ===========================================================================

/** Typed mock callback for `fetch` — accepts all valid `fetch` signatures. */
type FetchMock = (input: string | URL | Request, init?: RequestInit) => Promise<Response>;

/** Typed mock callback for `Deno.resolveDns`. */
type ResolveDnsMock = (domain: string, recordType: string) => Promise<string[][]>;

/**
 * Mock a function on an object, restoring the original after the test.
 *
 * @param target - The object whose property to replace.
 * @param key - The property name to mock.
 * @param replacement - The replacement function.
 * @returns A cleanup function that restores the original.
 */
function mockFn(
  target: Record<string | symbol, unknown>,
  key: string,
  replacement: (...args: unknown[]) => unknown,
): () => void {
  const original = target[key];
  target[key] = replacement;
  return () => {
    if (original === undefined) {
      delete target[key];
    } else {
      target[key] = original;
    }
  };
}

/**
 * Mock `Deno.resolveDns` to return the given TXT records.
 */
function mockResolveDns(records: string[][]): () => void {
  const fn: ResolveDnsMock = () => Promise.resolve(records);
  return mockFn(
    Deno as unknown as Record<string, unknown>,
    "resolveDns",
    fn as unknown as (...args: unknown[]) => unknown,
  );
}

/**
 * Mock `Deno.resolveDns` to reject with a value (Error or otherwise).
 */
function mockResolveDnsReject(reason: unknown): () => void {
  const fn: ResolveDnsMock = () => Promise.reject(reason);
  return mockFn(
    Deno as unknown as Record<string, unknown>,
    "resolveDns",
    fn as unknown as (...args: unknown[]) => unknown,
  );
}

/**
 * Mock `globalThis.fetch` with a custom callback.
 *
 * Accepts the narrower `FetchMock` signature and casts internally to
 * satisfy strict function types.
 */
function mockFetch(fn: FetchMock): () => void {
  return mockFn(
    globalThis as unknown as Record<string, unknown>,
    "fetch",
    fn as unknown as (...args: unknown[]) => unknown,
  );
}

/** A minimal valid DID document fixture. */
function didDoc(overrides?: Partial<DidDocument>): DidDocument {
  return {
    id: "did:plc:test",
    service: [{
      id: "#atproto_pds",
      type: "AtprotoPersonalDataServer",
      serviceEndpoint: "https://pds.example",
    }],
    ...overrides,
  };
}

/** A minimal valid LexiconDoc fixture. */
function lexiconDoc(overrides?: Partial<LexiconDoc>): LexiconDoc {
  return {
    lexicon: 1,
    id: "app.bsky.feed.post",
    defs: {},
    ...overrides,
  };
}

/** Create a mock Response with the given status and JSON body. */
function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// ===========================================================================
// DenoDnsResolver
// ===========================================================================

Deno.test("DenoDnsResolver: resolveTxt returns records on success", async () => {
  const records = [["did=did:plc:test"]];
  const restore = mockResolveDns(records);

  try {
    const resolver = new DenoDnsResolver();
    const result = await resolver.resolveTxt(asDomain("feed.bsky.app"));

    assert(result.ok);
    assertEquals(result.value, records);
    assertEquals(result.value[0][0], "did=did:plc:test");
  } finally {
    restore();
  }
});

Deno.test("DenoDnsResolver: resolveTxt prepends _lexicon prefix", async () => {
  let queriedDomain = "";
  const restore = mockFn(
    Deno as unknown as Record<string, unknown>,
    "resolveDns",
    ((domain: string) => {
      queriedDomain = domain;
      return Promise.resolve([["did=did:plc:test"]]);
    }) as unknown as (...args: unknown[]) => unknown,
  );

  try {
    const resolver = new DenoDnsResolver();
    await resolver.resolveTxt(asDomain("feed.bsky.app"));

    assertEquals(queriedDomain, "_lexicon.feed.bsky.app");
  } finally {
    restore();
  }
});

Deno.test("DenoDnsResolver: resolveTxt handles Error rejection", async () => {
  const restore = mockResolveDnsReject(new Error("NXDOMAIN"));

  try {
    const resolver = new DenoDnsResolver();
    const result = await resolver.resolveTxt(asDomain("nonexistent.example"));

    assert(!result.ok);
    if (!result.ok) {
      assert(result.error.includes("DNS query failed"));
      assert(result.error.includes("_lexicon.nonexistent.example"));
      assert(result.error.includes("NXDOMAIN"));
    }
  } finally {
    restore();
  }
});

Deno.test("DenoDnsResolver: resolveTxt handles non-Error rejection", async () => {
  const restore = mockResolveDnsReject("SERVFAIL");

  try {
    const resolver = new DenoDnsResolver();
    const result = await resolver.resolveTxt(asDomain("broken.example"));

    assert(!result.ok);
    if (!result.ok) {
      assert(result.error.includes("DNS query failed"));
      assert(result.error.includes("_lexicon.broken.example"));
      assert(result.error.includes("SERVFAIL"));
    }
  } finally {
    restore();
  }
});

Deno.test("DenoDnsResolver: resolveTxt handles empty records", async () => {
  const restore = mockResolveDns([]);

  try {
    const resolver = new DenoDnsResolver();
    const result = await resolver.resolveTxt(asDomain("feed.bsky.app"));

    assert(result.ok);
    assertEquals(result.value, []);
  } finally {
    restore();
  }
});

Deno.test("DenoDnsResolver: resolveTxt handles multiple TXT records", async () => {
  const records = [
    ["v=spf1 mx ~all"],
    ["did=did:plc:first"],
    ["did=did:plc:second"],
  ];
  const restore = mockResolveDns(records);

  try {
    const resolver = new DenoDnsResolver();
    const result = await resolver.resolveTxt(asDomain("feed.bsky.app"));

    assert(result.ok);
    assertEquals(result.value.length, 3);
  } finally {
    restore();
  }
});

// ===========================================================================
// HttpDidResolver — did:plc
// ===========================================================================

Deno.test("HttpDidResolver: resolves did:plc via PLC directory", async () => {
  const doc: DidDocument = didDoc({ id: "did:plc:ewvi7nxzyoun6zhxrhs64oiz" });

  let fetchedUrl = "";
  const restore = mockFetch((input) => {
    fetchedUrl = typeof input === "string" ? input : input instanceof URL
      ? input.href
      : input.url;
    return Promise.resolve(jsonResponse(200, doc));
  });

  try {
    const resolver = new HttpDidResolver();
    const result = await resolver.resolve(
      asDid("did:plc:ewvi7nxzyoun6zhxrhs64oiz"),
    );

    assert(result.ok);
    if (result.ok) {
      assertEquals(result.value.id, "did:plc:ewvi7nxzyoun6zhxrhs64oiz");
      assertEquals(
        fetchedUrl,
        "https://plc.directory/did:plc:ewvi7nxzyoun6zhxrhs64oiz",
      );
    }
  } finally {
    restore();
  }
});

Deno.test("HttpDidResolver: did:plc does NOT encode colons in URL", async () => {
  let fetchedUrl = "";
  const restore = mockFetch((input) => {
    fetchedUrl = typeof input === "string" ? input : String(input);
    return Promise.resolve(jsonResponse(200, didDoc()));
  });

  try {
    const resolver = new HttpDidResolver();
    await resolver.resolve(asDid("did:plc:ewvi7nxzyoun6zhxrhs64oiz"));

    // Colons must remain unencoded in the PLC directory path.
    assert(fetchedUrl.includes("/did:plc:"));
    assert(!fetchedUrl.includes("%3A"));
  } finally {
    restore();
  }
});

Deno.test("HttpDidResolver: returns error on HTTP non-200 for did:plc", async () => {
  const restore = mockFetch(() =>
    Promise.resolve(jsonResponse(404, { error: "not found" }))
  );

  try {
    const resolver = new HttpDidResolver();
    const result = await resolver.resolve(asDid("did:plc:missing"));

    assert(!result.ok);
    if (!result.ok) {
      assert(result.error.includes("HTTP 404"));
      assert(result.error.includes("did:plc:missing"));
    }
  } finally {
    restore();
  }
});

Deno.test("HttpDidResolver: returns error when fetch throws for did:plc", async () => {
  const restore = mockFetch(() =>
    Promise.reject(new TypeError("Network error"))
  );

  try {
    const resolver = new HttpDidResolver();
    const result = await resolver.resolve(asDid("did:plc:test"));

    assert(!result.ok);
    if (!result.ok) {
      assert(result.error.includes("DID resolution failed"));
      assert(result.error.includes("Network error"));
    }
  } finally {
    restore();
  }
});

// ===========================================================================
// HttpDidResolver — did:web
// ===========================================================================

Deno.test("HttpDidResolver: resolves did:web (simple domain)", async () => {
  const doc = didDoc({ id: "did:web:example.com" });

  let fetchedUrl = "";
  const restore = mockFetch((input) => {
    fetchedUrl = typeof input === "string" ? input : String(input);
    return Promise.resolve(jsonResponse(200, doc));
  });

  try {
    const resolver = new HttpDidResolver();
    const result = await resolver.resolve(asDid("did:web:example.com"));

    assert(result.ok);
    if (result.ok) {
      assertEquals(result.value.id, "did:web:example.com");
      assertEquals(fetchedUrl, "https://example.com/.well-known/did.json");
    }
  } finally {
    restore();
  }
});

Deno.test("HttpDidResolver: resolves did:web (domain with path)", async () => {
  const doc = didDoc({ id: "did:web:example.com:path:to:did" });

  let fetchedUrl = "";
  const restore = mockFetch((input) => {
    fetchedUrl = typeof input === "string" ? input : String(input);
    return Promise.resolve(jsonResponse(200, doc));
  });

  try {
    const resolver = new HttpDidResolver();
    const result = await resolver.resolve(
      asDid("did:web:example.com:path:to:did"),
    );

    assert(result.ok);
    if (result.ok) {
      assertEquals(fetchedUrl, "https://example.com/path/to/did/.well-known/did.json");
    }
  } finally {
    restore();
  }
});

Deno.test("HttpDidResolver: returns error on HTTP non-200 for did:web", async () => {
  const restore = mockFetch(() =>
    Promise.resolve(jsonResponse(500, { error: "server error" }))
  );

  try {
    const resolver = new HttpDidResolver();
    const result = await resolver.resolve(asDid("did:web:example.com"));

    assert(!result.ok);
    if (!result.ok) {
      assert(result.error.includes("HTTP 500"));
    }
  } finally {
    restore();
  }
});

Deno.test("HttpDidResolver: returns error when fetch throws for did:web", async () => {
  const restore = mockFetch(() =>
    Promise.reject(new Error("Connection refused"))
  );

  try {
    const resolver = new HttpDidResolver();
    const result = await resolver.resolve(asDid("did:web:example.com"));

    assert(!result.ok);
    if (!result.ok) {
      assert(result.error.includes("Connection refused"));
    }
  } finally {
    restore();
  }
});

// ===========================================================================
// HttpDidResolver — other DID methods (fallback)
// ===========================================================================

Deno.test("HttpDidResolver: falls back to PLC directory for unknown DID methods", async () => {
  let fetchedUrl = "";
  const restore = mockFetch((input) => {
    fetchedUrl = typeof input === "string" ? input : String(input);
    return Promise.resolve(jsonResponse(200, didDoc({ id: "did:key:z6Mk" })));
  });

  try {
    const resolver = new HttpDidResolver();
    const result = await resolver.resolve(asDid("did:key:z6Mk"));

    assert(result.ok);
    // Fallback uses PLC directory with unencoded DID.
    assertEquals(fetchedUrl, "https://plc.directory/did:key:z6Mk");
  } finally {
    restore();
  }
});

// ===========================================================================
// HttpDidResolver — non-string error handling
// ===========================================================================

Deno.test("HttpDidResolver: handles non-Error fetch rejection", async () => {
  const restore = mockFetch(() => Promise.reject("raw string error"));

  try {
    const resolver = new HttpDidResolver();
    const result = await resolver.resolve(asDid("did:plc:test"));

    assert(!result.ok);
    if (!result.ok) {
      assert(result.error.includes("raw string error"));
    }
  } finally {
    restore();
  }
});

// ===========================================================================
// HttpRecordFetcher
// ===========================================================================

Deno.test("HttpRecordFetcher: fetches and extracts .value from envelope", async () => {
  const lex = lexiconDoc();
  const envelope = { uri: "at://did:plc:test/com.atproto.lexicon.schema/app.bsky.feed.post", cid: "bafy123", value: lex };

  const restore = mockFetch(() =>
    Promise.resolve(jsonResponse(200, envelope))
  );

  try {
    const fetcher = new HttpRecordFetcher();
    const result = await fetcher.fetch("https://pds.example/xrpc/com.atproto.repo.getRecord?repo=did:plc:test");

    assert(result.ok);
    if (result.ok) {
      assertEquals(result.value.id, "app.bsky.feed.post");
      assertEquals(result.value.lexicon, 1);
    }
  } finally {
    restore();
  }
});

Deno.test("HttpRecordFetcher: fetches and extracts lexicon with defs", async () => {
  const lex: LexiconDoc = {
    lexicon: 1,
    id: "com.atproto.repo.createRecord",
    defs: {
      main: { type: "procedure", description: "Create a record" },
    },
  };
  const envelope = { uri: "at://...", cid: "bafy456", value: lex };

  const restore = mockFetch(() => Promise.resolve(jsonResponse(200, envelope)));

  try {
    const fetcher = new HttpRecordFetcher();
    const result = await fetcher.fetch("https://pds.example/xrpc/...");

    assert(result.ok);
    if (result.ok) {
      assertEquals(result.value.defs.main.type, "procedure");
    }
  } finally {
    restore();
  }
});

Deno.test("HttpRecordFetcher: returns error on HTTP error status", async () => {
  const restore = mockFetch(() =>
    Promise.resolve(jsonResponse(503, { error: "Service Unavailable" }))
  );

  try {
    const fetcher = new HttpRecordFetcher();
    const result = await fetcher.fetch("https://pds.example/xrpc/...");

    assert(!result.ok);
    if (!result.ok) {
      assert(result.error.includes("HTTP 503"));
      assert(result.error.includes("https://pds.example"));
    }
  } finally {
    restore();
  }
});

Deno.test("HttpRecordFetcher: returns error when .value is missing", async () => {
  const envelope = { uri: "at://...", cid: "bafy123" }; // No .value

  const restore = mockFetch(() => Promise.resolve(jsonResponse(200, envelope)));

  try {
    const fetcher = new HttpRecordFetcher();
    const result = await fetcher.fetch("https://pds.example/xrpc/...");

    assert(!result.ok);
    if (!result.ok) {
      assert(result.error.includes("missing or invalid .value field"));
    }
  } finally {
    restore();
  }
});

Deno.test("HttpRecordFetcher: returns error when .value is null", async () => {
  const envelope = { uri: "at://...", cid: "bafy123", value: null };

  const restore = mockFetch(() => Promise.resolve(jsonResponse(200, envelope)));

  try {
    const fetcher = new HttpRecordFetcher();
    const result = await fetcher.fetch("https://pds.example/xrpc/...");

    assert(!result.ok);
    if (!result.ok) {
      assert(result.error.includes("missing or invalid .value field"));
    }
  } finally {
    restore();
  }
});

Deno.test("HttpRecordFetcher: returns error when .value.lexicon is not a number", async () => {
  const envelope = { uri: "at://...", cid: "bafy123", value: { lexicon: "1", id: "test", defs: {} } };

  const restore = mockFetch(() => Promise.resolve(jsonResponse(200, envelope)));

  try {
    const fetcher = new HttpRecordFetcher();
    const result = await fetcher.fetch("https://pds.example/xrpc/...");

    assert(!result.ok);
    if (!result.ok) {
      assert(result.error.includes("missing or invalid .value field"));
    }
  } finally {
    restore();
  }
});

Deno.test("HttpRecordFetcher: returns error when fetch throws", async () => {
  const restore = mockFetch(() =>
    Promise.reject(new TypeError("Network error"))
  );

  try {
    const fetcher = new HttpRecordFetcher();
    const result = await fetcher.fetch("https://pds.example/xrpc/...");

    assert(!result.ok);
    if (!result.ok) {
      assert(result.error.includes("Record fetch failed"));
      assert(result.error.includes("Network error"));
    }
  } finally {
    restore();
  }
});

Deno.test("HttpRecordFetcher: returns error when non-Error is thrown", async () => {
  const restore = mockFetch(() => Promise.reject("timeout"));

  try {
    const fetcher = new HttpRecordFetcher();
    const result = await fetcher.fetch("https://pds.example/xrpc/...");

    assert(!result.ok);
    if (!result.ok) {
      assert(result.error.includes("timeout"));
    }
  } finally {
    restore();
  }
});

Deno.test("HttpRecordFetcher: error message includes the endpoint URL", async () => {
  const restore = mockFetch(() =>
    Promise.resolve(jsonResponse(404, { error: "not found" }))
  );

  try {
    const fetcher = new HttpRecordFetcher();
    const result = await fetcher.fetch("https://pds.bsky.app/xrpc/com.atproto.repo.getRecord?repo=did:plc:test&collection=com.atproto.lexicon.schema&rkey=app.bsky.feed.post");

    assert(!result.ok);
    if (!result.ok) {
      assert(result.error.includes("https://pds.bsky.app"));
    }
  } finally {
    restore();
  }
});

// ===========================================================================
// Interface compliance: all adapters implement their ports
// ===========================================================================

Deno.test("ports: DenoDnsResolver satisfies DnsResolver interface", () => {
  // Static check — this test confirms the class compiles against the
  // interface.  The runtime assertion verifies the method exists.
  const resolver = new DenoDnsResolver();
  assertEquals(typeof resolver.resolveTxt, "function");
});

Deno.test("ports: HttpDidResolver satisfies DidResolver interface", () => {
  const resolver = new HttpDidResolver();
  assertEquals(typeof resolver.resolve, "function");
});

Deno.test("ports: HttpRecordFetcher satisfies RecordFetcher interface", () => {
  const fetcher = new HttpRecordFetcher();
  assertEquals(typeof fetcher.fetch, "function");
});
