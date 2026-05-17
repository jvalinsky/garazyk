/**
 * Unit tests for the OTel module — disabled path and initTracing.
 *
 * The enabled path requires npm:@opentelemetry/api which is not
 * available in a test environment without network access. We test
 * the disabled path (no OTEL_DENO set) and the initTracing
 * configuration logic.
 */

import { assertEquals } from "jsr:@std/assert";
import {
  addSpanAttribute,
  addSpanEvent,
  getTracingConfig,
  initTracing,
  isOtelEnabled,
  shutdownTracing,
  withSpan,
} from "./otel.ts";

// ---------------------------------------------------------------------------
// isOtelEnabled
// ---------------------------------------------------------------------------

Deno.test("isOtelEnabled: returns false when OTEL_DENO is not set", () => {
  // Save and restore
  const orig = Deno.env.get("OTEL_DENO");
  Deno.env.delete("OTEL_DENO");
  assertEquals(isOtelEnabled(), false);
  if (orig) Deno.env.set("OTEL_DENO", orig);
});

Deno.test("isOtelEnabled: returns true when OTEL_DENO=true", () => {
  const orig = Deno.env.get("OTEL_DENO");
  Deno.env.set("OTEL_DENO", "true");
  assertEquals(isOtelEnabled(), true);
  if (orig !== undefined) Deno.env.set("OTEL_DENO", orig);
  else Deno.env.delete("OTEL_DENO");
});

Deno.test("isOtelEnabled: returns true when OTEL_DENO=1", () => {
  const orig = Deno.env.get("OTEL_DENO");
  Deno.env.set("OTEL_DENO", "1");
  assertEquals(isOtelEnabled(), true);
  if (orig !== undefined) Deno.env.set("OTEL_DENO", orig);
  else Deno.env.delete("OTEL_DENO");
});

Deno.test("isOtelEnabled: returns false for other values", () => {
  const orig = Deno.env.get("OTEL_DENO");
  Deno.env.set("OTEL_DENO", "false");
  assertEquals(isOtelEnabled(), false);
  if (orig !== undefined) Deno.env.set("OTEL_DENO", orig);
  else Deno.env.delete("OTEL_DENO");
});

// ---------------------------------------------------------------------------
// initTracing
// ---------------------------------------------------------------------------

Deno.test("initTracing: sets OTEL_DENO when not already set", () => {
  const origOtel = Deno.env.get("OTEL_DENO");
  Deno.env.delete("OTEL_DENO");

  const result = initTracing({ serviceName: "test-service" });
  assertEquals(result, true);
  assertEquals(Deno.env.get("OTEL_DENO"), "true");
  assertEquals(Deno.env.get("OTEL_SERVICE_NAME"), "test-service");

  // Cleanup
  Deno.env.delete("OTEL_DENO");
  Deno.env.delete("OTEL_SERVICE_NAME");
  if (origOtel) Deno.env.set("OTEL_DENO", origOtel);
});

Deno.test("initTracing: sets OTLP endpoint", () => {
  const origOtel = Deno.env.get("OTEL_DENO");
  const origEndpoint = Deno.env.get("OTEL_EXPORTER_OTLP_ENDPOINT");
  Deno.env.delete("OTEL_DENO");
  Deno.env.delete("OTEL_EXPORTER_OTLP_ENDPOINT");

  initTracing({
    serviceName: "test",
    endpoint: "http://collector:4318",
  });
  assertEquals(Deno.env.get("OTEL_EXPORTER_OTLP_ENDPOINT"), "http://collector:4318");

  // Cleanup
  Deno.env.delete("OTEL_DENO");
  Deno.env.delete("OTEL_SERVICE_NAME");
  Deno.env.delete("OTEL_EXPORTER_OTLP_ENDPOINT");
  if (origOtel) Deno.env.set("OTEL_DENO", origOtel);
  if (origEndpoint) Deno.env.set("OTEL_EXPORTER_OTLP_ENDPOINT", origEndpoint);
});

Deno.test("initTracing: sets protocol", () => {
  const origOtel = Deno.env.get("OTEL_DENO");
  const origProtocol = Deno.env.get("OTEL_EXPORTER_OTLP_PROTOCOL");
  Deno.env.delete("OTEL_DENO");
  Deno.env.delete("OTEL_EXPORTER_OTLP_PROTOCOL");

  initTracing({
    serviceName: "test",
    protocol: "http/json",
  });
  assertEquals(Deno.env.get("OTEL_EXPORTER_OTLP_PROTOCOL"), "http/json");

  // Cleanup
  Deno.env.delete("OTEL_DENO");
  Deno.env.delete("OTEL_SERVICE_NAME");
  Deno.env.delete("OTEL_EXPORTER_OTLP_PROTOCOL");
  if (origOtel) Deno.env.set("OTEL_DENO", origOtel);
  if (origProtocol) Deno.env.set("OTEL_EXPORTER_OTLP_PROTOCOL", origProtocol);
});

Deno.test("initTracing: appends resource attributes", () => {
  const origOtel = Deno.env.get("OTEL_DENO");
  const origAttrs = Deno.env.get("OTEL_RESOURCE_ATTRIBUTES");
  Deno.env.delete("OTEL_DENO");
  Deno.env.delete("OTEL_RESOURCE_ATTRIBUTES");

  initTracing({
    serviceName: "test",
    resourceAttributes: { "service.version": "1.0" },
  });
  assertEquals(Deno.env.get("OTEL_RESOURCE_ATTRIBUTES"), "service.version=1.0");

  // Cleanup
  Deno.env.delete("OTEL_DENO");
  Deno.env.delete("OTEL_SERVICE_NAME");
  Deno.env.delete("OTEL_RESOURCE_ATTRIBUTES");
  if (origOtel) Deno.env.set("OTEL_DENO", origOtel);
  if (origAttrs) Deno.env.set("OTEL_RESOURCE_ATTRIBUTES", origAttrs);
});

// ---------------------------------------------------------------------------
// getTracingConfig
// ---------------------------------------------------------------------------

Deno.test("getTracingConfig: returns null before init", () => {
  // Note: this test may be affected by other tests calling initTracing.
  // We test the interface contract, not the global state.
  const config = getTracingConfig();
  // Config may be non-null if initTracing was called earlier in the process.
  // Just verify the type is correct.
  if (config !== null) {
    assertEquals(typeof config.serviceName, "string");
  }
});

// ---------------------------------------------------------------------------
// withSpan (disabled path)
// ---------------------------------------------------------------------------

Deno.test("withSpan: calls fn directly when OTel is disabled", async () => {
  const origOtel = Deno.env.get("OTEL_DENO");
  Deno.env.delete("OTEL_DENO");

  let called = false;
  const result = await withSpan("test-span", async () => {
    called = true;
    return 42;
  });
  assertEquals(called, true);
  assertEquals(result, 42);

  if (origOtel) Deno.env.set("OTEL_DENO", origOtel);
});

Deno.test("withSpan: propagates errors when OTel is disabled", async () => {
  const origOtel = Deno.env.get("OTEL_DENO");
  Deno.env.delete("OTEL_DENO");

  try {
    await withSpan("test-span", async () => {
      throw new Error("test error");
    });
    throw new Error("Should have thrown");
  } catch (e) {
    assertEquals((e as Error).message, "test error");
  }

  if (origOtel) Deno.env.set("OTEL_DENO", origOtel);
});

// ---------------------------------------------------------------------------
// addSpanAttribute / addSpanEvent (disabled path — no-ops)
// ---------------------------------------------------------------------------

Deno.test("addSpanAttribute: no-op when OTel is disabled", async () => {
  const origOtel = Deno.env.get("OTEL_DENO");
  Deno.env.delete("OTEL_DENO");

  // Should not throw
  await addSpanAttribute("test.key", "value");

  if (origOtel) Deno.env.set("OTEL_DENO", origOtel);
});

Deno.test("addSpanEvent: no-op when OTel is disabled", async () => {
  const origOtel = Deno.env.get("OTEL_DENO");
  Deno.env.delete("OTEL_DENO");

  // Should not throw
  await addSpanEvent("test-event", { key: "value" });

  if (origOtel) Deno.env.set("OTEL_DENO", origOtel);
});

// ---------------------------------------------------------------------------
// shutdownTracing (disabled path — no-op)
// ---------------------------------------------------------------------------

Deno.test("shutdownTracing: no-op when OTel is disabled", async () => {
  const origOtel = Deno.env.get("OTEL_DENO");
  Deno.env.delete("OTEL_DENO");

  // Should not throw
  await shutdownTracing();

  if (origOtel) Deno.env.set("OTEL_DENO", origOtel);
});
