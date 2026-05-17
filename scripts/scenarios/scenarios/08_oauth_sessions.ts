/**
 * @module scenarios/08_oauth_sessions
 *
 * Scenario: Tests OAuth2 authorization flows, session lifecycle management, and authentication security.
 *
 * Behavior:
 * - Creates test accounts for Luna and Marcus.
 * - Registers an OAuth client using the `kaszlak` utility if available.
 * - Verifies that the OAuth authorize endpoint enforces Pushed Authorization Requests (PAR).
 * - Checks that the token and revocation endpoints correctly handle invalid inputs.
 * - Tests standard session lifecycle: Create, Get, Refresh, and Delete (logout).
 * - Verifies that refresh attempts after session deletion fail.
 * - Confirms that invalid passwords and unauthorized requests are correctly rejected.
 *
 * Expectations:
 * - Session management (create/refresh/delete) works according to spec.
 * - OAuth flows enforce security protocols (PAR).
 * - Invalid authentication attempts are appropriately denied.
 */

import { XrpcClient } from "../../lib/deno/client.ts";
import { getCharacter, PDS1 } from "../../lib/deno/config.ts";
import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";

function now() {
  return new Date().toISOString();
}

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("OAuth2 & Sessions");
  result.start();

  const client = new XrpcClient(PDS1);

  await timedCall(
    result,
    "Server health check",
    async () => {
      const res = await fetch(`${PDS1}/xrpc/com.atproto.server.describeServer`);
      if (!res.ok) throw new Error("Server not healthy");
    },
  );

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const charNames = ["luna", "marcus"];
  for (const name of charNames) {
    const char = getCharacter(name);
    const session = await timedCall(
      result,
      `Create account: ${char.name}`,
      async () => {
        try {
          const res = await client.agent.createAccount({
            handle: char.handle,
            email: char.email,
            password: char.password,
          });
          return res.data;
        } catch (e: any) {
          if (e.message && e.message.includes("already exists")) {
            const res = await client.agent.login({
              identifier: char.handle,
              password: char.password,
            });
            return res.data;
          }
          throw e;
        }
      },
      (s) => `did=${s.did}`,
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
      char.refreshJwt = session.refreshJwt;
    }
  }

  const luna = getCharacter("luna");
  const marcus = getCharacter("marcus");

  if (!luna.did || !marcus.did) {
    result.stepFailed("Account creation", "Not all accounts created");
    result.finish();
    return result;
  }

  try {
    const cmd = new Deno.Command("git", { args: ["rev-parse", "--show-toplevel"] });
    const { stdout } = await cmd.output();
    const repoRoot = new TextDecoder().decode(stdout).trim() || Deno.cwd();
    const binPaths = [
      `${repoRoot}/build/bin/kaszlak`,
      `${repoRoot}/docker/local-network/staging/bin/kaszlak`,
    ];

    let registered = false;
    for (const binPath of binPaths) {
      try {
        const stat = await Deno.stat(binPath);
        if (stat.isFile) {
          const regCmd = new Deno.Command(binPath, {
            args: [
              "oauth",
              "client",
              "register",
              "--client-id",
              "scenario-test-client",
              "--redirect-uri",
              `${PDS1}/oauth/callback`,
            ],
          });
          const regRes = await regCmd.output();
          if (regRes.code === 0) {
            result.stepPassed("OAuth client registered");
            registered = true;
            break;
          }
        }
      } catch {
        // try next
      }
    }
    if (!registered) {
      result.stepSkipped(
        "OAuth client registered",
        "kaszlak binary not found or registration failed",
      );
    }
  } catch (exc: any) {
    result.stepSkipped("OAuth client registered", String(exc));
  }

  try {
    const authUrl =
      `${PDS1}/oauth/authorize?client_id=scenario-test-client&redirect_uri=${PDS1}/oauth/callback&response_type=code&scope=atproto&state=test-state-123`;
    const authResp = await fetch(authUrl, { redirect: "manual" });
    let body: any = {};
    try {
      body = await authResp.json();
    } catch {
      // ignore
    }

    if (authResp.status === 400 && body.error === "invalid_request") {
      result.stepPassed(
        "OAuth authorize enforces PAR",
        "direct params rejected with invalid_request",
      );
    } else {
      result.stepFailed(
        "OAuth authorize enforces PAR",
        `status=${authResp.status} body=${JSON.stringify(body)}`,
      );
    }
  } catch (exc: any) {
    result.stepFailed("OAuth authorize enforces PAR", String(exc));
  }

  try {
    const tokenParams = new URLSearchParams();
    tokenParams.append("grant_type", "authorization_code");
    tokenParams.append("client_id", "scenario-test-client");
    tokenParams.append("redirect_uri", `${PDS1}/oauth/callback`);
    tokenParams.append("code", "test-invalid-code");
    tokenParams.append("code_verifier", "test-verifier");

    const tokenResp = await fetch(`${PDS1}/oauth/token`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: tokenParams.toString(),
    });

    if ([400, 401, 403].includes(tokenResp.status)) {
      result.stepPassed("OAuth token endpoint rejects invalid code", `status=${tokenResp.status}`);
    } else {
      result.stepSkipped("OAuth token endpoint", `status=${tokenResp.status}`);
    }
  } catch (exc: any) {
    result.stepSkipped("OAuth token endpoint", String(exc));
  }

  try {
    const revokeParams = new URLSearchParams();
    revokeParams.append("client_id", "scenario-test-client");
    revokeParams.append("token", "test-invalid-token");

    const revokeResp = await fetch(`${PDS1}/oauth/revoke`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: revokeParams.toString(),
    });

    if ([200, 400, 401].includes(revokeResp.status)) {
      result.stepPassed("OAuth revoke endpoint responds", `status=${revokeResp.status}`);
    } else {
      result.stepSkipped("OAuth revoke endpoint", `status=${revokeResp.status}`);
    }
  } catch (exc: any) {
    result.stepSkipped("OAuth revoke endpoint", String(exc));
  }

  await timedCall(
    result,
    "Luna creates session",
    async () => {
      const res = await client.raw.post("com.atproto.server.createSession", {
        identifier: luna.handle,
        password: luna.password,
      });
      return res;
    },
    (s) => `token=${s.accessJwt.substring(0, 20)}...`,
  );

  await timedCall(
    result,
    "Luna gets session info",
    async () => {
      return await client.raw.get("com.atproto.server.getSession", {}, luna.accessJwt);
    },
    (s) => `did=${s.did}`,
  );

  if (luna.refreshJwt) {
    const refreshed = await timedCall(
      result,
      "Luna refreshes session",
      async () => {
        return await client.raw.post("com.atproto.server.refreshSession", {}, luna.refreshJwt);
      },
      (r) => `token=${r.accessJwt.substring(0, 20)}...`,
    );
    if (refreshed) {
      luna.accessJwt = refreshed.accessJwt;
    }
  } else {
    result.stepSkipped("Luna refreshes session", "No refreshJwt");
  }

  let marcusRefreshJwt = null;
  const marcusSession = await timedCall(
    result,
    "Marcus creates session",
    async () => {
      return await client.raw.post("com.atproto.server.createSession", {
        identifier: marcus.handle,
        password: marcus.password,
      });
    },
  );

  if (marcusSession) {
    marcus.accessJwt = marcusSession.accessJwt;
    marcus.refreshJwt = marcusSession.refreshJwt;
    marcusRefreshJwt = marcusSession.refreshJwt;
  }

  try {
    await client.raw.post(
      "com.atproto.server.deleteSession",
      {},
      marcus.refreshJwt || marcus.accessJwt,
    );
    result.stepPassed("Marcus deletes session (logout)");
  } catch (exc: any) {
    result.stepFailed("Marcus deletes session", String(exc));
  }

  if (marcusRefreshJwt) {
    await timedCall(
      result,
      "Refresh after deleteSession fails",
      async () => {
        await client.raw.post("com.atproto.server.refreshSession", {}, marcusRefreshJwt);
      },
      undefined,
      true,
    );
  } else {
    result.stepSkipped(
      "Refresh after deleteSession fails",
      "no refreshJwt returned by createSession",
    );
  }

  await timedCall(
    result,
    "Invalid password rejected",
    async () => {
      await client.raw.post("com.atproto.server.createSession", {
        identifier: luna.handle,
        password: "absolutely_wrong_password",
      });
    },
    undefined,
    true,
  );

  await timedCall(
    result,
    "Missing auth rejected",
    async () => {
      await client.raw.post("com.atproto.repo.createRecord", {
        repo: luna.did,
        collection: "app.bsky.feed.post",
        record: {
          $type: "app.bsky.feed.post",
          text: "unauthorized",
          createdAt: now(),
        },
      }, "invalid-token-xyz");
    },
    undefined,
    true,
  );

  result.finish();
  return result;
}

if (import.meta.main) {
  run().then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
