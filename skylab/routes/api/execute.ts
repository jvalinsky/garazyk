// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @abstract POST /skylab/api/execute
 * @discussion Execute an XRPC call via the connected browser client.
 *
 * The server forwards the command to the browser via WebSocket,
 * waits for the result, and returns it. This tests the actual
 * browser code path (CORS, DPoP, cookie handling, etc.).
 *
 * If no browser is connected, falls back to direct server-side
 * proxy (useful for headless testing).
 */

import { Handlers } from "$fresh/server.ts";
import { SERVICE_URLS } from "../../services/config.ts";
import { routeMethod, xrpcMethodUsesHttpGet } from "../../services/routing.ts";
import {
  dispatchCommand,
  getBrowserClientCount,
} from "../../services/control_bridge.ts";
import {
  parseProxyResponse,
  proxyUpstreamHeaders,
} from "../../services/proxy.ts";

export const handler: Handlers = {
  async POST(req: Request) {
    const body = await req.json();
    const method: string = body.method || "";
    const params: Record<string, string> = body.params || {};
    const xrpcBody: unknown = body.body;
    const service: string = body.service || routeMethod(method);

    // Try browser client first
    if (getBrowserClientCount() > 0) {
      try {
        const result = await dispatchCommand({
          method,
          params,
          body: xrpcBody,
          service,
        });
        return Response.json(result);
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        if (message.includes("No browser client")) {
          // Fall through to direct proxy
        } else if (message.includes("did not respond")) {
          return Response.json(
            { error: "timeout", detail: "Browser did not respond within 30s" },
            { status: 504 },
          );
        } else {
          return Response.json(
            { error: "browser_error", detail: message },
            { status: 500 },
          );
        }
      }
    }

    // Fallback: direct server-side proxy
    const targetUrl = SERVICE_URLS[service] || SERVICE_URLS.pds;
    const isQuery = xrpcMethodUsesHttpGet(method);
    const url = `${targetUrl}/xrpc/${method}`;

    const headers = proxyUpstreamHeaders(req);
    const authHeader: string | undefined = body.authorization;
    if (authHeader) {
      headers["Authorization"] = authHeader;
    }

    try {
      let resp: Response;

      if (isQuery && !xrpcBody) {
        resp = await fetch(`${url}?${new URLSearchParams(params)}`, {
          headers,
        });
      } else {
        headers["Content-Type"] = "application/json";
        resp = await fetch(url, {
          method: "POST",
          headers,
          body: JSON.stringify(xrpcBody || params),
        });
      }

      const payload = await parseProxyResponse(resp);
      return Response.json(payload, { status: resp.status });
    } catch (err) {
      const detail = err instanceof Error ? err.message : String(err);
      return Response.json(
        { error: "proxy_error", detail, message: detail },
        { status: 502 },
      );
    }
  },
};
