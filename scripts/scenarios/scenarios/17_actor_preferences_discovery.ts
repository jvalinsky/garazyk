/**
 * @module scenarios/17_actor_preferences_discovery
 *
 * Scenario: Actor Preferences & Discovery
 *
 * Behavior:
 * - Create multiple test accounts.
 * - Set and get actor preferences.
 * - Create posts, perform likes and reposts.
 * - Test typeahead actor search and get actor suggestions.
 *
 * Expectations:
 * - Preferences are saved and retrieved correctly.
 * - Discovery features (search, suggestions, feed lookups) return expected actor and feed data.
 */

import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { PDS1, getCharacter } from "../../lib/deno/config.ts";

function now() {
  return new Date().toISOString();
}

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Actor Preferences & Discovery");
  result.start();

  const client = new XrpcClient(PDS1);

  await timedCall(result, "Server health check", async () => {
    await client.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const charNames = ["luna", "marcus", "rosa", "volt"];
  for (const name of charNames) {
    const char = getCharacter(name);
    const session = await timedCall(
      result, `Create account: ${char.name}`,
      async () => {
        return await client.accounts.createAccount(char.handle, char.email, char.password);
      },
      (s) => `did=${s.did}`
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  const active = charNames.filter(n => getCharacter(n).did);
  for (const name of active) {
    const char = getCharacter(name);
    try {
      await client.records.createRecord(
        char.did, "app.bsky.actor.profile",
        { $type: "app.bsky.actor.profile", displayName: char.name, description: char.persona },
        char.accessJwt
      );
    } catch (e) {
      if (!(e instanceof XrpcError && e.status === 404)) throw e;
    }
  }

  const luna = getCharacter("luna");
  const marcus = getCharacter("marcus");

  if (marcus.accessJwt) {
    await timedCall(
      result, "Marcus sets preferences",
      async () => {
        return await client.search.putPreferences(
          [{ $type: "app.bsky.actor.defs#contentLabelPref", label: "nsfw", visibility: "show" }],
          marcus.accessJwt
        );
      }
    );

    await timedCall(
      result, "Marcus gets preferences",
      async () => {
        return await client.search.getPreferences(marcus.accessJwt);
      },
      (r) => `count=${r.preferences?.length || 0}`
    );
  }

  const lunaPosts: any[] = [];
  const lunaTexts = [
    "The Orion Nebula through my telescope tonight!",
    "Saturn's rings are visible, come take a look!",
    "New research paper on exoplanet atmospheres",
  ];
  for (const text of lunaTexts) {
    if (luna.did && luna.accessJwt) {
      const rec = await timedCall(
        result, "Luna posts",
        async () => {
          return await client.records.createRecord(
            luna.did, "app.bsky.feed.post",
            { $type: "app.bsky.feed.post", text, createdAt: now() },
            luna.accessJwt
          );
        },
        (r) => `uri=${r.uri}`
      );
      if (rec) lunaPosts.push(rec);
    }
  }

  const marcusPosts: any[] = [];
  const marcusTexts = [
    "Just deployed a new microservice for ATProto relay",
    "Open source contribution: fixed a race condition in the firehose",
  ];
  for (const text of marcusTexts) {
    if (marcus.did && marcus.accessJwt) {
      const rec = await timedCall(
        result, "Marcus posts",
        async () => {
          return await client.records.createRecord(
            marcus.did, "app.bsky.feed.post",
            { $type: "app.bsky.feed.post", text, createdAt: now() },
            marcus.accessJwt
          );
        },
        (r) => `uri=${r.uri}`
      );
      if (rec) marcusPosts.push(rec);
    }
  }

  if (luna.accessJwt) {
    for (const postRec of marcusPosts) {
      await timedCall(
        result, "Luna likes Marcus's post",
        async () => {
          return await client.records.createRecord(
            luna.did, "app.bsky.feed.like",
            { $type: "app.bsky.feed.like", subject: { uri: postRec.uri, cid: postRec.cid }, createdAt: now() },
            luna.accessJwt
          );
        }
      );
    }
  }

  if (marcus.accessJwt) {
    for (const postRec of lunaPosts) {
      await timedCall(
        result, "Marcus likes Luna's post",
        async () => {
          return await client.records.createRecord(
            marcus.did, "app.bsky.feed.like",
            { $type: "app.bsky.feed.like", subject: { uri: postRec.uri, cid: postRec.cid }, createdAt: now() },
            marcus.accessJwt
          );
        }
      );
    }
  }

  await new Promise(r => setTimeout(r, 2000));

  if (marcus.accessJwt) {
    for (const query of ["Lun", "Ro", "zzz nonexistent"]) {
      await timedCall(
        result, `Typeahead search '${query}'`,
        async () => {
          return await client.search.searchActorsTypeahead(query, { token: marcus.accessJwt });
        },
        (r) => `found=${r.actors?.length || 0}`
      );
    }
  }

  if (luna.did && marcus.accessJwt) {
    await timedCall(
      result, "Luna's liked posts",
      async () => {
        return await client.feed.getActorLikes(luna.did, { token: marcus.accessJwt });
      },
      (r) => `count=${(r.likes || r.feed)?.length || 0}`
    );
  }

  if (marcus.accessJwt && lunaPosts.length > 0) {
    await timedCall(
      result, "Marcus reposts Luna's post",
      async () => {
        return await client.records.createRecord(
          marcus.did, "app.bsky.feed.repost",
          { $type: "app.bsky.feed.repost", subject: { uri: lunaPosts[0].uri, cid: lunaPosts[0].cid }, createdAt: now() },
          marcus.accessJwt
        );
      }
    );

    await new Promise(r => setTimeout(r, 1000));

    await timedCall(
      result, "Get reposted by",
      async () => {
        return await client.feed.getRepostedBy(lunaPosts[0].uri, { token: marcus.accessJwt });
      },
      (r) => `count=${r.repostedBy?.length || 0}`
    );
  }

  if (marcus.accessJwt) {
    await timedCall(
      result, "Get actor suggestions",
      async () => {
        return await client.search.getSuggestions(marcus.accessJwt);
      },
      (r) => `count=${r.actors?.length || 0}`
    );
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
