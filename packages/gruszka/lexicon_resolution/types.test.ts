/**
 * Tests for the sans-IO lexicon resolution types module.
 *
 * These tests exercise branded type creation/validation, the Result
 * discriminated union, the ResolutionError union, state machine types,
 * LexiconDoc structure, and the assertNever exhaustiveness helper.
 *
 * All tests are pure — zero I/O, zero dependencies beyond @std/assert.
 */
import { assertEquals, assertThrows } from "@std/assert";
import {
  asDid,
  asDomain,
  asNsid,
  assertNever,
  isValidNsid,
  type Did,
  type DnsFailedMsg,
  type DnsPendingState,
  type DnsSuccessMsg,
  type Domain,
  type DoneCmd,
  type FailedState,
  type FetchRecordCmd,
  type InitState,
  type LexiconDef,
  type LexiconDoc,
  type LexiconSchema,
  type Nsid,
  type RecordPendingState,
  type RecordSuccessMsg,
  type ResolveDidCmd,
  type ResolveDnsCmd,
  type ResolvedState,
  type ResolverCmd,
  type ResolverMsg,
  type ResolverState,
  type ResolutionError,
  type Result,
} from "./types.ts";

// ===========================================================================
// isValidNsid
// ===========================================================================

Deno.test("isValidNsid: valid three-segment NSID", () => {
  assertEquals(isValidNsid("com.atproto.repo"), true);
});

Deno.test("isValidNsid: valid four-segment NSID", () => {
  assertEquals(isValidNsid("com.atproto.repo.createRecord"), true);
});

Deno.test("isValidNsid: valid five-segment NSID", () => {
  assertEquals(isValidNsid("app.bsky.feed.post"), true);
});

Deno.test("isValidNsid: valid with digits", () => {
  assertEquals(isValidNsid("com.example.v1.hello"), true);
});

Deno.test("isValidNsid: empty string", () => {
  assertEquals(isValidNsid(""), false);
});

Deno.test("isValidNsid: single segment", () => {
  assertEquals(isValidNsid("com"), false);
});

Deno.test("isValidNsid: two segments", () => {
  assertEquals(isValidNsid("com.example"), false);
});

Deno.test("isValidNsid: uppercase accepted (real lexicons use camelCase)", () => {
  assertEquals(isValidNsid("com.atproto.repo.createRecord"), true);
});

Deno.test("isValidNsid: hyphens rejected", () => {
  assertEquals(isValidNsid("com.at-proto.repo"), false);
});

Deno.test("isValidNsid: leading dot rejected", () => {
  assertEquals(isValidNsid(".com.example.repo"), false);
});

Deno.test("isValidNsid: trailing dot rejected", () => {
  assertEquals(isValidNsid("com.example.repo."), false);
});

Deno.test("isValidNsid: consecutive dots rejected", () => {
  assertEquals(isValidNsid("com..example.repo"), false);
});

Deno.test("isValidNsid: special characters rejected", () => {
  assertEquals(isValidNsid("com.example.repo!"), false);
});

// ===========================================================================
// asNsid
// ===========================================================================

Deno.test("asNsid: brands a valid NSID", () => {
  const nsid: Nsid = asNsid("com.atproto.repo.createRecord");
  // Branded types are structurally strings at runtime
  assertEquals(typeof nsid, "string");
  assertEquals(nsid, "com.atproto.repo.createRecord");
});

Deno.test("asNsid: throws on invalid NSID", () => {
  assertThrows(
    () => asNsid("bad"),
    TypeError,
    "Invalid NSID",
  );
});

// ===========================================================================
// asDid
// ===========================================================================

Deno.test("asDid: brands a valid PLC DID", () => {
  const did: Did = asDid("did:plc:ewvi7nxzyoun6zhxrhs64oiz");
  assertEquals(typeof did, "string");
});

Deno.test("asDid: brands a valid web DID", () => {
  const did: Did = asDid("did:web:bsky.app");
  assertEquals(typeof did, "string");
});

Deno.test("asDid: throws on string without did: prefix", () => {
  assertThrows(
    () => asDid("not-a-did"),
    TypeError,
    "Invalid DID",
  );
});

Deno.test("asDid: throws on did: with no method", () => {
  assertThrows(
    () => asDid("did:"),
    TypeError,
    "Invalid DID",
  );
});

Deno.test("asDid: throws on did:method with no id", () => {
  assertThrows(
    () => asDid("did:plc:"),
    TypeError,
    "Invalid DID",
  );
});

Deno.test("asDid: throws on empty string", () => {
  assertThrows(
    () => asDid(""),
    TypeError,
    "Invalid DID",
  );
});

// ===========================================================================
// asDomain
// ===========================================================================

Deno.test("asDomain: brands a valid domain", () => {
  const domain: Domain = asDomain("bsky.app");
  assertEquals(typeof domain, "string");
  assertEquals(domain, "bsky.app");
});

Deno.test("asDomain: trims whitespace", () => {
  const domain: Domain = asDomain("  bsky.app  ");
  assertEquals(domain, "bsky.app");
});

Deno.test("asDomain: throws on empty string", () => {
  assertThrows(
    () => asDomain(""),
    TypeError,
    "Domain must not be empty",
  );
});

Deno.test("asDomain: throws on whitespace-only string", () => {
  assertThrows(
    () => asDomain("   "),
    TypeError,
    "Domain must not be empty",
  );
});

// ===========================================================================
// Result type
// ===========================================================================

Deno.test("Result: ok variant", () => {
  const r: Result<number> = { ok: true, value: 42 };
  if (r.ok) {
    assertEquals(r.value, 42);
  } else {
    throw new Error("expected ok");
  }
});

Deno.test("Result: error variant", () => {
  const r: Result<number> = {
    ok: false,
    error: { type: "InvalidNsid", nsid: "bad" },
  };
  if (!r.ok) {
    // TypeScript can't narrow through the Result wrapper, so we narrow
    // the error's discriminated union explicitly.
    const err = r.error;
    assertEquals(err.type, "InvalidNsid");
    if (err.type === "InvalidNsid") {
      assertEquals(err.nsid, "bad");
    }
  } else {
    throw new Error("expected error");
  }
});

Deno.test("Result: custom error type", () => {
  type CustomErr = { type: "Timeout"; ms: number };
  const r: Result<string, CustomErr> = { ok: true, value: "done" };
  assertEquals(r.ok, true);
});

// ===========================================================================
// ResolutionError discriminated union
// ===========================================================================

Deno.test("ResolutionError: InvalidNsid", () => {
  const err: ResolutionError = { type: "InvalidNsid", nsid: "!bad!" };
  assertEquals(err.type, "InvalidNsid");
  assertEquals(err.nsid, "!bad!");
});

Deno.test("ResolutionError: DnsQueryFailed", () => {
  const domain: Domain = asDomain("bsky.app");
  const err: ResolutionError = {
    type: "DnsQueryFailed",
    domain,
    reason: "NXDOMAIN",
  };
  assertEquals(err.type, "DnsQueryFailed");
  assertEquals(err.domain, "bsky.app");
  assertEquals(err.reason, "NXDOMAIN");
});

Deno.test("ResolutionError: NoLexiconDnsRecord", () => {
  const domain: Domain = asDomain("bsky.app");
  const err: ResolutionError = { type: "NoLexiconDnsRecord", domain };
  assertEquals(err.type, "NoLexiconDnsRecord");
});

Deno.test("ResolutionError: DidResolutionFailed", () => {
  const did: Did = asDid("did:plc:test");
  const err: ResolutionError = {
    type: "DidResolutionFailed",
    did,
    reason: "not found",
  };
  assertEquals(err.type, "DidResolutionFailed");
  assertEquals(err.did, "did:plc:test");
});

Deno.test("ResolutionError: PdsEndpointMissing", () => {
  const did: Did = asDid("did:plc:test");
  const err: ResolutionError = { type: "PdsEndpointMissing", did };
  assertEquals(err.type, "PdsEndpointMissing");
});

Deno.test("ResolutionError: RecordFetchFailed", () => {
  const err: ResolutionError = {
    type: "RecordFetchFailed",
    endpoint: "https://pds.example/xrpc/...",
    reason: "connection refused",
  };
  assertEquals(err.type, "RecordFetchFailed");
});

Deno.test("ResolutionError: RecordVerificationFailed", () => {
  const nsid: Nsid = asNsid("app.bsky.feed.post");
  const err: ResolutionError = {
    type: "RecordVerificationFailed",
    nsid,
    reason: "commit mismatch",
  };
  assertEquals(err.type, "RecordVerificationFailed");
  assertEquals(err.nsid, "app.bsky.feed.post");
});

Deno.test("ResolutionError: discriminated switch covers all variants", () => {
  const errors: ResolutionError[] = [
    { type: "InvalidNsid", nsid: "bad" },
    { type: "DnsQueryFailed", domain: asDomain("example.com"), reason: "err" },
    { type: "NoLexiconDnsRecord", domain: asDomain("example.com") },
    {
      type: "DidResolutionFailed",
      did: asDid("did:plc:test"),
      reason: "err",
    },
    { type: "PdsEndpointMissing", did: asDid("did:plc:test") },
    {
      type: "RecordFetchFailed",
      endpoint: "https://x",
      reason: "err",
    },
    {
      type: "RecordVerificationFailed",
      nsid: asNsid("com.example.test"),
      reason: "err",
    },
  ];

  for (const err of errors) {
    switch (err.type) {
      case "InvalidNsid":
        assertEquals(typeof err.nsid, "string");
        break;
      case "DnsQueryFailed":
        assertEquals(typeof err.domain, "string");
        assertEquals(typeof err.reason, "string");
        break;
      case "NoLexiconDnsRecord":
        assertEquals(typeof err.domain, "string");
        break;
      case "DidResolutionFailed":
        assertEquals(typeof err.did, "string");
        assertEquals(typeof err.reason, "string");
        break;
      case "PdsEndpointMissing":
        assertEquals(typeof err.did, "string");
        break;
      case "RecordFetchFailed":
        assertEquals(typeof err.endpoint, "string");
        assertEquals(typeof err.reason, "string");
        break;
      case "RecordVerificationFailed":
        assertEquals(typeof err.nsid, "string");
        assertEquals(typeof err.reason, "string");
        break;
      default:
        assertNever(err);
    }
  }
});

// ===========================================================================
// ResolverState discriminated union
// ===========================================================================

Deno.test("ResolverState: InitState", () => {
  const state: InitState = { status: "init" };
  assertEquals(state.status, "init");
});

Deno.test("ResolverState: DnsPendingState", () => {
  const state: DnsPendingState = {
    status: "dnsPending",
    nsid: asNsid("app.bsky.feed.post"),
    domain: asDomain("feed.bsky.app"),
  };
  assertEquals(state.status, "dnsPending");
  assertEquals(state.nsid, "app.bsky.feed.post");
  assertEquals(state.domain, "feed.bsky.app");
});

Deno.test("ResolverState: DidPendingState", () => {
  const state = {
    status: "didPending" as const,
    nsid: asNsid("app.bsky.feed.post"),
    domain: asDomain("feed.bsky.app"),
    did: asDid("did:plc:test"),
  };
  assertEquals(state.status, "didPending");
  assertEquals(state.did, "did:plc:test");
});

Deno.test("ResolverState: RecordPendingState", () => {
  const state: RecordPendingState = {
    status: "recordPending",
    nsid: asNsid("app.bsky.feed.post"),
    domain: asDomain("feed.bsky.app"),
    did: asDid("did:plc:test"),
    pdsEndpoint: "https://pds.example",
  };
  assertEquals(state.status, "recordPending");
  assertEquals(state.pdsEndpoint, "https://pds.example");
});

Deno.test("ResolverState: ResolvedState", () => {
  const lexicon: LexiconDoc = {
    lexicon: 1,
    id: "app.bsky.feed.post",
    defs: {},
  };
  const state: ResolvedState = {
    status: "resolved",
    lexicon,
    nsid: asNsid("app.bsky.feed.post"),
  };
  assertEquals(state.status, "resolved");
  assertEquals(state.lexicon.id, "app.bsky.feed.post");
});

Deno.test("ResolverState: FailedState", () => {
  const state: FailedState = {
    status: "failed",
    error: { type: "InvalidNsid", nsid: "bad" },
  };
  assertEquals(state.status, "failed");
  assertEquals(state.error.type, "InvalidNsid");
});

Deno.test("ResolverState: discriminated switch covers all states", () => {
  const states: ResolverState[] = [
    { status: "init" },
    {
      status: "dnsPending",
      nsid: asNsid("com.example.test"),
      domain: asDomain("test.example.com"),
    },
    {
      status: "didPending",
      nsid: asNsid("com.example.test"),
      domain: asDomain("test.example.com"),
      did: asDid("did:plc:test"),
    },
    {
      status: "recordPending",
      nsid: asNsid("com.example.test"),
      domain: asDomain("test.example.com"),
      did: asDid("did:plc:test"),
      pdsEndpoint: "https://pds.example",
    },
    {
      status: "resolved",
      lexicon: { lexicon: 1, id: "com.example.test", defs: {} },
      nsid: asNsid("com.example.test"),
    },
    {
      status: "failed",
      error: { type: "InvalidNsid", nsid: "bad" },
    },
  ];

  for (const state of states) {
    switch (state.status) {
      case "init":
        break;
      case "dnsPending":
        assertEquals(typeof state.nsid, "string");
        assertEquals(typeof state.domain, "string");
        break;
      case "didPending":
        assertEquals(typeof state.did, "string");
        break;
      case "recordPending":
        assertEquals(typeof state.pdsEndpoint, "string");
        break;
      case "resolved":
        assertEquals(typeof state.lexicon.lexicon, "number");
        break;
      case "failed":
        assertEquals(typeof state.error.type, "string");
        break;
      default:
        assertNever(state);
    }
  }
});

// ===========================================================================
// ResolverMsg discriminated union
// ===========================================================================

Deno.test("ResolverMsg: DnsSuccessMsg", () => {
  const msg: DnsSuccessMsg = {
    type: "dnsSuccess",
    records: [["did=did:plc:test"]],
  };
  assertEquals(msg.type, "dnsSuccess");
  assertEquals(msg.records.length, 1);
});

Deno.test("ResolverMsg: DnsSuccessMsg with multiple records", () => {
  const msg: DnsSuccessMsg = {
    type: "dnsSuccess",
    records: [
      ["did=did:plc:test"],
      ["other=data"],
    ],
  };
  assertEquals(msg.records.length, 2);
});

Deno.test("ResolverMsg: DnsFailedMsg", () => {
  const msg: DnsFailedMsg = {
    type: "dnsFailed",
    reason: "NXDOMAIN",
  };
  assertEquals(msg.type, "dnsFailed");
  assertEquals(msg.reason, "NXDOMAIN");
});

Deno.test("ResolverMsg: DidSuccessMsg", () => {
  const did: Did = asDid("did:plc:test");
  const msg = {
    type: "didSuccess" as const,
    document: { id: did, service: [] },
  };
  assertEquals(msg.type, "didSuccess");
  assertEquals(msg.document.id, "did:plc:test");
});

Deno.test("ResolverMsg: DidFailedMsg", () => {
  const msg = { type: "didFailed" as const, reason: "not found" };
  assertEquals(msg.type, "didFailed");
  assertEquals(msg.reason, "not found");
});

Deno.test("ResolverMsg: RecordSuccessMsg", () => {
  const lexicon: LexiconDoc = {
    lexicon: 1,
    id: "app.bsky.feed.post",
    defs: {},
  };
  const msg: RecordSuccessMsg = { type: "recordSuccess", lexicon };
  assertEquals(msg.type, "recordSuccess");
  assertEquals(msg.lexicon.id, "app.bsky.feed.post");
});

Deno.test("ResolverMsg: RecordFailedMsg", () => {
  const msg = { type: "recordFailed" as const, reason: "404 Not Found" };
  assertEquals(msg.type, "recordFailed");
  assertEquals(msg.reason, "404 Not Found");
});

Deno.test("ResolverMsg: discriminated switch covers all messages", () => {
  const did: Did = asDid("did:plc:test");
  const messages: ResolverMsg[] = [
    { type: "dnsSuccess", records: [["did=did:plc:test"]] },
    { type: "dnsFailed", reason: "NXDOMAIN" },
    { type: "didSuccess", document: { id: did, service: [] } },
    { type: "didFailed", reason: "not found" },
    {
      type: "recordSuccess",
      lexicon: { lexicon: 1, id: "com.example.test", defs: {} },
    },
    { type: "recordFailed", reason: "timeout" },
  ];

  for (const msg of messages) {
    switch (msg.type) {
      case "dnsSuccess":
        assertEquals(Array.isArray(msg.records), true);
        break;
      case "dnsFailed":
        assertEquals(typeof msg.reason, "string");
        break;
      case "didSuccess":
        assertEquals(typeof msg.document.id, "string");
        break;
      case "didFailed":
        assertEquals(typeof msg.reason, "string");
        break;
      case "recordSuccess":
        assertEquals(typeof msg.lexicon.id, "string");
        break;
      case "recordFailed":
        assertEquals(typeof msg.reason, "string");
        break;
      default:
        assertNever(msg);
    }
  }
});

// ===========================================================================
// ResolverCmd discriminated union
// ===========================================================================

Deno.test("ResolverCmd: ResolveDnsCmd", () => {
  const cmd: ResolveDnsCmd = {
    type: "resolveDns",
    domain: asDomain("feed.bsky.app"),
  };
  assertEquals(cmd.type, "resolveDns");
  assertEquals(cmd.domain, "feed.bsky.app");
});

Deno.test("ResolverCmd: ResolveDidCmd", () => {
  const cmd: ResolveDidCmd = {
    type: "resolveDid",
    did: asDid("did:plc:test"),
  };
  assertEquals(cmd.type, "resolveDid");
  assertEquals(cmd.did, "did:plc:test");
});

Deno.test("ResolverCmd: FetchRecordCmd", () => {
  const cmd: FetchRecordCmd = {
    type: "fetchRecord",
    endpoint: "https://pds.example/xrpc/com.atproto.repo.getRecord",
    did: asDid("did:plc:test"),
    nsid: asNsid("app.bsky.feed.post"),
  };
  assertEquals(cmd.type, "fetchRecord");
  assertEquals(cmd.endpoint, "https://pds.example/xrpc/com.atproto.repo.getRecord");
  assertEquals(cmd.did, "did:plc:test");
  assertEquals(cmd.nsid, "app.bsky.feed.post");
});

Deno.test("ResolverCmd: DoneCmd", () => {
  const cmd: DoneCmd = { type: "done" };
  assertEquals(cmd.type, "done");
});

Deno.test("ResolverCmd: discriminated switch covers all commands", () => {
  const cmds: ResolverCmd[] = [
    { type: "resolveDns", domain: asDomain("bsky.app") },
    { type: "resolveDid", did: asDid("did:plc:test") },
    {
      type: "fetchRecord",
      endpoint: "https://x",
      did: asDid("did:plc:test"),
      nsid: asNsid("com.example.test"),
    },
    { type: "done" },
  ];

  for (const cmd of cmds) {
    switch (cmd.type) {
      case "resolveDns":
        assertEquals(typeof cmd.domain, "string");
        break;
      case "resolveDid":
        assertEquals(typeof cmd.did, "string");
        break;
      case "fetchRecord":
        assertEquals(typeof cmd.endpoint, "string");
        assertEquals(typeof cmd.did, "string");
        assertEquals(typeof cmd.nsid, "string");
        break;
      case "done":
        break;
      default:
        assertNever(cmd);
    }
  }
});

// ===========================================================================
// LexiconDoc and LexiconDef construction
// ===========================================================================

Deno.test("LexiconDoc: minimal valid document", () => {
  const doc: LexiconDoc = {
    lexicon: 1,
    id: "app.bsky.feed.post",
    defs: {},
  };
  assertEquals(doc.lexicon, 1);
  assertEquals(doc.id, "app.bsky.feed.post");
});

Deno.test("LexiconDoc: full query document", () => {
  const doc: LexiconDoc = {
    lexicon: 1,
    id: "app.bsky.actor.getProfile",
    revision: 0,
    description: "Get a detailed profile view of an actor.",
    defs: {
      main: {
        type: "query",
        description: "Get a profile.",
        parameters: {
          type: "params",
          required: ["actor"],
          properties: {
            actor: { type: "string", description: "Handle or DID" },
          },
        },
        output: {
          encoding: "application/json",
        },
      },
    },
  };
  assertEquals(doc.defs.main.type, "query");
});

Deno.test("LexiconDoc: procedure document", () => {
  const main: LexiconDef = {
    type: "procedure",
    description: "Upload a blob.",
    input: { encoding: "*/*" },
  };
  assertEquals(main.type, "procedure");
  assertEquals(main.input?.encoding, "*/*");
});

Deno.test("LexiconDoc: record document", () => {
  const main: LexiconDef = {
    type: "record",
    description: "A post record.",
    record: {
      type: "object",
      required: ["text", "createdAt"],
      properties: {
        text: { type: "string", maxLength: 3000 },
        createdAt: { type: "string", format: "datetime" },
      },
    },
  };
  assertEquals(main.type, "record");
});

Deno.test("LexiconSchema: ref type", () => {
  const schema: LexiconSchema = { type: "ref", ref: "#post" };
  assertEquals(schema.type, "ref");
  assertEquals(schema.ref, "#post");
});

Deno.test("LexiconSchema: union with closed", () => {
  const schema: LexiconSchema = {
    type: "union",
    refs: ["#post", "#repost"],
    closed: true,
  };
  assertEquals(schema.type, "union");
  assertEquals(schema.refs?.length, 2);
  assertEquals(schema.closed, true);
});

Deno.test("LexiconSchema: array with items", () => {
  const schema: LexiconSchema = {
    type: "array",
    items: { type: "string" },
    minLength: 1,
    maxLength: 100,
  };
  assertEquals(schema.type, "array");
  assertEquals(schema.items?.type, "string");
});

// ===========================================================================
// assertNever
// ===========================================================================

Deno.test("assertNever: throws at runtime", () => {
  // We must force the call with an unexpected value to test the runtime
  // behaviour, but TypeScript won't let us pass a non-never value directly.
  assertThrows(
    () => assertNever("unexpected" as never),
    TypeError,
    "Unexpected value",
  );
});

Deno.test("assertNever: includes JSON representation in error", () => {
  assertThrows(
    () => assertNever(42 as never),
    TypeError,
    "42",
  );
});
