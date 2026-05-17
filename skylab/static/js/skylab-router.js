(function (global) {
  "use strict";

  class SkyLabRouter {
    constructor(options = {}) {
      this._routes = {};
      this._listeners = {};
      this._prevPanel = null;
      this._defaultRoute = options.defaultRoute || "timeline";

      window.addEventListener("hashchange", () => this._handleRoute());
    }

    on(route, callback) {
      if (!this._listeners[route]) {
        this._listeners[route] = [];
      }
      this._listeners[route].push(callback);
      return () => {
        this._listeners[route] = this._listeners[route].filter((cb) => cb !== callback);
      };
    }

    navigate(route, params = {}) {
      const hash = "#" + route +
        (Object.keys(params).length ? "/" + Object.values(params).join("/") : "");
      if (window.location.hash !== hash) {
        window.location.hash = hash;
      } else {
        this._dispatch(route, params);
      }
    }

    goBack() {
      window.history.back();
    }

    currentRoute() {
      return this._parseHash(window.location.hash);
    }

    _parseHash(hash) {
      const h = hash.replace(/^#/, "");
      if (!h) return { route: this._defaultRoute, params: {} };
      const parts = h.split("/").filter(Boolean);
      return { route: parts[0], params: parts.slice(1) };
    }

    _handleRoute() {
      const { route, params } = this._parseHash(window.location.hash);
      this._dispatch(route, params);
    }

    _dispatch(route, params) {
      const listeners = this._listeners[route] || [];
      for (const cb of listeners) {
        try {
          cb(params);
        } catch (e) {
          console.error("Router handler error:", e);
        }
      }
    }
  }

  global.SkyLabRouter = SkyLabRouter;
})(typeof window !== "undefined" ? window : globalThis);
