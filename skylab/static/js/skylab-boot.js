// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * SkyLab boot script — reads server-injected config and initializes the bridge.
 */
(async function () {
  // Read config from inline JSON script tag, or fetch from server
  let config = {};
  const configEl = document.getElementById("skylab-config");
  if (configEl) {
    try {
      config = JSON.parse(configEl.textContent);
    } catch (e) {
      console.warn("[skylab] Failed to parse inline config, fetching from server", e);
    }
  }

  if (!config.services) {
    try {
      const resp = await fetch("/skylab/api/config");
      if (resp.ok) config = await resp.json();
    } catch (e) {
      config.services = {
        pds: "http://127.0.0.1:2583",
        appview: "http://127.0.0.1:3200",
        relay: "http://127.0.0.1:2584",
        chat: "http://127.0.0.1:2585",
        video: "http://127.0.0.1:2586",
        germ: "http://127.0.0.1:8082",
        plc: "http://127.0.0.1:2582",
      };
    }
  }

  const bridge = new SkyLabBridge({
    services: config.services || {},
    videoServiceDid: config.videoServiceDid || "did:web:localhost",
    useProxy: true,
  });

  bridge.connectControlBridge();
  window.bridge = bridge;

  // Panel navigation
  document.querySelectorAll(".skylab-nav-item").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var panel = btn.dataset.panel;
      document
        .querySelectorAll(".skylab-nav-item")
        .forEach(function (b) { b.classList.remove("active"); });
      document
        .querySelectorAll(".skylab-panel")
        .forEach(function (p) { p.classList.remove("active"); });
      btn.classList.add("active");
      var panelEl = document.getElementById("panel-" + panel);
      if (panelEl) panelEl.classList.add("active");
    });
  });

  // Auth UI
  var loginOverlay = document.getElementById("login-overlay");
  var authLoggedOut = document.getElementById("auth-logged-out");
  var authLoggedIn = document.getElementById("auth-logged-in");
  var authHandle = document.getElementById("auth-handle");
  var authDid = document.getElementById("auth-did");

  function updateAuthUI(auth) {
    if (auth) {
      authLoggedOut.style.display = "none";
      authLoggedIn.style.display = "block";
      authHandle.textContent = auth.handle || "\u2014";
      authDid.textContent =
        auth.did ? auth.did.substring(0, 20) + "..." : "\u2014";
    } else {
      authLoggedOut.style.display = "block";
      authLoggedIn.style.display = "none";
    }
  }

  bridge.on("auth_change", updateAuthUI);

  document.getElementById("login-btn").addEventListener("click", function () {
    loginOverlay.style.display = "flex";
  });

  document.getElementById("login-cancel").addEventListener("click", function () {
    loginOverlay.style.display = "none";
  });

  document
    .getElementById("login-submit")
    .addEventListener("click", async function () {
      var identifier = document.getElementById("login-identifier").value.trim();
      var password = document.getElementById("login-password").value;
      var errorEl = document.getElementById("login-error");

      if (!identifier || !password) {
        errorEl.textContent = "Handle and password required";
        errorEl.style.display = "block";
        return;
      }

      errorEl.style.display = "none";
      var result = await bridge.login(identifier, password);
      if (!result.ok) {
        errorEl.textContent =
          (result.data && (result.data.message || result.data.detail || result.data.error)) ||
          "Login failed";
        errorEl.style.display = "block";
      } else {
        loginOverlay.style.display = "none";
      }
    });

  document.getElementById("logout-btn").addEventListener("click", function () {
    bridge.logout();
  });

  // Initialize panels
  initTimelinePanel(bridge);
  initChatPanel(bridge);
  initVideoPanel(bridge);
  initAdminPanel(bridge);
  initFirehosePanel(bridge);
})();
