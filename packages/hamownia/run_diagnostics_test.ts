import { assertEquals, assertMatch, assertStringIncludes } from "@std/assert";
import {
  collectDiagnostics,
  createRunContext,
  redactDiagnosticText,
} from "./run_diagnostics.ts";

Deno.test("redactDiagnosticText preserves JSON strings while redacting secrets", () => {
  const input = JSON.stringify({
    accessJwt: "abc.def.ghi",
    password: "secret-password",
    nested: { token: "token-value" },
  });

  const redacted = redactDiagnosticText(input);
  const parsed = JSON.parse(redacted);
  assertEquals(parsed.accessJwt, "[REDACTED]");
  assertEquals(parsed.password, "[REDACTED]");
  assertEquals(parsed.nested.token, "[REDACTED]");
});

Deno.test("redactDiagnosticText redacts bearer tokens and env-style secrets", () => {
  const redacted = redactDiagnosticText(
    "Authorization: Bearer abc.def.ghi\nMASTER_SECRET=top-secret\n",
  );
  assertStringIncludes(redacted, "Authorization: Bearer [REDACTED]");
  assertStringIncludes(redacted, "MASTER_SECRET=[REDACTED]");
});

// ---------------------------------------------------------------------------
// redactDiagnosticText — edge cases
// ---------------------------------------------------------------------------

Deno.test("redactDiagnosticText: redacts refreshJwt field", () => {
  const input = JSON.stringify({
    refreshJwt: "eyJhbGciOiJIUzI1NiJ9.payload.sig",
  });
  const redacted = redactDiagnosticText(input);
  const parsed = JSON.parse(redacted);
  assertEquals(parsed.refreshJwt, "[REDACTED]");
});

Deno.test("redactDiagnosticText: redacts ADMIN_SECRET env-style", () => {
  const redacted = redactDiagnosticText("ADMIN_SECRET=letmein123");
  assertStringIncludes(redacted, "ADMIN_SECRET=[REDACTED]");
});

Deno.test("redactDiagnosticText: preserves non-secret fields unchanged", () => {
  const input = JSON.stringify({ username: "alice", did: "did:plc:abc" });
  const redacted = redactDiagnosticText(input);
  const parsed = JSON.parse(redacted);
  assertEquals(parsed.username, "alice");
  assertEquals(parsed.did, "did:plc:abc");
});

// ---------------------------------------------------------------------------
// createRunContext
// ---------------------------------------------------------------------------

const DIAG_ENV_KEYS = [
  "ATPROTO_E2E_RUN_ID",
  "ATPROTO_E2E_RUN_DIR",
  "ATPROTO_E2E_LOG_DIR",
  "ATPROTO_E2E_REPORTS_DIR",
  "ATPROTO_E2E_DIAGNOSTICS_DIR",
  "ATPROTO_E2E_PID_FILE",
  "ATPROTO_E2E_COMPOSE_PROJECT",
  "ATPROTO_E2E_BASE_DIR",
  "ATPROTO_RESOURCE_MANIFEST",
  "ATPROTO_TOPOLOGY_MANIFEST",
  "ATPROTO_BINARY_MODE",
];

async function withTempRunContext<T>(
  fn: (tempDir: string) => Promise<T>,
): Promise<T> {
  const dir = await Deno.makeTempDir();
  const originals: Record<string, string | undefined> = {};
  for (const key of DIAG_ENV_KEYS) {
    originals[key] = Deno.env.get(key);
    Deno.env.delete(key);
  }
  Deno.env.set("ATPROTO_E2E_BASE_DIR", dir);
  try {
    return await fn(dir);
  } finally {
    for (const [key, val] of Object.entries(originals)) {
      if (val === undefined) Deno.env.delete(key);
      else Deno.env.set(key, val);
    }
    await Deno.remove(dir, { recursive: true });
  }
}

Deno.test("createRunContext: creates all required directories", async () => {
  await withTempRunContext(async () => {
    const ctx = await createRunContext();
    for (
      const path of [
        ctx.runDir,
        ctx.logsDir,
        ctx.reportsDir,
        ctx.diagnosticsDir,
      ]
    ) {
      const stat = await Deno.stat(path);
      assertEquals(stat.isDirectory, true);
    }
  });
});

Deno.test("createRunContext: generates a default runId when none provided", async () => {
  await withTempRunContext(async () => {
    const ctx = await createRunContext();
    // Default: timestamp + pid, sanitized to lowercase alphanum-dash
    assertMatch(ctx.runId, /^[a-z0-9][a-z0-9-]*[a-z0-9]$/);
    assertEquals(ctx.runId.length > 4, true);
  });
});

Deno.test("createRunContext: uses the provided runId", async () => {
  await withTempRunContext(async () => {
    const ctx = await createRunContext("my-run-xyz");
    assertEquals(ctx.runId, "my-run-xyz");
  });
});

Deno.test("createRunContext: sanitizes unsafe characters in runId", async () => {
  await withTempRunContext(async () => {
    const ctx = await createRunContext("my run!@#");
    // Only safe chars: lowercase alphanum and dash
    assertMatch(ctx.runId, /^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$/);
  });
});

Deno.test("createRunContext: composeProject starts with garazyk-e2e-", async () => {
  await withTempRunContext(async () => {
    const ctx = await createRunContext("test-id-42");
    assertEquals(ctx.composeProject.startsWith("garazyk-e2e-"), true);
  });
});

Deno.test("createRunContext: sets ATPROTO_E2E_RUN_ID env var", async () => {
  await withTempRunContext(async () => {
    const ctx = await createRunContext("env-test-run");
    assertEquals(Deno.env.get("ATPROTO_E2E_RUN_ID"), ctx.runId);
  });
});

Deno.test("collectDiagnostics: tolerates missing topology manifest when resource manifest drives the run", async () => {
  await withTempRunContext(async (dir) => {
    const ctx = await createRunContext("manifest-only-run");
    Deno.env.set("ATPROTO_BINARY_MODE", "1");
    Deno.env.set("ATPROTO_TOPOLOGY_MANIFEST", `${dir}/missing-topology.json`);
    await collectDiagnostics(ctx, {
      serviceUrls: { pds: "http://127.0.0.1:9" },
    });

    const metadata = JSON.parse(
      await Deno.readTextFile(`${ctx.diagnosticsDir}/run-metadata.json`),
    );
    assertEquals(metadata.run_id, "manifest-only-run");
    assertEquals(metadata.service_urls.pds, "http://127.0.0.1:9");
  });
});
