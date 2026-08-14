import { assertEquals } from "@std/assert";
import {
  relayCurrentSequence,
  splitWebSocketUpgradeResponse,
} from "./scenarios/102_zuk_cursor_containment.ts";

Deno.test("splitWebSocketUpgradeResponse preserves a coalesced first WebSocket frame", () => {
  const header =
    "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n\r\n";
  const frame = new Uint8Array([0x82, 0x02, 0xaa, 0xbb]);
  const bytes = new Uint8Array(
    new TextEncoder().encode(header).length + frame.length,
  );
  bytes.set(new TextEncoder().encode(header));
  bytes.set(frame, header.length);

  const result = splitWebSocketUpgradeResponse(bytes);

  assertEquals(result?.header, header);
  assertEquals(result?.remaining, frame);
});

Deno.test("splitWebSocketUpgradeResponse waits for a complete header", () => {
  const partial = new TextEncoder().encode(
    "HTTP/1.1 101 Switching Protocols\r\n",
  );
  assertEquals(splitWebSocketUpgradeResponse(partial), undefined);
});

Deno.test("relayCurrentSequence accepts the relay health sequence", () => {
  assertEquals(relayCurrentSequence({ currentSequence: 42 }), 42);
});

Deno.test("relayCurrentSequence rejects absent or invalid health sequences", () => {
  for (
    const response of [undefined, {}, { currentSequence: -1 }, {
      currentSequence: "42",
    }]
  ) {
    let failed = false;
    try {
      relayCurrentSequence(response);
    } catch {
      failed = true;
    }
    assertEquals(failed, true);
  }
});
