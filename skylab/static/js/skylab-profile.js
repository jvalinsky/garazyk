(function (global) {
  "use strict";

  function initProfilePanel(bridge, router) {
    const container = document.getElementById("panel-profile");
    if (!container) return;

    let currentActor = null;
    let profileData = null;

    function showLoading() {
      container.innerHTML = '<div class="skylab-empty-state">Loading profile\u2026</div>';
    }

    function showError(msg) {
      container.innerHTML = '<div class="skylab-empty-state">' + msg + "</div>";
    }

    function renderProfile(actor) {
      showLoading();
      currentActor = actor;

      Promise.all([
        bridge.xrpc("app.bsky.actor.getProfile", { actor: actor }, null, {
          service: "appview",
          auth: !!bridge.auth,
        }),
        bridge.xrpc("app.bsky.feed.getAuthorFeed", { actor: actor, limit: 25 }, null, {
          service: "appview",
          auth: !!bridge.auth,
        }),
        bridge.xrpc("app.bsky.graph.getFollows", { actor: actor, limit: 50 }, null, {
          service: "appview",
          auth: !!bridge.auth,
        }),
        bridge.xrpc("app.bsky.graph.getFollowers", { actor: actor, limit: 50 }, null, {
          service: "appview",
          auth: !!bridge.auth,
        }),
      ]).then(([profileResp, feedResp, followsResp, followersResp]) => {
        if (!profileResp.ok) {
          showError("Profile not found");
          return;
        }
        profileData = profileResp.data;

        const feed = Array.isArray(feedResp.data?.feed) ? feedResp.data.feed : [];
        const follows = Array.isArray(followsResp.data?.follows) ? followsResp.data.follows : [];
        const followers = Array.isArray(followersResp.data?.followers)
          ? followersResp.data.followers
          : [];

        container.innerHTML = "";
        container.appendChild(buildHeader(profileData));
        container.appendChild(buildTabs(feed, follows, followers));
      }).catch(() => showError("Failed to load profile"));
    }

    function buildHeader(profile) {
      const section = document.createElement("div");
      section.className = "skylab-profile-header";

      const avatar = document.createElement("div");
      avatar.className = "skylab-profile-avatar-large";
      avatar.textContent = (profile.displayName || profile.handle || "?").slice(0, 2).toUpperCase();

      const name = document.createElement("div");
      name.className = "skylab-profile-name";
      name.textContent = profile.displayName || profile.handle || "";

      const handle = document.createElement("div");
      handle.className = "skylab-profile-handle";
      handle.textContent = "@" + (profile.handle || "");

      const desc = document.createElement("div");
      desc.className = "skylab-profile-description";
      desc.textContent = profile.description || "";

      const meta = document.createElement("div");
      meta.className = "skylab-profile-meta";

      const postsCount = document.createElement("span");
      postsCount.className = "skylab-profile-count";
      postsCount.innerHTML = "<strong>" + (profile.postsCount ?? 0) + "</strong> posts";

      const followsCount = document.createElement("span");
      followsCount.className = "skylab-profile-count";
      followsCount.innerHTML = "<strong>" + (profile.followsCount ?? 0) + "</strong> following";

      const followersCount = document.createElement("span");
      followersCount.className = "skylab-profile-count";
      followersCount.innerHTML = "<strong>" + (profile.followersCount ?? 0) + "</strong> followers";

      meta.appendChild(postsCount);
      meta.appendChild(followsCount);
      meta.appendChild(followersCount);

      section.appendChild(avatar);
      section.appendChild(name);
      section.appendChild(handle);
      if (profile.description) section.appendChild(desc);
      section.appendChild(meta);

      return section;
    }

    function buildTabs(feed, follows, followers) {
      const wrapper = document.createElement("div");
      wrapper.className = "skylab-profile-tabs";

      const tabBar = document.createElement("div");
      tabBar.className = "skylab-tab-bar";

      const tabs = [
        { id: "posts", label: "Posts", count: feed.length },
        { id: "follows", label: "Following", count: follows.length },
        { id: "followers", label: "Followers", count: followers.length },
      ];

      const content = document.createElement("div");
      content.className = "skylab-tab-content";

      let activeTab = "posts";

      function showTab(tabId) {
        activeTab = tabId;
        tabBar.querySelectorAll(".skylab-tab").forEach((t) =>
          t.classList.toggle("active", t.dataset.tab === tabId)
        );
        content.innerHTML = "";
        if (tabId === "posts") renderFeedTab(content, feed);
        else if (tabId === "follows") renderPeopleTab(content, follows);
        else if (tabId === "followers") renderPeopleTab(content, followers);
      }

      for (const t of tabs) {
        const tab = document.createElement("button");
        tab.className = "skylab-tab" + (t.id === activeTab ? " active" : "");
        tab.dataset.tab = t.id;
        tab.innerHTML = t.label + ' <span class="skylab-tab-count">' + t.count + "</span>";
        tab.addEventListener("click", () => showTab(t.id));
        tabBar.appendChild(tab);
      }

      wrapper.appendChild(tabBar);
      wrapper.appendChild(content);
      showTab("posts");
      return wrapper;
    }

    function renderFeedTab(container, feed) {
      if (feed.length === 0) {
        container.innerHTML = '<div class="skylab-empty-state">No posts yet</div>';
        return;
      }
      for (const item of feed) {
        const el = SkyLabPost.renderPost(item);
        if (el) container.appendChild(el);
      }
    }

    function renderPeopleTab(container, people) {
      if (people.length === 0) {
        container.innerHTML = '<div class="skylab-empty-state">None yet</div>';
        return;
      }
      for (const p of people) {
        const card = document.createElement("a");
        card.className = "skylab-person-card";
        card.href = "#/profile/" + (p.handle || p.did);
        card.innerHTML = '<div class="skylab-person-avatar">' +
          ((p.displayName || p.handle || "?").slice(0, 2).toUpperCase()) +
          '</div><div class="skylab-person-info"><div class="skylab-person-name">' +
          (p.displayName || p.handle || "Unknown") +
          '</div><div class="skylab-person-handle">@' + (p.handle || "") + "</div></div>";
        container.appendChild(card);
      }
    }

    router.on("profile", (params) => {
      const actor = params[0];
      if (actor) renderProfile(actor);
    });

    if (router.currentRoute().route === "profile") {
      const p = router.currentRoute().params;
      if (p[0]) renderProfile(p[0]);
    } else {
      showLoading();
    }
  }

  global.initProfilePanel = initProfilePanel;
  if (typeof module !== "undefined" && module.exports) module.exports = { initProfilePanel };
})(typeof window !== "undefined" ? window : globalThis);
