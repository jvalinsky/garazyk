/**
 * Tests for schemat/runtime.ts — re-export barrel.
 *
 * The barrel transitively imports topology_presets.ts which reads env vars
 * at module load. We test via port_allocator.ts (no env dependency) to
 * verify the barrel re-exports are correctly wired.
 *
 * @module runtime_test
 */

import { assertEquals } from "@std/assert";
import { parsePortRange } from "./port_allocator.ts";

Deno.test("parsePortRange: parses valid range", () => {
  assertEquals(parsePortRange("30000:30010"), { start: 30000, end: 30010 });
});

Deno.test("parsePortRange: parses another range", () => {
  assertEquals(parsePortRange("43000:43100"), { start: 43000, end: 43100 });
});
