// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @abstract XRPC method routing logic
 * @discussion Determines which service handles a given XRPC method and
 * whether the method uses HTTP GET (lexicon query) or POST (procedure).
 * Mirrors the Python server.py routing functions.
 */

import { METHOD_ROUTES, APPVIEW_READ_METHODS } from "./config.ts";

/**
 * Determine which service handles a given XRPC method.
 *
 * Checks METHOD_ROUTES prefixes first, then APPVIEW_READ_METHODS,
 * then defaults to "pds".
 */
export function routeMethod(method: string): string {
  for (const [prefix, service] of Object.entries(METHOD_ROUTES)) {
    if (method.startsWith(prefix)) return service;
  }
  if (APPVIEW_READ_METHODS.has(method)) return "appview";
  return "pds";
}

/**
 * True when the XRPC method is a lexicon query (HTTP GET + query params).
 *
 * Match on the final NSID segment: app.bsky.feed.getTimeline → getTimeline.
 * Full-NSID prefix checks are wrong because NSIDs start with the domain.
 */
export function xrpcMethodUsesHttpGet(method: string): boolean {
  if (!method) return false;
  const seg = method.slice(method.lastIndexOf(".") + 1).toLowerCase();
  if (
    seg.startsWith("get") ||
    seg.startsWith("list") ||
    seg.startsWith("search") ||
    seg.startsWith("describe")
  ) {
    return true;
  }
  // resolve* queries (identity, lexicon); exclude procedures like admin.resolveReport
  if (seg.startsWith("resolve") && seg !== "resolvereport") {
    return true;
  }
  return false;
}
