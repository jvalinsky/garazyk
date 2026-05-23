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

/**
 * Task: An actor creates a new post (status update).
 */
export async function postStatus(
  client: XrpcClient,
  actor: Actor,
  options: PostOptions,
): Promise<any> {
  const record: any = {
    $type: "app.bsky.feed.post",
    text: options.text,
    createdAt: new Date().toISOString(),
  };
  if (options.facets) record.facets = options.facets;
  if (options.reply) record.reply = options.reply;
  if (options.embed) record.embed = options.embed;

  // Utilize the new client.as(actor) binding:
  const res = await client.as(actor).raw.post("com.atproto.repo.createRecord", {
    repo: actor.did,
    collection: "app.bsky.feed.post",
    record,
  });
  return res;
}

/**
 * Task: An actor follows another user.
 */
export async function followUser(
  client: XrpcClient,
  follower: Actor,
  targetDid: string,
): Promise<any> {
  const res = await client.as(follower).raw.post("com.atproto.repo.createRecord", {
    repo: follower.did,
    collection: "app.bsky.graph.follow",
    record: {
      $type: "app.bsky.graph.follow",
      subject: targetDid,
      createdAt: new Date().toISOString(),
    },
  });
  return res;
}

/**
 * Task: An actor likes a target post.
 */
export async function likePost(
  client: XrpcClient,
  actor: Actor,
  targetPost: { uri: string; cid: string },
): Promise<any> {
  const res = await client.as(actor).raw.post("com.atproto.repo.createRecord", {
    repo: actor.did,
    collection: "app.bsky.feed.like",
    record: {
      $type: "app.bsky.feed.like",
      subject: targetPost,
      createdAt: new Date().toISOString(),
    },
  });
  return res;
}

/**
 * Task: An actor blocks another user.
 */
export async function blockUser(
  client: XrpcClient,
  actor: Actor,
  targetDid: string,
): Promise<any> {
  const res = await client.as(actor).raw.post("com.atproto.repo.createRecord", {
    repo: actor.did,
    collection: "app.bsky.graph.block",
    record: {
      $type: "app.bsky.graph.block",
      subject: targetDid,
      createdAt: new Date().toISOString(),
    },
  });
  return res;
}
