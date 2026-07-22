// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * SkyLab Chat Panel — DMs and group conversations.
 *
 * The E2EE (Germ) mode selector was removed per the Phase 10 product-surface
 * decision (docs/plans/phase-10-product-surface-decision-brief.md):
 * selecting it announced client-side encryption but silently sent plaintext,
 * a privacy/consent failure, not just an unimplemented feature. This client
 * only ever sends plaintext now. Incoming messages that arrive as
 * ciphertext (e.g. from a federated client that does support Germ) still
 * render as "[Encrypted]" below - that's an honest statement that this
 * client can't read them, not a claim this client encrypts anything itself.
 */

function initChatPanel(bridge) {
  const listEl = document.getElementById("chat-list");
  const viewEl = document.getElementById("chat-view");

  let selectedConvoId = null;
  let conversations = [];

  // ---- Load conversations ----
  async function loadConversations() {
    if (!bridge.auth) return;
    const resp = await bridge.xrpc("chat.bsky.convo.getList", { limit: 20 }, null, {
      service: "chat",
      auth: true,
    });
    if (resp.ok && resp.data?.convos) {
      conversations = resp.data.convos;
      renderConversationList();
    } else {
      listEl.innerHTML = '<div class="skylab-empty-state">Could not load conversations</div>';
    }
  }

  function renderConversationList() {
    if (conversations.length === 0) {
      listEl.innerHTML = '<div class="skylab-empty-state">No conversations</div>';
      return;
    }
    listEl.innerHTML = "";
    for (const convo of conversations) {
      const item = document.createElement("div");
      item.className = "skylab-chat-item" + (convo.id === selectedConvoId ? " active" : "");
      const members = (convo.members || []).map((m) => m.handle || m.did?.substring(0, 16)).join(
        ", ",
      );
      const lastMsg = convo.lastMessage?.text || "";
      const preview = lastMsg.length > 50 ? lastMsg.substring(0, 50) + "..." : lastMsg;
      item.innerHTML = `
                <div style="font-weight:600;font-size:var(--font-size-sm);">${
        escapeHtml(members)
      }</div>
                <div style="font-size:var(--font-size-xs);color:var(--color-text-secondary);margin-top:2px;">${
        escapeHtml(preview)
      }</div>
            `;
      item.addEventListener("click", () => selectConversation(convo.id));
      listEl.appendChild(item);
    }
  }

  // ---- Select conversation ----
  async function selectConversation(convoId) {
    selectedConvoId = convoId;
    renderConversationList(); // update active state

    const resp = await bridge.xrpc(
      "chat.bsky.convo.getMessages",
      {
        convoId: convoId,
        limit: 50,
      },
      null,
      { service: "chat", auth: true },
    );

    if (resp.ok && resp.data?.messages) {
      renderMessages(resp.data.messages);
    } else {
      viewEl.innerHTML = '<div class="skylab-empty-state">Could not load messages</div>';
    }
  }

  function renderMessages(messages) {
    viewEl.innerHTML = `
            <div class="skylab-chat-messages" id="chat-messages"></div>
            <div class="skylab-chat-composer">
                <input type="text" class="skylab-chat-composer-input" id="chat-msg-input"
                       placeholder="Type a message...">
                <button class="skylab-btn skylab-btn-primary skylab-btn-sm" id="chat-msg-send">Send</button>
            </div>
        `;

    const messagesEl = document.getElementById("chat-messages");
    for (const msg of messages) {
      messagesEl.appendChild(renderMessage(msg));
    }
    messagesEl.scrollTop = messagesEl.scrollHeight;

    // Wire up send
    const input = document.getElementById("chat-msg-input");
    const sendBtn = document.getElementById("chat-msg-send");

    sendBtn.addEventListener("click", () => sendMessage(input));
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        sendMessage(input);
      }
    });
  }

  function renderMessage(msg) {
    const el = document.createElement("div");
    const isSent = msg.sender?.did === bridge.auth?.did;
    el.className = "skylab-chat-message" + (isSent ? " sent" : "");

    const text = msg.text || (msg.ciphertext ? "[Encrypted]" : "");
    const isE2EE = !!msg.ciphertext;

    el.innerHTML = `
            <div class="skylab-chat-message-bubble">${escapeHtml(text)}</div>
            ${isE2EE ? '<div class="skylab-chat-message-e2ee">🔒 End-to-end encrypted</div>' : ""}
        `;
    return el;
  }

  async function sendMessage(input) {
    const text = input.value.trim();
    if (!text || !selectedConvoId) return;

    const resp = await bridge.xrpc("chat.bsky.convo.sendMessage", null, {
      convoId: selectedConvoId,
      message: {
        $type: "chat.bsky.convo.message",
        text: text,
        createdAt: new Date().toISOString(),
      },
    }, { service: "chat", auth: true });

    if (resp.ok) {
      input.value = "";
      // Append sent message to view
      const messagesEl = document.getElementById("chat-messages");
      if (messagesEl) {
        messagesEl.appendChild(renderMessage({
          sender: { did: bridge.auth.did },
          text: text,
        }));
        messagesEl.scrollTop = messagesEl.scrollHeight;
      }
    }
  }

  // ---- New conversation ----
  // (Future: add "New DM" button that calls getConvoForMembers)

  // ---- Auth change ----
  bridge.on("auth_change", (auth) => {
    if (auth) {
      loadConversations();
    } else {
      conversations = [];
      selectedConvoId = null;
      listEl.innerHTML = '<div class="skylab-empty-state">Sign in to see chats</div>';
      viewEl.innerHTML = '<div class="skylab-empty-state">Select a conversation</div>';
    }
  });

  // ---- HTML escaping ----
  function escapeHtml(str) {
    const div = document.createElement("div");
    div.textContent = str || "";
    return div.innerHTML;
  }
}
