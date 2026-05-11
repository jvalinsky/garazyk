#!/usr/bin/env -S deno run -A
import { BskyAgent } from "npm:@atproto/api@^0.13.0";
import { DEFAULT_ACCOUNTS, createAccountOrLogin } from "./lib/deno/seed.ts";

async function main() {
  const pdsUrl = Deno.env.get("PDS_URL") || "http://127.0.0.1:2583";
  const chatUrl = Deno.env.get("CHAT_URL") || pdsUrl;

  console.log("\n  ╔════════════════════════════════════════════════════╗");
  console.log("  ║     Seeding Full Suite Demo Data               ║");
  console.log("  ╚════════════════════════════════════════════════════╝\n");
  console.log(`  [SETUP] Target PDS: ${pdsUrl}`);

  const agent = new BskyAgent({ service: pdsUrl });
  const dids: Record<string, string> = {};

  console.log("  [ACCT] Creating accounts...");
  for (const acct of DEFAULT_ACCOUNTS) {
    try {
      const session = await createAccountOrLogin(agent, acct.handle, acct.email, acct.password);
      dids[acct.handle] = session?.did || "";
      console.log(`  [ACCT]   ${acct.handle}: ${session?.did}`);
    } catch (e: any) {
      console.error(`  [ACCT]   FAILED ${acct.handle}: ${e.message}`);
      Deno.exit(1);
    }
  }

  console.log("\n  [POST] Creating posts...");
  for (const acct of DEFAULT_ACCOUNTS) {
    try {
      await agent.login({ identifier: acct.handle, password: acct.password });
      for (let i = 1; i <= 5; i++) {
        await agent.post({ text: `Hello world! This is post ${i} from ${acct.handle}` });
      }
      console.log(`  [POST]   5 posts created for ${acct.handle}`);
    } catch (e: any) {
      console.error(`  [POST]   Failed for ${acct.handle}: ${e.message}`);
    }
  }

  console.log("\n  [DONE] Full suite seeding complete!");
}

if (import.meta.main) {
  main();
}
