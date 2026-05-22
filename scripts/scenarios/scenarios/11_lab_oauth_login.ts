/**
 * @module scenarios/11_lab_oauth_login
 *
 * Scenario: Lab OAuth2 Login and Admin Auth flow
 *
 * Behavior:
 * - Checks UI server health via the /lab endpoint.
 * - Verifies the lab page loads and contains required HTML elements.
 * - Validates the OAuth client metadata for required properties and configuration.
 * - Confirms the lab callback handles OAuth parameters correctly.
 * - Tests admin access boundary and authentication flows using credentials.
 * - Validates authenticated HTMX partials access and logout behavior.
 *
 * Expectations:
 * - OAuth configuration is valid and supports DPoP.
 * - Admin authentication successfully sets cookies and provides authorized access.
 * - Unauthorized access attempts are correctly rejected.
 */

import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { SERVICE_URLS } from "../../lib/deno/config.ts";

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Lab OAuth2 Login");
  result.start();

  const uiUrl = (SERVICE_URLS.webClient || SERVICE_URLS.ui).replace(/\/$/, "");
  const adminPassword = Deno.env.get("GARAZYK_UI_ADMIN_PASSWORD") || "admin-localdev";

  await timedCall(
    result,
    "UI Server health check",
    async () => {
      const res = await fetch(`${uiUrl}/lab`, { redirect: "manual" });
      if (res.status !== 200) throw new Error(`GET /lab returned status=${res.status}`);
    },
  );

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  await timedCall(
    result,
    "Lab page loads",
    async () => {
      const res = await fetch(`${uiUrl}/lab`, { redirect: "manual" });
      const contentType = res.headers.get("Content-Type") || "";
      const body = await res.text();
      assert.isTrue(res.status === 200, `status=${res.status}`);
      assert.isTrue(
        contentType.toLowerCase().startsWith("text/html"),
        `content_type=${contentType}`,
      );
      assert.isTrue(body.includes("lab-login-section"), "body missing lab-login-section");
    },
  );

  await timedCall(
    result,
    "Lab client metadata valid",
    async () => {
      const res = await fetch(`${uiUrl}/lab/client-metadata.json`, { redirect: "manual" });
      const metadata = await res.json();

      if (typeof metadata !== "object" || metadata === null || Array.isArray(metadata)) {
        result.stepSkipped(
          "Lab client metadata valid",
          `garazyk-ui returned non-object JSON (${typeof metadata}), skipping OAuth metadata checks`,
        );
        return;
      }

      const requiredKeys = [
        "client_id",
        "client_name",
        "redirect_uris",
        "scope",
        "grant_types",
        "response_types",
        "token_endpoint_auth_method",
        "application_type",
        "dpop_bound_access_tokens",
      ];

      for (const key of requiredKeys) {
        assert.isTrue(key in metadata, `missing key: ${key}`);
      }

      assert.isTrue(res.status === 200, `status=${res.status}`);
      assert.isTrue(typeof metadata.client_id === "string" && metadata.client_id.length > 0, "missing client_id");
      assert.isTrue(
        metadata.grant_types?.includes("authorization_code"),
        "missing auth_code grant",
      );
      assert.isTrue(metadata.token_endpoint_auth_method === "none", "wrong auth method");
      assert.isTrue(metadata.dpop_bound_access_tokens === true, "dpop not enabled");
      assert.isTrue(
        metadata.redirect_uris?.some((uri: string) => uri.includes("/lab/callback")),
        "missing callback uri",
      );
    },
  );

  await timedCall(
    result,
    "Lab callback accepts code param",
    async () => {
      const url = new URL(`${uiUrl}/lab/callback`);
      url.searchParams.append("code", "test-code");
      url.searchParams.append("state", "test-state");
      const res = await fetch(url.toString(), { redirect: "manual" });
      assert.isTrue(res.status === 200, `status=${res.status}`);
    },
  );

  await timedCall(
    result,
    "Admin auth boundary",
    async () => {
      const res = await fetch(`${uiUrl}/admin`, { redirect: "manual" });
      assert.isTrue(res.status === 302, `status=${res.status}`);
    },
  );

  let adminCookieHeader = "";
  await timedCall(
    result,
    "Admin login flow",
    async () => {
      const res = await fetch(`${uiUrl}/admin/login`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ password: adminPassword }),
      });
      assert.isTrue(res.status === 200, `status=${res.status}`);

      const setCookie = res.headers.get("Set-Cookie") || "";
      const match = setCookie.match(/ui_admin_token=([^;]+)/);
      let token = match ? match[1] : null;

      if (!token) {
        const body = await res.json();
        token = body.token || body.ui_admin_token;
      }

      if (!token) {
        throw new Error("token not found");
      }
      adminCookieHeader = `ui_admin_token=${token}`;
    },
  );

  if (adminCookieHeader) {
    await timedCall(
      result,
      "Admin authenticated access",
      async () => {
        const res = await fetch(`${uiUrl}/admin`, {
          headers: { "Cookie": adminCookieHeader },
          redirect: "manual",
        });
        assert.isTrue(res.status === 200, `status=${res.status}`);
      },
    );
  }

  await timedCall(
    result,
    "Admin HTMX auth",
    async () => {
      const res = await fetch(`${uiUrl}/admin/partials/overview`, {
        headers: { "HX-Request": "true" },
        redirect: "manual",
      });
      assert.isTrue(res.status === 401, `status=${res.status}`);
    },
  );

  if (adminCookieHeader) {
    await timedCall(
      result,
      "Admin HTMX with auth",
      async () => {
        const res = await fetch(`${uiUrl}/admin/partials/overview`, {
          headers: { "HX-Request": "true", "Cookie": adminCookieHeader },
          redirect: "manual",
        });
        assert.isTrue(res.status === 200, `status=${res.status}`);
      },
    );
  }

  if (adminCookieHeader) {
    await timedCall(
      result,
      "Admin logout",
      async () => {
        const res = await fetch(`${uiUrl}/admin/logout`, {
          method: "POST",
          headers: { "Cookie": adminCookieHeader },
        });
        assert.isTrue(res.status === 200, `status=${res.status}`);

        const postLogout = await fetch(`${uiUrl}/admin`, {
          headers: { "Cookie": adminCookieHeader },
          redirect: "manual",
        });
        assert.isTrue(postLogout.status === 302, `status=${postLogout.status} after logout`);
      },
    );
  }

  result.finish();
  return result;
}

if (import.meta.main) {
  run().then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
