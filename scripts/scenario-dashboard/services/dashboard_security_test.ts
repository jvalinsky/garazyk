import { assertEquals, assertNotEquals, assertThrows } from "@std/assert";
import {
  createDashboardSecurity,
  validateDashboardMutation,
} from "./dashboard_security.ts";

const MUTATION_PATHS = [
  "/api/network/start",
  "/api/network/stop",
  "/api/runs/start",
  "/api/runs/run-123/stop",
  "/api/runs/run-123/restart",
  "/api/scenarios",
];

const NOW = 1_000_000;

function loopbackSecurity(expiresAt = NOW + 60_000) {
  return createDashboardSecurity({
    host: "127.0.0.1",
    port: 3001,
    capability: "valid-capability",
    expiresAt,
  });
}

function mutationRequest(
  path: string,
  headers: HeadersInit = {},
): Request {
  return new Request(`http://127.0.0.1:3001${path}`, {
    method: "POST",
    headers: {
      Host: "127.0.0.1:3001",
      Origin: "http://127.0.0.1:3001",
      ...headers,
    },
  });
}

Deno.test("dashboard security defaults to an explicit loopback bind", () => {
  const security = createDashboardSecurity({
    capability: "valid-capability",
    expiresAt: NOW + 60_000,
  });

  assertEquals(security.host, "127.0.0.1");
  assertEquals(security.isLoopback, true);
});

Deno.test("dashboard security generates a distinct capability for each launch", () => {
  const first = createDashboardSecurity();
  const second = createDashboardSecurity();

  assertEquals(first.mutationCapability.length, 64);
  assertNotEquals(first.mutationCapability, second.mutationCapability);
});

Deno.test("dashboard security rejects a non-loopback bind without authentication", () => {
  assertThrows(
    () => createDashboardSecurity({ host: "0.0.0.0" }),
    Error,
    "DASHBOARD_AUTH_TOKEN",
  );
});

for (const path of MUTATION_PATHS) {
  Deno.test(`dashboard mutation ${path} rejects a missing capability`, () => {
    const result = validateDashboardMutation(
      mutationRequest(path),
      loopbackSecurity(),
      NOW,
    );

    assertEquals(result?.status, 403);
  });

  Deno.test(`dashboard mutation ${path} rejects a wrong capability`, () => {
    const result = validateDashboardMutation(
      mutationRequest(path, { "X-Dashboard-Capability": "wrong" }),
      loopbackSecurity(),
      NOW,
    );

    assertEquals(result?.status, 403);
  });

  Deno.test(`dashboard mutation ${path} rejects an expired capability`, () => {
    const result = validateDashboardMutation(
      mutationRequest(path, { "X-Dashboard-Capability": "valid-capability" }),
      loopbackSecurity(NOW - 1),
      NOW,
    );

    assertEquals(result?.status, 403);
  });

  Deno.test(`dashboard mutation ${path} accepts a valid capability`, () => {
    const result = validateDashboardMutation(
      mutationRequest(path, { "X-Dashboard-Capability": "valid-capability" }),
      loopbackSecurity(),
      NOW,
    );

    assertEquals(result, null);
  });

  Deno.test(`dashboard mutation ${path} rejects a hostile Host header`, () => {
    const result = validateDashboardMutation(
      mutationRequest(path, {
        Host: "attacker.invalid:3001",
        "X-Dashboard-Capability": "valid-capability",
      }),
      loopbackSecurity(),
      NOW,
    );

    assertEquals(result?.status, 403);
  });

  Deno.test(`dashboard mutation ${path} rejects a hostile Origin header`, () => {
    const result = validateDashboardMutation(
      mutationRequest(path, {
        Origin: "https://attacker.invalid",
        "X-Dashboard-Capability": "valid-capability",
      }),
      loopbackSecurity(),
      NOW,
    );

    assertEquals(result?.status, 403);
  });
}

Deno.test("non-loopback mutations require the configured authentication token", () => {
  const security = createDashboardSecurity({
    host: "0.0.0.0",
    port: 3001,
    authenticationToken: "dashboard-authentication",
    capability: "valid-capability",
    expiresAt: NOW + 60_000,
  });
  const headers = {
    Host: "0.0.0.0:3001",
    Origin: "http://0.0.0.0:3001",
    "X-Dashboard-Capability": "valid-capability",
  };

  assertEquals(
    validateDashboardMutation(
      mutationRequest("/api/runs/start", headers),
      security,
      NOW,
    )?.status,
    401,
  );
  assertEquals(
    validateDashboardMutation(
      mutationRequest("/api/runs/start", {
        ...headers,
        Authorization: "Bearer wrong",
      }),
      security,
      NOW,
    )?.status,
    401,
  );
  assertEquals(
    validateDashboardMutation(
      mutationRequest("/api/runs/start", {
        ...headers,
        Authorization: "Bearer dashboard-authentication",
      }),
      security,
      NOW,
    ),
    null,
  );
});
