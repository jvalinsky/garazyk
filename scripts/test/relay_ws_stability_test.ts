#!/usr/bin/env -S deno test -A
import { assertEquals, assertThrows } from "@std/assert";
import { firehoseURL, parseOptions } from "./relay_ws_stability.ts";

Deno.test("firehoseURL upgrades https to wss subscribeRepos", () => {
  const url = firehoseURL("https://relay.garazyk.xyz", 42);
  assertEquals(url.protocol, "wss:");
  assertEquals(url.host, "relay.garazyk.xyz");
  assertEquals(url.pathname, "/xrpc/com.atproto.sync.subscribeRepos");
  assertEquals(url.searchParams.get("cursor"), "42");
});

Deno.test("parseOptions defaults to relay.garazyk.xyz and reconnect", () => {
  const opts = parseOptions([], {});
  assertEquals(opts.relayUrl, "https://relay.garazyk.xyz");
  assertEquals(opts.durationS, 600);
  assertEquals(opts.reconnect, true);
  assertEquals(opts.parseFrames, true);
});

Deno.test("parseOptions --no-reconnect disables reconnect", () => {
  const opts = parseOptions(["--no-reconnect", "--duration", "120"], {});
  assertEquals(opts.reconnect, false);
  assertEquals(opts.durationS, 120);
});

Deno.test("parseOptions --no-parse disables frame parsing", () => {
  const opts = parseOptions(["--no-parse"], {});
  assertEquals(opts.parseFrames, false);
});

Deno.test("firehoseURL rejects non-http schemes", () => {
  assertThrows(() => firehoseURL("ftp://relay.example"), Error, "HTTP(S)");
});
