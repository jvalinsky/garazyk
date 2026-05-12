import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { PDS1, getCharacter } from "../../lib/deno/config.ts";

function now() {
  return new Date().toISOString();
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Unspecced Search & Discovery");
  result.start();

  const client = new XrpcClient(PDS1);

  await timedCall(result, "Server health check", async () => {
    await client.wait_for_healthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const charNames = ["luna", "marcus", "rosa"];
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
  const rosa = getCharacter("rosa");

  const postData = [
    {
      name: "luna",
      texts: [
        "The Orion Nebula is absolutely stunning tonight! #astrophotography",
        "Just published my deep space photography guide #astronomy",
      ]
    },
    {
      name: "marcus",
      texts: [
        "ATProto is the future of decentralized social networking",
        "Building a firehose consumer in Go — streaming thousands of events per second",
      ]
    },
    {
      name: "rosa",
      texts: [
        "Homemade sourdough with roasted garlic and herbs #baking",
        "The best cacio e pepe recipe you will ever try #cooking",
      ]
    },
  ];

  for (const group of postData) {
    const char = getCharacter(group.name);
    if (char.did && char.accessJwt) {
      for (const text of group.texts) {
        await timedCall(
          result, `${char.name} posts`,
          async () => {
            return await client.records.createRecord(
              char.did, "app.bsky.feed.post",
              { $type: "app.bsky.feed.post", text, createdAt: now() },
              char.accessJwt
            );
          },
          (r) => `uri=${r.uri}`
        );
      }
    }
  }

  if (rosa.did && luna.did && marcus.did) {
    const listRec = await timedCall(
      result, "Rosa creates list for starter pack",
      async () => {
        return await client.records.createRecord(
          rosa.did, "app.bsky.graph.list",
          {
            $type: "app.bsky.graph.list",
            name: "Space & Code Enthusiasts",
            purpose: "app.bsky.graph.defs#curatelist",
            createdAt: now(),
          },
          rosa.accessJwt
        );
      },
      (r) => `uri=${r.uri}`
    );

    if (listRec) {
      await timedCall(
        result, "Rosa creates starter pack for search",
        async () => {
          return await client.records.createRecord(
            rosa.did, "app.bsky.graph.starterpack",
            {
              $type: "app.bsky.graph.starterpack",
              name: "Space & Code Enthusiasts",
              description: "Friends who love space and technology",
              list: listRec.uri,
              createdAt: now(),
            },
            rosa.accessJwt
          );
        },
        (r) => `uri=${r.uri}`
      );
    }
  }

  await new Promise(r => setTimeout(r, 2000));

  if (marcus.accessJwt) {
    try {
      for (const query of ["nebula", "Luna"]) {
        await timedCall(
          result, `Search actors skeleton '${query}'`,
          async () => {
            return await client.search.searchActorsSkeleton(query, { token: marcus.accessJwt });
          },
          (r) => `found=${r.actors?.length || 0}`
        );
      }

      for (const query of ["nebula", "sourdough", "zzz nonexistent content"]) {
        await timedCall(
          result, `Search posts skeleton '${query}'`,
          async () => {
            return await client.search.searchPostsSkeleton(query, { token: marcus.accessJwt });
          },
          (r) => `found=${r.posts?.length || 0}`
        );
      }

      await timedCall(
        result, "Search starter packs skeleton 'Space'",
        async () => {
          return await client.search.searchStarterPacksSkeleton("Space", { token: marcus.accessJwt });
        },
        (r) => `found=${r.starterPacks?.length || 0}`
      );
    } catch (e) {
      if (!(e instanceof XrpcError && e.status === 404)) throw e;
    }
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
