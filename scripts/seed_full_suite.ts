#!/usr/bin/env -S deno run -A
import { XrpcClient } from "@garazyk/gruszka";
import {
  chatGetConvoForMembers,
  chatSendMessage,
  createAccountOrLogin,
  createChatServiceContext,
  createRecordIdempotent,
  DEFAULT_ACCOUNTS,
  DEFAULT_POSTS_TEMPLATES,
  nowIso,
  waitForServer,
} from "@garazyk/gruszka/seed";

const pdsUrl = (Deno.env.get("PDS_URL") || "http://127.0.0.1:2583").replace(/\/$/, "");
const chatUrl = (Deno.env.get("CHAT_URL") || "http://127.0.0.1:2585").replace(/\/$/, "");

const conversations: Record<string, Array<[string, string]>> = {
  "alice.test|bob.test": [
    ["alice.test", "Hey Bob! Have you had a chance to look at the ATProto spec?"],
    ["bob.test", "Yeah. The XRPC layer is pretty elegant."],
    ["alice.test", "The lexicon system is the real winner for endpoint testing."],
    ["bob.test", "Agreed. Machine-readable schemas save a lot of guesswork."],
    ["alice.test", "I am seeding this chat so the admin UI has real scrollback."],
    ["bob.test", "Perfect. It makes the local demo feel much less empty."],
  ],
  "alice.test|carol.test": [
    ["alice.test", "Carol, how is the AppView indexing work going?"],
    ["carol.test", "Coming along. Denormalized record tables are doing the heavy lifting."],
    ["alice.test", "That should make actor profile and feed smoke tests easier."],
    ["carol.test", "Exactly. Backfill plus notifications is the interesting part."],
    ["alice.test", "This seeded thread should give both paths something visible."],
    ["carol.test", "Nice. I will check it after relay catch-up."],
  ],
  "bob.test|carol.test": [
    ["bob.test", "Quick chat-system question: are DMs stored in repos?"],
    ["carol.test", "No, chat is separate from the public repo and firehose."],
    ["bob.test", "That keeps private messages out of content-addressed sync."],
    ["carol.test", "Right. The service owns conversation state and membership."],
    ["bob.test", "Good material for endpoint smoke tests."],
    ["carol.test", "And good demo data for conversation list views."],
  ],
};

function capitalizedHandle(handle: string): string {
  const first = handle.split(".")[0] || handle;
  return first.charAt(0).toUpperCase() + first.slice(1);
}

async function main() {
  console.log("\n  ╔════════════════════════════════════════════════════╗");
  console.log("  ║     Seeding Full Suite Demo Data                  ║");
  console.log("  ╚════════════════════════════════════════════════════╝\n");
  console.log(`  [SETUP] Target PDS: ${pdsUrl}`);
  await waitForServer(pdsUrl);
  console.log("  [SETUP] PDS is healthy");
  console.log(`  [SETUP] Target Chat: ${chatUrl}`);
  await waitForServer(chatUrl);
  console.log("  [SETUP] Chat is healthy");

  const pds = new XrpcClient(pdsUrl);
  const chatContext = createChatServiceContext(
    pds,
    chatUrl,
    Deno.env.get("CHAT_SERVICE_DID") || undefined,
  );
  console.log(`  [SETUP] Chat DID: ${chatContext.serviceDid}`);
  const now = nowIso();
  const sessions: Record<string, any> = {};
  const dids: Record<string, string> = {};
  const seedErrors: string[] = [];

  console.log("  [ACCT] Creating accounts...");
  for (const account of DEFAULT_ACCOUNTS) {
    try {
      const session = await createAccountOrLogin(
        pds,
        account.handle,
        account.email,
        account.password,
      );
      sessions[account.handle] = session;
      dids[account.handle] = session.did;
      console.log(`  [ACCT]   ${account.handle}: ${session.did}`);
    } catch (exc) {
      console.error(`  [ACCT]   FAILED ${account.handle}: ${exc}`);
      Deno.exit(1);
    }
  }

  for (const account of DEFAULT_ACCOUNTS) {
    const handle = account.handle;
    const did = dids[handle];
    const jwt = sessions[handle]?.accessJwt;
    if (!did || !jwt) continue;

    console.log(`  [SEED] Seeding records for ${handle} (${did})...`);

    try {
      await createRecordIdempotent(pds, did, "app.bsky.actor.profile", {
        "$type": "app.bsky.actor.profile",
        displayName: capitalizedHandle(handle),
        description: `Demo account for ${handle}. Seeded for full suite demo.`,
        createdAt: now,
      }, jwt);
      console.log("  [SEED]   Profile created");
    } catch (exc) {
      console.log(`  [SEED]   Profile failed: ${exc}`);
      seedErrors.push(`profile ${handle}: ${exc}`);
    }

    const postUris: string[] = [];
    for (let i = 0; i < 5; i++) {
      try {
        const response = await createRecordIdempotent(pds, did, "app.bsky.feed.post", {
          "$type": "app.bsky.feed.post",
          text: DEFAULT_POSTS_TEMPLATES[i].replace("{handle}", handle.split(".")[0]),
          createdAt: now,
        }, jwt);
        if (response.uri) postUris.push(response.uri);
        console.log(`  [SEED]   Post #${i + 1}`);
      } catch (exc) {
        console.log(`  [SEED]   Post #${i + 1} failed: ${exc}`);
        seedErrors.push(`post ${handle} #${i + 1}: ${exc}`);
      }
    }

    const otherHandles = Object.keys(dids).filter((other) => other !== handle);
    for (const targetHandle of otherHandles.slice(0, 2)) {
      try {
        await createRecordIdempotent(pds, did, "app.bsky.graph.follow", {
          "$type": "app.bsky.graph.follow",
          subject: dids[targetHandle],
          createdAt: now,
        }, jwt);
        console.log(`  [SEED]   Followed ${targetHandle.split(".")[0]}`);
      } catch (exc) {
        console.log(`  [SEED]   Follow failed: ${exc}`);
        seedErrors.push(`follow ${handle}->${targetHandle}: ${exc}`);
      }
    }

    try {
      await createRecordIdempotent(pds, did, "app.bsky.graph.list", {
        "$type": "app.bsky.graph.list",
        name: `${handle.split(".")[0]}'s Follows`,
        purpose: "app.bsky.graph.defs#curatelist",
        description: "A list of interesting accounts",
        createdAt: now,
      }, jwt);
      console.log("  [SEED]   List created");
    } catch (exc) {
      console.log(`  [SEED]   List failed: ${exc}`);
      seedErrors.push(`list ${handle}: ${exc}`);
    }

    try {
      await createRecordIdempotent(pds, did, "app.bsky.feed.generator", {
        "$type": "app.bsky.feed.generator",
        did,
        displayName: `${handle.split(".")[0]}'s Feed`,
        description: "A demo feed generator",
        createdAt: now,
      }, jwt);
      console.log("  [SEED]   Feed generator created");
    } catch (exc) {
      console.log(`  [SEED]   Feed generator failed: ${exc}`);
      seedErrors.push(`feed generator ${handle}: ${exc}`);
    }

    if (postUris.length > 0) {
      console.log(`  [SEED]   Captured ${postUris.length} post URI(s)`);
    }
  }

  console.log("  [CHAT] Seeding DM conversations...");
  let chatCount = 0;
  let expectedChatCount = 0;
  for (const [key, messages] of Object.entries(conversations)) {
    const [h1, h2] = key.split("|");
    if (!dids[h1] || !dids[h2]) continue;
    expectedChatCount += messages.length;
    console.log(`  [CHAT]   ${capitalizedHandle(h1)} <-> ${capitalizedHandle(h2)}`);

    try {
      const convo = await chatGetConvoForMembers(chatContext, sessions[h1].accessJwt, [
        dids[h1],
        dids[h2],
      ]);
      const convoId = (convo.convo ?? convo).id;
      if (!convoId) {
        seedErrors.push(`chat ${h1}<->${h2}: no convo id returned`);
        continue;
      }

      for (const [sender, text] of messages) {
        await chatSendMessage(chatContext, sessions[sender].accessJwt, convoId, text);
        chatCount++;
      }
      console.log(`  [CHAT]     Sent ${messages.length} messages`);
    } catch (exc) {
      console.log(`  [CHAT]     Failed: ${exc}`);
      seedErrors.push(`chat ${h1}<->${h2}: ${exc}`);
    }
  }

  console.log("\n  [SUMMARY]");
  console.log(`  Accounts: ${Object.keys(sessions).length}`);
  console.log(`  Records attempted for: ${DEFAULT_ACCOUNTS.length} accounts`);
  console.log(`  Chat messages sent: ${chatCount}/${expectedChatCount}`);

  if (seedErrors.length > 0) {
    console.log("  Seed completed with errors:");
    for (const error of seedErrors) console.log(`  - ${error}`);
    Deno.exit(1);
  }

  console.log("\n  [DONE] Full suite seeding complete!");
}

if (import.meta.main) {
  await main();
}
