(function (global) {
  "use strict";

  function initNotificationsPanel(bridge) {
    const container = document.getElementById("panel-notifications");
    if (!container) return;

    let notifs = [];

    function showLoading() {
      container.innerHTML = '<div class="skylab-empty-state">Loading notifications\u2026</div>';
    }

    function showEmpty() {
      container.innerHTML = '<div class="skylab-empty-state">No notifications</div>';
    }

    function reasonIcon(reason) {
      const icons = {
        like: "\u2764",
        follow: "\u2795",
        reply: "\u21A9",
        repost: "\u267B",
        quote: "\u201C",
      };
      return icons[reason] || "\u25CF";
    }

    function reasonLabel(reason) {
      return reason ? reason.charAt(0).toUpperCase() + reason.slice(1) : "Event";
    }

    function render() {
      if (notifs.length === 0) {
        showEmpty();
        return;
      }
      container.innerHTML = "";
      const list = document.createElement("div");
      list.className = "skylab-notif-list";

      for (const n of notifs) {
        const item = document.createElement("div");
        item.className = "skylab-notif-item" + (n.isRead ? "" : " skylab-notif-unread");

        const icon = document.createElement("span");
        icon.className = "skylab-notif-icon";
        icon.textContent = reasonIcon(n.reason);

        const body = document.createElement("div");
        body.className = "skylab-notif-body";

        const author = n.author?.handle || n.reasonSubject?.handle || "someone";
        const reasonText = n.reason === "like"
          ? "liked your post"
          : n.reason === "follow"
          ? "followed you"
          : n.reason === "reply"
          ? "replied to your post"
          : n.reason === "repost"
          ? "reposted your post"
          : n.reason === "quote"
          ? "quoted your post"
          : "interacted";

        const text = document.createElement("div");
        text.className = "skylab-notif-text";
        text.innerHTML = "<strong>" + author + "</strong> " + reasonText;

        if (n.record?.text) {
          const preview = document.createElement("div");
          preview.className = "skylab-notif-preview";
          preview.textContent = n.record.text.slice(0, 120);
          body.appendChild(preview);
        }

        body.insertBefore(text, body.firstChild);

        const meta = document.createElement("div");
        meta.className = "skylab-notif-time";
        meta.textContent = SkyLabPost.formatTimestamp(n.indexedAt || n.timestamp);

        if (n.author?.handle) {
          const profileLink = document.createElement("a");
          profileLink.className = "skylab-notif-profile-link";
          profileLink.href = "#/profile/" + n.author.handle;
          profileLink.textContent = "View profile";
          body.appendChild(profileLink);
        }

        item.appendChild(icon);
        item.appendChild(body);
        item.appendChild(meta);

        item.addEventListener("click", () => {
          if (n.author?.handle && !n.uri) {
            window.location.hash = "#/profile/" + n.author.handle;
          } else if (n.uri) {
            const parsed = SkyLabPost.parseUri(n.uri);
            if (parsed) window.location.hash = "#/thread/" + parsed.did + "/" + parsed.rkey;
          } else if (n.author?.handle) {
            window.location.hash = "#/profile/" + n.author.handle;
          }
        });

        list.appendChild(item);
      }
      container.appendChild(list);
    }

    async function load() {
      showLoading();
      const resp = await bridge.xrpc(
        "app.bsky.notification.listNotifications",
        { limit: 30 },
        null,
        { service: "appview", auth: true },
      );
      if (resp.ok) {
        notifs = Array.isArray(resp.data?.notifications) ? resp.data.notifications : [];
      }
      render();
    }

    bridge.on("auth_change", (auth) => {
      if (auth?.did) load();
      else {
        notifs = [];
        showEmpty();
      }
    });

    if (bridge.auth?.did) load();
    else showEmpty();

    const panel = document.getElementById("panel-notifications");
    if (panel) {
      const observer = new MutationObserver(() => {
        if (panel.classList.contains("active") && bridge.auth?.did && notifs.length === 0) {
          load();
        }
      });
      observer.observe(panel, { attributes: true, attributeFilter: ["class"] });
    }
  }

  global.initNotificationsPanel = initNotificationsPanel;
  if (typeof module !== "undefined" && module.exports) module.exports = { initNotificationsPanel };
})(typeof window !== "undefined" ? window : globalThis);
