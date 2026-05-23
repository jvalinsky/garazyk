import { assert, assertEquals } from "@std/assert";
import {
  ROLE_TO_ENV,
  ROLE_TO_PORT,
  ROLE_TO_SERVICE,
} from "./topology_types.ts";
import type { ServiceRole } from "./topology_types.ts";

Deno.test("ROLE_TO_SERVICE: maps every known role to a service name", () => {
  const roles: ServiceRole[] = [
    "pds",
    "relay",
    "appview",
    "plc",
    "mikrus",
    "beskid",
    "chat",
    "video",
    "ui",
    "backfill",
    "pds2",
  ];
  for (const role of roles) {
    const service = ROLE_TO_SERVICE[role];
    assert(
      typeof service === "string",
      `ROLE_TO_SERVICE[${role}] should be a string`,
    );
    assert(service.length > 0, `ROLE_TO_SERVICE[${role}] should not be empty`);
  }
});

Deno.test("ROLE_TO_PORT: maps every known role to a port string", () => {
  const roles: ServiceRole[] = [
    "pds",
    "relay",
    "appview",
    "plc",
    "mikrus",
    "beskid",
    "chat",
    "video",
    "ui",
    "backfill",
    "pds2",
  ];
  for (const role of roles) {
    const port = ROLE_TO_PORT[role];
    assert(
      typeof port === "string",
      `ROLE_TO_PORT[${role}] should be a string`,
    );
    // Port should be a numeric string
    assert(
      /^\d+$/.test(port),
      `ROLE_TO_PORT[${role}] = '${port}' should be numeric`,
    );
  }
});

Deno.test("ROLE_TO_ENV: maps known roles to environment variable names", () => {
  // Check that the core roles have env var mappings
  const coreRoles = ["pds", "relay", "appview", "plc"];
  for (const role of coreRoles) {
    const envKey = ROLE_TO_ENV[role];
    assert(
      typeof envKey === "string",
      `ROLE_TO_ENV[${role}] should be a string`,
    );
    assert(envKey.length > 0, `ROLE_TO_ENV[${role}] should not be empty`);
  }
});

Deno.test("ROLE_TO_SERVICE: pds maps to local-pds", () => {
  assertEquals(ROLE_TO_SERVICE["pds"], "local-pds");
});

Deno.test("ROLE_TO_SERVICE: relay maps to local-relay", () => {
  assertEquals(ROLE_TO_SERVICE["relay"], "local-relay");
});

Deno.test("ROLE_TO_PORT: pds and pds2 have different ports", () => {
  assert(
    ROLE_TO_PORT["pds"] !== ROLE_TO_PORT["pds2"],
    "pds and pds2 should use different ports",
  );
});
