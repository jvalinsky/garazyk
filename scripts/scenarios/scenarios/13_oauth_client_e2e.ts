/**
 * @module scenarios/13_oauth_client_e2e
 *
 * Scenario: E2E OAuth2 Client Integration and Browser Flow
 *
 * Behavior:
 * - Creates a user account and resolves handle/DID.
 * - Inspects the DID document for PDS endpoint configuration.
 * - Verifies OAuth protected resource and authorization server metadata.
 * - Automates browser-based OAuth login flow including PAR, consent, and redirect.
 * - Validates profile display post-login and checks for public network leaks.
 *
 * Expectations:
 * - OAuth metadata is correctly configured and reachable.
 * - Browser automation successfully completes the full OAuth login and consent process.
 * - Post-login profile is correctly resolved and displayed.
 */

import { ScenarioResult, timedCall } from "@garazyk/hamownia";
export { ScenarioResult, StepResult, StepStatus } from "@garazyk/hamownia";
export type { ScenarioReport } from "@garazyk/hamownia";
import { assert } from "@garazyk/hamownia";
import { XrpcClient } from "@garazyk/gruszka";
import type { ScenarioContext } from "@garazyk/hamownia";
import { createScenarioContext } from "@garazyk/hamownia";
import { attachPublicNetworkLeakGuard } from "@garazyk/hamownia";
import { chromium } from "npm:playwright";

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(ctx: ScenarioContext): Promise<ScenarioResult> {
  const result = new ScenarioResult("E2E OAuth2 Client Integration");
  result.start();

  const pds = new XrpcClient(ctx.pds1);
  const luna = ctx.getCharacter("luna");
  const PDS_URL = (ctx as any).serviceUrls?.pds;
  const PLC_URL = ctx.serviceUrls.plc;

  const session = await timedCall(
    result,
    "Create account",
    async () => {
      return await pds.accounts.createAccount(
        luna.handle,
        luna.email,
        luna.password,
      );
    },
    (s: any) => `did=${s.did}`,
  );

  if (!session) {
    result.finish();
    return result;
  }
  luna.did = session.did;

  await timedCall(
    result,
    "Verify account resolution",
    async () => {
      const res = await pds.identity.resolveHandle(luna.handle);
      assert.isTrue(
        res.did === luna.did,
        `DID mismatch: expected ${luna.did}, got ${res.did}`,
      );
      return res;
    },
    (r: any) => `handle ${luna.handle} -> ${r.did}`,
  );

  await timedCall(
    result,
    "DID document inspection",
    async () => {
      const res = await fetch(`${PLC_URL}/${luna.did}`);
      const didDoc = await res.json();
      const services = didDoc.service || [];
      const pdsEndpoint = services.find((s: any) =>
        s.id === "#atproto_pds" || s.id.includes("atproto_pds")
      )?.serviceEndpoint;
      assert.isTrue(pdsEndpoint, "PDS serviceEndpoint not found in DID doc");
      return { pdsEndpoint };
    },
    (r: any) => `serviceEndpoint=${r.pdsEndpoint}`,
  );

  await timedCall(
    result,
    "Protected resource metadata",
    async () => {
      const res = await fetch(
        `${PDS_URL}/.well-known/oauth-protected-resource`,
        {
          headers: {
            "Accept": "application/json",
            "Origin": ctx.serviceUrls.oauthClient,
          },
        },
      );
      const body = await res.json();
      assert.isTrue(res.status === 200, `status=${res.status}`);
      assert.isTrue(
        body.resource === PDS_URL,
        `unexpected resource: ${body.resource}`,
      );
    },
  );

  await timedCall(
    result,
    "Authorization server metadata",
    async () => {
      const res = await fetch(
        `${PDS_URL}/.well-known/oauth-authorization-server`,
        {
          headers: {
            "Accept": "application/json",
            "Origin": ctx.serviceUrls.oauthClient,
          },
        },
      );
      const body = await res.json();
      assert.isTrue(res.status === 200, `status=${res.status}`);
      assert.isTrue(
        body.issuer === PDS_URL,
        `unexpected issuer: ${body.issuer}`,
      );
    },
  );

  const clientUrl = ctx.serviceUrls.oauthClient.replace(/\/$/, "");
  try {
    const res = await fetch(`${clientUrl}/client-metadata.json`);
    if (res.status !== 200) {
      result.stepSkipped(
        "OAuth Client availability",
        `Status ${res.status}; skipping browser automation`,
      );
      result.finish();
      return result;
    }
  } catch (e: any) {
    result.stepSkipped(
      "OAuth Client availability",
      `OAuth client not reachable: ${e.message}; skipping browser automation`,
    );
    result.finish();
    return result;
  }

  try {
    const browser = await chromium.launch({ headless: true });
    const context = await browser.newContext();
    const page = await context.newPage();
    const publicNetworkLeaks = attachPublicNetworkLeakGuard(page);

    await page.goto(clientUrl);
    result.stepPassed("Step 1: Navigate to client app");

    await page.fill("#handle", luna.handle);
    await page.click("#login-btn");
    result.stepPassed("Step 2: Initiate login flow & Resolve Handle");

    try {
      await page.waitForSelector("#auth-handle", { timeout: 30000 });
      result.stepPassed(
        "Step 3: Redirected to PDS authorize page (PAR completed)",
      );
    } catch (e) {
      const screenshotPath = `/tmp/oauth_failure_${Date.now()}.png`;
      await page.screenshot({ path: screenshotPath });
      result.stepFailed(
        "Redirected to PDS authorize page",
        `Timeout waiting for #auth-handle. Screenshot: ${screenshotPath}`,
      );
      await browser.close();
      result.finish();
      return result;
    }

    await page.fill("#auth-handle", luna.handle);
    await page.fill("#auth-password", luna.password);
    await page.click("#auth-signin-btn");
    result.stepPassed("PDS Sign-in successful");

    await page.waitForSelector("button[type='submit'].btn-primary", {
      timeout: 5000,
    });
    await page.click("button[type='submit'].btn-primary");
    result.stepPassed("Consent granted");

    await page.waitForSelector("#profile", { timeout: 10000 });
    const displayName = await page.innerText("#display-name");
    assert.isTrue(
      displayName.includes("did:plc:"),
      `Unexpected display name: ${displayName}`,
    );
    result.stepPassed("Profile displayed", `Logged in as ${displayName}`);
    if (publicNetworkLeaks.length > 0) {
      result.stepFailed(
        "Public network leak guard",
        publicNetworkLeaks.slice(0, 5).join(", "),
      );
    } else {
      result.stepPassed("Public network leak guard");
    }

    await browser.close();
  } catch (e: any) {
    result.stepFailed("Browser automation", e.message || String(e));
  }

  result.finish();
  return result;
}

if (import.meta.main) {
  run(createScenarioContext()).then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
