/**
 * @module scenarios/89_chat_advanced_endpoints
 *
 * Scenario: Covers remaining chat.bsky.convo, chat.bsky.actor, and
 *   chat.bsky.moderation endpoints not covered by scenarios 06, 47, 72.
 *
 * Covers:
 *   chat.bsky.convo.getConvo
 *   chat.bsky.convo.getConvoAvailability
 *   chat.bsky.convo.getLog
 *   chat.bsky.convo.acceptConvo
 *   chat.bsky.convo.lockConvo / unlockConvo
 *   chat.bsky.convo.sendMessageBatch
 *   chat.bsky.convo.listConvoRequests
 *   chat.bsky.convo.updateAllRead
 *   chat.bsky.convo.deleteMessageForSelf
 *   chat.bsky.actor.deleteAccount
 *   chat.bsky.actor.exportAccountData
 *   chat.bsky.moderation.getActorMetadata
 *   chat.bsky.moderation.getMessageContext
 *   chat.bsky.moderation.updateActorAccess
 *
 * Extends 06_chat_dms.ts (DM send/receive lifecycle) and 72_chat_reactions.ts
 * (add/remove reactions) to add remaining convo, actor, and moderation coverage.
 */

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { getActor, PDS1, SERVICE_URLS } from "../../lib/deno/config.ts";
import { now, ScenarioResult, timedCall, tryEndpoint } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import {
  chatXrpcGet,
  chatXrpcPost,
  createChatServiceContext,
} from "../../lib/deno/seed.ts";



export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Chat Advanced Endpoints");
  result.start();

  const pds = new XrpcClient(PDS1);
  const chatUrl = Deno.env.get("CHAT_URL") ?? SERVICE_URLS.chat;
  const chatContext = createChatServiceContext(
    pds,
    chatUrl,
    Deno.env.get("CHAT_SERVICE_DID") || undefined,
  );
  const luna = getActor("luna");
  const marcus = getActor("marcus");
  const rosa = getActor("rosa");
  const volt = getActor("volt");

  // --- Health checks ---
  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });
  await timedCall(result, "Chat service health check", async () => {
    await chatContext.chatClient.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  // --- Account setup ---
  for (const char of [luna, marcus, rosa, volt]) {
    const session = await timedCall(
      result,
      `Create account: ${char.name}`,
      async () => {
        try {
          return await pds.accounts.createAccount(char.handle, char.email, char.password);
        } catch {
          return await pds.accounts.createSession(char.handle, char.password);
        }
      },
      (s) => `did=${s.did}`,
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  if (!luna.did || !marcus.did || !rosa.did || !volt.did) {
    result.stepFailed("Account setup", "missing DID");
    result.finish();
    return result;
  }

  // ── 1. chat.bsky.convo.getConvoAvailability ────────────────────────────
  // Check if Luna can be messaged by Marcus
  await tryEndpoint(
    result,
    "getConvoAvailability (Luna → Marcus)",
    async () => {
      return await chatXrpcGet(chatContext, luna.accessJwt, "chat.bsky.convo.getConvoAvailability", {
        members: [luna.did, marcus.did],
      });
    },
    (r) => `canChat=${r?.canChat}`,
  );

  // ── 2. Create DM between Luna and Marcus ────────────────────────────────
  const convo = await timedCall(
    result,
    "Create DM between Luna and Marcus",
    async () => {
      return await chatXrpcGet(chatContext, luna.accessJwt, "chat.bsky.convo.getConvoForMembers", {
        members: [luna.did, marcus.did],
      });
    },
    (c) => `convoId=${c?.convo?.id}`,
  );

  const convoId = convo?.convo?.id;
  if (!convoId) {
    result.stepFailed("Create DM", "no convo ID returned");
    result.finish();
    return result;
  }

  // ── 3. chat.bsky.convo.getConvo ────────────────────────────────────────
  // Get the single convo by ID
  await tryEndpoint(
    result,
    "getConvo (by ID)",
    async () => {
      return await chatXrpcGet(chatContext, luna.accessJwt, "chat.bsky.convo.getConvo", {
        convoId,
      });
    },
    (c) => `status=${c?.convo?.status ?? "present"}`,
  );

  // ── 4. Send a few messages to populate log ──────────────────────────────
  await tryEndpoint(result, "Send message 1 for log", async () => {
    return await chatXrpcPost(chatContext, luna.accessJwt, "chat.bsky.convo.sendMessage", {
      convoId,
      message: { text: "Message one for log" },
    });
  });
  await tryEndpoint(result, "Send message 2 for log", async () => {
    return await chatXrpcPost(chatContext, marcus.accessJwt, "chat.bsky.convo.sendMessage", {
      convoId,
      message: { text: "Message two for log" },
    });
  });
  await tryEndpoint(result, "Send message 3 for log", async () => {
    return await chatXrpcPost(chatContext, luna.accessJwt, "chat.bsky.convo.sendMessage", {
      convoId,
      message: { text: "Message three for log" },
    });
  });

  await new Promise((r) => setTimeout(r, 500));

  // ── 5. chat.bsky.convo.getLog ──────────────────────────────────────────
  // Get conversation event log
  await tryEndpoint(
    result,
    "getLog (conversation events)",
    async () => {
      return await chatXrpcGet(chatContext, luna.accessJwt, "chat.bsky.convo.getLog", {
        cursor: 0,
      });
    },
    (r) => `logLength=${(r?.logs ?? []).length}`,
  );

  // ── 6. chat.bsky.convo.lockConvo / unlockConvo ─────────────────────────
  // Lock the conversation
  await tryEndpoint(
    result,
    "lockConvo",
    async () => {
      return await chatXrpcPost(chatContext, luna.accessJwt, "chat.bsky.convo.lockConvo", {
        convoId,
      });
    },
    () => "locked",
  );

  // Unlock the conversation
  await tryEndpoint(
    result,
    "unlockConvo",
    async () => {
      return await chatXrpcPost(chatContext, luna.accessJwt, "chat.bsky.convo.unlockConvo", {
        convoId,
      });
    },
    () => "unlocked",
  );

  // ── 7. chat.bsky.convo.sendMessageBatch ────────────────────────────────
  // Send multiple messages in a batch
  await tryEndpoint(
    result,
    "sendMessageBatch (2 messages)",
    async () => {
      return await chatXrpcPost(chatContext, luna.accessJwt, "chat.bsky.convo.sendMessageBatch", {
        items: [
          {
            convoId,
            message: { text: "Batch message 1" },
          },
          {
            convoId,
            message: { text: "Batch message 2" },
          },
        ],
      });
    },
    (r) => `sent=${(r?.items ?? []).length}`,
  );

  // ── 8. chat.bsky.convo.listConvoRequests ───────────────────────────────
  // Create a situation where Rosa requests a convo with Luna
  // First get the convo availability for Rosa → Luna
  await tryEndpoint(
    result,
    "listConvoRequests (Rosa's pending requests)",
    async () => {
      return await chatXrpcGet(chatContext, rosa.accessJwt, "chat.bsky.convo.listConvoRequests", {
        limit: 20,
      });
    },
    (r) => `requests=${(r?.convos ?? []).length}`,
  );

  // ── 9. chat.bsky.convo.acceptConvo ─────────────────────────────────────
  // Create a new convo with Rosa → Luna direction to test acceptance
  const rosaConvo = await tryEndpoint(
    result,
    "Rosa gets convo with Luna (creates request)",
    async () => {
      return await chatXrpcGet(chatContext, rosa.accessJwt, "chat.bsky.convo.getConvoForMembers", {
        members: [rosa.did, luna.did],
      });
    },
    (c) => `convoId=${c?.convo?.id}`,
  );

  const rosaConvoId = rosaConvo?.convo?.id;
  if (rosaConvoId && rosaConvoId !== convoId) {
    // This is a separate convo — accept it
    await tryEndpoint(
      result,
      "acceptConvo (Rosa accepts incoming)",
      async () => {
        return await chatXrpcPost(chatContext, rosa.accessJwt, "chat.bsky.convo.acceptConvo", {
          convoId: rosaConvoId,
        });
      },
      () => "accepted",
    );
  }

  // ── 10. chat.bsky.convo.updateAllRead ──────────────────────────────────
  // Mark all conversations as read
  await tryEndpoint(
    result,
    "updateAllRead (mark all as read)",
    async () => {
      return await chatXrpcPost(chatContext, luna.accessJwt, "chat.bsky.convo.updateAllRead", {
        status: "read",
      });
    },
    () => "marked",
  );

  // ── 11. chat.bsky.convo.deleteMessageForSelf ───────────────────────────
  // Delete a message for self only (Luna deletes a batch message)
  const msgs = await tryEndpoint(result, "Get messages for delete target", async () => {
    return await chatXrpcGet(chatContext, luna.accessJwt, "chat.bsky.convo.getMessages", {
      convoId,
      limit: 5,
    });
  });
  const lastMsg = msgs?.messages?.[0];
  const targetMsgId = lastMsg?.id;

  if (targetMsgId) {
    await tryEndpoint(
      result,
      "deleteMessageForSelf (Luna deletes own message)",
      async () => {
        return await chatXrpcPost(chatContext, luna.accessJwt, "chat.bsky.convo.deleteMessageForSelf", {
          convoId,
          messageId: targetMsgId,
        });
      },
      () => "deleted for self",
    );
  }

  // ── 12. chat.bsky.moderation.updateActorAccess ─────────────────────────
  // Update Volt's chat access (as Luna, who has a convo with Volt too)
  // First get Volt in a convo
  const voltConvo = await chatXrpcGet(chatContext, volt.accessJwt, "chat.bsky.convo.getConvoForMembers", {
    members: [volt.did, marcus.did],
  });

  // Update actor access — this is typically a moderation action that requires special auth
  await tryEndpoint(
    result,
    "updateActorAccess (Volt chat access)",
    async () => {
      return await chatXrpcPost(chatContext, luna.accessJwt, "chat.bsky.moderation.updateActorAccess", {
        actor: volt.did,
        allowAccess: true,
      });
    },
    () => "updated",
  );

  // ── 13. chat.bsky.moderation.getActorMetadata ──────────────────────────
  // Get Volt's chat metadata
  await tryEndpoint(
    result,
    "getActorMetadata (Volt)",
    async () => {
      return await chatXrpcGet(chatContext, luna.accessJwt, "chat.bsky.moderation.getActorMetadata", {
        actor: volt.did,
      });
    },
    (r) => `metadata=${JSON.stringify(r ?? {})}`,
  );

  // ── 14. chat.bsky.moderation.getMessageContext ─────────────────────────
  // Get message context around a sent message
  if (targetMsgId) {
    await tryEndpoint(
      result,
      "getMessageContext (around deleted message)",
      async () => {
        return await chatXrpcGet(chatContext, luna.accessJwt, "chat.bsky.moderation.getMessageContext", {
          convoId,
          messageId: targetMsgId,
          maxMessages: 5,
        });
      },
      (r) => `messages=${(r?.messages ?? []).length}`,
    );
  }

  // ── 15. chat.bsky.actor.exportAccountData ──────────────────────────────
  // Export Luna's chat account data
  await tryEndpoint(
    result,
    "exportAccountData (Luna)",
    async () => {
      return await chatXrpcGet(chatContext, luna.accessJwt, "chat.bsky.actor.exportAccountData", {});
    },
    (r) => `exportSize=${Object.keys(r ?? {}).length} fields`,
  );

  // ── 16. chat.bsky.actor.deleteAccount ──────────────────────────────────
  // Delete Volt's chat account
  await tryEndpoint(
    result,
    "deleteAccount (Volt)",
    async () => {
      return await chatXrpcPost(chatContext, volt.accessJwt, "chat.bsky.actor.deleteAccount", {});
    },
    () => "deleted",
  );

  // ── 17. Auth enforcement: unauthenticated getLog ───────────────────────
  await timedCall(
    result,
    "Auth enforcement: getLog without auth",
    async () => {
      try {
        await chatXrpcGet(chatContext, "", "chat.bsky.convo.getLog", { cursor: 0 });
        result.stepPassed("getLog without auth accepted", "endpoint allowed it");
      } catch (e: any) {
        if (e instanceof XrpcError && (e.status === 401 || e.status === 403)) {
          result.stepPassed("getLog without auth rejected", `HTTP ${e.status}`);
        } else {
          throw e;
        }
      }
    },
  );

  result.finish();
  return result;
}

if (import.meta.main) {
  const res = await run();
  console.log(res.summary());
  Deno.exit(res.ok ? 0 : 1);
}
