/**
 * Asciicast parse/serialize tests.
 *
 * @module tui/testing/cast_test
 */

import { assertEquals } from "@std/assert";
import { extractMarkers, parseAsciicast, serializeAsciicast } from "./cast.ts";

Deno.test("parseAsciicast: round-trips header and events", () => {
  const raw = serializeAsciicast(
    { version: 2, width: 80, height: 24, title: "test" },
    [[0, "o", "hello"], [1, "m", "step-1"]],
  );
  const parsed = parseAsciicast(raw);
  assertEquals(parsed.header.width, 80);
  assertEquals(parsed.events.length, 2);
  assertEquals(extractMarkers(parsed.events)[0].label, "step-1");
});
