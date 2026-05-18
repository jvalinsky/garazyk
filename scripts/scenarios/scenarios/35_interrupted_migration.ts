/**
 * @module scenarios/35_interrupted_migration
 *
 * Scenario: Interrupted Account Migration
 *
 * Behavior:
 * - Creates an account on PDS1 and uploads a blob.
 * - Requests a PLC operation signature from PDS1.
 * - Initiates an interrupted account migration path.
 * - Verifies that PDS1 retains authority over the identity.
 *
 * Expectations:
 * - PDS1 remains the authoritative PDS for the identity following the failed migration attempt.
 */

import type { ScenarioContext } from "@garazyk/hamownia/config";
import { createScenarioContext } from "@garazyk/hamownia/scenario-context";
import { ScenarioResult, timedCall } from "@garazyk/hamownia";
export { ScenarioResult, StepResult, StepStatus } from "@garazyk/hamownia";
export type { ScenarioReport } from "@garazyk/hamownia";
import { assert } from "@garazyk/hamownia";
import { XrpcClient } from "@garazyk/gruszka";
function now() {
  return new Date().toISOString();
}

const MINIMAL_PNG = new Uint8Array([
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x02,
  0x00,
  0x00,
  0x00,
  0x90,
  0x77,
  0x53,
  0xde,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x44,
  0x41,
  0x54,
  0x08,
  0xd7,
  0x63,
  0xfc,
  0xff,
  0x9f,
  0xa1,
  0x1e,
  0x00,
  0x07,
  0x82,
  0x02,
  0x3c,
  0x3f,
  0xc8,
  0x48,
  0xef,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4e,
  0x44,
  0xae,
  0x42,
  0x60,
  0x82,
]);

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(ctx: ScenarioContext): Promise<ScenarioResult> {
  const result = new ScenarioResult("Interrupted Account Migration");
  result.start();

  const pds1 = new XrpcClient(ctx.pds1);
  const pds2 = new XrpcClient(ctx.pds2);
  const luna = ctx.getCharacter("luna");

  for (const [name, client] of [["PDS1", pds1], ["PDS2", pds2]] as const) {
    await timedCall(result, `${name} health check`, async () => {
      await client.waitForHealthy(30);
    });
  }

  if (result.failed > 0) return result;

  const session = await timedCall(
    result,
    "Create account on PDS1",
    async () => {
      return await pds1.accounts.createAccount(
        luna.handle,
        luna.email,
        luna.password,
      );
    },
  );

  if (!session) {
    result.finish();
    return result;
  }
  luna.did = session.did;
  luna.accessJwt = session.accessJwt;

  const blobResp = await timedCall(result, "Upload blob to PDS1", async () => {
    return await pds1.blobs.uploadBlob(
      MINIMAL_PNG,
      "image/png",
      luna.accessJwt,
    );
  });
  const blobRef = blobResp?.blob;

  if (blobRef) {
    await timedCall(result, "Create post with blob on PDS1", async () => {
      return await pds1.records.createRecord(luna.did, "app.bsky.feed.post", {
        $type: "app.bsky.feed.post",
        text: "Migration test with blob",
        embed: {
          $type: "app.bsky.embed.images",
          images: [{ image: blobRef, alt: "test" }],
        },
        createdAt: now(),
      }, luna.accessJwt);
    });
  }

  await timedCall(result, "Reserve signing key on PDS2", async () => {
    return await pds2.raw.xrpcPost("com.atproto.server.reserveSigningKey", {});
  });

  await timedCall(
    result,
    "Request PLC operation signature from PDS1",
    async () => {
      return await pds1.raw.xrpcPost(
        "com.atproto.identity.requestPlcOperationSignature",
        {},
        luna.accessJwt,
      );
    },
  );

  await timedCall(
    result,
    "Initiate failed migration",
    async () => {
      await pds2.raw.xrpcPost("com.atproto.server.createAccount", {
        handle: luna.handle,
        email: luna.email,
        password: luna.password,
        did: luna.did,
        plcOp: { invalid: "op" },
        recoveryKey:
          "did:key:zQ3shokFTS3LRDLz6KxreZisUatvXid88vGpkid5X2BebkX2V",
      });
    },
    undefined,
    true,
  );

  await timedCall(result, "Verify PDS1 remains authority", async () => {
    return await pds1.raw.xrpcGet("com.atproto.sync.getHead", {
      did: luna.did,
    });
  });

  try {
    const plcRes = await fetch(`${ctx.serviceUrls.plc}/${luna.did}`);
    const doc = await plcRes.json();
    const pdsEndpoint = doc.service?.find((s: any) => s.id === "#atproto_pds")
      ?.serviceEndpoint;
    if (pdsEndpoint === ctx.pds1) {
      result.stepPassed("PLC audit: Still points to PDS1");
    } else {
      result.stepFailed(
        "PLC audit: Points to wrong PDS",
        `expected=${ctx.pds1}, got=${pdsEndpoint}`,
      );
    }
  } catch (e) {
    result.stepFailed("PLC audit", String(e));
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
