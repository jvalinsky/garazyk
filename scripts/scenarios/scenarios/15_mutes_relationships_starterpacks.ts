/**
 * @module scenarios/15_mutes_relationships_starterpacks
 *
 * Scenario: Mutes, Relationships, and Starter Packs Management
 *
 * Behavior:
 * - Creates multiple user accounts and profiles.
 * - Establishes follow relationships between users.
 * - Tests mute/unmute functionality for actors.
 * - Verifies relationship lookups.
 * - Tests creating and retrieving lists and starter packs.
 *
 * Expectations:
 * - Relationships and mutes are tracked correctly.
 * - Starter packs can be created and retrieved by URI.
 * - User interactions adhere to the expected graph API behavior.
 */

import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { getActor, PDS1 } from "../../lib/deno/config.ts";

function now() {
  return new Date().toISOString();
}

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Mutes, Relationships & Starter Packs");
  result.start();

  const client = new XrpcClient(PDS1);

  await timedCall(result, "Server health check", async () => {
    await client.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const charNames = ["luna", "marcus", "rosa", "troll", "quiet", "admin"];
  for (const name of charNames) {
    const char = getActor(name);
    const session = await timedCall(
      result,
      `Create account: ${char.name}`,
      async () => {
        return await client.accounts.createAccount(char.handle, char.email, char.password);
      },
      (s) => `did=${s.did}`,
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  const active = charNames.filter((n) => getActor(n).did);
  for (const name of active) {
    const char = getActor(name);
    try {
      await client.records.createRecord(
        char.did,
        "app.bsky.actor.profile",
        { $type: "app.bsky.actor.profile", displayName: char.name, description: char.persona },
        char.accessJwt,
      );
    } catch (e) {
      if (!(e instanceof XrpcError && e.status === 404)) throw e;
    }
  }

  const luna = getActor("luna");
  const marcus = getActor("marcus");
  const rosa = getActor("rosa");
  const troll = getActor("troll");
  const quiet = getActor("quiet");

  // Establish follows
  for (const [f, t] of [["luna", "marcus"], ["marcus", "luna"]] as const) {
    const ff = getActor(f);
    const tt = getActor(t);
    if (ff.did && tt.did) {
      await timedCall(
        result,
        `${ff.name} follows ${tt.name}`,
        async () => {
          return await client.records.createRecord(
            ff.did,
            "app.bsky.graph.follow",
            { $type: "app.bsky.graph.follow", subject: tt.did, createdAt: now() },
            ff.accessJwt,
          );
        },
        (r) => `uri=${r.uri}`,
      );
    }
  }

  await new Promise((r) => setTimeout(r, 1000));

  if (quiet.did && troll.did) {
    await timedCall(
      result,
      "Quiet mutes Trollface",
      async () => {
        return await client.graph.muteActor(troll.did, quiet.accessJwt);
      },
    );

    await timedCall(
      result,
      "Quiet checks mutes list",
      async () => {
        return await client.graph.getMutes(quiet.accessJwt);
      },
      (r) => `count=${r.mutes?.length || 0}`,
    );

    await timedCall(
      result,
      "Quiet unmutes Trollface",
      async () => {
        return await client.graph.unmuteActor(troll.did, quiet.accessJwt);
      },
    );

    await timedCall(
      result,
      "Quiet verifies unmute",
      async () => {
        return await client.graph.getMutes(quiet.accessJwt);
      },
      (r) => `count=${r.mutes?.length || 0}`,
    );
  }

  if (luna.did && marcus.did) {
    await timedCall(
      result,
      "Luna→Marcus relationship",
      async () => {
        return await client.graph.getRelationships(luna.did, [marcus.did], luna.accessJwt);
      },
      (r) => `count=${r.relationships?.length || 0}`,
    );
  }

  let rosaSpUri: string | null = null;
  if (rosa.did && luna.did && marcus.did) {
    const listRec = await timedCall(
      result,
      "Rosa creates list for starter pack",
      async () => {
        return await client.records.createRecord(
          rosa.did,
          "app.bsky.graph.list",
          {
            $type: "app.bsky.graph.list",
            name: "Foodie Friends",
            purpose: "app.bsky.graph.defs#curatelist",
            createdAt: now(),
          },
          rosa.accessJwt,
        );
      },
      (r) => `uri=${r.uri}`,
    );

    if (listRec) {
      const sp = await timedCall(
        result,
        "Rosa creates starter pack",
        async () => {
          return await client.records.createRecord(
            rosa.did,
            "app.bsky.graph.starterpack",
            {
              $type: "app.bsky.graph.starterpack",
              name: "Foodie Friends",
              list: listRec.uri,
              createdAt: now(),
            },
            rosa.accessJwt,
          );
        },
        (r) => `uri=${r.uri}`,
      );
      rosaSpUri = sp?.uri || null;
    }
  }

  if (rosa.did) {
    await timedCall(
      result,
      "Wait for starter pack in AppView",
      async () => {
        const deadline = Date.now() + 30_000;
        while (Date.now() < deadline) {
          const r = await client.graph.getActorStarterPacks(rosa.did, { token: rosa.accessJwt });
          if (r.starterPacks && r.starterPacks.length > 0) return r;
          await new Promise((r) => setTimeout(r, 1000));
        }
        throw new Error("Timed out waiting for starter pack to appear in AppView");
      },
      (r) => `count=${r.starterPacks?.length || 0}`,
    );
  }

  if (rosaSpUri) {
    await timedCall(
      result,
      "Get starter pack by URI",
      async () => {
        return await client.graph.getStarterPack(rosaSpUri!, rosa.accessJwt);
      },
      (r) => `name=${r.starterPack?.name || ""}`,
    );

    await timedCall(
      result,
      "Get starter packs by URIs",
      async () => {
        return await client.graph.getStarterPacks([rosaSpUri!], rosa.accessJwt);
      },
      (r) => `count=${r.starterPacks?.length || 0}`,
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
