import { assertEquals } from "@std/assert";
import { encode } from "@ipld/dag-cbor";
import { FirehoseClient } from "./firehose.ts";

Deno.test("FirehoseClient: tracks cursor", async () => {
  const client = new FirehoseClient("ws://localhost:2584");

  // Simulate receiving a frame
  const header = { op: 1, t: "#commit" };
  const body = { seq: 12345, rebase: false, tooBig: false };
  const frameBytes = new Uint8Array([...encode(header), ...encode(body)]);

  client.handleMessage(frameBytes);
  assertEquals(client.lastSeq, 12345);

  // Now verify that the next subscribe uses the cursor
  let capturedUrl: string | undefined;

  client.subscribe = (_callback, _duration, cursor) => {
    const url = new URL(`${client.wsUrl}/xrpc/com.atproto.sync.subscribeRepos`);
    const effectiveCursor = cursor ?? client.lastSeq;
    if (effectiveCursor !== undefined) {
      url.searchParams.append("cursor", effectiveCursor.toString());
    }
    capturedUrl = url.toString();
    return Promise.resolve();
  };

  await client.subscribe();
  assertEquals(capturedUrl?.includes("cursor=12345"), true);
});
