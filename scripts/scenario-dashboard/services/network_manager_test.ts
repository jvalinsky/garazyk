import { assertEquals } from "@std/assert";
import { healthUrlFromManifest } from "./network_manager.ts";
import type { RunResourceManifest } from "@garazyk/schemat";

function baseManifest(
  services: RunResourceManifest["services"],
): RunResourceManifest {
  return {
    version: 1,
    runId: "test-run",
    runDir: "/tmp/test-run",
    ownerPid: 1,
    createdAt: "2026-01-01T00:00:00.000Z",
    updatedAt: "2026-01-01T00:00:00.000Z",
    composeProject: "test",
    isolation: "auto",
    services,
    cleanup: { status: "active" },
  };
}

Deno.test("healthUrlFromManifest: valid manifest returns hostUrl + healthPath", () => {
  const manifest = baseManifest({
    pds: {
      role: "pds",
      hostUrl: "http://127.0.0.1:2583",
      healthPath: "/xrpc/com.atproto.server.describeServer",
    },
  });
  assertEquals(
    healthUrlFromManifest(manifest, "local-pds", "pds"),
    "http://127.0.0.1:2583/xrpc/com.atproto.server.describeServer",
  );
});

Deno.test("healthUrlFromManifest: falls back to the raw (non-normalized) name", () => {
  const manifest = baseManifest({
    relay: {
      role: "relay",
      hostUrl: "http://127.0.0.1:2584",
      healthPath: "/api/relay/health",
    },
  });
  assertEquals(
    healthUrlFromManifest(manifest, "relay", "relay"),
    "http://127.0.0.1:2584/api/relay/health",
  );
});

Deno.test("healthUrlFromManifest: missing manifest returns null", () => {
  assertEquals(healthUrlFromManifest(undefined, "pds", "pds"), null);
});

Deno.test("healthUrlFromManifest: manifest with no services map returns null", () => {
  const manifest = baseManifest(
    undefined as unknown as RunResourceManifest["services"],
  );
  assertEquals(healthUrlFromManifest(manifest, "pds", "pds"), null);
});

Deno.test("healthUrlFromManifest: role not present in manifest returns null", () => {
  const manifest = baseManifest({
    pds: {
      role: "pds",
      hostUrl: "http://127.0.0.1:2583",
      healthPath: "/xrpc/com.atproto.server.describeServer",
    },
  });
  assertEquals(healthUrlFromManifest(manifest, "appview", "appview"), null);
});

Deno.test("healthUrlFromManifest: role present but missing healthPath returns null (malformed probe)", () => {
  const manifest = baseManifest({
    pds: { role: "pds", hostUrl: "http://127.0.0.1:2583" },
  });
  assertEquals(healthUrlFromManifest(manifest, "pds", "pds"), null);
});

Deno.test("healthUrlFromManifest: role present but missing hostUrl returns null (malformed probe)", () => {
  const manifest = baseManifest({
    pds: { role: "pds", healthPath: "/xrpc/com.atproto.server.describeServer" },
  });
  assertEquals(healthUrlFromManifest(manifest, "pds", "pds"), null);
});
