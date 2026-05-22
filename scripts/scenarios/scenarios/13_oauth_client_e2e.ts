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

import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
export {
  ScenarioResult,
  StepResult,
  StepStatus,
} from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { getCharacter, PDS1, SERVICE_URLS } from "../../lib/deno/config.ts";
import { attachPublicNetworkLeakGuard } from "../../lib/deno/browser_flow.ts";
import { chromium } from "npm:playwright";
import type { Browser } from "npm:playwright";

const PDS_URL = SERVICE_URLS.pds;
const PLC_URL = SERVICE_URLS.plc;

interface OAuthClientMetadata {
  client_uri?: string;
  redirect_uris?: string[];
}

function recent(items: string[], limit = 12): string {
  return items.slice(-limit).join("\n");
}

async function resolveOAuthClientUrl(
  configuredClientUrl: string,
): Promise<string | null> {
  const metadataUrl = `${configuredClientUrl}/client-metadata.json`;
  const res = await fetch(metadataUrl);
  if (res.status !== 200) {
    return null;
  }

  const metadata = await res.json() as OAuthClientMetadata;
  const redirectUri = metadata.redirect_uris?.[0];
  const browserUrl = metadata.client_uri ?? redirectUri;
  if (!browserUrl) {
    throw new Error(
      `OAuth client metadata at ${metadataUrl} did not include client_uri or redirect_uris`,
    );
  }

  return new URL(browserUrl).origin;
}

async function pageState(page: any): Promise<string> {
  let status = "<unavailable>";
  try {
    status = await page.locator("#status").innerText({ timeout: 1000 });
  } catch {
    // The browser may be on the PDS authorization page or a failed navigation.
  }

  return `url=${page.url()}\nstatus=${status}`;
}

async function waitForOAuthClientOutcome(
  page: any,
): Promise<"profile" | "failure"> {
  const profilePromise = page.locator("#profile").waitFor({
    state: "visible",
    timeout: 10000,
  }).then(() => "profile" as const).catch(() => "failure" as const);
  const failurePromise = (async () => {
    const deadline = Date.now() + 10000;
    while (Date.now() < deadline) {
      try {
        const status = await page.locator("#status").innerText({
          timeout: 500,
        });
        if (
          status.includes("Authorization failed") ||
          status.includes("Sign in failed")
        ) {
          return "failure" as const;
        }
      } catch {
        // Page may still be navigating between the PDS and client.
      }
      await page.waitForTimeout(250);
    }
    return "failure" as const;
  })();

  return await Promise.race([profilePromise, failurePromise]);
}

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("E2E OAuth2 Client Integration");
  result.start();

  const pds = new XrpcClient(PDS1);
  const luna = getCharacter("luna");

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
    (s) => `did=${s.did}`,
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
    (r) => `handle ${luna.handle} -> ${r.did}`,
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
      assert.isTrue(
        typeof pdsEndpoint === "string" && pdsEndpoint.length > 0,
        "PDS serviceEndpoint not found in DID doc",
      );
      return { pdsEndpoint };
    },
    (r) => `serviceEndpoint=${r.pdsEndpoint}`,
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
            "Origin": SERVICE_URLS.oauthClient,
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
            "Origin": SERVICE_URLS.oauthClient,
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

  const configuredClientUrl = SERVICE_URLS.oauthClient.replace(/\/$/, "");
  let clientUrl = configuredClientUrl;
  try {
    const resolvedClientUrl = await resolveOAuthClientUrl(configuredClientUrl);
    if (!resolvedClientUrl) {
      result.stepSkipped(
        "OAuth Client availability",
        "client-metadata.json was not available; skipping browser automation",
      );
      result.finish();
      return result;
    }
    clientUrl = resolvedClientUrl;
  } catch (e: any) {
    result.stepSkipped(
      "OAuth Client availability",
      `OAuth client not reachable: ${e.message}; skipping browser automation`,
    );
    result.finish();
    return result;
  }

  let browser: Browser | null = null;
  try {
    browser = await chromium.launch({ headless: true });
    const context = await browser.newContext();
    const page = await context.newPage();
    const publicNetworkLeaks = attachPublicNetworkLeakGuard(page);
    const consoleMessages: string[] = [];
    const pageErrors: string[] = [];
    const failedRequests: string[] = [];

    page.on("console", (message) => {
      consoleMessages.push(`[${message.type()}] ${message.text()}`);
    });
    page.on("pageerror", (error) => {
      pageErrors.push(error.message);
    });
    page.on("requestfailed", (request) => {
      failedRequests.push(
        `${request.method()} ${request.url()} :: ${
          request.failure()?.errorText ?? "unknown"
        }`,
      );
    });

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
      result.finish();
      return result;
    }

    await page.fill("#auth-handle", luna.handle);
    await page.fill("#auth-password", luna.password);
    await page.click("#auth-signin-btn");

    const consentButton = page.locator(
      "#auth-step-consent:not(.hidden) button[type='submit'].btn-primary",
    );
    await consentButton.waitFor({ state: "visible", timeout: 10000 });
    const sessionTokenInput = page.locator(
      "#auth-step-consent input[name='session_token']",
    );
    const sessionTokenDeadline = Date.now() + 10000;
    let consentSessionToken = "";
    while (Date.now() < sessionTokenDeadline) {
      consentSessionToken = await sessionTokenInput.inputValue().catch(() =>
        ""
      );
      if (consentSessionToken.length > 0) break;
      await page.waitForTimeout(100);
    }
    if (!consentSessionToken) {
      throw new Error("Consent session token was not populated after sign-in");
    }
    result.stepPassed("PDS Sign-in successful");

    await consentButton.click();
    result.stepPassed("Consent granted");

    const profileResult = await waitForOAuthClientOutcome(page);
    if (profileResult !== "profile") {
      const screenshotPath = `/tmp/oauth_failure_${Date.now()}.png`;
      await page.screenshot({ path: screenshotPath, fullPage: true });
      throw new Error(
        [
          "OAuth callback did not display a profile.",
          await pageState(page),
          `screenshot=${screenshotPath}`,
          `pageErrors:\n${recent(pageErrors)}`,
          `failedRequests:\n${recent(failedRequests)}`,
          `console:\n${recent(consoleMessages, 20)}`,
        ].join("\n"),
      );
    }
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
  } catch (e: any) {
    result.stepFailed("Browser automation", e.message || String(e));
  } finally {
    if (browser) {
      await browser.close().catch(() => {});
    }
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
