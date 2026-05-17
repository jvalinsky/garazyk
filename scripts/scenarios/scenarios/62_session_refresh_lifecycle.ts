/**
 * @module scenarios/62_session_refresh_lifecycle
 *
 * Scenario: 62 session refresh lifecycle
 *
 * Behavior:
 * - Executes the 62 session refresh lifecycle scenario.
 * - Validates core operations.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import { getCharacter, PDS1 } from "../../lib/deno/config.ts";
import { ScenarioResult } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { timedCall } from "../../lib/deno/runner.ts";

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Session Refresh Lifecycle");
  result.start();

  const client = new XrpcClient(PDS1);

  await timedCall(result, "PDS health check", async () => {
    await client.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const luna = getCharacter("luna");

  // ── Create account and get initial session ─────────────────────────────────
  const initialSession = await timedCall(
    result,
    "Create account",
    async () => {
      return await client.accounts.createAccount(luna.handle, luna.email, luna.password);
    },
    (s) => `did=${s.did}`,
  );

  if (!initialSession) {
    result.finish();
    return result;
  }

  luna.did = initialSession.did;
  luna.accessJwt = initialSession.accessJwt;
  luna.refreshJwt = initialSession.refreshJwt;

  // ── Verify initial session works ──────────────────────────────────────────
  await timedCall(
    result,
    "getSession works with initial accessJwt",
    async () => {
      return await client.accounts.getSession(luna.accessJwt);
    },
    (s) => `handle=${s.handle}`,
  );

  // ── Refresh the session ───────────────────────────────────────────────────
  const refreshedSession = await timedCall(
    result,
    "refreshSession with refreshJwt",
    async () => {
      return await client.accounts.refreshSession(luna.refreshJwt!);
    },
    (s) => `did=${s.did}, hasAccess=${!!s.accessJwt}, hasRefresh=${!!s.refreshJwt}`,
  );

  if (refreshedSession) {
    // ── Verify new access token works ────────────────────────────────────────
    await timedCall(
      result,
      "getSession works with new accessJwt",
      async () => {
        return await client.accounts.getSession(refreshedSession.accessJwt);
      },
      (s) => `handle=${s.handle}`,
    );

    // ── Verify new refresh token works (rotation) ────────────────────────────
    await timedCall(
      result,
      "Second refresh with rotated refreshJwt",
      async () => {
        return await client.accounts.refreshSession(refreshedSession.refreshJwt);
      },
      (s) => `did=${s.did}`,
    );

    // ── Verify old refresh token is invalidated ─────────────────────────────
    await timedCall(
      result,
      "Old refreshJwt is rejected",
      async () => {
        // The first refreshJwt should no longer work after rotation
        await client.accounts.refreshSession(luna.refreshJwt!);
      },
      undefined,
      true, // expectError
    );
  }

  // ── Verify invalid refresh token is rejected ──────────────────────────────
  await timedCall(
    result,
    "Invalid refreshJwt is rejected",
    async () => {
      await client.accounts.refreshSession("invalid-jwt-token-value");
    },
    undefined,
    true, // expectError
  );

  // ── Verify empty refresh token is rejected ────────────────────────────────
  await timedCall(
    result,
    "Empty refreshJwt is rejected",
    async () => {
      await client.accounts.refreshSession("");
    },
    undefined,
    true, // expectError
  );

  // ── Verify getSession with invalid token is rejected ──────────────────────
  await timedCall(
    result,
    "getSession with invalid accessJwt is rejected",
    async () => {
      await client.accounts.getSession("invalid-access-token");
    },
    undefined,
    true, // expectError
  );

  result.finish();
  return result;
}

if (import.meta.main) {
  const r = await run();
  console.log(r.summary());
  Deno.exit(r.ok ? 0 : 1);
}
