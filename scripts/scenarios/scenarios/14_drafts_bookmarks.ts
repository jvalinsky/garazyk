import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { PDS1, getCharacter } from "../../lib/deno/config.ts";

function now() {
  return new Date().toISOString();
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Drafts & Bookmarks Workflow");
  result.start();

  const client = new XrpcClient(PDS1);

  await timedCall(result, "Server health check", async () => {
    await client.wait_for_healthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const charNames = ["luna", "marcus", "quiet"];
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
      try {
        await client.records.createRecord(
          char.did, "app.bsky.actor.profile",
          { $type: "app.bsky.actor.profile", displayName: char.name },
          char.accessJwt
        );
        result.stepPassed(`Set profile: ${char.name}`);
      } catch (e) {
        if (e instanceof XrpcError && e.status === 404) {
          result.stepSkipped(`Set profile: ${char.name}`, "Endpoint not found");
        } else {
          throw e;
        }
      }
    }
  }

  const luna = getCharacter("luna");
  const marcus = getCharacter("marcus");
  const quiet = getCharacter("quiet");

  if (!luna.did || !marcus.did || !quiet.did) {
    result.stepFailed("Setup", "Not enough accounts created");
    result.finish();
    return result;
  }

  const lunaDraftContent = {
    text: "Just captured the most stunning image of the Orion Nebula!",
    facets: [], tags: [],
  };

  let lunaDraftId: string | null = null;
  try {
    const resp = await timedCall(
      result, "Luna creates draft",
      async () => {
        return await client.drafts.createDraft(lunaDraftContent, luna.accessJwt);
      },
      (r) => `id=${r.id || r.draft?.id || ""}`
    );
    lunaDraftId = resp?.id || resp?.draft?.id || null;
  } catch (e) {
    if (e instanceof XrpcError && e.status === 404) {
      result.stepSkipped("Luna creates draft", "Endpoint not found");
    } else {
      throw e;
    }
  }

  if (lunaDraftId) {
    await timedCall(
      result, "Luna lists drafts",
      async () => {
        return await client.drafts.getDrafts(luna.accessJwt);
      }
    );

    const updatedContent = {
      ...lunaDraftContent,
      text: "Just captured the most stunning image of the Orion Nebula! #astronomy",
      tags: ["astronomy", "nebula"],
    };

    await timedCall(
      result, "Luna edits draft",
      async () => {
        return await client.drafts.updateDraft(lunaDraftId!, updatedContent, luna.accessJwt);
      },
      () => `id=${lunaDraftId}`
    );

    let lunaPostUri: string | null = null;
    const post = await timedCall(
      result, "Luna publishes post from draft",
      async () => {
        return await client.records.createRecord(
          luna.did, "app.bsky.feed.post",
          {
            $type: "app.bsky.feed.post",
            text: updatedContent.text,
            createdAt: now()
          },
          luna.accessJwt
        );
      },
      (r) => `uri=${r.uri}`
    );
    lunaPostUri = post?.uri || null;

    await timedCall(
      result, "Luna deletes draft (cleanup)",
      async () => {
        return await client.drafts.deleteDraft(lunaDraftId!, luna.accessJwt);
      },
      () => `id=${lunaDraftId}`
    );

    await timedCall(
      result, "Luna verifies 0 drafts",
      async () => {
        return await client.drafts.getDrafts(luna.accessJwt);
      }
    );

    if (lunaPostUri) {
      await timedCall(
        result, "Quiet bookmarks Luna's post",
        async () => {
          return await client.raw.xrpcPost("app.bsky.bookmark.createBookmark", { uri: lunaPostUri }, quiet.accessJwt);
        },
        () => `uri=${lunaPostUri}`
      );

      await timedCall(
        result, "Quiet lists bookmarks",
        async () => {
          return await client.raw.xrpcGet("app.bsky.bookmark.getBookmarks", { limit: 50 }, quiet.accessJwt);
        }
      );

      await timedCall(
        result, "Quiet deletes bookmark",
        async () => {
          return await client.raw.xrpcPost("app.bsky.bookmark.deleteBookmark", { uri: lunaPostUri }, quiet.accessJwt);
        },
        () => `uri=${lunaPostUri}`
      );
    }
  }

  const marcusDraftIds: string[] = [];
  const marcusDrafts = ["Building a new ATProto feed generator", "Thoughts on CBOR encoding"];
  for (let i = 0; i < marcusDrafts.length; i++) {
    const resp = await timedCall(
      result, `Marcus creates draft ${i + 1}`,
      async () => {
        return await client.drafts.createDraft({ text: marcusDrafts[i] }, marcus.accessJwt);
      },
      (r) => `id=${r.id || r.draft?.id || ""}`
    );
    if (resp?.id || resp?.draft?.id) {
      marcusDraftIds.push(resp.id || resp.draft.id);
    }
  }

  if (marcusDraftIds.length > 0) {
    await timedCall(
      result, "Marcus deletes draft",
      async () => {
        return await client.drafts.deleteDraft(marcusDraftIds[0], marcus.accessJwt);
      },
      () => `id=${marcusDraftIds[0]}`
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
