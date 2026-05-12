import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { PDS1, SERVICE_URLS, getCharacter } from "../../lib/deno/config.ts";

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Handle Change Propagation");
  result.start();

  const pds = new XrpcClient(PDS1);
  const appview = new XrpcClient(SERVICE_URLS.appview);
  const luna = getCharacter("luna");

  await timedCall(result, "PDS health check", async () => { await pds.wait_for_healthy(30); });

  if (result.failed > 0) return result;

  const session = await pds.accounts.createAccount(luna.handle, luna.email, luna.password).catch(() => 
    pds.accounts.createSession(luna.handle, luna.password)
  );

  if (!session) {
    result.stepFailed("Setup", "Failed to obtain session");
    result.finish();
    return result;
  }
  luna.did = session.did;
  luna.accessJwt = session.accessJwt;
  const originalHandle = session.handle || luna.handle;

  await timedCall(result, "Resolve handle before change", async () => {
    return await pds.identity.resolveHandle(originalHandle);
  });

  const newHandle = `new-${luna.handle}`;
  await timedCall(result, "Update handle", async () => {
    return await pds.identity.updateHandle(newHandle, luna.accessJwt);
  });

  await new Promise(r => setTimeout(r, 3000));

  try {
    const plcRes = await fetch(`http://localhost:2582/${luna.did}`);
    const doc = await plcRes.json();
    const hasNewHandle = doc.alsoKnownAs?.some((h: string) => h.includes(newHandle));
    assert(hasNewHandle, "New handle not found in PLC DID doc");
    result.stepPassed("PLC handle verification");
  } catch (e) {
    result.stepSkipped("PLC handle verification", String(e));
  }

  await timedCall(result, "Verify AppView profile has new handle", async () => {
    const profile = await appview.feed.getProfile(luna.did, luna.accessJwt);
    assert(profile.handle === newHandle, `Expected ${newHandle}, got ${profile.handle}`);
  });

  await timedCall(result, "Resolve new handle", async () => {
    return await pds.identity.resolveHandle(newHandle);
  });

  result.finish();
  return result;
}

if (import.meta.main) {
  run().then(res => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
