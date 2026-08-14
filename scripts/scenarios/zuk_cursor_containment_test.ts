import { assertEquals } from "@std/assert";
import {
  downstreamConnectionsReleased,
  eventAtOrBeforeAttachment,
  graphemeCount,
  parseRelayHealthState,
  relayCurrentSequence,
  relaySequenceIsStable,
  slowConsumerPostText,
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
  const health = { currentSequence: 42, downstreamConnections: 3 };
  assertEquals(relayCurrentSequence(health), 42);
  assertEquals(parseRelayHealthState(health), health);
});

Deno.test("relayCurrentSequence rejects absent or invalid health sequences", () => {
  for (
    const response of [undefined, {}, {
      currentSequence: -1,
      downstreamConnections: 0,
    }, {
      currentSequence: "42",
      downstreamConnections: 0,
    }, { currentSequence: 42, downstreamConnections: -1 }]
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

Deno.test("relaySequenceIsStable requires several equal observations", () => {
  assertEquals(relaySequenceIsStable([4, 4, 4], 3), true);
  assertEquals(relaySequenceIsStable([3, 4, 4], 3), false);
  assertEquals(relaySequenceIsStable([4, 4], 3), false);
});

Deno.test("eventAtOrBeforeAttachment detects retained events without inspecting commit ops", () => {
  assertEquals(
    eventAtOrBeforeAttachment([{ seq: 8 }, { seq: 9 }], 8),
    { seq: 8 },
  );
  assertEquals(eventAtOrBeforeAttachment([{ seq: 9 }], 8), undefined);
});

Deno.test("downstreamConnectionsReleased requires the pre-connect baseline", () => {
  assertEquals(downstreamConnectionsReleased(2, 2), true);
  assertEquals(downstreamConnectionsReleased(1, 2), true);
  assertEquals(downstreamConnectionsReleased(3, 2), false);
});

Deno.test("slowConsumerPostText satisfies feed grapheme and wire-pressure bounds", () => {
  const text = slowConsumerPostText(
    127,
    "12345678-1234-1234-1234-123456789012",
  );
  assertEquals(text.length <= 3_000, true);
  assertEquals(graphemeCount(text) <= 300, true);
  assertEquals(new TextEncoder().encode(text).length >= 4_000, true);
  assertEquals(text.startsWith("z127-"), true);
});
