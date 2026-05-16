/**
 * @module scenarios/37_germ_e2ee_dms
 *
 * Scenario: 37 germ e2ee dms
 *
 * Behavior:
 * - Executes the 37 germ e2ee dms scenario.
 * - Validates core operations.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import {
  chatGetConvoForMembers,
  chatGetMessages,
  chatSendMessage,
  createChatServiceContext,
} from "../../lib/deno/seed.ts";
import { ScenarioResult } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { getCharacter, PDS1, SERVICE_URLS } from "../../lib/deno/config.ts";
import { timedCall } from "../../lib/deno/runner.ts";

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */


const GERM_URL = Deno.env.get("GERM_URL") || "http://127.0.0.1:8082";

function now() {
  return new Date().toISOString();
}

async function germPost(method: string, body: any, token: string) {
  const url = `${GERM_URL}/xrpc/${method}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": `Bearer ${token}` },
    body: JSON.stringify(body),
  });
  if (res.status === 200) return await res.json();
  return null;
}

async function germGet(method: string, params: Record<string, any>, token: string) {
  const url = new URL(`${GERM_URL}/xrpc/${method}`);
  for (const [k, v] of Object.entries(params)) url.searchParams.append(k, String(v));
  const res = await fetch(url.toString(), {
    headers: { "Authorization": `Bearer ${token}` },
  });
  if (res.status === 200) return await res.json();
  return null;
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Germ E2EE DMs");
  result.start();

  const client = new XrpcClient(PDS1);
  const chatUrl = Deno.env.get("CHAT_URL") || SERVICE_URLS.chat || "http://localhost:2585";
  const chatContext = createChatServiceContext(
    client,
    chatUrl,
    Deno.env.get("CHAT_SERVICE_DID") || undefined,
  );
  await timedCall(result, "PDS health check", async () => {
    await client.waitForHealthy(30);
  });
  await timedCall(result, "Chat service health check", async () => {
    await chatContext.chatClient.waitForHealthy(30);
  });

  if (result.failed > 0) return result;

  let germHealthy = false;
  try {
    const res = await fetch(`${GERM_URL}/_health`);
    germHealthy = res.status === 200;
  } catch { /* ignore */ }

  if (!germHealthy) result.stepSkipped("Germ service health check", "Not running on 8082");

  const luna = getCharacter("luna");
  const marcus = getCharacter("marcus");

  for (const char of [luna, marcus]) {
    const session = await client.accounts.createAccount(char.handle, char.email, char.password)
      .catch(() => client.accounts.createSession(char.handle, char.password));
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  // 2. Vanilla chat
  const convo = await timedCall(result, "Vanilla: Get convo", async () => {
    return await chatGetConvoForMembers(chatContext, luna.accessJwt, [luna.did, marcus.did]);
  });
  const convoId = convo?.convo?.id;

  const plaintext = "Hey Marcus! Plaintext message.";
  if (convoId) {
    await timedCall(result, "Vanilla: Send plaintext", async () => {
      return await chatSendMessage(chatContext, luna.accessJwt, convoId, plaintext);
    });

    const messages = await timedCall(result, "Vanilla: Server returns plaintext", async () => {
      return await chatGetMessages(chatContext, marcus.accessJwt, convoId, 20);
    });
    const found = messages?.messages?.some((m: any) => m.text === plaintext);
    assert.isTrue(found, "Plaintext not found");
  }

  if (germHealthy) {
    await timedCall(result, "Germ: Publish declaration", async () => {
      const decl = {
        $type: "com.germnetwork.declaration",
        version: "1.0.0",
        currentKey: {
          $bytes: btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(33)))),
        },
        messageMe: {
          showButtonTo: "everyone",
          messageMeUrl: "https://germ.network/dm",
        },
        createdAt: now(),
      };
      return await client.records.createRecord(
        luna.did,
        "com.germnetwork.declaration",
        decl,
        luna.accessJwt,
        { rkey: "self" },
      );
    });

    const claim = await timedCall(result, "Germ: Luna claims addresses", async () => {
      return await germPost("com.germnetwork.mailbox.claimAddresses", {
        agentRef: "luna-1",
        count: 3,
      }, luna.accessJwt);
    });

    const mClaim = await germPost("com.germnetwork.mailbox.claimAddresses", {
      agentRef: "marcus-1",
      count: 3,
    }, marcus.accessJwt);

    if (mClaim?.addresses?.length > 0) {
      const ciphertext = new Uint8Array(256);
      crypto.getRandomValues(ciphertext);
      const ctB64 = btoa(String.fromCharCode(...ciphertext));

      await timedCall(result, "Germ: Deliver ciphertext", async () => {
        return await germPost("com.germnetwork.mailbox.deliver", {
          address: mClaim.addresses[0],
          ciphertext: { $bytes: ctB64 },
        }, luna.accessJwt);
      });

      const poll = await timedCall(result, "Germ: Marcus polls mailbox", async () => {
        return await germGet(
          "com.germnetwork.mailbox.poll",
          { agentRef: "marcus-1" },
          marcus.accessJwt,
        );
      });

      console.log("Poll result:", JSON.stringify(poll));
      const foundCt = poll?.messages?.some((m: any) => m.ciphertext?.$bytes === ctB64);
      assert.isTrue(foundCt, "Ciphertext not found or mismatch");
      result.stepPassed("Verify: Germ ciphertext is opaque");
    }
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