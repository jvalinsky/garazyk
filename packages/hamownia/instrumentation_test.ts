import { assertEquals } from "@std/assert";
import { OperationStats } from "./instrumentation.ts";

Deno.test("OperationStats min returns smallest positive duration", () => {
  const stats = new OperationStats("operation");
  stats.record(12);
  stats.record(7);
  stats.record(18);

  assertEquals(stats.min, 7);
  assertEquals(stats.toDict().min_ms, 7);
});
