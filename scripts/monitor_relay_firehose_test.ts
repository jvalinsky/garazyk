import { assertEquals, assertStringIncludes } from "@std/assert";
import { FirehoseEvent } from "@garazyk/gruszka";
import {
  createStats,
  firehoseURL,
  parseOptions,
  printEvent,
  printStats,
  recordEvent,
} from "./monitor_relay_firehose.ts";

Deno.test("parseOptions applies defaults and environment relay URL", () => {
  const options = parseOptions([], { RELAY_URL: "http://relay.test:2470" });

  assertEquals(options.relayUrl, "http://relay.test:2470");
  assertEquals(options.durationS, 0);
  assertEquals(options.statsIntervalS, 10);
  assertEquals(options.reconnectDelayS, 3);
  assertEquals(options.color, true);
});

Deno.test("parseOptions parses monitor controls", () => {
  const options = parseOptions([
    "--relay-url",
    "https://relay.test",
    "--cursor",
    "42",
    "--duration",
    "30",
    "--max-events",
    "100",
    "--stats-interval",
    "5",
    "--reconnect-delay",
    "1.5",
    "--no-color",
  ], {});

  assertEquals(options, {
    relayUrl: "https://relay.test",
    cursor: 42,
    durationS: 30,
    maxEvents: 100,
    statsIntervalS: 5,
    reconnectDelayS: 1.5,
    color: false,
  });
});

Deno.test("firehoseURL converts relay HTTP URL and preserves cursor", () => {
  assertEquals(
    firehoseURL("https://relay.test/base", 123).toString(),
    "wss://relay.test/xrpc/com.atproto.sync.subscribeRepos?cursor=123",
  );
});

Deno.test("recordEvent computes commit and stream statistics", () => {
  const stats = createStats(1_000);
  const event = new FirehoseEvent(
    42,
    "#commit",
    new Uint8Array(12),
    { op: 1, t: "#commit" },
    {
      seq: 42,
      repo: "did:plc:test",
      ops: [
        { action: "create", path: "app.bsky.feed.post/rkey1" },
        { action: "delete", path: "app.bsky.feed.like/rkey2" },
      ],
    },
  );

  recordEvent(stats, event);

  assertEquals(stats.events, 1);
  assertEquals(stats.bytes, 12);
  assertEquals(stats.firstSeq, 42);
  assertEquals(stats.lastSeq, 42);
  assertEquals(stats.repos, new Set(["did:plc:test"]));
  assertEquals(stats.actions.get("create"), 1);
  assertEquals(stats.actions.get("delete"), 1);
  assertEquals(stats.collections.get("app.bsky.feed.post"), 1);
  assertEquals(stats.collections.get("app.bsky.feed.like"), 1);
});

Deno.test("printEvent emits a compact commit line", () => {
  const lines: string[] = [];
  const event = new FirehoseEvent(
    7,
    "#commit",
    new Uint8Array(4),
    {},
    {
      repo: "did:plc:test",
      ops: [{ action: "create", path: "app.bsky.feed.post/rkey" }],
    },
  );

  printEvent(event, 4, false, (line) => lines.push(line));

  assertEquals(lines.length, 1);
  assertStringIncludes(lines[0], "#commit");
  assertStringIncludes(lines[0], "seq=7");
  assertStringIncludes(lines[0], "ops=1");
  assertStringIncludes(lines[0], "create:1");
});

Deno.test("printStats reports throughput and top dimensions", () => {
  const lines: string[] = [];
  const stats = createStats(1_000);
  stats.events = 2;
  stats.bytes = 2_048;
  stats.lastSeq = 10;
  stats.firstSeq = 9;
  stats.reconnects = 1;
  stats.eventTypes.set("#commit", 2);
  stats.actions.set("create", 2);
  stats.collections.set("app.bsky.feed.post", 2);

  printStats(stats, false, (line) => lines.push(line), 3_000);

  const output = lines.join("\n");
  assertStringIncludes(output, "events=2");
  assertStringIncludes(output, "rate=1.00/s");
  assertStringIncludes(output, "seq=9..10");
  assertStringIncludes(output, "#commit=2");
  assertStringIncludes(output, "app.bsky.feed.post=2");
});
