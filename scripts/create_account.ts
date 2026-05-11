#!/usr/bin/env -S deno run -A
import { parseArgs } from "jsr:@std/cli/parse-args";
import { BskyAgent } from "npm:@atproto/api@^0.13.0";

async function main() {
  const args = parseArgs(Deno.args);
  const handle = args._[0]?.toString() || "alice.test";
  const email = args._[1]?.toString() || "alice@test.com";
  const password = args._[2]?.toString() || "password123";
  const pdsUrl = args["pds-url"] || Deno.env.get("PDS_URL") || "http://localhost:2583";

  console.log(`Creating account ${handle} on ${pdsUrl}...`);
  const agent = new BskyAgent({ service: pdsUrl });

  try {
    const res = await agent.createAccount({ handle, email, password });
    console.log(`Success! DID: ${res.data.did}`);
  } catch (e: any) {
    console.error(`Failed: ${e.message}`);
    Deno.exit(1);
  }
}

if (import.meta.main) {
  main();
}
