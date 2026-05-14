// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @abstract SkyLab service configuration
 * @discussion Environment-driven service URL map, method routing tables,
 * and appview read method set. Mirrors the Python server.py configuration.
 */

/** Server port (env SKYLAB_PORT, default 2591) */
export const SKYLAB_PORT = parseInt(Deno.env.get("SKYLAB_PORT") || "2591");

/** Server host (env SKYLAB_HOST, default 0.0.0.0) */
export const SKYLAB_HOST: string = Deno.env.get("SKYLAB_HOST") || "0.0.0.0";

/** Service URL map — each service's base URL */
export const SERVICE_URLS: Record<string, string> = {
  pds: Deno.env.get("PDS_URL") || "http://127.0.0.1:2583",
  appview: Deno.env.get("APPVIEW_URL") || "http://127.0.0.1:3200",
  relay: Deno.env.get("RELAY_URL") || "http://127.0.0.1:2584",
  chat: Deno.env.get("CHAT_URL") || "http://127.0.0.1:2585",
  video: Deno.env.get("VIDEO_URL") || "http://127.0.0.1:2586",
  germ: Deno.env.get("GERM_URL") || "http://127.0.0.1:8082",
  plc: Deno.env.get("PLC_URL") || "http://127.0.0.1:2582",
  ui: Deno.env.get("UI_URL") || "http://127.0.0.1:2590",
};

/** DID of the configured video service for direct browser uploads. */
export const VIDEO_SERVICE_DID: string = Deno.env.get("VIDEO_SERVICE_DID") ||
  Deno.env.get("JELCZ_DID") ||
  "did:web:localhost";

/** Method-to-service routing: NSID prefix → service name */
export const METHOD_ROUTES: Record<string, string> = {
  "chat.bsky": "chat",
  "app.bsky.video": "video",
  "com.germnetwork": "germ",
};

/** Read methods that should route to AppView instead of PDS */
export const APPVIEW_READ_METHODS: Set<string> = new Set([
  "app.bsky.feed.getTimeline",
  "app.bsky.feed.getAuthorFeed",
  "app.bsky.feed.getPostThread",
  "app.bsky.feed.getLikes",
  "app.bsky.feed.getRepostedBy",
  "app.bsky.feed.getPosts",
  "app.bsky.feed.getActorLikes",
  "app.bsky.feed.getFeed",
  "app.bsky.feed.getFeedGenerator",
  "app.bsky.feed.getFeedGenerators",
  "app.bsky.feed.getSuggestions",
  "app.bsky.actor.getProfile",
  "app.bsky.actor.getProfiles",
  "app.bsky.actor.searchActors",
  "app.bsky.actor.searchActorsTypeahead",
  "app.bsky.graph.getFollows",
  "app.bsky.graph.getFollowers",
  "app.bsky.graph.getBlocks",
  "app.bsky.graph.getMutes",
  "app.bsky.graph.getRelationships",
  "app.bsky.graph.getStarterPack",
  "app.bsky.graph.getActorStarterPacks",
  "app.bsky.graph.getStarterPacks",
  "app.bsky.graph.getList",
  "app.bsky.graph.getLists",
  "app.bsky.graph.getListMutes",
  "app.bsky.notification.listNotifications",
  "app.bsky.notification.getUnreadCount",
  "app.bsky.unspecced.searchActorsSkeleton",
  "app.bsky.unspecced.searchPostsSkeleton",
  "app.bsky.unspecced.searchStarterPacksSkeleton",
]);
