// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @abstract CORS proxy service
 * @discussion Forwards requests to upstream AT Protocol services with
 * filtered headers. Mirrors the Python server.py proxy logic including
 * the _PROXY_HEADER_ALLOW set and _proxy_upstream_headers function.
 */

import { SERVICE_URLS } from "./config.ts";

/**
 * Headers that are meaningful to forward upstream.
 *
 * Only forward headers that are meaningful upstream. Mirroring the entire
 * browser request can break fetch framing (e.g. Content-Length vs actual
 * body) or trip strict HTTP parsers on local services.
 */
const PROXY_HEADER_ALLOW = new Set([
  "authorization",
  "accept",
  "content-type",
  "user-agent",
  "atproto-accept-labelers",
  "atproto-proxy",
  "atproto-relay",
]);

/**
 * Extract upstream-safe headers from a request.
 * Adds a default Accept header if none is present.
 */
export function proxyUpstreamHeaders(req: Request): Record<string, string> {
  const headers: Record<string, string> = {};
  let hasAccept = false;

  for (const [key, value] of req.headers.entries()) {
    const lower = key.toLowerCase();
    if (PROXY_HEADER_ALLOW.has(lower)) {
      headers[key] = value;
      if (lower === "accept") hasAccept = true;
    }
  }

  if (!hasAccept) {
    headers["Accept"] = "application/json";
  }

  return headers;
}

export async function parseProxyResponse(resp: Response): Promise<unknown> {
  const contentType = resp.headers.get("content-type") || "";
  const text = await resp.text();

  if (contentType.includes("application/json")) {
    try {
      return JSON.parse(text);
    } catch {
      return { raw: text };
    }
  }

  return { raw: text };
}

/**
 * Proxy a request to the target service.
 *
 * @param service - Service name (must exist in SERVICE_URLS)
 * @param path - Path to append to the service base URL
 * @param req - Original browser request
 * @returns Response from the upstream service
 */
export async function proxyRequest(
  service: string,
  path: string,
  req: Request,
): Promise<Response> {
  const baseUrl = SERVICE_URLS[service];
  if (!baseUrl) {
    return Response.json(
      {
        error: "unknown_service",
        detail: `Service '${service}' not configured`,
      },
      { status: 400 },
    );
  }

  const target = new URL(`${baseUrl}/${path}`);
  // Preserve query string from original request
  const originalUrl = new URL(req.url);
  for (const [key, value] of originalUrl.searchParams.entries()) {
    target.searchParams.set(key, value);
  }

  const headers = proxyUpstreamHeaders(req);
  const body = req.method !== "GET" && req.method !== "HEAD" ? await req.arrayBuffer() : undefined;

  try {
    const resp = await fetch(target.toString(), {
      method: req.method,
      headers,
      body,
    });

    const payload = await parseProxyResponse(resp);
    return Response.json(payload, { status: resp.status });
  } catch (err) {
    const detail = err instanceof Error ? err.message : String(err);
    return Response.json(
      { error: "proxy_error", detail, message: detail },
      { status: 502 },
    );
  }
}

/**
 * Headers to pass through from upstream for binary passthrough responses.
 */
const PASSTHROUGH_RESPONSE_HEADERS = new Set([
  "content-type",
  "content-length",
  "cache-control",
  "content-range",
  "accept-ranges",
  "etag",
  "last-modified",
]);

/**
 * Proxy a request with binary passthrough — stream the upstream response
 * body directly without JSON wrapping. Used for video CDN assets
 * (HLS playlists, TS segments, thumbnails) where the browser needs
 * the raw bytes with correct content-type.
 *
 * @param service - Service name (must exist in SERVICE_URLS)
 * @param path - Path to append to the service base URL
 * @param req - Original browser request
 * @returns Streaming response from the upstream service
 */
export async function proxyPassthrough(
  service: string,
  path: string,
  req: Request,
): Promise<Response> {
  const baseUrl = SERVICE_URLS[service];
  if (!baseUrl) {
    return Response.json(
      {
        error: "unknown_service",
        detail: `Service '${service}' not configured`,
      },
      { status: 400 },
    );
  }

  const target = new URL(`${baseUrl}/${path}`);
  const originalUrl = new URL(req.url);
  for (const [key, value] of originalUrl.searchParams.entries()) {
    target.searchParams.set(key, value);
  }

  const headers = proxyUpstreamHeaders(req);
  const body = req.method !== "GET" && req.method !== "HEAD" ? await req.arrayBuffer() : undefined;

  try {
    const resp = await fetch(target.toString(), {
      method: req.method,
      headers,
      body,
    });

    // Forward relevant response headers
    const responseHeaders = new Headers();
    for (const [key, value] of resp.headers.entries()) {
      if (PASSTHROUGH_RESPONSE_HEADERS.has(key.toLowerCase())) {
        responseHeaders.set(key, value);
      }
    }
    // CORS headers for browser access
    responseHeaders.set("Access-Control-Allow-Origin", "*");
    responseHeaders.set("Access-Control-Allow-Methods", "GET, OPTIONS");

    return new Response(resp.body, {
      status: resp.status,
      headers: responseHeaders,
    });
  } catch (err) {
    const detail = err instanceof Error ? err.message : String(err);
    return Response.json(
      { error: "proxy_error", detail, message: detail },
      { status: 502 },
    );
  }
}
