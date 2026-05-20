import { assert, assertEquals } from "@std/assert";
import { neededPorts, serviceUrl } from "./docker_config.ts";

const basePorts = [2582, 2583, 2584, 3200, 8080];

Deno.test("neededPorts: returns the base set of ports when no options are given", () => {
  const ports = neededPorts({});
  assertEquals(ports.length, 5);
  for (const p of basePorts) assert(ports.includes(p), `expected ${p} in ports`);
});

Deno.test("neededPorts: adds pds2 port when withPds2 is enabled", () => {
  const ports = neededPorts({ withPds2: true });
  const expected = new Set([...basePorts, 2587]);
  assertEquals(new Set(ports), expected);
});

Deno.test("neededPorts: adds otel ports when otel is enabled", () => {
  const ports = neededPorts({ otel: true });
  const expected = new Set([...basePorts, 4317, 4318, 3301]);
  assertEquals(new Set(ports), expected);
});

Deno.test("neededPorts: includes both pds2 and otel ports when both flags are on", () => {
  const ports = neededPorts({ withPds2: true, otel: true });
  const expected = new Set([...basePorts, 2587, 4317, 4318, 3301]);
  assertEquals(new Set(ports), expected);
});

Deno.test("neededPorts: returns a new array each time", () => {
  const a = neededPorts({});
  const b = neededPorts({});
  assertEquals(a, b);
  a.push(9999);
  assertEquals(neededPorts({}).length, 5);
});

Deno.test("serviceUrl: uses the default port from SERVICE_PORTS", () => {
  // Ensure no env override is present.
  const prev = Deno.env.get("PDS_PORT");
  Deno.env.delete("PDS_PORT");
  try {
    assertEquals(serviceUrl("pds"), "http://127.0.0.1:2583");
  } finally {
    if (prev !== undefined) Deno.env.set("PDS_PORT", prev);
  }
});

Deno.test("serviceUrl: falls back to port 0 for unknown services", () => {
  assertEquals(serviceUrl("unknown_service"), "http://127.0.0.1:0");
});

Deno.test("serviceUrl: honors the env-var override", () => {
  const prev = Deno.env.get("PDS_PORT");
  Deno.env.set("PDS_PORT", "9090");
  try {
    assertEquals(serviceUrl("pds"), "http://127.0.0.1:9090");
  } finally {
    if (prev === undefined) Deno.env.delete("PDS_PORT");
    else Deno.env.set("PDS_PORT", prev);
  }
});

Deno.test("serviceUrl: constructs the URL with case-insensitive env lookup", () => {
  const prev = Deno.env.get("RELAY_PORT");
  Deno.env.set("RELAY_PORT", "7777");
  try {
    assertEquals(serviceUrl("relay"), "http://127.0.0.1:7777");
  } finally {
    if (prev === undefined) Deno.env.delete("RELAY_PORT");
    else Deno.env.set("RELAY_PORT", prev);
  }
});
