import { assertEquals, assertThrows } from "jsr:@std/assert";
import { assertServiceHealthResult } from "./docker.ts";

for (const label of ["PLC", "PDS", "Relay", "PDS2"]) {
  Deno.test(`health gating throws when ${label} is unhealthy`, () => {
    assertThrows(
      () => assertServiceHealthResult(label, false, 60),
      Error,
      `${label} failed to start within 60s`,
    );
  });
}

Deno.test("health gating preserves AppView-specific timeout", () => {
  assertThrows(
    () => assertServiceHealthResult("AppView", false, 90),
    Error,
    "AppView failed to start within 90s",
  );
});

Deno.test("health gating accepts healthy services", () => {
  assertEquals(assertServiceHealthResult("PDS", true, 60), undefined);
});
