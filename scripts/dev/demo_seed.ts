#!/usr/bin/env -S deno run -A
import { XrpcClient } from "@garazyk/gruszka";
import { createAccountOrLogin, nowIso, waitForServer } from "@garazyk/gruszka/seed";

const baseUrl = (Deno.env.get("PDS_URL") || "http://localhost:2583").replace(/\/$/, "");

const demoAccounts = [
  {
    handle: "alice.test",
    email: "alice@test.com",
    password: "hunter2",
    displayName: "Alice",
    description: "I am looking for the white rabbit.",
    posts: ["Alice's post number 1", "Alice's post number 2", "Alice's post number 3"],
  },
  {
    handle: "bob.test",
    email: "bob@test.com",
    password: "hunter2",
    displayName: "Bob",
    description: "I build things.",
    posts: ["Hello world from Bob!"],
  },
];

async function main() {
  console.log(`Waiting for server at ${baseUrl} to be ready...`);
  await waitForServer(baseUrl, 30);
  console.log("Server is up!");

  const client = new XrpcClient(baseUrl);
  const now = nowIso();

  for (const account of demoAccounts) {
    try {
      const session = await createAccountOrLogin(
        client,
        account.handle,
        account.email,
        account.password,
      );
      const did = session.did;
      const jwt = session.accessJwt;
      console.log(`Account ${account.handle} ready (${did})`);

      try {
        await client.records.createRecord(
          did,
          "app.bsky.actor.profile",
          {
            "$type": "app.bsky.actor.profile",
            displayName: account.displayName,
            description: account.description,
          },
          jwt,
          { rkey: "self" },
        );
        console.log(`  Profile created for ${account.displayName}`);
      } catch (exc) {
        console.log(`  Profile failed: ${exc}`);
      }

      for (let i = 0; i < account.posts.length; i++) {
        const text = account.posts[i];
        try {
          await client.records.createRecord(did, "app.bsky.feed.post", {
            "$type": "app.bsky.feed.post",
            text,
            createdAt: now,
          }, jwt);
          console.log(`  Post #${i + 1}: ${text.slice(0, 50)}`);
        } catch (exc) {
          console.log(`  Post #${i + 1} failed: ${exc}`);
        }
      }
    } catch (exc) {
      console.log(`Account ${account.handle} failed: ${exc}`);
    }
  }

  console.log("\nDone!");
}

if (import.meta.main) {
  await main();
}
