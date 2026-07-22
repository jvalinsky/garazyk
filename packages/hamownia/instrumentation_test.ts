import { assertEquals } from "@std/assert";
import {
  InstrumentationReport,
  OperationStats,
  OperationTimer,
  PhaseTimer,
} from "./instrumentation.ts";

Deno.test("OperationStats min returns smallest positive duration", () => {
  const stats = new OperationStats("operation");
  stats.record(12);
  stats.record(7);
  stats.record(18);

  assertEquals(stats.min, 7);
  assertEquals(stats.toDict().min_ms, 7);
});

// ---------------------------------------------------------------------------
// OperationStats — expanded
// ---------------------------------------------------------------------------

Deno.test("OperationStats: max returns largest duration", () => {
  const stats = new OperationStats("op");
  stats.record(5);
  stats.record(10);
  stats.record(3);
  assertEquals(stats.max, 10);
});

Deno.test("OperationStats: max with no records returns 0", () => {
  assertEquals(new OperationStats("op").max, 0);
});

Deno.test("OperationStats: mean returns average of all durations", () => {
  const stats = new OperationStats("op");
  stats.record(10);
  stats.record(20);
  stats.record(30);
  assertEquals(stats.mean, 20);
});

Deno.test("OperationStats: mean with no records returns 0", () => {
  assertEquals(new OperationStats("op").mean, 0);
});

Deno.test("OperationStats: totalMs sums all durations", () => {
  const stats = new OperationStats("op");
  stats.record(10);
  stats.record(20);
  assertEquals(stats.totalMs, 30);
});

Deno.test("OperationStats: count tracks number of records", () => {
  const stats = new OperationStats("op");
  stats.record(1);
  stats.record(2);
  stats.record(3);
  assertEquals(stats.count, 3);
});

Deno.test("OperationStats: p50 of odd-length list", () => {
  // sorted [1,2,3,4,5], idx = floor(5*50/100) = 2 → 3
  const stats = new OperationStats("op");
  for (const v of [3, 1, 4, 2, 5]) stats.record(v);
  assertEquals(stats.p50, 3);
});

Deno.test("OperationStats: p95 of 20 values", () => {
  // sorted [1..20], idx = min(floor(20*95/100), 19) = min(19,19) = 19 → 20
  const stats = new OperationStats("op");
  for (let i = 1; i <= 20; i++) stats.record(i);
  assertEquals(stats.p95, 20);
});

Deno.test("OperationStats: percentile with no records returns 0", () => {
  assertEquals(new OperationStats("op").p50, 0);
  assertEquals(new OperationStats("op").p95, 0);
  assertEquals(new OperationStats("op").p99, 0);
});

Deno.test("OperationStats: toDict contains all keys", () => {
  const stats = new OperationStats("myop");
  stats.record(100);
  const d = stats.toDict();
  assertEquals(d.name, "myop");
  assertEquals(typeof d.count, "number");
  assertEquals(typeof d.min_ms, "number");
  assertEquals(typeof d.max_ms, "number");
  assertEquals(typeof d.mean_ms, "number");
  assertEquals(typeof d.p50_ms, "number");
  assertEquals(typeof d.p95_ms, "number");
  assertEquals(typeof d.p99_ms, "number");
});

Deno.test("OperationStats: toDict rounds to 2 decimal places", () => {
  const stats = new OperationStats("op");
  // 10.565 → toFixed(2) → "10.57" (unambiguously rounds up away from .5 edge cases)
  stats.record(10.565);
  const d = stats.toDict();
  // toFixed(2) of 10.565 === "10.57" on all JS engines
  assertEquals(d.min_ms, Number((10.565).toFixed(2)));
  assertEquals(d.max_ms, Number((10.565).toFixed(2)));
  assertEquals(d.mean_ms, Number((10.565).toFixed(2)));
});

// ---------------------------------------------------------------------------
// OperationTimer
// ---------------------------------------------------------------------------

Deno.test("OperationTimer: measure returns the function's return value", async () => {
  const timer = new OperationTimer();
  const result = await timer.measure("op", () => Promise.resolve("hello"));
  assertEquals(result, "hello");
});

Deno.test("OperationTimer: measure records a duration entry", async () => {
  const timer = new OperationTimer();
  await timer.measure("op", async () => {});
  assertEquals(timer.getStats("op").count, 1);
});

Deno.test("OperationTimer: measure increments count on each call", async () => {
  const timer = new OperationTimer();
  await timer.measure("op", async () => {});
  await timer.measure("op", async () => {});
  assertEquals(timer.getStats("op").count, 2);
});

Deno.test("OperationTimer: measure tracks different operation names separately", async () => {
  const timer = new OperationTimer();
  await timer.measure("op1", async () => {});
  await timer.measure("op2", async () => {});
  await timer.measure("op2", async () => {});
  assertEquals(timer.getStats("op1").count, 1);
  assertEquals(timer.getStats("op2").count, 2);
});

Deno.test("OperationTimer: measure propagates thrown errors and still records duration", async () => {
  const timer = new OperationTimer();
  let caught = false;
  try {
    await timer.measure("op", () => {
      throw new Error("boom");
    });
  } catch {
    caught = true;
  }
  assertEquals(caught, true);
  assertEquals(timer.getStats("op").count, 1);
});

Deno.test("OperationTimer: getStats returns undefined for unknown operation", () => {
  const timer = new OperationTimer();
  assertEquals(timer.getStats("unknown"), undefined);
});

Deno.test("OperationTimer: getAllStats returns all tracked operations", async () => {
  const timer = new OperationTimer();
  await timer.measure("alpha", async () => {});
  await timer.measure("beta", async () => {});
  const all = timer.getAllStats();
  assertEquals("alpha" in all, true);
  assertEquals("beta" in all, true);
});

Deno.test("OperationTimer: toDict serializes all operations", async () => {
  const timer = new OperationTimer();
  await timer.measure("alpha", async () => {});
  await timer.measure("beta", async () => {});
  const d = timer.toDict();
  assertEquals("alpha" in d, true);
  assertEquals("beta" in d, true);
});

// ---------------------------------------------------------------------------
// PhaseTimer
// ---------------------------------------------------------------------------

Deno.test("PhaseTimer: startPhase and endPhase record a duration >= 0", () => {
  const timer = new PhaseTimer();
  timer.startPhase("setup");
  timer.endPhase();
  const d = timer.toDict() as Record<string, number>;
  assertEquals(typeof d.setup, "number");
  assertEquals(d.setup >= 0, true);
});

Deno.test("PhaseTimer: multiple phases tracked independently", () => {
  const timer = new PhaseTimer();
  timer.startPhase("setup");
  timer.endPhase();
  timer.startPhase("run");
  timer.endPhase();
  const d = timer.toDict() as Record<string, number>;
  assertEquals("setup" in d, true);
  assertEquals("run" in d, true);
});

Deno.test("PhaseTimer: endPhase without startPhase is a no-op", () => {
  const timer = new PhaseTimer();
  timer.endPhase(); // no-op
  assertEquals(Object.keys(timer.toDict()).length, 0);
});

Deno.test("PhaseTimer: recorded duration is in seconds (less than 1 for fast ops)", async () => {
  const timer = new PhaseTimer();
  timer.startPhase("x");
  await new Promise((r) => setTimeout(r, 10));
  timer.endPhase();
  const d = timer.toDict() as Record<string, number>;
  assertEquals(d.x > 0, true);
  assertEquals(d.x < 1, true); // Should be ~0.01s, well under 1s
});

// ---------------------------------------------------------------------------
// InstrumentationReport
// ---------------------------------------------------------------------------

Deno.test("InstrumentationReport: toDict returns all required keys", () => {
  const report = new InstrumentationReport(
    { op: {} },
    { metric: {} },
    { pid: 1 },
    { db: [] },
    { setup: 0.5 },
  );
  const d = report.toDict();
  assertEquals("operations" in d, true);
  assertEquals("metrics" in d, true);
  assertEquals("process" in d, true);
  assertEquals("storage" in d, true);
  assertEquals("phase_timings" in d, true);
});

Deno.test("InstrumentationReport: writeJson creates file with valid JSON", async () => {
  const dir = await Deno.makeTempDir();
  try {
    const path = `${dir}/report.json`;
    const report = new InstrumentationReport(
      { op: { count: 1 } },
      {},
      { pid: 999 },
      {},
      { setup: 0.1 },
    );
    await report.writeJson(path);
    const text = await Deno.readTextFile(path);
    const parsed = JSON.parse(text);
    assertEquals("operations" in parsed, true);
    assertEquals("metrics" in parsed, true);
    assertEquals("process" in parsed, true);
    assertEquals("storage" in parsed, true);
    assertEquals("phase_timings" in parsed, true);
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});
