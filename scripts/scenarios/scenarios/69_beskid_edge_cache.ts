/**
 * @module scenarios/69_beskid_edge_cache
 *
 * Scenario: Verifies the edge caching, bi-directional handle verification, service resolution,
 * and response hydration behaviors of the Beskid edge cache.
 */

import { getCharacter, PDS1, SERVICE_URLS } from "../../lib/deno/config.ts";
import { ScenarioResult } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { assert } from "jsr:@std/assert@0.224.0";
import { timedCall } from "../../lib/deno/runner.ts";

const BESKID_URL = Deno.env.get("BESKID_URL") ||
  SERVICE_URLS.beskid ||
  "http://localhost:8085";

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Beskid Edge Cache");
  result.start();

  const pds = new XrpcClient(PDS1);
  const beskid = new XrpcClient(BESKID_URL);
  const luna = getCharacter("luna");
  const marcus = getCharacter("marcus");

  // 1. Service Health Checks
  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });
  await timedCall(result, "Beskid health check", async () => {
    await beskid.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  // 2. Setup/Create Accounts on PDS
  for (const character of [luna, marcus]) {
    const session = await timedCall(result, `Create account: ${character.name}`, async () => {
      return await pds.accounts.createAccount(
        character.handle,
        character.email,
        character.password,
      ).catch(() => pds.accounts.createSession(character.handle, character.password));
    }, (session) => `did=${session.did}`);
    if (session) {
      character.did = session.did;
      character.accessJwt = session.accessJwt;
    }
  }

  if (!luna.did || !marcus.did) {
    result.stepFailed("Account setup", "missing DID after account creation");
    result.finish();
    return result;
  }

  // 3. Test Bi-directional Handle Resolution
  await timedCall(result, "Resolve handle via Beskid", async () => {
    const res = await beskid.raw.xrpcGet("com.atproto.identity.resolveHandle", {
      handle: luna.handle,
    });
    assert(res.did === luna.did, "DID should match");
  });

  // 4. Test Compact MiniDoc Resolution
  await timedCall(result, "Resolve MiniDoc via Beskid", async () => {
    const res = await beskid.raw.xrpcGet("com.bad-example.identity.resolveMiniDoc", {
      identifier: luna.handle,
    });
    assert(res.did === luna.did, "DID should match");
    assert(res.handle === luna.handle, "Handle should match");
    assert(res.pds.length > 0, "PDS endpoint should not be empty");
    assert(res.signing_key.length > 0, "Signing key should not be empty");
  });

  // 5. Create Target Post on PDS
  let postUri = "";
  let postCid = "";
  const postText = `Beskid edge cache test - ${Date.now()}`;
  await timedCall(result, "Create cache-target post on PDS", async () => {
    const record = {
      $type: "app.bsky.feed.post",
      text: postText,
      createdAt: new Date().toISOString(),
    };
    const res = await pds.records.createRecord(luna.did!, "app.bsky.feed.post", record, luna.accessJwt!);
    postUri = res.uri;
    postCid = res.cid;
    assert(postUri.length > 0, "Post URI should be valid");
  });

  // 6. Test Read-Through Cache Lookup (Cache Miss + Cache Load)
  await timedCall(result, "Read-through record cache lookup via Beskid", async () => {
    const res = await beskid.raw.xrpcGet("com.bad-example.repo.getUriRecord", {
      at_uri: postUri,
    });
    assert(res.uri === postUri, "URI should match");
    assert(res.cid === postCid, "CID should match");
    assert(res.value.text === postText, "Value text should match");
  });

  // 7. Verify Cache Persistence (TTL protection)
  // Delete record from the primary PDS
  await timedCall(result, "Delete post from primary PDS", async () => {
    const uriParts = postUri.split("/");
    const rkey = uriParts[uriParts.length - 1];
    await pds.records.deleteRecord(luna.did!, "app.bsky.feed.post", rkey, luna.accessJwt!);
  });

  // Request the deleted record from Beskid: it should STILL serve the cached record
  await timedCall(result, "Query Beskid for deleted post (cache hit on deleted record)", async () => {
    const res = await beskid.raw.xrpcGet("com.bad-example.repo.getUriRecord", {
      at_uri: postUri,
    });
    assert(res.uri === postUri, "URI should match");
    assert(res.value.text === postText, "Value text should match");
  });

  // 8. Test Response Hydration (hydrateQueryResponse)
  await timedCall(result, "Verify dynamic response hydration", async () => {
    // First create a profile for Marcus so the proxy query doesn't 404
    await pds.records.createRecord(marcus.did!, "app.bsky.actor.profile", {
      $type: "app.bsky.actor.profile",
      displayName: "Marcus",
      description: "Code test",
    }, marcus.accessJwt!, { rkey: "self" });

    const payload = {
      xrpc: "com.atproto.repo.getRecord",
      atproto_proxy: PDS1,
      params: {
        repo: marcus.did,
        collection: "app.bsky.actor.profile",
        rkey: "self"
      },
      hydration_sources: [
        {
          path: "value.avatar",
          shape: "strong-ref"
        }
      ]
    };
    
    // We send the hydration post query to Beskid
    const res = await beskid.raw.xrpcPost("com.bad-example.proxy.hydrateQueryResponse", payload);
    assert(res.output !== undefined, "Output envelope must contain upstream response");
    assert(res.records !== undefined, "Records dictionary must be present");
  });

  result.recordArtifact("beskid_caching", {
    pds_url: PDS1,
    beskid_url: BESKID_URL,
    test_uri: postUri,
    test_cid: postCid
  });

  result.finish();
  return result;
}

if (import.meta.main) {
  const result = await run();
  console.log(result.summary());
  Deno.exit(result.ok ? 0 : 1);
}
