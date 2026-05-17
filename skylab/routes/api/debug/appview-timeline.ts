// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @abstract GET /skylab/api/debug/appview-timeline
 * @discussion GET AppView home timeline as JSON (for curl / checks without the browser).
 *
 * Example:
 *   TOKEN=$(curl -s -X POST .../createSession ... | jq -r .accessJwt)
 *   curl -s -H "Authorization: Bearer $TOKEN" \
 *     "http://127.0.0.1:2591/skylab/api/debug/appview-timeline?limit=10"
 */

import { Handlers } from "$fresh/server.ts";
import { SERVICE_URLS } from "../../../services/config.ts";

export const handler: Handlers = {
  async GET(req) {
    const auth = req.headers.get("Authorization") || "";
    if (!auth.startsWith("Bearer ")) {
      return Response.json(
        {
          ok: false,
          error: "expected Authorization: Bearer <accessJwt from PDS createSession>",
        },
        { status: 401 },
      );
    }

    const url = new URL(req.url);
    const limit = Math.max(1, Math.min(parseInt(url.searchParams.get("limit") || "25"), 100));
    const appview = SERVICE_URLS.appview;
    const targetUrl = `${appview}/xrpc/app.bsky.feed.getTimeline?limit=${limit}`;

    try {
      const resp = await fetch(targetUrl, {
        headers: { Authorization: auth },
      });

      const contentType = resp.headers.get("content-type") || "";
      let payload: unknown;

      if (contentType.includes("application/json")) {
        try {
          payload = await resp.json();
        } catch {
          payload = { raw: await resp.text() };
        }
      } else {
        payload = { raw: await resp.text() };
      }

      const feedLen = typeof payload === "object" && payload !== null &&
          Array.isArray((payload as Record<string, unknown>).feed)
        ? ((payload as Record<string, unknown>).feed as unknown[]).length
        : 0;

      return Response.json(
        {
          ok: resp.ok,
          upstreamStatus: resp.status,
          appview,
          feedItemCount: feedLen,
          xrpc: payload,
        },
        { status: resp.status },
      );
    } catch (err) {
      const detail = err instanceof Error ? err.message : String(err);
      return Response.json(
        { ok: false, error: "proxy_error", detail, message: detail },
        { status: 502 },
      );
    }
  },
};
