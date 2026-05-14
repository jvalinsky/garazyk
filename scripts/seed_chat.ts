#!/usr/bin/env -S deno run -A
import { XrpcClient } from "./lib/deno/client.ts";
import {
  getConvoForMembers,
  getMessages,
  listConvos,
  sendMessage,
  waitForServer,
} from "./lib/deno/seed.ts";

const baseUrl = (Deno.env.get("PDS_URL") || "http://localhost:2583").replace(/\/$/, "");
const handles = (Deno.env.get("CHAT_ACCOUNTS") ||
  "alice.garazyk.xyz,bob.garazyk.xyz,carol.garazyk.xyz")
  .split(",")
  .map((handle) => handle.trim())
  .filter(Boolean);

const defaultPasswords = "alicepass123,bobpass123,carolpass123";
const singlePassword = Deno.env.get("CHAT_PASSWORD") || "";
const passwordsRaw = Deno.env.get("CHAT_PASSWORDS") || defaultPasswords;
const passwords = singlePassword
  ? handles.map(() => singlePassword)
  : passwordsRaw.split(",").map((password) => password.trim()).filter(Boolean);

while (passwords.length < handles.length) {
  passwords.push(passwords.at(-1) || "changeme");
}

function short(value: string, length = 30): string {
  return value.length > length ? `${value.slice(0, length)}...` : value;
}

async function main() {
  if (handles.length < 2) {
    console.error("ERROR: Need at least 2 accounts for chat");
    Deno.exit(1);
  }

  console.log(`Waiting for PDS at ${baseUrl} ...`);
  await waitForServer(baseUrl);
  console.log("PDS is up!");

  const client = new XrpcClient(baseUrl);
  const sessions: Record<string, Record<string, string>> = {};

  for (let i = 0; i < handles.length; i++) {
    const handle = handles[i];
    const password = passwords[i] || passwords.at(-1) || "changeme";
    try {
      const session = await client.accounts.createSession(handle, password);
      sessions[handle] = session;
      console.log(`  Logged in: ${handle} (${session.did})`);
    } catch (exc) {
      console.error(`  FAILED: ${exc instanceof Error ? exc.message : String(exc)}`);
      Deno.exit(1);
    }
  }

  const dids = Object.fromEntries(handles.map((handle) => [handle, sessions[handle].did]));
  const jwts = Object.fromEntries(handles.map((handle) => [handle, sessions[handle].accessJwt]));
  const errors: string[] = [];
  const dmConvoIds = new Map<string, string>();
  const dmMessages = new Map<string, Array<[string, string]>>();

  let expectedDmMessages = 0;
  let sentDmMessages = 0;

  for (let i = 0; i < Math.min(handles.length, 3); i++) {
    for (let j = i + 1; j < Math.min(handles.length, 3); j++) {
      const h1 = handles[i];
      const h2 = handles[j];
      const pairKey = `${h1}<->${h2}`;
      console.log(`\n=== DM: ${h1} <-> ${h2} ===`);

      const convo = await getConvoForMembers(client, jwts[h1], [dids[h1], dids[h2]]);
      const convoData = convo.convo ?? convo;
      const convoId = convoData.id ?? "";
      if (!convoId) {
        errors.push(`DM ${pairKey}: no convo id returned`);
        console.log("  FAILED: no convo id returned");
        continue;
      }

      dmConvoIds.set(pairKey, convoId);
      console.log(`  Convo ID: ${convoId}`);

      const messages: Array<[string, string]> = [
        [h1, `Hey ${h2.split(".")[0]}! How's it going?`],
        [h2, `Hey ${h1.split(".")[0]}! Doing great, thanks!`],
        [h1, "Have you seen the latest ATProto spec updates?"],
        [h2, "Yes. The new XRPC methods are sharp."],
      ];
      dmMessages.set(pairKey, []);
      expectedDmMessages += messages.length;

      for (const [sender, text] of messages) {
        try {
          const msg = await sendMessage(client, jwts[sender], convoId, text);
          dmMessages.get(pairKey)?.push([sender, text]);
          sentDmMessages++;
          console.log(`  [${sender}]: ${text}`);
          console.log(`    msg_id: ${short(msg.id ?? "?")}`);
        } catch (exc) {
          errors.push(`DM ${pairKey}: send failed for ${sender}: ${exc}`);
          console.log(`  FAILED send from ${sender}: ${exc}`);
          break;
        }
      }
    }
  }

  let groupConvoId = "";
  let expectedGroupMessages = 0;
  let sentGroupMessages = 0;
  if (handles.length >= 3) {
    console.log(`\n=== Group Chat: ${handles.slice(0, 3).join(", ")} ===`);
    const groupDids = handles.slice(0, 3).map((handle) => dids[handle]);
    const groupConvo = await getConvoForMembers(client, jwts[handles[0]], groupDids);
    const groupData = groupConvo.convo ?? groupConvo;
    groupConvoId = groupData.id ?? "";
    if (!groupConvoId) {
      errors.push("Group chat: no convo id returned");
      console.log("  FAILED: no group convo id returned");
    } else {
      console.log(`  Convo ID: ${groupConvoId}`);
      const groupMessages: Array<[string, string]> = [
        [handles[0], "Hey team! Group chat is live!"],
        [handles[1], "Love seeing the chat endpoint wired up."],
        [handles[2], "Count me in for relay coordination."],
        [handles[0], "Let's use this thread for smoke-test notes."],
      ];
      expectedGroupMessages = groupMessages.length;

      for (const [sender, text] of groupMessages) {
        try {
          await sendMessage(client, jwts[sender], groupConvoId, text);
          sentGroupMessages++;
          console.log(`  [${sender}]: ${text}`);
        } catch (exc) {
          errors.push(`Group chat: send failed for ${sender}: ${exc}`);
          console.log(`  FAILED send from ${sender}: ${exc}`);
          break;
        }
      }
    }
  }

  console.log("\n=== Verification ===");
  const convos = await listConvos(client, jwts[handles[0]]);
  const convoList = convos.convos ?? [];
  console.log(`  ${handles[0]} has ${convoList.length} conversation(s)`);
  for (const convo of convoList) {
    const members = (convo.members ?? []).map((member: Record<string, string>) =>
      (member.did ?? "?").slice(0, 25)
    );
    console.log(`    Convo ${short(convo.id ?? "?")} members: ${members.join(", ")}`);
  }

  const firstDm = dmConvoIds.entries().next().value as [string, string] | undefined;
  if (firstDm) {
    const [pairKey, convoId] = firstDm;
    const firstHandle = pairKey.split("<->")[0];
    const messages = await getMessages(client, jwts[firstHandle], convoId);
    const messageList = messages.messages ?? [];
    const expected = dmMessages.get(pairKey)?.length ?? 0;
    console.log(`\n  Messages in ${pairKey}: ${messageList.length}`);
    if (messageList.length < expected) {
      errors.push(
        `DM ${pairKey}: read ${messageList.length} messages, expected at least ${expected}`,
      );
    }
  }

  if (groupConvoId) {
    const messages = await getMessages(client, jwts[handles[0]], groupConvoId);
    const messageList = messages.messages ?? [];
    console.log(`\n  Messages in group chat: ${messageList.length}`);
    if (messageList.length < sentGroupMessages) {
      errors.push(
        `Group chat: read ${messageList.length} messages, expected at least ${sentGroupMessages}`,
      );
    }
  }

  console.log("\n=== Summary ===");
  console.log(`  Accounts: ${Object.keys(sessions).length}`);
  console.log(`  DM conversations: ${dmConvoIds.size}`);
  console.log(`  DM messages sent: ${sentDmMessages}/${expectedDmMessages}`);
  if (handles.length >= 3) {
    console.log(`  Group conversation: ${groupConvoId ? 1 : 0}`);
    console.log(`  Group messages sent: ${sentGroupMessages}/${expectedGroupMessages}`);
  }

  if (errors.length > 0) {
    console.log("  FAILED:");
    for (const error of errors) console.log(`  - ${error}`);
    Deno.exit(1);
  }
  console.log("  Done!");
}

if (import.meta.main) {
  await main();
}
