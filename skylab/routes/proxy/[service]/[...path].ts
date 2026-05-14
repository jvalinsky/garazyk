// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @abstract CORS proxy: /skylab/proxy/{service}/{path}
 * @discussion Proxy XRPC calls to the correct service, adding CORS headers.
 *
 * This avoids browser CORS issues during local development.
 * The browser can call /skylab/proxy/pds/xrpc/com.atproto.server.getSession
 * instead of http://localhost:2583/xrpc/... directly.
 */

import { Handlers } from "$fresh/server.ts";
import { proxyRequest, proxyPassthrough } from "../../../services/proxy.ts";

/**
 * Determine if a path should use binary passthrough instead of JSON proxy.
 * Video CDN assets (HLS playlists, TS segments, thumbnails) need raw streaming.
 */
function isPassthroughPath(service: string, path: string): boolean {
  if (service !== "video") return false;
  // Jelcz serves HLS at /watch/{did}/{cid}/...
  if (path.startsWith("watch/")) return true;
  return false;
}

export const handler: Handlers = {
  async GET(req, ctx) {
    const service = ctx.params.service;
    const path = ctx.params["...path"] || "";
    if (isPassthroughPath(service, path)) {
      return await proxyPassthrough(service, path, req);
    }
    return await proxyRequest(service, path, req);
  },

  async POST(req, ctx) {
    const service = ctx.params.service;
    const path = ctx.params["...path"] || "";
    return await proxyRequest(service, path, req);
  },

  async PUT(req, ctx) {
    const service = ctx.params.service;
    const path = ctx.params["...path"] || "";
    return await proxyRequest(service, path, req);
  },

  async DELETE(req, ctx) {
    const service = ctx.params.service;
    const path = ctx.params["...path"] || "";
    return await proxyRequest(service, path, req);
  },

  async OPTIONS(req, ctx) {
    const service = ctx.params.service;
    const path = ctx.params["...path"] || "";
    if (isPassthroughPath(service, path)) {
      // CORS preflight for video CDN
      return new Response(null, {
        status: 204,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET, OPTIONS",
          "Access-Control-Allow-Headers": "Authorization, Accept, Content-Type",
          "Access-Control-Max-Age": "86400",
        },
      });
    }
    return await proxyRequest(service, path, req);
  },
};
