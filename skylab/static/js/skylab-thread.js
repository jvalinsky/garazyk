(function (global) {
  "use strict";

  function initThreadPanel(bridge, router) {
    const container = document.getElementById("panel-thread");
    if (!container) return;

    function showLoading() {
      container.innerHTML = '<div class="skylab-empty-state">Loading thread\u2026</div>';
    }

    function showError(msg) {
      container.innerHTML = '<div class="skylab-empty-state">' + msg + "</div>";
    }

    function renderThread(did, rkey) {
      showLoading();

      bridge.xrpc(
        "app.bsky.feed.getPostThread",
        { uri: "at://" + did + "/app.bsky.feed.post/" + rkey, depth: 10 },
        null,
        { service: "appview", auth: !!bridge.auth },
      ).then((resp) => {
        if (!resp.ok) {
          showError("Thread not found");
          return;
        }
        const thread = resp.data?.thread;
        if (!thread) {
          showError("Thread not found");
          return;
        }

        container.innerHTML = "";

        const backBtn = document.createElement("button");
        backBtn.className = "skylab-btn skylab-btn-sm";
        backBtn.textContent = "\u2190 Back";
        backBtn.addEventListener("click", () => window.history.back());
        container.appendChild(backBtn);

        const threadEl = document.createElement("div");
        threadEl.className = "skylab-thread";
        renderThreadNode(threadEl, thread, 0);
        container.appendChild(threadEl);
      }).catch(() => showError("Failed to load thread"));
    }

    function renderThreadNode(container, node, depth) {
      if (!node) return;

      if (node.post) {
        const el = SkyLabPost.renderPost(node, { threadDepth: depth });
        if (el) {
          el.addEventListener("skylab-navigate", (e) => {
            const { route, params } = e.detail;
            window.location.hash = "#/" + route + "/" + params.join("/");
          });
          container.appendChild(el);
        }
      }

      if (node.replies && Array.isArray(node.replies)) {
        for (const reply of node.replies) {
          renderThreadNode(container, reply, depth + 1);
        }
      }

      if (depth === 0 && (!node.replies || node.replies.length === 0)) {
        const empty = document.createElement("div");
        empty.className = "skylab-empty-state";
        empty.textContent = "No replies yet";
        container.appendChild(empty);
      }
    }

    router.on("thread", (params) => {
      const did = params[0];
      const rkey = params[1];
      if (did && rkey) renderThread(did, rkey);
    });

    if (router.currentRoute().route === "thread") {
      const p = router.currentRoute().params;
      if (p[0] && p[1]) renderThread(p[0], p[1]);
    } else {
      showLoading();
    }
  }

  global.initThreadPanel = initThreadPanel;
  if (typeof module !== "undefined" && module.exports) module.exports = { initThreadPanel };
})(typeof window !== "undefined" ? window : globalThis);
