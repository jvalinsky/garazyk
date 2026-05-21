/**
 * Integration tests for the full lexicon resolution pipeline.
 *
 * Uses real {@link DenoDnsResolver}, {@link HttpDidResolver}, and
 * {@link HttpRecordFetcher} adapters to resolve a known-good AT Protocol
 * lexicon through the DNS → DID → record fetch pipeline.
 *
 * These tests require network access (`--allow-net`).  They are gated
 * behind `Deno.env.get("GARAZYK_INTEGRATION")` so they can be skipped in
 * CI environments without DNS/fetch access.
 *
 * @module lexicon_resolution
 */

import { assertEquals, assert, assertFalse } from "jsr:@std/assert";
import { resolveLexicon } from "./mod.ts";
import {
  DenoDnsResolver,
  HttpDidResolver,
  HttpRecordFetcher,
} from "./adapters.ts";
import { InMemoryCache } from "./cache.ts";
import type { DidDocument, LexiconDoc, ResolutionError } from "./types.ts";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Check whether integration tests should run. */
function shouldRunIntegration(): boolean {
  // Run if GARAZYK_INTEGRATION is "1" or "true", or if not in CI.
  const env = Deno.env.get("GARAZYK_INTEGRATION");
  if (env === "1" || env === "true") return true;
  if (Deno.env.get("CI")) return false;
  // Default: run locally, skip in CI.
  return true;
}

/** Shared caches so repeated integration runs reuse resolved results. */
const _dnsCache = new InMemoryCache<string[][]>({ ttlMs: 3600_000 });
const _didCache = new InMemoryCache<DidDocument>({ ttlMs: 3600_000 });
const _recordCache = new InMemoryCache<LexiconDoc>({ ttlMs: 3600_000 });

/** Build the real port implementations with in-memory caching enabled. */
function makeRealPorts() {
  return {
    dns: new DenoDnsResolver(),
    did: new HttpDidResolver(),
    record: new HttpRecordFetcher(),
    cache: {
      dns: _dnsCache,
      did: _didCache,
      record: _recordCache,
    },
  };
}

/**
 * Verify that a lexicon document has the expected structure.
 *
 * Checks that the top-level fields and the `main` definition are present
 * and correctly typed.
 */
function assertValidLexicon(doc: LexiconDoc, expectedId: string): void {
  assertEquals(doc.id, expectedId, `Lexicon id should match the requested NSID`);
  assertEquals(typeof doc.lexicon, "number", "lexicon version should be a number");
  assert(doc.lexicon >= 1, "lexicon version should be >= 1");
  assert(typeof doc.defs === "object" && doc.defs !== null, "defs should be a non-null object");
  assert("main" in doc.defs, "lexicon should have a main definition");
  assert(
    ["query", "procedure", "record", "token", "subscription"].includes(doc.defs.main.type),
    `main.type should be a valid definition type, got: ${doc.defs.main.type}`,
  );
}

// =============================================================================
// Known-good NSID: app.bsky.feed.post
// =============================================================================

Deno.test({
  name: "integration: resolve app.bsky.feed.post through real adapters",
  ignore: !shouldRunIntegration(),
  fn: async () => {
    const result = await resolveLexicon("app.bsky.feed.post", makeRealPorts());

    assert(result.ok, `Expected resolution to succeed, got: ${
      result.ok ? "" : `${result.error.type}: ${JSON.stringify(result.error)}`
    }`);

    assertValidLexicon(result.value, "app.bsky.feed.post");

    // app.bsky.feed.post should be a record type.
    assertEquals(result.value.defs.main.type, "record",
      "app.bsky.feed.post should be a record type");

    // The record should have a schema with a properties block.
    assert(result.value.defs.main.record, "record definition should have a record schema");
  },
});

// =============================================================================
// Known-good NSID: com.atproto.repo.createRecord
// =============================================================================

Deno.test({
  name: "integration: resolve com.atproto.repo.createRecord through real adapters",
  ignore: !shouldRunIntegration(),
  fn: async () => {
    const result = await resolveLexicon("com.atproto.repo.createRecord", makeRealPorts());

    assert(result.ok, `Expected resolution to succeed, got: ${
      result.ok ? "" : `${result.error.type}: ${JSON.stringify(result.error)}`
    }`);

    assertValidLexicon(result.value, "com.atproto.repo.createRecord");

    // com.atproto.repo.createRecord should be a procedure type.
    assertEquals(result.value.defs.main.type, "procedure",
      "com.atproto.repo.createRecord should be a procedure type");
  },
});

// =============================================================================
// Known-good NSID: com.atproto.repo.getRecord
// =============================================================================

Deno.test({
  name: "integration: resolve com.atproto.repo.getRecord through real adapters",
  ignore: !shouldRunIntegration(),
  fn: async () => {
    const result = await resolveLexicon("com.atproto.repo.getRecord", makeRealPorts());

    assert(result.ok, `Expected resolution to succeed, got: ${
      result.ok ? "" : `${result.error.type}: ${JSON.stringify(result.error)}`
    }`);

    assertValidLexicon(result.value, "com.atproto.repo.getRecord");

    // com.atproto.repo.getRecord should be a query type with parameters.
    assertEquals(result.value.defs.main.type, "query",
      "com.atproto.repo.getRecord should be a query type");
    assert(result.value.defs.main.parameters,
      "com.atproto.repo.getRecord should have query parameters");
  },
});

// =============================================================================
// Error path: unresolvable NSID
// =============================================================================

Deno.test({
  name: "integration: unresolvable NSID returns an error",
  ignore: !shouldRunIntegration(),
  fn: async () => {
    // A namespace that almost certainly has no _lexicon DNS record.
    const result = await resolveLexicon("com.nonexistent.integration.test", makeRealPorts());

    assertFalse(result.ok);

    // The error should be one of the early-stage failures (DNS or DID),
    // not something unexpected.
    if (!result.ok) {
      const validErrorTypes: ResolutionError["type"][] = [
        "InvalidNsid",
        "DnsQueryFailed",
        "NoLexiconDnsRecord",
        "DidResolutionFailed",
        "PdsEndpointMissing",
        "RecordFetchFailed",
        "RecordVerificationFailed",
      ];
      assert(
        validErrorTypes.includes(result.error.type),
        `Unexpected error type: ${result.error.type}`,
      );
    }
  },
});

// =============================================================================
// Consistency: resolve the same NSID twice returns the same id
// =============================================================================

Deno.test({
  name: "integration: resolving the same NSID twice is idempotent",
  ignore: !shouldRunIntegration(),
  fn: async () => {
    const ports = makeRealPorts();

    const first = await resolveLexicon("app.bsky.feed.post", ports);
    const second = await resolveLexicon("app.bsky.feed.post", ports);

    assert(first.ok, "first resolution should succeed");
    assert(second.ok, "second resolution should succeed");

    assertEquals(first.value.id, second.value.id,
      "same NSID should resolve to the same lexicon id");
    assertEquals(first.value.lexicon, second.value.lexicon,
      "same NSID should return the same lexicon version");
    assertEquals(first.value.defs.main.type, second.value.defs.main.type,
      "same NSID should return the same main definition type");
  },
});
