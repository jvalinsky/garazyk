#!/usr/bin/env -S deno run -A
import { BskyAgent } from "npm:@atproto/api@^0.13.0";

async function main() {
  const baseUrl = Deno.env.get("PDS_URL") || "http://localhost:2583";
  const accountsRaw = Deno.env.get("CHAT_ACCOUNTS") || "alice.garazyk.xyz,bob.garazyk.xyz,carol.garazyk.xyz";
  const handles = accountsRaw.split(",").map(h => h.trim()).filter(h => h);
  
  const singlePassword = Deno.env.get("CHAT_PASSWORD");
  const defaultPasswords = "alicepass123,bobpass123,carolpass123";
  const passwordsRaw = Deno.env.get("CHAT_PASSWORDS") || defaultPasswords;
  
  let passwords: string[] = [];
  if (singlePassword) {
    passwords = handles.map(() => singlePassword);
  } else {
    passwords = passwordsRaw.split(",").map(p => p.trim());
    while (passwords.length < handles.length) {
      passwords.push(passwords[passwords.length - 1] || "changeme");
    }
  }

  if (handles.length < 2) {
    console.error("ERROR: Need at least 2 accounts for chat");
    Deno.exit(1);
  }

  console.log(`Waiting for PDS at ${baseUrl} ...`);
  const agent = new BskyAgent({ service: baseUrl });

  const sessions: Record<string, any> = {};
  for (let i = 0; i < handles.length; i++) {
    const handle = handles[i];
    const password = passwords[i];
    try {
      await agent.login({ identifier: handle, password });
      sessions[handle] = agent.session;
      console.log(`  Logged in: ${handle} (${agent.session?.did})`);
    } catch (e: any) {
      console.error(`  FAILED: ${e.message}`);
      Deno.exit(1);
    }
  }

  console.log("\n  [CHAT] Creating pairwise DMs...");
  for (let i = 0; i < Math.min(handles.length, 3); i++) {
    for (let j = i + 1; j < Math.min(handles.length, 3); j++) {
      const h1 = handles[i];
      const h2 = handles[j];
      const did1 = sessions[h1].did;
      const did2 = sessions[h2].did;

      agent.session = sessions[h1];
      try {
        const convoRes = await agent.api.chat.bsky.convo.getConvoForMembers({ members: [did1, did2] });
        const convoId = convoRes.data.convo.id;
        console.log(`  [CHAT]   Convo ${h1} <-> ${h2}: ${convoId}`);
        
        await agent.api.chat.bsky.convo.sendMessage({
          convoId,
          message: { text: `Hello from ${h1} to ${h2}!` }
        });
        console.log(`  [CHAT]     ${h1} sent message`);
      } catch (e: any) {
        console.error(`  [CHAT]   Failed to setup chat between ${h1} and ${h2}: ${e.message}`);
      }
    }
  }
}

if (import.meta.main) {
  main();
}
