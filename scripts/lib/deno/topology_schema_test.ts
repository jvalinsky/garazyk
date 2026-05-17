/**
 * Unit tests for topology_schema pure functions:
 * parseScenarioRequirement, normalizePorts, renderPortSpec,
 * normalizeVolumes, renderVolumeSpec.
 *
 * These tests exercise the pure synchronous parsing logic
 * without requiring filesystem access or Docker.
 */

import { assertEquals, assertRejects, assertThrows } from "jsr:@std/assert";
import {
  normalizePorts,
  normalizeVolumes,
  parseScenarioRequirement,
  renderPortSpec,
  renderVolumeSpec,
} from "./topology_schema.ts";

// ---------------------------------------------------------------------------
// parseScenarioRequirement
// ---------------------------------------------------------------------------

Deno.test("parseScenarioRequirement: parses 'role:capability' string", () => {
  const result = parseScenarioRequirement("pds:repo");
  assertEquals(result, { role: "pds", capability: "repo" });
});

Deno.test("parseScenarioRequirement: parses bare capability string", () => {
  const result = parseScenarioRequirement("pds");
  assertEquals(result, { capability: "pds" });
});

Deno.test("parseScenarioRequirement: throws on triple-colon string", () => {
  assertThrows(
    () => parseScenarioRequirement("a:b:c"),
    Error,
    "Invalid scenario requirement",
  );
});

Deno.test("parseScenarioRequirement: passes through object input", () => {
  const result = parseScenarioRequirement({ role: "pds", capability: "repo" });
  assertEquals(result, { role: "pds", capability: "repo" });
});

Deno.test("parseScenarioRequirement: passes through capability-only object", () => {
  const result = parseScenarioRequirement({ capability: "pds" });
  assertEquals(result, { capability: "pds" });
});

// ---------------------------------------------------------------------------
// normalizePorts
// ---------------------------------------------------------------------------

Deno.test("normalizePorts: parses host:container string", () => {
  const result = normalizePorts(["2583:2583"]);
  assertEquals(result.length, 1);
  assertEquals(result[0].host, "2583");
  assertEquals(result[0].container, "2583");
  assertEquals(result[0].protocol, "tcp");
});

Deno.test("normalizePorts: parses container-only string", () => {
  const result = normalizePorts(["2583"]);
  assertEquals(result.length, 1);
  assertEquals(result[0].container, "2583");
  assertEquals(result[0].host, undefined);
  assertEquals(result[0].protocol, "tcp");
});

Deno.test("normalizePorts: parses UDP protocol suffix", () => {
  const result = normalizePorts(["2583:2583/udp"]);
  assertEquals(result.length, 1);
  assertEquals(result[0].protocol, "udp");
});

Deno.test("normalizePorts: defaults to TCP protocol", () => {
  const result = normalizePorts(["2583:2583"]);
  assertEquals(result[0].protocol, "tcp");
});

Deno.test("normalizePorts: parses PortSpec objects", () => {
  const result = normalizePorts([{ container: "2583", protocol: "tcp" as const }]);
  assertEquals(result.length, 1);
  assertEquals(result[0].container, "2583");
  assertEquals(result[0].protocol, "tcp");
});

Deno.test("normalizePorts: returns empty array for undefined", () => {
  assertEquals(normalizePorts(undefined), []);
  assertEquals(normalizePorts([]), []);
});

// ---------------------------------------------------------------------------
// renderPortSpec
// ---------------------------------------------------------------------------

Deno.test("renderPortSpec: renders host:container", () => {
  assertEquals(renderPortSpec({ host: "2583", container: "2583", protocol: "tcp" }), "2583:2583");
});

Deno.test("renderPortSpec: renders container-only", () => {
  assertEquals(renderPortSpec({ container: "2583", protocol: "tcp" }), "2583");
});

Deno.test("renderPortSpec: appends /udp for UDP", () => {
  assertEquals(
    renderPortSpec({ host: "2583", container: "2583", protocol: "udp" }),
    "2583:2583/udp",
  );
});

// ---------------------------------------------------------------------------
// normalizeVolumes
// ---------------------------------------------------------------------------

Deno.test("normalizeVolumes: parses bind mount string", () => {
  const result = normalizeVolumes(["./data:/app/data"]);
  assertEquals(result.length, 1);
  assertEquals(result[0].kind, "bind");
  assertEquals(result[0].source, "./data");
  assertEquals(result[0].target, "/app/data");
});

Deno.test("normalizeVolumes: parses absolute bind mount", () => {
  const result = normalizeVolumes(["/var/data:/app/data"]);
  assertEquals(result.length, 1);
  assertEquals(result[0].kind, "bind");
  assertEquals(result[0].source, "/var/data");
  assertEquals(result[0].target, "/app/data");
});

Deno.test("normalizeVolumes: parses named volume", () => {
  const result = normalizeVolumes(["myvolume:/app/data"]);
  assertEquals(result.length, 1);
  assertEquals(result[0].kind, "named");
  assertEquals(result[0].source, "myvolume");
  assertEquals(result[0].target, "/app/data");
});

Deno.test("normalizeVolumes: parses read-only mode", () => {
  const result = normalizeVolumes(["./data:/app/data:ro"]);
  assertEquals(result.length, 1);
  assertEquals(result[0].mode, "ro");
});

Deno.test("normalizeVolumes: parses single-component as named volume", () => {
  const result = normalizeVolumes(["myvolume"]);
  assertEquals(result.length, 1);
  assertEquals(result[0].kind, "named");
  assertEquals(result[0].source, "myvolume");
  assertEquals(result[0].target, "myvolume");
});

Deno.test("normalizeVolumes: returns empty array for undefined", () => {
  assertEquals(normalizeVolumes(undefined), []);
  assertEquals(normalizeVolumes([]), []);
});

// ---------------------------------------------------------------------------
// renderVolumeSpec
// ---------------------------------------------------------------------------

Deno.test("renderVolumeSpec: renders source:target", () => {
  assertEquals(
    renderVolumeSpec({ kind: "bind", source: "./data", target: "/app/data" }),
    "./data:/app/data",
  );
});

Deno.test("renderVolumeSpec: renders source:target:mode", () => {
  assertEquals(
    renderVolumeSpec({ kind: "bind", source: "./data", target: "/app/data", mode: "ro" }),
    "./data:/app/data:ro",
  );
});

Deno.test("renderVolumeSpec: renders source:target without mode", () => {
  assertEquals(
    renderVolumeSpec({ kind: "named", source: "vol", target: "/app/data" }),
    "vol:/app/data",
  );
});
