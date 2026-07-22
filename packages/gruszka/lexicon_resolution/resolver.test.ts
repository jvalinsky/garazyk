/**
 * Deterministic unit tests for the sans-IO lexicon resolver state machine.
 *
 * Every `(state, msg)` transition is tested with precise assertions on the
 * returned state status, discriminated fields, and emitted command.  Pipeline
 * tests exercise full resolution flows end-to-end without any I/O.
 *
 * @module lexicon_resolution
 */

import { assert, assertEquals } from "@std/assert";

import { init, update } from "./resolver.ts";
import {
  asDid,
  asDomain,
  asNsid,
  type Did,
  type DidDocument,
  type DidPendingState,
  type DnsPendingState,
  type LexiconDoc,
  type RecordPendingState,
  type ResolverMsg,
  type ResolverState,
} from "./types.ts";

// ===========================================================================
// Test data
// ===========================================================================

const validNsid = "app.bsky.feed.post";
const brandedNsid = asNsid(validNsid);
const expectedDomain = asDomain("feed.bsky.app");
const testDid = asDid("did:plc:test");

/** Create a lexicon doc with the given id. */
function lexicon(id: string): LexiconDoc {
  return { lexicon: 1, id, defs: {} };
}

/** Create a DID document with an AtprotoPersonalDataServer service. */
function didDoc(id: string, pdsUrl: string): DidDocument {
  return {
    id,
    service: [{
      id: "#atproto_pds",
      type: "AtprotoPersonalDataServer",
      serviceEndpoint: pdsUrl,
    }],
  };
}

/** DnsPendingState fixture. */
function dnsPending(
  nsid = brandedNsid,
  domain = expectedDomain,
): DnsPendingState {
  return { status: "dnsPending", nsid, domain };
}

/** DidPendingState fixture. */
function didPending(
  nsid = brandedNsid,
  domain = expectedDomain,
  did: Did = testDid,
): DidPendingState {
  return { status: "didPending", nsid, domain, did };
}

/** RecordPendingState fixture. */
function recordPending(
  nsid = brandedNsid,
  domain = expectedDomain,
  did: Did = testDid,
  pdsEndpoint = "https://pds.example",
): RecordPendingState {
  return { status: "recordPending", nsid, domain, did, pdsEndpoint };
}

// ===========================================================================
// init
// ===========================================================================

Deno.test("init: valid NSID returns dnsPending + resolveDns", () => {
  const [state, cmd] = init(validNsid);

  assertEquals(state.status, "dnsPending");
  if (state.status !== "dnsPending") throw new Error("unreachable");

  assertEquals(state.nsid, brandedNsid);
  assertEquals(state.domain, expectedDomain);
  assertEquals(cmd.type, "resolveDns");
  if (cmd.type === "resolveDns") {
    assertEquals(cmd.domain, expectedDomain);
  }
});

Deno.test("init: invalid NSID returns failed + done with InvalidNsid", () => {
  const [state, cmd] = init("bogus!");

  assertEquals(state.status, "failed");
  if (state.status !== "failed") throw new Error("unreachable");

  assertEquals(state.error.type, "InvalidNsid");
  assertEquals(cmd.type, "done");
});

Deno.test("init: NSID with fewer than 3 segments returns failed", () => {
  const [state, cmd] = init("example.hello");

  assertEquals(state.status, "failed");
  assertEquals(cmd.type, "done");
});

Deno.test("init: empty string returns failed", () => {
  const [state, cmd] = init("");

  assertEquals(state.status, "failed");
  assertEquals(cmd.type, "done");
});

// ===========================================================================
// Terminal sinks
// ===========================================================================

Deno.test("resolved: ignores all message types", () => {
  const resolved: ResolverState = {
    status: "resolved",
    lexicon: lexicon("app.bsky.feed.post"),
    nsid: brandedNsid,
  };

  const msgs: ResolverMsg[] = [
    { type: "dnsSuccess", records: [] },
    { type: "dnsFailed", reason: "e" },
    { type: "didSuccess", document: didDoc("did:plc:x", "https://p.example") },
    { type: "didFailed", reason: "e" },
    { type: "recordSuccess", lexicon: lexicon("app.bsky.feed.post") },
    { type: "recordFailed", reason: "e" },
  ];

  for (const msg of msgs) {
    const [next, cmd] = update(resolved, msg);
    assertEquals(next, resolved);
    assertEquals(cmd.type, "done");
  }
});

Deno.test("failed: ignores all message types", () => {
  const failed: ResolverState = {
    status: "failed",
    error: { type: "InvalidNsid", nsid: "x" },
  };

  const msgs: ResolverMsg[] = [
    { type: "dnsSuccess", records: [] },
    { type: "dnsFailed", reason: "e" },
    { type: "didSuccess", document: didDoc("did:plc:x", "https://p.example") },
    { type: "didFailed", reason: "e" },
    { type: "recordSuccess", lexicon: lexicon("app.bsky.feed.post") },
    { type: "recordFailed", reason: "e" },
  ];

  for (const msg of msgs) {
    const [next, cmd] = update(failed, msg);
    assertEquals(next, failed);
    assertEquals(cmd.type, "done");
  }
});

// ===========================================================================
// init state (defensive)
// ===========================================================================

Deno.test("init state: any message → failed + done", () => {
  const initState: ResolverState = { status: "init" };

  for (
    const msg of [
      { type: "dnsSuccess" as const, records: [] },
      { type: "dnsFailed" as const, reason: "e" },
      {
        type: "didSuccess" as const,
        document: didDoc("did:plc:x", "https://p.example"),
      },
      { type: "didFailed" as const, reason: "e" },
      { type: "recordSuccess" as const, lexicon: lexicon("x.y.z") },
      { type: "recordFailed" as const, reason: "e" },
    ]
  ) {
    const [next, cmd] = update(initState, msg);
    assertEquals(next.status, "failed");
    assertEquals(cmd.type, "done");
  }
});

// ===========================================================================
// dnsPending transitions
// ===========================================================================

Deno.test("T2: dnsPending + dnsSuccess with valid DID → didPending + resolveDid", () => {
  const state = dnsPending();
  const msg: ResolverMsg = {
    type: "dnsSuccess",
    records: [["did=did:plc:ewvi7nxzyoun6zhxrhs64oiz"]],
  };

  const [next, cmd] = update(state, msg);

  assertEquals(next.status, "didPending");
  if (next.status !== "didPending") throw new Error("unreachable");
  assertEquals(next.nsid, brandedNsid);
  assertEquals(next.domain, expectedDomain);
  assertEquals(next.did, "did:plc:ewvi7nxzyoun6zhxrhs64oiz" as Did);
  assertEquals(cmd.type, "resolveDid");
  if (cmd.type === "resolveDid") {
    assertEquals(cmd.did, "did:plc:ewvi7nxzyoun6zhxrhs64oiz" as Did);
  }
});

Deno.test("T2: dnsPending + dnsSuccess preserves nsid even with different domain from init", () => {
  const nsid = asNsid("com.atproto.repo.createRecord");
  const domain = asDomain("repo.atproto.com");
  const state = dnsPending(nsid, domain);
  const msg: ResolverMsg = {
    type: "dnsSuccess",
    records: [["did=did:plc:other"]],
  };

  const [next] = update(state, msg);
  assertEquals(next.status, "didPending");
  if (next.status !== "didPending") throw new Error("unreachable");
  assertEquals(next.nsid, nsid);
  assertEquals(next.domain, domain);
});

Deno.test("T3: dnsPending + dnsSuccess with no did= record → failed + done", () => {
  const state = dnsPending();
  const msg: ResolverMsg = {
    type: "dnsSuccess",
    records: [["v=spf1 mx ~all"]],
  };

  const [next, cmd] = update(state, msg);

  assertEquals(next.status, "failed");
  if (next.status !== "failed") throw new Error("unreachable");
  assertEquals(next.error.type, "NoLexiconDnsRecord");
  if (next.error.type === "NoLexiconDnsRecord") {
    assertEquals(next.error.domain, expectedDomain);
  }
  assertEquals(cmd.type, "done");
});

Deno.test("T4: dnsPending + dnsFailed → failed + done", () => {
  const state = dnsPending();
  const msg: ResolverMsg = { type: "dnsFailed", reason: "NXDOMAIN" };

  const [next, cmd] = update(state, msg);

  assertEquals(next.status, "failed");
  if (next.status !== "failed") throw new Error("unreachable");
  assertEquals(next.error.type, "DnsQueryFailed");
  if (next.error.type === "DnsQueryFailed") {
    assertEquals(next.error.domain, expectedDomain);
    assertEquals(next.error.reason, "NXDOMAIN");
  }
  assertEquals(cmd.type, "done");
});

Deno.test("T5: dnsPending + didSuccess (stale) → re-emit resolveDns", () => {
  const state = dnsPending();
  const msg: ResolverMsg = {
    type: "didSuccess",
    document: didDoc("did:plc:test", "https://pds.example"),
  };

  const [next, cmd] = update(state, msg);

  assertEquals(next.status, "dnsPending");
  assertEquals(next, state); // exact same reference
  assertEquals(cmd.type, "resolveDns");
  if (cmd.type === "resolveDns") {
    assertEquals(cmd.domain, expectedDomain);
  }
});

Deno.test("T6: dnsPending + didFailed (stale) → re-emit resolveDns", () => {
  const state = dnsPending();
  const msg: ResolverMsg = { type: "didFailed", reason: "timeout" };

  const [next, cmd] = update(state, msg);

  assertEquals(next.status, "dnsPending");
  assertEquals(cmd.type, "resolveDns");
});

Deno.test("T7: dnsPending + recordSuccess (stale) → re-emit resolveDns", () => {
  const state = dnsPending();
  const msg: ResolverMsg = {
    type: "recordSuccess",
    lexicon: lexicon("app.bsky.feed.post"),
  };

  const [next, cmd] = update(state, msg);

  assertEquals(next.status, "dnsPending");
  assertEquals(cmd.type, "resolveDns");
});

Deno.test("T8: dnsPending + recordFailed (stale) → re-emit resolveDns", () => {
  const state = dnsPending();
  const msg: ResolverMsg = { type: "recordFailed", reason: "500" };

  const [next, cmd] = update(state, msg);

  assertEquals(next.status, "dnsPending");
  assertEquals(cmd.type, "resolveDns");
});

// ===========================================================================
// didPending transitions
// ===========================================================================

Deno.test("T9: didPending + didSuccess with PDS endpoint → recordPending + fetchRecord", () => {
  const state = didPending();
  const msg: ResolverMsg = {
    type: "didSuccess",
    document: didDoc(testDid, "https://pds.bsky.app"),
  };

  const [next, cmd] = update(state, msg);

  assertEquals(next.status, "recordPending");
  if (next.status !== "recordPending") throw new Error("unreachable");
  assertEquals(next.nsid, brandedNsid);
  assertEquals(next.domain, expectedDomain);
  assertEquals(next.did, testDid);
  assertEquals(next.pdsEndpoint, "https://pds.bsky.app");
  assertEquals(cmd.type, "fetchRecord");
  if (cmd.type === "fetchRecord") {
    assertEquals(cmd.did, testDid);
    assertEquals(cmd.nsid, brandedNsid);
    assert(cmd.endpoint.includes("com.atproto.repo.getRecord"));
    assert(cmd.endpoint.includes("collection=com.atproto.lexicon.schema"));
  }
});

Deno.test("T9: didPending + didSuccess forwards arbitrary PDS URL", () => {
  const state = didPending();
  const msg: ResolverMsg = {
    type: "didSuccess",
    document: didDoc(testDid, "https://custom-pds.example:3000"),
  };

  const [next, cmd] = update(state, msg);

  assertEquals(next.status, "recordPending");
  if (next.status !== "recordPending") {
    throw new Error("unreachable");
  }
  assertEquals(next.pdsEndpoint, "https://custom-pds.example:3000");
  if (cmd.type === "fetchRecord") {
    assert(cmd.endpoint.startsWith("https://custom-pds.example:3000/xrpc/"));
  }
});

Deno.test("T10: didPending + didSuccess with no PDS service → failed + done", () => {
  const state = didPending();
  const doc: DidDocument = {
    id: testDid,
    service: [],
  };
  const msg: ResolverMsg = { type: "didSuccess", document: doc };

  const [next, cmd] = update(state, msg);

  assertEquals(next.status, "failed");
  if (next.status !== "failed") throw new Error("unreachable");
  assertEquals(next.error.type, "PdsEndpointMissing");
  assertEquals(cmd.type, "done");
});

Deno.test("T11: didPending + didFailed → failed + done", () => {
  const state = didPending();
  const msg: ResolverMsg = { type: "didFailed", reason: "did not found" };

  const [next, cmd] = update(state, msg);

  assertEquals(next.status, "failed");
  if (next.status !== "failed") throw new Error("unreachable");
  assertEquals(next.error.type, "DidResolutionFailed");
  if (next.error.type === "DidResolutionFailed") {
    assertEquals(next.error.did, testDid);
    assertEquals(next.error.reason, "did not found");
  }
  assertEquals(cmd.type, "done");
});

Deno.test("T12: didPending + dnsSuccess (stale) → re-emit resolveDid", () => {
  const state = didPending();
  const msg: ResolverMsg = {
    type: "dnsSuccess",
    records: [["did=did:plc:new"]],
  };

  const [next, cmd] = update(state, msg);

  assertEquals(next.status, "didPending");
  assertEquals(cmd.type, "resolveDid");
  if (cmd.type === "resolveDid") {
    assertEquals(cmd.did, testDid); // uses stored DID, not the new one
  }
});

Deno.test("T13: didPending + dnsFailed (stale) → re-emit resolveDid", () => {
  const state = didPending();
  const msg: ResolverMsg = { type: "dnsFailed", reason: "timeout" };

  const [next, cmd] = update(state, msg);

  assertEquals(next.status, "didPending");
  assertEquals(cmd.type, "resolveDid");
});

Deno.test("T14: didPending + recordSuccess (stale) → re-emit resolveDid", () => {
  const state = didPending();
  const msg: ResolverMsg = {
    type: "recordSuccess",
    lexicon: lexicon("app.bsky.feed.post"),
  };

  const [next, cmd] = update(state, msg);

  assertEquals(next.status, "didPending");
  assertEquals(cmd.type, "resolveDid");
});

Deno.test("T15: didPending + recordFailed (stale) → re-emit resolveDid", () => {
  const state = didPending();
  const msg: ResolverMsg = { type: "recordFailed", reason: "404" };

  const [next, cmd] = update(state, msg);

  assertEquals(next.status, "didPending");
  assertEquals(cmd.type, "resolveDid");
});

// ===========================================================================
// recordPending transitions
// ===========================================================================

Deno.test("T16: recordPending + recordSuccess with matching NSID → resolved + done", () => {
  const state = recordPending();
  const msg: ResolverMsg = {
    type: "recordSuccess",
    lexicon: lexicon(validNsid),
  };

  const [next, cmd] = update(state, msg);

  assertEquals(next.status, "resolved");
  if (next.status !== "resolved") throw new Error("unreachable");
  assertEquals(next.nsid, brandedNsid);
  assertEquals(next.lexicon.id, validNsid);
  assertEquals(cmd.type, "done");
});

Deno.test("T17: recordPending + recordSuccess with mismatched NSID → failed + done", () => {
  const state = recordPending();
  const msg: ResolverMsg = {
    type: "recordSuccess",
    lexicon: lexicon("app.bsky.feed.like"), // different from validNsid
  };

  const [next, cmd] = update(state, msg);

  assertEquals(next.status, "failed");
  if (next.status !== "failed") throw new Error("unreachable");
  assertEquals(next.error.type, "RecordVerificationFailed");
  if (next.error.type === "RecordVerificationFailed") {
    assertEquals(next.error.nsid, brandedNsid);
  }
  assertEquals(cmd.type, "done");
});

Deno.test("T18: recordPending + recordFailed → failed + done", () => {
  const state = recordPending();
  const msg: ResolverMsg = { type: "recordFailed", reason: "network error" };

  const [next, cmd] = update(state, msg);

  assertEquals(next.status, "failed");
  if (next.status !== "failed") throw new Error("unreachable");
  assertEquals(next.error.type, "RecordFetchFailed");
  if (next.error.type === "RecordFetchFailed") {
    assert(next.error.endpoint.includes("com.atproto.repo.getRecord"));
    assertEquals(next.error.reason, "network error");
  }
  assertEquals(cmd.type, "done");
});

Deno.test("T19: recordPending + dnsSuccess (stale) → re-emit fetchRecord", () => {
  const state = recordPending();
  const msg: ResolverMsg = {
    type: "dnsSuccess",
    records: [["did=did:plc:stale"]],
  };

  const [next, cmd] = update(state, msg);

  assertEquals(next.status, "recordPending");
  assertEquals(next, state); // same reference
  assertEquals(cmd.type, "fetchRecord");
  if (cmd.type === "fetchRecord") {
    assertEquals(cmd.did, testDid);
    assertEquals(cmd.nsid, brandedNsid);
    assert(cmd.endpoint.includes("com.atproto.repo.getRecord"));
  }
});

Deno.test("T20: recordPending + dnsFailed (stale) → re-emit fetchRecord", () => {
  const state = recordPending();
  const msg: ResolverMsg = { type: "dnsFailed", reason: "timeout" };

  const [next, cmd] = update(state, msg);

  assertEquals(next.status, "recordPending");
  assertEquals(cmd.type, "fetchRecord");
});

Deno.test("T21: recordPending + didSuccess (stale) → re-emit fetchRecord", () => {
  const state = recordPending();
  const msg: ResolverMsg = {
    type: "didSuccess",
    document: didDoc(testDid, "https://different.example"),
  };

  const [next, cmd] = update(state, msg);

  assertEquals(next.status, "recordPending");
  assertEquals(cmd.type, "fetchRecord");
});

Deno.test("T22: recordPending + didFailed (stale) → re-emit fetchRecord", () => {
  const state = recordPending();
  const msg: ResolverMsg = { type: "didFailed", reason: "not found" };

  const [next, cmd] = update(state, msg);

  assertEquals(next.status, "recordPending");
  assertEquals(cmd.type, "fetchRecord");
});

// ===========================================================================
// Pipeline: full happy path
// ===========================================================================

Deno.test("pipeline: full happy path — init → dnsSuccess → didSuccess → recordSuccess → resolved", () => {
  // Step 0: init
  const [s0] = init("app.bsky.feed.post");
  assertEquals(s0.status, "dnsPending");

  // Step 1: DNS TXT returns a DID
  const [s1, c1] = update(s0, {
    type: "dnsSuccess",
    records: [["did=did:plc:ewvi7nxzyoun6zhxrhs64oiz"]],
  });
  assertEquals(s1.status, "didPending");
  assertEquals(c1.type, "resolveDid");

  // Step 2: DID resolution returns a PDS endpoint
  const [s2, c2] = update(s1, {
    type: "didSuccess",
    document: {
      id: "did:plc:ewvi7nxzyoun6zhxrhs64oiz",
      service: [{
        id: "#atproto_pds",
        type: "AtprotoPersonalDataServer",
        serviceEndpoint: "https://pds.bsky.app",
      }],
    },
  });
  assertEquals(s2.status, "recordPending");
  assertEquals(c2.type, "fetchRecord");

  // Step 3: Record fetch returns a lexicon that matches
  const [s3, c3] = update(s2, {
    type: "recordSuccess",
    lexicon: {
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
    },
  });
  assertEquals(s3.status, "resolved");
  assertEquals(c3.type, "done");

  // Verify the resolved state
  if (s3.status !== "resolved") throw new Error("unreachable");
  assertEquals(s3.nsid, asNsid("app.bsky.feed.post"));
  assertEquals(s3.lexicon.id, "app.bsky.feed.post");
});

// ===========================================================================
// Pipeline: error paths
// ===========================================================================

Deno.test("pipeline: fails at DNS lookup", () => {
  const [s0] = init("com.atproto.repo.createRecord");
  assertEquals(s0.status, "dnsPending");

  const [s1, c1] = update(s0, { type: "dnsFailed", reason: "SERVFAIL" });
  assertEquals(s1.status, "failed");
  if (s1.status !== "failed") throw new Error("unreachable");
  assertEquals(s1.error.type, "DnsQueryFailed");
  assertEquals(c1.type, "done");
});

Deno.test("pipeline: fails at DID resolution", () => {
  const [s0] = init("com.atproto.repo.createRecord");

  const [s1] = update(s0, {
    type: "dnsSuccess",
    records: [["did=did:plc:test"]],
  });
  assertEquals(s1.status, "didPending");

  const [s2, c2] = update(s1, { type: "didFailed", reason: "rate limited" });
  assertEquals(s2.status, "failed");
  if (s2.status !== "failed") throw new Error("unreachable");
  assertEquals(s2.error.type, "DidResolutionFailed");
  assertEquals(c2.type, "done");
});

Deno.test("pipeline: fails at record fetch", () => {
  const [s0] = init("com.atproto.repo.createRecord");

  const [s1] = update(s0, {
    type: "dnsSuccess",
    records: [["did=did:plc:test"]],
  });

  const [s2] = update(s1, {
    type: "didSuccess",
    document: didDoc("did:plc:test", "https://pds.example"),
  });
  assertEquals(s2.status, "recordPending");

  const [s3, c3] = update(s2, {
    type: "recordFailed",
    reason: "connection refused",
  });
  assertEquals(s3.status, "failed");
  if (s3.status !== "failed") throw new Error("unreachable");
  assertEquals(s3.error.type, "RecordFetchFailed");
  assertEquals(c3.type, "done");
});

Deno.test("pipeline: fails at record verification", () => {
  const [s0] = init("com.atproto.repo.createRecord");

  const [s1] = update(s0, {
    type: "dnsSuccess",
    records: [["did=did:plc:test"]],
  });

  const [s2] = update(s1, {
    type: "didSuccess",
    document: didDoc("did:plc:test", "https://pds.example"),
  });
  assertEquals(s2.status, "recordPending");

  const [s3, c3] = update(s2, {
    type: "recordSuccess",
    lexicon: lexicon("com.atproto.repo.deleteRecord"), // wrong NSID!
  });
  assertEquals(s3.status, "failed");
  if (s3.status !== "failed") throw new Error("unreachable");
  assertEquals(s3.error.type, "RecordVerificationFailed");
  assertEquals(c3.type, "done");
});

Deno.test("pipeline: recovers from stale messages via retry", () => {
  const [s0] = init("app.bsky.feed.post");
  assertEquals(s0.status, "dnsPending");

  // A stale DID response arrives before DNS resolves.
  const [s1, c1] = update(s0, {
    type: "didSuccess",
    document: didDoc("did:plc:stale", "https://stale.example"),
  });
  // Should stay in dnsPending and re-emit resolveDns
  assertEquals(s1.status, "dnsPending");
  assertEquals(c1.type, "resolveDns");

  // Now the real DNS response arrives
  const [s2] = update(s1, {
    type: "dnsSuccess",
    records: [["did=did:plc:real"]],
  });
  assertEquals(s2.status, "didPending");

  // Real DID resolution succeeds
  const [s3] = update(s2, {
    type: "didSuccess",
    document: didDoc("did:plc:real", "https://pds.real.example"),
  });
  assertEquals(s3.status, "recordPending");

  // Verify final state fields were all forwarded correctly
  if (s3.status !== "recordPending") throw new Error("unreachable");
  assertEquals(s3.nsid, asNsid("app.bsky.feed.post"));
  assertEquals(s3.did, asDid("did:plc:real"));
  assertEquals(s3.pdsEndpoint, "https://pds.real.example");
});
