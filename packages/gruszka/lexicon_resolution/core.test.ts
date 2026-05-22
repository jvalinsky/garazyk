/**
 * Unit tests for the sans-IO core transformation functions.
 *
 * Every test in this file exercises a pure, deterministic function with zero
 * external dependencies.  No Deno.* APIs, no fetch, no DNS — just data in,
 * data out.  This makes the suite fast and trivially parallelisable.
 *
 * @module lexicon_resolution
 */

import { assert, assertEquals } from "jsr:@std/assert";

import {
  buildXrpcUrl,
  deriveDnsDomain,
  extractPdsEndpoint,
  parseDnsTxtRecords,
  parseNsid,
  verifyRecord,
} from "./core.ts";
import {
  asDid,
  asDomain,
  asNsid,
  type Did,
  type DidDocument,
  type Domain,
  type LexiconDoc,
  type Nsid,
  type ResolutionError,
  type Result,
} from "./types.ts";

// ===========================================================================
// Helpers
// ===========================================================================

/** Assert that a Result is ok and return its value. */
function unwrap<T>(result: Result<T>): T {
  if (!result.ok) {
    throw new Error(
      `Expected ok but got error: ${JSON.stringify(result.error)}`,
    );
  }
  return result.value;
}

/** Assert that a Result is an error and return it. */
function unwrapErr(result: Result<unknown>): ResolutionError {
  if (result.ok) {
    throw new Error(
      `Expected error but got value: ${JSON.stringify(result.value)}`,
    );
  }
  return result.error;
}

/** Shared domain used across parseDnsTxtRecords tests. */
const testDomain = asDomain("feed.bsky.app");

// ===========================================================================
// parseNsid
// ===========================================================================

Deno.test("parseNsid: splits a three-segment protocol NSID", () => {
  const result = parseNsid(asNsid("com.atproto.repo.createRecord"));
  assert(result.ok);
  assertEquals(result.value.authority, "com.atproto.repo");
  assertEquals(result.value.name, "createRecord");
});

Deno.test("parseNsid: splits a four-segment application NSID", () => {
  const result = parseNsid(asNsid("app.bsky.feed.post"));
  assert(result.ok);
  assertEquals(result.value.authority, "app.bsky.feed");
  assertEquals(result.value.name, "post");
});

Deno.test("parseNsid: splits a deep-namespace NSID", () => {
  const result = parseNsid(
    asNsid("edu.university.dept.lab.blogging.getBlogPost"),
  );
  assert(result.ok);
  assertEquals(result.value.authority, "edu.university.dept.lab.blogging");
  assertEquals(result.value.name, "getBlogPost");
});

Deno.test("parseNsid: returns error when NSID has no dots", () => {
  // Defensive: validator should catch this, but parseNsid handles it anyway.
  const result = parseNsid("bogus" as Nsid);
  if (result.ok) throw new Error("expected error");
  assertEquals(result.error.type, "InvalidNsid");
});

// ===========================================================================
// deriveDnsDomain
// ===========================================================================

Deno.test("deriveDnsDomain: reverses a three-segment authority", () => {
  const domain = deriveDnsDomain("app.bsky.feed");
  assertEquals(domain, "feed.bsky.app" as Domain);
});

Deno.test("deriveDnsDomain: reverses a two-segment authority", () => {
  const domain = deriveDnsDomain("com.atproto");
  assertEquals(domain, "atproto.com" as Domain);
});

Deno.test("deriveDnsDomain: reverses a single-segment authority", () => {
  const domain = deriveDnsDomain("example");
  assertEquals(domain, "example" as Domain);
});

Deno.test("deriveDnsDomain: reverses a four-segment authority", () => {
  const domain = deriveDnsDomain("edu.university.dept.lab");
  assertEquals(domain, "lab.dept.university.edu" as Domain);
});

Deno.test("deriveDnsDomain: returns branded Domain type", () => {
  const domain: Domain = deriveDnsDomain("app.bsky.feed");
  assertEquals(typeof domain, "string");
});

// ===========================================================================
// parseDnsTxtRecords
// ===========================================================================

Deno.test("parseDnsTxtRecords: extracts a PLC DID from a single record", () => {
  const result = parseDnsTxtRecords(
    [["did=did:plc:ewvi7nxzyoun6zhxrhs64oiz"]],
    testDomain,
  );
  assert(result.ok);
  assertEquals(result.value, "did:plc:ewvi7nxzyoun6zhxrhs64oiz" as Did);
});

Deno.test("parseDnsTxtRecords: extracts a web DID", () => {
  const result = parseDnsTxtRecords(
    [["did=did:web:example.com"]],
    testDomain,
  );
  assert(result.ok);
  assertEquals(result.value, "did:web:example.com" as Did);
});

Deno.test("parseDnsTxtRecords: skips whitespace between did= and value", () => {
  const result = parseDnsTxtRecords(
    [["did=  did:plc:test  "]],
    testDomain,
  );
  assert(result.ok);
  assertEquals(result.value, "did:plc:test" as Did);
});

Deno.test("parseDnsTxtRecords: concatenates multiple character strings", () => {
  const result = parseDnsTxtRecords(
    [["did=did:plc:", "ewvi7nxzyoun6zhxrhs64oiz"]],
    testDomain,
  );
  assert(result.ok);
  assertEquals(result.value, "did:plc:ewvi7nxzyoun6zhxrhs64oiz" as Did);
});

Deno.test("parseDnsTxtRecords: picks first did= among multiple records", () => {
  const result = parseDnsTxtRecords([
    ["v=spf1", "did=did:plc:first"],
    ["did=did:plc:second"],
  ], testDomain);
  assert(result.ok);
  assertEquals(result.value, "did:plc:first" as Did);
});

Deno.test("parseDnsTxtRecords: skips records without did= key", () => {
  const result = parseDnsTxtRecords([
    ["v=spf1 mx ~all"],
    ["some=other value"],
    ["did=did:plc:finally"],
  ], testDomain);
  assert(result.ok);
  assertEquals(result.value, "did:plc:finally" as Did);
});

Deno.test("parseDnsTxtRecords: returns error for empty records array", () => {
  const result = parseDnsTxtRecords([], testDomain);
  if (result.ok) throw new Error("expected error");
  assertEquals(result.error.type, "NoLexiconDnsRecord");
  if (result.error.type === "NoLexiconDnsRecord") {
    assertEquals(result.error.domain, testDomain);
  }
});

Deno.test("parseDnsTxtRecords: returns error when no did= entry found", () => {
  const result = parseDnsTxtRecords(
    [["v=spf1 mx ~all"], ["key=value"]],
    testDomain,
  );
  if (result.ok) throw new Error("expected error");
  assertEquals(result.error.type, "NoLexiconDnsRecord");
});

Deno.test("parseDnsTxtRecords: error carries the queried domain for diagnostics", () => {
  const myDomain = asDomain("repo.atproto.com");
  const result = parseDnsTxtRecords([["v=spf1 mx ~all"]], myDomain);
  if (result.ok) throw new Error("expected error");
  if (result.error.type === "NoLexiconDnsRecord") {
    assertEquals(result.error.domain, myDomain);
  }
});

Deno.test("parseDnsTxtRecords: skips malformed DID and finds next valid one", () => {
  const result = parseDnsTxtRecords([
    ["did=did:plc:"],
    ["did=did:plc:valid"],
  ], testDomain);
  assert(result.ok);
  assertEquals(result.value, "did:plc:valid" as Did);
});

Deno.test("parseDnsTxtRecords: returns branded Did type", () => {
  const result = parseDnsTxtRecords(
    [["did=did:plc:test"]],
    testDomain,
  );
  assert(result.ok);
  const did: Did = result.value;
  assertEquals(typeof did, "string");
});

// ===========================================================================
// extractPdsEndpoint
// ===========================================================================

Deno.test("extractPdsEndpoint: extracts a string serviceEndpoint", () => {
  const doc: DidDocument = {
    id: "did:plc:test",
    service: [{
      id: "#atproto_pds",
      type: "AtprotoPersonalDataServer",
      serviceEndpoint: "https://pds.example",
    }],
  };
  const result = extractPdsEndpoint(doc);
  assert(result.ok);
  assertEquals(result.value, "https://pds.example");
});

Deno.test("extractPdsEndpoint: extracts from object-form serviceEndpoint", () => {
  const doc: DidDocument = {
    id: "did:plc:test",
    service: [{
      id: "#atproto_pds",
      type: "AtprotoPersonalDataServer",
      serviceEndpoint: { url: "https://pds-object.example" },
    }],
  };
  const result = extractPdsEndpoint(doc);
  assert(result.ok);
  assertEquals(result.value, "https://pds-object.example");
});

Deno.test("extractPdsEndpoint: picks first PDS when multiple services exist", () => {
  const doc: DidDocument = {
    id: "did:plc:test",
    service: [
      {
        id: "#atproto_pds_primary",
        type: "AtprotoPersonalDataServer",
        serviceEndpoint: "https://primary.example",
      },
      {
        id: "#atproto_pds_fallback",
        type: "AtprotoPersonalDataServer",
        serviceEndpoint: "https://fallback.example",
      },
    ],
  };
  const result = extractPdsEndpoint(doc);
  assert(result.ok);
  assertEquals(result.value, "https://primary.example");
});

Deno.test("extractPdsEndpoint: skips non-PDS service types", () => {
  const doc: DidDocument = {
    id: "did:plc:test",
    service: [
      {
        id: "#some_other",
        type: "LinkedDomains",
        serviceEndpoint: "https://other.example",
      },
      {
        id: "#atproto_pds",
        type: "AtprotoPersonalDataServer",
        serviceEndpoint: "https://pds.example",
      },
    ],
  };
  const result = extractPdsEndpoint(doc);
  assert(result.ok);
  assertEquals(result.value, "https://pds.example");
});

Deno.test("extractPdsEndpoint: returns error for empty service array", () => {
  const doc: DidDocument = {
    id: "did:plc:test",
    service: [],
  };
  const result = extractPdsEndpoint(doc);
  if (result.ok) throw new Error("expected error");
  assertEquals(result.error.type, "PdsEndpointMissing");
  if (result.error.type === "PdsEndpointMissing") {
    assertEquals(result.error.did, "did:plc:test" as Did);
  }
});

Deno.test("extractPdsEndpoint: returns error when services undefined", () => {
  const doc: DidDocument = {
    id: "did:plc:test",
  };
  const result = extractPdsEndpoint(doc);
  if (result.ok) throw new Error("expected error");
  assertEquals(result.error.type, "PdsEndpointMissing");
});

Deno.test("extractPdsEndpoint: returns error for empty serviceEndpoint string", () => {
  const doc: DidDocument = {
    id: "did:plc:test",
    service: [{
      id: "#atproto_pds",
      type: "AtprotoPersonalDataServer",
      serviceEndpoint: "",
    }],
  };
  const result = extractPdsEndpoint(doc);
  if (result.ok) throw new Error("expected error");
  assertEquals(result.error.type, "PdsEndpointMissing");
});

Deno.test("extractPdsEndpoint: returns error for missing url in object endpoint", () => {
  const doc: DidDocument = {
    id: "did:plc:test",
    service: [{
      id: "#atproto_pds",
      type: "AtprotoPersonalDataServer",
      serviceEndpoint: {} as unknown as { url: string },
    }],
  };
  const result = extractPdsEndpoint(doc);
  if (result.ok) throw new Error("expected error");
  assertEquals(result.error.type, "PdsEndpointMissing");
});

// ===========================================================================
// buildXrpcUrl
// ===========================================================================

Deno.test("buildXrpcUrl: constructs a URL with encoded parameters", () => {
  const url = buildXrpcUrl(
    "https://pds.example",
    asDid("did:plc:test"),
    asNsid("app.bsky.feed.post"),
  );
  assertEquals(
    url,
    "https://pds.example/xrpc/com.atproto.repo.getRecord" +
      "?repo=did%3Aplc%3Atest" +
      "&collection=com.atproto.lexicon.schema" +
      "&rkey=app.bsky.feed.post",
  );
});

Deno.test("buildXrpcUrl: strips trailing slash from PDS endpoint", () => {
  const url = buildXrpcUrl(
    "https://pds.example/",
    asDid("did:plc:test"),
    asNsid("app.bsky.feed.post"),
  );
  assertEquals(
    url,
    "https://pds.example/xrpc/com.atproto.repo.getRecord" +
      "?repo=did%3Aplc%3Atest" +
      "&collection=com.atproto.lexicon.schema" +
      "&rkey=app.bsky.feed.post",
  );
});

Deno.test("buildXrpcUrl: strips multiple trailing slashes", () => {
  const url = buildXrpcUrl(
    "https://pds.example///",
    asDid("did:plc:test"),
    asNsid("app.bsky.feed.post"),
  );
  assertEquals(
    url,
    "https://pds.example/xrpc/com.atproto.repo.getRecord" +
      "?repo=did%3Aplc%3Atest" +
      "&collection=com.atproto.lexicon.schema" +
      "&rkey=app.bsky.feed.post",
  );
});

Deno.test("buildXrpcUrl: encodes colons in DID as %3A", () => {
  const url = buildXrpcUrl(
    "https://pds.example",
    asDid("did:plc:ewvi7nxzyoun6zhxrhs64oiz"),
    asNsid("com.atproto.repo.createRecord"),
  );
  assert(url.includes("repo=did%3Aplc%3A"));
});

Deno.test("buildXrpcUrl: dots are not encoded in rkey", () => {
  const url = buildXrpcUrl(
    "https://pds.example",
    asDid("did:plc:test"),
    asNsid("app.bsky.feed.post"),
  );
  assert(url.includes("rkey=app.bsky.feed.post"));
});

Deno.test("buildXrpcUrl: always uses com.atproto.lexicon.schema collection", () => {
  const url = buildXrpcUrl(
    "https://pds.example",
    asDid("did:plc:test"),
    asNsid("app.bsky.feed.post"),
  );
  assert(url.includes("collection=com.atproto.lexicon.schema"));
});

// ===========================================================================
// verifyRecord
// ===========================================================================

Deno.test("verifyRecord: returns ok when id matches nsid", () => {
  const lexicon: LexiconDoc = {
    lexicon: 1,
    id: "app.bsky.feed.post",
    defs: {},
  };
  const result = verifyRecord(lexicon, asNsid("app.bsky.feed.post"));
  assert(result.ok);
  assertEquals(result.value.id, "app.bsky.feed.post");
});

Deno.test("verifyRecord: returns same LexiconDoc object on success", () => {
  const lexicon: LexiconDoc = {
    lexicon: 1,
    id: "app.bsky.feed.post",
    defs: {},
  };
  const result = verifyRecord(lexicon, asNsid("app.bsky.feed.post"));
  assert(result.ok);
  assertEquals(result.value, lexicon);
});

Deno.test("verifyRecord: returns error when id does not match nsid", () => {
  const lexicon: LexiconDoc = {
    lexicon: 1,
    id: "app.bsky.feed.like",
    defs: {},
  };
  const result = verifyRecord(lexicon, asNsid("app.bsky.feed.post"));
  if (result.ok) throw new Error("expected error");
  assertEquals(result.error.type, "RecordVerificationFailed");
});

Deno.test("verifyRecord: error includes nsid in the error payload", () => {
  const lexicon: LexiconDoc = {
    lexicon: 1,
    id: "spoofed.id",
    defs: {},
  };
  const result = verifyRecord(lexicon, asNsid("app.bsky.feed.post"));
  if (result.ok) throw new Error("expected error");
  if (result.error.type === "RecordVerificationFailed") {
    assertEquals(result.error.nsid, "app.bsky.feed.post" as Nsid);
  }
});

Deno.test("verifyRecord: error reason contains both IDs for diagnostics", () => {
  const lexicon: LexiconDoc = {
    lexicon: 1,
    id: "spoofed.id",
    defs: {},
  };
  const result = verifyRecord(lexicon, asNsid("app.bsky.feed.post"));
  if (result.ok) throw new Error("expected error");
  if (result.error.type === "RecordVerificationFailed") {
    assert(result.error.reason.includes("spoofed.id"));
    assert(result.error.reason.includes("app.bsky.feed.post"));
  }
});

Deno.test("verifyRecord: passes when both id and nsid are long NSIDs", () => {
  const nsid = asNsid("edu.university.dept.lab.blogging.getBlogPost");
  const lexicon: LexiconDoc = {
    lexicon: 1,
    id: "edu.university.dept.lab.blogging.getBlogPost",
    defs: {},
  };
  const result = verifyRecord(lexicon, nsid);
  assert(result.ok);
});

// ===========================================================================
// Integration: full resolution pipeline (sans-IO)
// ===========================================================================

Deno.test("core pipeline: parseNsid → deriveDnsDomain → … → verifyRecord (happy path)", () => {
  const nsid = asNsid("app.bsky.feed.post");

  const parsed = unwrap(parseNsid(nsid));
  assertEquals(parsed.authority, "app.bsky.feed");
  assertEquals(parsed.name, "post");

  const domain = deriveDnsDomain(parsed.authority);
  assertEquals(domain, "feed.bsky.app" as Domain);

  const dnsResult = parseDnsTxtRecords(
    [["did=did:plc:test"]],
    asDomain("feed.bsky.app"),
  );
  const did = unwrap(dnsResult);
  assertEquals(did, "did:plc:test" as Did);

  const doc: DidDocument = {
    id: did,
    service: [{
      id: "#atproto_pds",
      type: "AtprotoPersonalDataServer",
      serviceEndpoint: "https://pds.bsky.app",
    }],
  };
  const pdsUrl = unwrap(extractPdsEndpoint(doc));
  assertEquals(pdsUrl, "https://pds.bsky.app");

  const xrpcUrl = buildXrpcUrl(pdsUrl, did, nsid);
  assertEquals(
    xrpcUrl,
    "https://pds.bsky.app/xrpc/com.atproto.repo.getRecord" +
      "?repo=did%3Aplc%3Atest" +
      "&collection=com.atproto.lexicon.schema" +
      "&rkey=app.bsky.feed.post",
  );

  const fetched: LexiconDoc = {
    lexicon: 1,
    id: "app.bsky.feed.post",
    defs: {
      main: {
        type: "record",
        record: {
          type: "object",
          properties: { text: { type: "string" } },
        },
      },
    },
  };
  const verified = unwrap(verifyRecord(fetched, nsid));
  assertEquals(verified.id, "app.bsky.feed.post");
});

Deno.test("core pipeline: verification rejects mismatched records", () => {
  const nsid = asNsid("app.bsky.feed.post");
  const parsed = unwrap(parseNsid(nsid));

  const dnsResult = parseDnsTxtRecords(
    [["did=did:plc:test"]],
    asDomain("feed.bsky.app"),
  );
  const did = unwrap(dnsResult);

  const pdsUrl = unwrap(extractPdsEndpoint({
    id: did,
    service: [{
      id: "#atproto_pds",
      type: "AtprotoPersonalDataServer",
      serviceEndpoint: "https://pds.bsky.app",
    }],
  }));

  const xrpcUrl = buildXrpcUrl(pdsUrl, did, nsid);
  assert(xrpcUrl.includes("app.bsky.feed.post"));

  const fetched: LexiconDoc = {
    lexicon: 1,
    id: "app.bsky.feed.like",
    defs: {},
  };
  const error = unwrapErr(verifyRecord(fetched, nsid));
  assertEquals(error.type, "RecordVerificationFailed");
});

Deno.test("core pipeline: fails early on NoLexiconDnsRecord", () => {
  const nsid = asNsid("app.bsky.feed.post");
  const parsed = unwrap(parseNsid(nsid));

  const domain = asDomain("feed.bsky.app");
  const result = parseDnsTxtRecords([["v=spf1 mx ~all"]], domain);
  if (result.ok) throw new Error("expected error");
  assertEquals(result.error.type, "NoLexiconDnsRecord");
  if (result.error.type === "NoLexiconDnsRecord") {
    assertEquals(result.error.domain, domain);
  }
});
