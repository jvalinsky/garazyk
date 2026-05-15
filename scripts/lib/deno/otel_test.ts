/**
 * Tests for the OpenTelemetry wrapper module.
 *
 * These tests verify the otel.ts API without requiring an actual OTel
 * backend. When OTEL_DENO is not set, all operations should be no-ops.
 */

import {
  addSpanAttribute,
  addSpanEvent,
  initE2eTracing,
  initTracing,
  isOtelEnabled,
  shutdownTracing,
  withSpan,
} from "./otel.ts";
import { assertEquals } from "@std/assert";

// ---------------------------------------------------------------------------
// isOtelEnabled
// ---------------------------------------------------------------------------

Deno.test("isOtelEnabled: returns false by default", () => {
  // OTEL_DENO should not be set in the test environment
  const original = Deno.env.get("OTEL_DENO");
  Deno.env.delete("OTEL_DENO");
  assertEquals(isOtelEnabled(), false);
  // Restore
  if (original !== undefined) Deno.env.set("OTEL_DENO", original);
});

Deno.test("isOtelEnabled: returns true when OTEL_DENO=true", () => {
  const original = Deno.env.get("OTEL_DENO");
  Deno.env.set("OTEL_DENO", "true");
  assertEquals(isOtelEnabled(), true);
  // Restore
  if (original !== undefined) Deno.env.set("OTEL_DENO", original);
  else Deno.env.delete("OTEL_DENO");
});

Deno.test("isOtelEnabled: returns true when OTEL_DENO=1", () => {
  const original = Deno.env.get("OTEL_DENO");
  Deno.env.set("OTEL_DENO", "1");
  assertEquals(isOtelEnabled(), true);
  // Restore
  if (original !== undefined) Deno.env.set("OTEL_DENO", original);
  else Deno.env.delete("OTEL_DENO");
});

// ---------------------------------------------------------------------------
// initTracing
// ---------------------------------------------------------------------------

Deno.test("initTracing: sets OTEL_DENO and environment variables", () => {
  const origOtelDeno = Deno.env.get("OTEL_DENO");
  const origServiceName = Deno.env.get("OTEL_SERVICE_NAME");
  const origEndpoint = Deno.env.get("OTEL_EXPORTER_OTLP_ENDPOINT");
  const origProtocol = Deno.env.get("OTEL_EXPORTER_OTLP_PROTOCOL");
  const origResourceAttrs = Deno.env.get("OTEL_RESOURCE_ATTRIBUTES");

  Deno.env.delete("OTEL_DENO");
  Deno.env.delete("OTEL_SERVICE_NAME");
  Deno.env.delete("OTEL_EXPORTER_OTLP_ENDPOINT");
  Deno.env.delete("OTEL_EXPORTER_OTLP_PROTOCOL");
  Deno.env.delete("OTEL_RESOURCE_ATTRIBUTES");

  const result = initTracing({
    serviceName: "test-service",
    endpoint: "http://localhost:4318",
    protocol: "http/protobuf",
    resourceAttributes: { "service.version": "test" },
  });

  assertEquals(result, true);
  assertEquals(Deno.env.get("OTEL_DENO"), "true");
  assertEquals(Deno.env.get("OTEL_SERVICE_NAME"), "test-service");
  assertEquals(Deno.env.get("OTEL_EXPORTER_OTLP_ENDPOINT"), "http://localhost:4318");
  assertEquals(Deno.env.get("OTEL_EXPORTER_OTLP_PROTOCOL"), "http/protobuf");
  assertEquals(Deno.env.get("OTEL_RESOURCE_ATTRIBUTES"), "service.version=test");

  // Restore
  if (origOtelDeno !== undefined) Deno.env.set("OTEL_DENO", origOtelDeno);
  else Deno.env.delete("OTEL_DENO");
  if (origServiceName !== undefined) Deno.env.set("OTEL_SERVICE_NAME", origServiceName);
  else Deno.env.delete("OTEL_SERVICE_NAME");
  if (origEndpoint !== undefined) Deno.env.set("OTEL_EXPORTER_OTLP_ENDPOINT", origEndpoint);
  else Deno.env.delete("OTEL_EXPORTER_OTLP_ENDPOINT");
  if (origProtocol !== undefined) Deno.env.set("OTEL_EXPORTER_OTLP_PROTOCOL", origProtocol);
  else Deno.env.delete("OTEL_EXPORTER_OTLP_PROTOCOL");
  if (origResourceAttrs !== undefined) Deno.env.set("OTEL_RESOURCE_ATTRIBUTES", origResourceAttrs);
  else Deno.env.delete("OTEL_RESOURCE_ATTRIBUTES");
});

// ---------------------------------------------------------------------------
// initE2eTracing
// ---------------------------------------------------------------------------

Deno.test("initE2eTracing: uses default endpoint when not set", () => {
  const origEndpoint = Deno.env.get("OTEL_EXPORTER_OTLP_ENDPOINT");
  Deno.env.delete("OTEL_EXPORTER_OTLP_ENDPOINT");

  initE2eTracing("garazyk-e2e-runner");
  assertEquals(Deno.env.get("OTEL_EXPORTER_OTLP_ENDPOINT"), "http://localhost:4318");
  assertEquals(Deno.env.get("OTEL_SERVICE_NAME"), "garazyk-e2e-runner");

  // Restore
  if (origEndpoint !== undefined) Deno.env.set("OTEL_EXPORTER_OTLP_ENDPOINT", origEndpoint);
  else Deno.env.delete("OTEL_EXPORTER_OTLP_ENDPOINT");
});

Deno.test("initE2eTracing: respects existing endpoint env var", () => {
  const origEndpoint = Deno.env.get("OTEL_EXPORTER_OTLP_ENDPOINT");
  Deno.env.set("OTEL_EXPORTER_OTLP_ENDPOINT", "http://custom:4318");

  initE2eTracing("garazyk-e2e-runner");
  assertEquals(Deno.env.get("OTEL_EXPORTER_OTLP_ENDPOINT"), "http://custom:4318");

  // Restore
  if (origEndpoint !== undefined) Deno.env.set("OTEL_EXPORTER_OTLP_ENDPOINT", origEndpoint);
  else Deno.env.delete("OTEL_EXPORTER_OTLP_ENDPOINT");
});

// ---------------------------------------------------------------------------
// withSpan
// ---------------------------------------------------------------------------

Deno.test("withSpan: calls function directly when OTel disabled", async () => {
  const origOtelDeno = Deno.env.get("OTEL_DENO");
  Deno.env.delete("OTEL_DENO");

  let called = false;
  const result = await withSpan("test.span", async () => {
    called = true;
    return 42;
  });
  assertEquals(called, true);
  assertEquals(result, 42);

  if (origOtelDeno !== undefined) Deno.env.set("OTEL_DENO", origOtelDeno);
  else Deno.env.delete("OTEL_DENO");
});

Deno.test("withSpan: propagates errors when OTel disabled", async () => {
  const origOtelDeno = Deno.env.get("OTEL_DENO");
  Deno.env.delete("OTEL_DENO");

  let caught = false;
  try {
    await withSpan("test.span", async () => {
      throw new Error("test error");
    });
  } catch (err) {
    caught = true;
    assertEquals((err as Error).message, "test error");
  }
  assertEquals(caught, true);

  if (origOtelDeno !== undefined) Deno.env.set("OTEL_DENO", origOtelDeno);
  else Deno.env.delete("OTEL_DENO");
});

Deno.test("withSpan: works with attributes when OTel disabled", async () => {
  const origOtelDeno = Deno.env.get("OTEL_DENO");
  Deno.env.delete("OTEL_DENO");

  const result = await withSpan("test.span", async () => "hello", {
    "key": "value",
    "count": 42,
    "flag": true,
  });
  assertEquals(result, "hello");

  if (origOtelDeno !== undefined) Deno.env.set("OTEL_DENO", origOtelDeno);
  else Deno.env.delete("OTEL_DENO");
});

// ---------------------------------------------------------------------------
// addSpanAttribute / addSpanEvent (no-op when disabled)
// ---------------------------------------------------------------------------

Deno.test("addSpanAttribute: no-op when OTel disabled", async () => {
  const origOtelDeno = Deno.env.get("OTEL_DENO");
  Deno.env.delete("OTEL_DENO");

  // Should not throw
  await addSpanAttribute("test.key", "test.value");

  if (origOtelDeno !== undefined) Deno.env.set("OTEL_DENO", origOtelDeno);
  else Deno.env.delete("OTEL_DENO");
});

Deno.test("addSpanEvent: no-op when OTel disabled", async () => {
  const origOtelDeno = Deno.env.get("OTEL_DENO");
  Deno.env.delete("OTEL_DENO");

  // Should not throw
  await addSpanEvent("test.event", { "key": "value" });

  if (origOtelDeno !== undefined) Deno.env.set("OTEL_DENO", origOtelDeno);
  else Deno.env.delete("OTEL_DENO");
});

// ---------------------------------------------------------------------------
// shutdownTracing
// ---------------------------------------------------------------------------

Deno.test("shutdownTracing: no-op when not initialized", async () => {
  // Should not throw
  await shutdownTracing();
});

// ---------------------------------------------------------------------------
// Topology compiler OTel integration
// ---------------------------------------------------------------------------

Deno.test("topology compiler: --otel flag injects OTel env vars", async () => {
  const { renderComposeYaml } = await import("./topology_compiler.ts");
  const { resolvePreset } = await import("./topology.ts");
  const preset = resolvePreset("garazyk-default");

  const yaml = renderComposeYaml(preset, {
    preset: "garazyk-default",
    runDir: "/tmp/test",
    repoRoot: "/tmp/test",
    composeProject: "test",
    otel: true,
  });

  // Should contain OTel env vars in service definitions
  assertEquals(yaml.includes("OTEL_SERVICE_NAME="), true);
  assertEquals(yaml.includes("OTEL_EXPORTER_OTLP_ENDPOINT=http://signoz-otel-collector:4318"), true);
  assertEquals(yaml.includes("OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf"), true);

  // Should contain SigNoz services
  assertEquals(yaml.includes("signoz-otel-collector"), true);
  assertEquals(yaml.includes("clickhouse"), true);
  assertEquals(yaml.includes("signoz:"), true);
  assertEquals(yaml.includes("4317:4317"), true);
  assertEquals(yaml.includes("4318:4318"), true);
  assertEquals(yaml.includes("3301:8080"), true);
});

Deno.test("topology compiler: no OTel env vars when --otel not set", async () => {
  const { renderComposeYaml } = await import("./topology_compiler.ts");
  const { resolvePreset } = await import("./topology.ts");
  const preset = resolvePreset("garazyk-default");

  const yaml = renderComposeYaml(preset, {
    preset: "garazyk-default",
    runDir: "/tmp/test",
    repoRoot: "/tmp/test",
    composeProject: "test",
    otel: false,
  });

  // Should NOT contain OTel env vars
  assertEquals(yaml.includes("OTEL_SERVICE_NAME="), false);
  assertEquals(yaml.includes("signoz-otel-collector"), false);
});
