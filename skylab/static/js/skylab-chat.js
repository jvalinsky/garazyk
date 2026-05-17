// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * SkyLab Chat Panel — DMs and group conversations with plaintext/E2EE toggle.
 */

function initChatPanel(bridge) {
  const listEl = document.getElementById("chat-list");
  const viewEl = document.getElementById("chat-view");
  const plainBtn = document.getElementById("chat-mode-plain");
  const e2eeBtn = document.getElementById("chat-mode-e2ee");

  let currentMode = "plaintext"; // or 'e2ee'
  let selectedConvoId = null;
  let conversations = [];

  // ---- Mode toggle ----
  plainBtn.addEventListener("click", () => {
    currentMode = "plaintext";
    plainBtn.classList.add("active");
    e2eeBtn.classList.remove("active");
  });

  e2eeBtn.addEventListener("click", () => {
    currentMode = "e2ee";
    e2eeBtn.classList.add("active");
    plainBtn.classList.remove("active");
    // Show note about Germ
    viewEl.innerHTML = `
            <div class="skylab-empty-state" style="padding:var(--space-xl);">
                <p>E2EE mode requires the Germ service to be running on port 8082.</p>
                <p style="color:var(--color-text-tertiary);font-size:var(--font-size-xs);margin-top:var(--space-sm);">
                    Messages will be encrypted client-side before delivery via the Germ mailbox.
                </p>
            </div>`;
  });

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

    if (currentMode === "e2ee") {
      // Germ E2EE — placeholder for SDK integration
      appendSystemMessage(
        "E2EE messaging requires Germ SDK integration. Falling back to plaintext for now.",
      );
    }

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

  function appendSystemMessage(text) {
    const messagesEl = document.getElementById("chat-messages");
    if (!messagesEl) return;
    const el = document.createElement("div");
    el.style.cssText =
      "text-align:center;color:var(--color-text-tertiary);font-size:var(--font-size-xs);padding:var(--space-sm);";
    el.textContent = text;
    messagesEl.appendChild(el);
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
