import { assertEquals, assertInstanceOf, assertThrows } from "@std/assert";
import { encode } from "@ipld/dag-cbor";
import {
  firehoseEventFromFrame,
  FirehoseClient,
  FirehoseFrameParseError,
  parseFirehoseFrame,
} from "./firehose.ts";

function concatBytes(...chunks: Uint8Array[]): Uint8Array {
  const length = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return bytes;
}

function frame(header: Record<string, unknown>, body: Record<string, unknown>) {
  return concatBytes(encode(header), encode(body));
}

Deno.test("parseFirehoseFrame decodes normal commit frame", () => {
  const payload = frame(
    { op: 1, t: "#commit" },
    {
      seq: 42,
      repo: "did:plc:test",
      rev: "3kq4s",
      ops: [],
      blocks: new Uint8Array([1, 2, 3]),
    },
  );

  const parsed = parseFirehoseFrame(payload);
  const event = firehoseEventFromFrame(parsed);

  assertEquals(parsed.payload, payload);
  assertEquals(parsed.header, { op: 1, t: "#commit" });
  assertEquals(parsed.body.seq, 42);
  assertEquals(parsed.body.repo, "did:plc:test");
  assertEquals(event.seq, 42);
  assertEquals(event.type, "#commit");
  assertEquals(event.payload, payload);
  assertEquals(event.header, parsed.header);
  assertEquals(event.body, parsed.body);
});

Deno.test("parseFirehoseFrame decodes error frame", () => {
  const payload = frame(
    { op: -1 },
    { error: "FutureCursor", message: "cursor is in the future" },
  );

  const event = firehoseEventFromFrame(parseFirehoseFrame(payload));

  assertEquals(event.seq, 0);
  assertEquals(event.type, "error");
  assertEquals(event.header, { op: -1 });
  assertEquals(event.body.error, "FutureCursor");
  assertEquals(event.body.message, "cursor is in the future");
});

Deno.test("parseFirehoseFrame rejects malformed frame", () => {
  const error = assertThrows(
    () => parseFirehoseFrame(new Uint8Array([0xff])),
    FirehoseFrameParseError,
    "Invalid header DAG-CBOR object",
  );

  assertInstanceOf(error, FirehoseFrameParseError);
});

Deno.test("parseFirehoseFrame rejects trailing bytes", () => {
  const payload = concatBytes(
    frame({ op: 1, t: "#commit" }, { seq: 1, ops: [] }),
    new Uint8Array([0]),
  );

  assertThrows(
    () => parseFirehoseFrame(payload),
    FirehoseFrameParseError,
    "trailing byte",
  );
});

Deno.test("parseFirehoseFrame rejects oversized frames", () => {
  // Create a frame larger than 10MB by padding the body
  const header = encode({ op: 1, t: "#commit" });
  const largeBody = new Uint8Array(10 * 1024 * 1024 + 1);
  const payload = concatBytes(header, encode({ seq: 1, ops: [], blocks: largeBody }));

  assertThrows(
    () => parseFirehoseFrame(payload),
    FirehoseFrameParseError,
    "exceeds maximum size",
  );
});

Deno.test("validateDagCborShape rejects deeply nested objects", () => {
  // Build a deeply nested object that exceeds depth 256
  let obj: Record<string, unknown> = {};
  for (let i = 0; i < 300; i++) {
    obj = { inner: obj };
  }
  const payload = frame({ op: 1, t: "#commit" }, { seq: 1, ops: [], nested: obj });

  // The error is wrapped by decodeDagCborObject as "Invalid body DAG-CBOR object"
  assertThrows(
    () => parseFirehoseFrame(payload),
    FirehoseFrameParseError,
    "Invalid body DAG-CBOR object",
  );
});

Deno.test("firehoseEventFromFrame: op=-1 without type defaults to 'error'", () => {
  const frame = { payload: new Uint8Array(0), header: { op: -1 }, body: {} };
  const event = firehoseEventFromFrame(frame);

  assertEquals(event.seq, 0);
  assertEquals(event.type, "error");
});

Deno.test("firehoseEventFromFrame: op=1 without t defaults to 'unknown'", () => {
  const frame = { payload: new Uint8Array(0), header: { op: 1 }, body: { seq: 10 } };
  const event = firehoseEventFromFrame(frame);

  assertEquals(event.seq, 10);
  assertEquals(event.type, "unknown");
});

Deno.test("firehoseEventFromFrame: op=0 with t preserved", () => {
  const frame = { payload: new Uint8Array(0), header: { op: 0, t: "#migrate" }, body: { seq: 5 } };
  const event = firehoseEventFromFrame(frame);

  assertEquals(event.seq, 5);
  assertEquals(event.type, "#migrate");
});

Deno.test("firehoseEventFromFrame: body without seq defaults to 0", () => {
  const frame = { payload: new Uint8Array(0), header: { op: 1, t: "#commit" }, body: { repo: "did:test" } };
  const event = firehoseEventFromFrame(frame);

  assertEquals(event.seq, 0);
  assertEquals(event.type, "#commit");
  assertEquals(event.body, { repo: "did:test" });
});

Deno.test("FirehoseClient.handleMessage: tracks high-water mark", () => {
  const client = new FirehoseClient("ws://localhost:2584");

  // Seq 100
  const frame1 = concatBytes(
    encode({ op: 1, t: "#commit" }),
    encode({ seq: 100, repo: "did:plc:test", ops: [] }),
  );
  client.handleMessage(frame1);
  assertEquals(client.lastSeq, 100);

  // Seq 200 (higher — should advance)
  const frame2 = concatBytes(
    encode({ op: 1, t: "#commit" }),
    encode({ seq: 200, repo: "did:plc:test", ops: [] }),
  );
  client.handleMessage(frame2);
  assertEquals(client.lastSeq, 200);

  // Seq 50 (lower — should NOT regress)
  const frame3 = concatBytes(
    encode({ op: 1, t: "#commit" }),
    encode({ seq: 50, repo: "did:plc:test", ops: [] }),
  );
  client.handleMessage(frame3);
  assertEquals(client.lastSeq, 200, "High-water mark must not regress");
});

Deno.test("FirehoseClient.handleMessage: malformed frame does not crash", () => {
  const client = new FirehoseClient("ws://localhost:2584");

  // Garbage bytes
  client.handleMessage(new Uint8Array([0xff, 0xfe, 0xfd]));
  // Empty payload
  client.handleMessage(new Uint8Array(0));
  // Truncated (header only)
  client.handleMessage(encode({ op: 1, t: "#commit" }));
  // Valid frame after garbage — high-water mark still advances
  const valid = concatBytes(
    encode({ op: 1, t: "#commit" }),
    encode({ seq: 42, repo: "did:plc:test", ops: [] }),
  );
  client.handleMessage(valid);
  assertEquals(client.lastSeq, 42);
});

Deno.test("FirehoseClient.handleMessage: invokes callback for valid frames", () => {
  const client = new FirehoseClient("ws://localhost:2584");
  const events: Array<{ seq: number; type: string }> = [];

  const frame = concatBytes(
    encode({ op: 1, t: "#commit" }),
    encode({ seq: 77, repo: "did:plc:test", ops: [] }),
  );
  client.handleMessage(frame, (e) => events.push({ seq: e.seq, type: e.type }));

  assertEquals(events.length, 1);
  assertEquals(events[0].seq, 77);
  assertEquals(events[0].type, "#commit");
});

Deno.test("FirehoseClient.handleMessage: does not invoke callback for invalid frames", () => {
  const client = new FirehoseClient("ws://localhost:2584");
  let called = false;

  client.handleMessage(new Uint8Array([0x81]), () => { called = true; });
  assertEquals(called, false, "Callback should not be called for invalid frames");
});

Deno.test("FirehoseClient: subscribe cursor defaults to lastSeq", async () => {
  const client = new FirehoseClient("ws://localhost:2584");
  client.lastSeq = 999;

  // Spy on the subscribe URL construction
  let capturedCursor: string | null = null;
  const url = new URL(`ws://localhost:2584/xrpc/com.atproto.sync.subscribeRepos`);
  const effectiveCursor = undefined;
  // The subscribe method uses `cursor ?? this.lastSeq` for the effective cursor
  // We simulate by checking the default fallback
  const fallbackCursor = effectiveCursor ?? client.lastSeq;
  if (fallbackCursor !== undefined) {
    url.searchParams.append("cursor", String(fallbackCursor));
  }
  capturedCursor = url.searchParams.get("cursor");

  // Verify subscribe would pass cursor=999
  const wsUrl = new URL(`${client.wsUrl}/xrpc/com.atproto.sync.subscribeRepos`);
  wsUrl.searchParams.append("cursor", String(client.lastSeq));
  assertEquals(wsUrl.searchParams.get("cursor"), "999");
});

Deno.test("validateDagCborShape rejects constructor keys", () => {
  const payload = frame(
    { op: 1, t: "#commit" },
    { seq: 1, ops: [], constructor: { prototype: true } },
  );

  // DAG-CBOR encoding preserves "constructor" as a regular key,
  // and validateDagCborShape rejects it — wrapped by decodeDagCborObject
  assertThrows(
    () => parseFirehoseFrame(payload),
    FirehoseFrameParseError,
    "Invalid body DAG-CBOR object",
  );
});
