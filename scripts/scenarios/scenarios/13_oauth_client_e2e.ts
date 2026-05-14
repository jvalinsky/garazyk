import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { PDS1, getCharacter } from "../../lib/deno/config.ts";
import { chromium } from "npm:playwright";
import { join } from "@std/path";

const PDS_URL = "http://127.0.0.1:2583";
const PLC_URL = "http://127.0.0.1:2582";

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("E2E OAuth2 Client Integration");
  result.start();

  const pds = new XrpcClient(PDS1);
  const luna = getCharacter("luna");

  const session = await timedCall(
    result, "Create account",
    async () => {
      return await pds.accounts.createAccount(luna.handle, luna.email, luna.password);
    },
    (s) => `did=${s.did}`
  );

  if (!session) {
    result.finish();
    return result;
  }
  luna.did = session.did;

  await timedCall(
    result, "Verify account resolution",
    async () => {
      const res = await pds.identity.resolveHandle(luna.handle);
      assert.isTrue(res.did === luna.did, `DID mismatch: expected ${luna.did}, got ${res.did}`);
      return res;
    },
    (r) => `handle ${luna.handle} -> ${r.did}`
  );

  await timedCall(
    result, "DID document inspection",
    async () => {
      const res = await fetch(`${PLC_URL}/${luna.did}`);
      const didDoc = await res.json();
      const services = didDoc.service || [];
      const pdsEndpoint = services.find((s: any) => s.id === "#atproto_pds" || s.id.includes("atproto_pds"))?.serviceEndpoint;
      assert.isTrue(pdsEndpoint, "PDS serviceEndpoint not found in DID doc");
      return { pdsEndpoint };
    },
    (r) => `serviceEndpoint=${r.pdsEndpoint}`
  );

  await timedCall(
    result, "Protected resource metadata",
    async () => {
      const res = await fetch(`${PDS_URL}/.well-known/oauth-protected-resource`, {
        headers: { "Accept": "application/json", "Origin": "http://127.0.0.1:8080" }
      });
      const body = await res.json();
      assert.isTrue(res.status === 200, `status=${res.status}`);
      assert.isTrue(body.resource === "http://127.0.0.1:2583", `unexpected resource: ${body.resource}`);
    }
  );

  await timedCall(
    result, "Authorization server metadata",
    async () => {
      const res = await fetch(`${PDS_URL}/.well-known/oauth-authorization-server`, {
        headers: { "Accept": "application/json", "Origin": "http://127.0.0.1:8080" }
      });
      const body = await res.json();
      assert.isTrue(res.status === 200, `status=${res.status}`);
      assert.isTrue(body.issuer === "http://127.0.0.1:2583", `unexpected issuer: ${body.issuer}`);
    }
  );

  const clientUrl = "http://localhost:8080";
  try {
    const res = await fetch(`${clientUrl}/client-metadata.json`);
    if (res.status !== 200) {
      result.stepSkipped("OAuth Client availability", `Status ${res.status}; skipping browser automation`);
      result.finish();
      return result;
    }
  } catch (e: any) {
    result.stepSkipped("OAuth Client availability", `OAuth client not reachable: ${e.message}; skipping browser automation`);
    result.finish();
    return result;
  }

  try {
    const browser = await chromium.launch({ headless: true });
    const runId = Deno.env.get("ATPROTO_SCENARIO_RUN_ID") || "default";
    const context = await browser.newContext();
    const page = await context.newPage();

    await page.goto("http://127.0.0.1:8080");
    result.stepPassed("Step 1: Navigate to client app");

    await page.fill("#handle", luna.handle);
    await page.click("#login-btn");
    result.stepPassed("Step 2: Initiate login flow & Resolve Handle");

    try {
      await page.waitForSelector("#auth-handle", { timeout: 30000 });
      result.stepPassed("Step 3: Redirected to PDS authorize page (PAR completed)");
    } catch (e) {
      const screenshotPath = `/tmp/oauth_failure_${Date.now()}.png`;
      await page.screenshot({ path: screenshotPath });
      result.stepFailed("Redirected to PDS authorize page", `Timeout waiting for #auth-handle. Screenshot: ${screenshotPath}`);
      await browser.close();
      result.finish();
      return result;
    }

    await page.fill("#auth-handle", luna.handle);
    await page.fill("#auth-password", luna.password);
    await page.click("#auth-signin-btn");
    result.stepPassed("PDS Sign-in successful");

    await page.waitForSelector("button[type='submit'].btn-primary", { timeout: 5000 });
    await page.click("button[type='submit'].btn-primary");
    result.stepPassed("Consent granted");

    await page.waitForSelector("#profile", { timeout: 10000 });
    const displayName = await page.innerText("#display-name");
    assert.isTrue(displayName.includes("did:plc:"), `Unexpected display name: ${displayName}`);
    result.stepPassed("Profile displayed", `Logged in as ${displayName}`);

    await browser.close();
  } catch (e: any) {
    result.stepFailed("Browser automation", e.message || String(e));
  }

  result.finish();
  return result;
}

if (import.meta.main) {
  run().then(res => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
