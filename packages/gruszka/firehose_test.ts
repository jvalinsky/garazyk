import { assertEquals, assertInstanceOf, assertThrows } from "@std/assert";
import { encode } from "@ipld/dag-cbor";
import {
  firehoseEventFromFrame,
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
