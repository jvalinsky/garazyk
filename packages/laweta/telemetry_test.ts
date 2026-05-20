import { assert, assertEquals } from "@std/assert";
import {
  addSpanEvent,
  isOtelEnabled,
  recordCounter,
  recordGauge,
  setTelemetryTestHook,
  withSpan,
} from "./telemetry.ts";

Deno.test("isOtelEnabled: returns false when OTEL_DENO is not set", () => {
  assert(!isOtelEnabled());
});

Deno.test("isOtelEnabled: returns true when OTEL_DENO is 'true'", () => {
  const prev = Deno.env.get("OTEL_DENO");
  Deno.env.set("OTEL_DENO", "true");
  try {
    assert(isOtelEnabled());
  } finally {
    if (prev === undefined) Deno.env.delete("OTEL_DENO");
    else Deno.env.set("OTEL_DENO", prev);
  }
});

Deno.test("isOtelEnabled: returns false for values other than 'true'", () => {
  const prev = Deno.env.get("OTEL_DENO");
  Deno.env.set("OTEL_DENO", "false");
  try {
    assert(!isOtelEnabled());
  } finally {
    if (prev === undefined) Deno.env.delete("OTEL_DENO");
    else Deno.env.set("OTEL_DENO", prev);
  }
});

Deno.test("withSpan: invokes the wrapped function and returns its result", async () => {
  const result = await withSpan("test-span", () => 42);
  assertEquals(result, 42);
});

Deno.test("withSpan: works with synchronous functions", async () => {
  const result = await withSpan("sync-span", () => "hello");
  assertEquals(result, "hello");
});

Deno.test("withSpan: propagates errors from the wrapped function", async () => {
  let caught = false;
  try {
    await withSpan("err-span", () => {
      throw new Error("test failure");
    });
  } catch (e) {
    caught = true;
    assert(e instanceof Error && e.message === "test failure");
  }
  assert(caught);
});

Deno.test("setTelemetryTestHook: hook is invoked when telemetry is triggered", async () => {
  const calls: string[] = [];
  setTelemetryTestHook({
    addSpanEvent: (name) => {
      calls.push(name);
    },
  });

  await addSpanEvent("hook-test");
  assertEquals(calls, ["hook-test"]);

  setTelemetryTestHook(null);
});

Deno.test("setTelemetryTestHook: resetting the hook disables callbacks", async () => {
  const calls: string[] = [];
  setTelemetryTestHook({
    addSpanEvent: (name) => {
      calls.push(name);
    },
  });
  setTelemetryTestHook(null);

  await addSpanEvent("should-not-fire");
  assertEquals(calls.length, 0);
});

Deno.test("recordGauge: invokes the test hook when installed", async () => {
  let recordedName = "";
  let recordedValue = 0;
  setTelemetryTestHook({
    recordGauge: (name, value) => {
      recordedName = name;
      recordedValue = value;
    },
  });

  await recordGauge("test_gauge", 99);
  assertEquals(recordedName, "test_gauge");
  assertEquals(recordedValue, 99);

  setTelemetryTestHook(null);
});

Deno.test("recordGauge: is a no-op when no test hook is installed", async () => {
  setTelemetryTestHook(null);
  await recordGauge("noop_gauge", 42);
  // No assertion needed — just verifying it doesn't throw.
});

Deno.test("recordCounter: invokes the test hook when installed", async () => {
  let recordedName = "";
  let recordedValue = 0;
  setTelemetryTestHook({
    recordCounter: (name, value) => {
      recordedName = name;
      recordedValue = value;
    },
  });

  await recordCounter("test_counter", 5);
  assertEquals(recordedName, "test_counter");
  assertEquals(recordedValue, 5);

  setTelemetryTestHook(null);
});

Deno.test("recordCounter: is a no-op when no test hook is installed", async () => {
  setTelemetryTestHook(null);
  await recordCounter("noop_counter", 1);
});

Deno.test("addSpanEvent: invokes the test hook when installed", async () => {
  let eventName = "";
  setTelemetryTestHook({
    addSpanEvent: (name) => {
      eventName = name;
    },
  });

  await addSpanEvent("test_event");
  assertEquals(eventName, "test_event");

  setTelemetryTestHook(null);
});

Deno.test("addSpanEvent: is a no-op when no test hook is installed", async () => {
  setTelemetryTestHook(null);
  await addSpanEvent("noop_event");
});

Deno.test("recordGauge: passes attributes to the test hook", async () => {
  let capturedAttributes: Record<string, string | number | boolean> | undefined;
  setTelemetryTestHook({
    recordGauge: (_name, _value, attrs) => {
      capturedAttributes = attrs;
    },
  });

  await recordGauge("attr_gauge", 1, { key: "val", count: 3 });
  assertEquals(capturedAttributes, { key: "val", count: 3 });

  setTelemetryTestHook(null);
});

Deno.test("addSpanEvent: passes attributes to the test hook", async () => {
  let capturedAttributes: Record<string, string | number | boolean> | undefined;
  setTelemetryTestHook({
    addSpanEvent: (_name, attrs) => {
      capturedAttributes = attrs;
    },
  });

  await addSpanEvent("attr_event", { tag: "demo", active: true });
  assertEquals(capturedAttributes, { tag: "demo", active: true });

  setTelemetryTestHook(null);
});
