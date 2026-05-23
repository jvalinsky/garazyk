import { assertEquals, assertMatch } from "@std/assert";
import { DurationCache, ProgressBar } from "./progress.ts";

// Strip ANSI escape sequences for deterministic assertions.
function stripAnsi(s: string): string {
  // deno-lint-ignore no-control-regex
  return s.replace(/\x1b\[[0-9;]*m/g, "");
}

Deno.test("ProgressBar: start returns a string with task name", () => {
  const bar = new ProgressBar(10);
  const output = bar.start("test-scenario");
  assertEquals(typeof output, "string");
  const plain = stripAnsi(output);
  assertMatch(plain, /test-scenario/);
  assertMatch(plain, /0%/);
  assertMatch(plain, /10 left/);
  assertMatch(plain, /0\/10/);
});

Deno.test("ProgressBar: update returns a string with progress", () => {
  const bar = new ProgressBar(10);
  bar.start("first");
  const output = bar.update(5, "second");
  assertEquals(typeof output, "string");
  const plain = stripAnsi(output);
  assertMatch(plain, /50%/);
  assertMatch(plain, /5 left/);
  assertMatch(plain, /5\/10/);
  assertMatch(plain, /second/);
});

Deno.test("ProgressBar: update can clear the current task", () => {
  const bar = new ProgressBar(2);
  bar.start("first");
  const output = bar.update(1, "");
  const plain = stripAnsi(output);
  assertMatch(plain, /1 left/);
  assertEquals(plain.includes("Running:"), false);
});

Deno.test("ProgressBar: finish returns a string with total time", () => {
  const bar = new ProgressBar(3);
  bar.start("a");
  bar.update(1);
  bar.update(2);
  bar.update(3);
  const output = bar.finish();
  assertEquals(typeof output, "string");
  const plain = stripAnsi(output);
  assertMatch(plain, /100%/);
  assertMatch(plain, /3\/3/);
  assertMatch(plain, /Total time/);
  // Should end with a newline
  assertMatch(output, /\n$/);
});

Deno.test("ProgressBar: zero total returns empty string", () => {
  const bar = new ProgressBar(0);
  const output = bar.start("nothing");
  assertEquals(output, "");
});

Deno.test("ProgressBar: output starts with carriage return", () => {
  const bar = new ProgressBar(5);
  const output = bar.start("task");
  assertMatch(output, /^\r/);
});

Deno.test("ProgressBar: padding clears previous longer output", () => {
  const bar = new ProgressBar(10);
  const long = bar.start("a-very-long-task-name-that-is-long");
  const short = bar.update(5, "x");
  // The short output should be padded to at least the raw length of the long output
  // (including ANSI codes, since padding is computed on the raw string)
  assertEquals(short.length >= long.length, true);
});

Deno.test("ProgressBar: expected durations influence estimation", () => {
  // Provide expected durations for all 5 tasks
  const bar = new ProgressBar(5, [1000, 2000, 3000, 4000, 5000]);
  const output = bar.start("task");
  const plain = stripAnsi(output);
  // After starting (0 completed), should show estimation based on all durations
  // Total expected = 15000ms → "15s"
  assertMatch(plain, /Est\. remaining/);
});

Deno.test("ProgressBar: formatDuration via finish output", () => {
  // We can't easily test formatDuration directly (private),
  // but we can observe it through the finish output.
  // A 1-task bar finished immediately should show "0s" or "1s" total time.
  const bar = new ProgressBar(1);
  bar.start("fast");
  bar.update(1);
  const output = bar.finish();
  const plain = stripAnsi(output);
  assertMatch(plain, /\d+s/); // matches "0s", "1s", etc.
});

// ---------------------------------------------------------------------------
// DurationCache
// ---------------------------------------------------------------------------

Deno.test("DurationCache: get returns null for unknown scenario", () => {
  const cache = new DurationCache("/nonexistent/path/that/does/not/exist");
  assertEquals(cache.get("unknown-scenario"), null);
});

Deno.test("DurationCache: set and get round-trips a duration", () => {
  const cache = new DurationCache("/nonexistent/path/that/does/not/exist");
  cache.set("01", 5000);
  assertEquals(cache.get("01"), 5000);
});

Deno.test("DurationCache: set applies EMA on subsequent calls (0.3 old + 0.7 new)", () => {
  const cache = new DurationCache("/nonexistent/path/that/does/not/exist");
  cache.set("01", 1000);
  cache.set("01", 2000);
  // EMA: Math.round(1000 * 0.3 + 2000 * 0.7) = Math.round(300 + 1400) = 1700
  assertEquals(cache.get("01"), 1700);
});

Deno.test("DurationCache: constructor with nonexistent path does not throw", () => {
  // Should silently initialize with empty cache
  const cache = new DurationCache("/nonexistent/path/that/does/not/exist");
  assertEquals(cache.get("anything"), null);
});
