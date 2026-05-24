import { assertEquals } from "@std/assert";
import { offsetMsToLogLineIndex, offsetMsToLogScrollRatio } from "./timeline.ts";

Deno.test("offsetMsToLogLineIndex: maps offset to last log line at or before t", () => {
  const started = 1000;
  const events = [
    { eventType: "run_started", timestamp: 1000 },
    { eventType: "log_line", timestamp: 1500 },
    { eventType: "log_line", timestamp: 2000 },
    { eventType: "log_line", timestamp: 3000 },
  ];
  assertEquals(offsetMsToLogLineIndex(events, started, 0), 0);
  assertEquals(offsetMsToLogLineIndex(events, started, 600), 0);
  assertEquals(offsetMsToLogLineIndex(events, started, 1600), 1);
  assertEquals(offsetMsToLogLineIndex(events, started, 9000), 2);
});

Deno.test("offsetMsToLogScrollRatio: falls back when no log lines", () => {
  const started = 0;
  const events = [
    { eventType: "scenario_started", timestamp: 500 },
    { eventType: "scenario_finished", timestamp: 1000 },
  ];
  assertEquals(offsetMsToLogScrollRatio(events, started, 500), 0.5);
});
