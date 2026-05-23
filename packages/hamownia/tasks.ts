/**
 * Screenplay-style task primitives for scenario testing.
 *
 * Tasks are simple, awaitable async functions that represent high-level
 * user actions (e.g., posting, following, liking) executing against an XRPC client.
 *
 * @module tasks
 */

import type { Actor } from "./actor.ts";
import type { XrpcClient } from "../../scripts/lib/deno/client.ts";

/** Options for creating a post task. */
export interface PostOptions {
  text: string;
  facets?: any[];
  reply?: any;
  embed?: any;
}

/** Options for creating a profile. */
export interface ProfileOptions {
  displayName?: string;
  description?: string;
  avatar?: string;
  banner?: string;
}

/**
 * Build a standard record with $type and createdAt.
 */
function record($type: string, extra: Record<string, unknown> = {}): Record<string, unknown> {
  return { $type, createdAt: new Date().toISOString(), ...extra };
}

/**
 * Task: An actor creates a new post (status update).
 *
 * @example
 * ```ts
 * await postStatus(client, luna, { text: "Hello!" });
 * await postStatus(client, luna, { text: "Reply", reply: { root, parent } });
 * ```
 */
export async function postStatus(
  client: XrpcClient,
  actor: Actor,
  options: PostOptions,
): Promise<any> {
  const r = record("app.bsky.feed.post", { text: options.text });
  if (options.facets) r.facets = options.facets;
  if (options.reply) r.reply = options.reply;
  if (options.embed) r.embed = options.embed;
  return await client.as(actor).repo.createRecord({ collection: "app.bsky.feed.post", record: r });
}

/**
 * Task: An actor follows another user.
 *
 * @example
 * ```ts
 * await followUser(client, marcus, luna.did);
 * ```
 */
export async function followUser(
  client: XrpcClient,
  follower: Actor,
  targetDid: string,
): Promise<any> {
  return await client.as(follower).repo.createRecord({
    collection: "app.bsky.graph.follow",
    record: record("app.bsky.graph.follow", { subject: targetDid }),
  });
}

/**
 * Task: An actor likes a target post.
 *
 * @example
 * ```ts
 * await likePost(client, luna, { uri: post.uri, cid: post.cid });
 * ```
 */
export async function likePost(
  client: XrpcClient,
  actor: Actor,
  targetPost: { uri: string; cid: string },
): Promise<any> {
  return await client.as(actor).repo.createRecord({
    collection: "app.bsky.feed.like",
    record: record("app.bsky.feed.like", { subject: targetPost }),
  });
}

/**
 * Task: An actor blocks another user.
 *
 * @example
 * ```ts
 * await blockUser(client, luna, troll.did);
 * ```
 */
export async function blockUser(
  client: XrpcClient,
  actor: Actor,
  targetDid: string,
): Promise<any> {
  return await client.as(actor).repo.createRecord({
    collection: "app.bsky.graph.block",
    record: record("app.bsky.graph.block", { subject: targetDid }),
  });
}

/**
 * Task: An actor creates or updates their profile.
 *
 * @example
 * ```ts
 * await createProfile(client, luna, { displayName: "Luna", description: "Astro nerd" });
 * ```
 */
export async function createProfile(
  client: XrpcClient,
  actor: Actor,
  profile: ProfileOptions,
): Promise<any> {
  return await client.as(actor).repo.createRecord({
    collection: "app.bsky.actor.profile",
    record: record("app.bsky.actor.profile", profile as Record<string, unknown>),
  });
}

/**
 * Task: An actor deletes a record by collection and rkey.
 *
 * @example
 * ```ts
 * await deleteRecord(client, luna, "app.bsky.feed.post", rkey);
 * ```
 */
export async function deleteRecord(
  client: XrpcClient,
  actor: Actor,
  collection: string,
  rkey: string,
): Promise<any> {
  return await client.as(actor).repo.deleteRecord({ collection, rkey });
}

/**
 * Task: An actor reposts (shares) a target post.
 *
 * @example
 * ```ts
 * await repost(client, marcus, { uri: post.uri, cid: post.cid });
 * ```
 */
export async function repost(
  client: XrpcClient,
  actor: Actor,
  targetPost: { uri: string; cid: string },
): Promise<any> {
  return await client.as(actor).repo.createRecord({
    collection: "app.bsky.feed.repost",
    record: record("app.bsky.feed.repost", { subject: targetPost }),
  });
}
