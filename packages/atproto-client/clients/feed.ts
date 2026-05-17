import { TransportLayer } from "../transport.ts";

/**
 * Feed, timeline, post thread, and actor profile operations.
 * @module feed
 */
export class FeedClient {
  /**
   * Constructs the feed client.
   * @param transport - The transport layer for XRPC calls
   */
  constructor(private transport: TransportLayer) {}

  /**
   * Get an actor's profile.
   * @param actor - The actor's DID or handle
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the profile object
   * @throws XrpcError if the request fails
   */
  async getProfile(actor: string, token?: string): Promise<any> {
    return await this.transport.get("app.bsky.actor.getProfile", { actor }, token);
  }

  /**
   * Get the authenticated user's timeline.
   * @param token - The authentication bearer token
   * @param limit - The maximum number of results to return
   * @returns A promise that resolves to the timeline feed
   * @throws XrpcError if the request fails
   */
  async getTimeline(token: string, limit = 50): Promise<any> {
    return await this.transport.get("app.bsky.feed.getTimeline", { limit }, token);
  }

  /**
   * Get an actor's authored feed posts.
   * @param actor - The actor's DID or handle
   * @param options - Feed options
   * @returns A promise that resolves to the author feed
   * @throws XrpcError if the request fails
   */
  async getAuthorFeed(
    actor: string,
    options: { token?: string; limit?: number } = {},
  ): Promise<any> {
    return await this.transport.get(
      "app.bsky.feed.getAuthorFeed",
      { actor, limit: options.limit ?? 50 },
      options.token,
    );
  }

  /**
   * Get a post thread by URI.
   * @param uri - The post URI
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the post thread
   * @throws XrpcError if the request fails
   */
  async getPostThread(uri: string, token?: string): Promise<any> {
    return await this.transport.get("app.bsky.feed.getPostThread", { uri }, token);
  }

  /**
   * Get likes for a post or record.
   * @param uri - The record URI
   * @param options - Options for retrieving likes
   * @returns A promise that resolves to the list of likes
   * @throws XrpcError if the request fails
   */
  async getLikes(uri: string, options: { token?: string; limit?: number } = {}): Promise<any> {
    return await this.transport.get(
      "app.bsky.feed.getLikes",
      { uri, limit: options.limit ?? 50 },
      options.token,
    );
  }

  /**
   * Search actors by query string.
   * @param query - The search query
   * @param options - Search options
   * @returns A promise that resolves to the list of matched actors
   * @throws XrpcError if the request fails
   */
  async searchActors(
    query: string,
    options: { token?: string; limit?: number } = {},
  ): Promise<any> {
    return await this.transport.get(
      "app.bsky.actor.searchActors",
      { q: query, limit: options.limit ?? 10 },
      options.token,
    );
  }

  /**
   * Get posts liked by an actor.
   * @param actor - The actor's DID or handle
   * @param options - Options for retrieving actor likes
   * @returns A promise that resolves to the list of posts liked by the actor
   * @throws XrpcError if the request fails
   */
  async getActorLikes(
    actor: string,
    options: { token?: string; limit?: number } = {},
  ): Promise<any> {
    return await this.transport.get(
      "app.bsky.feed.getActorLikes",
      { actor, limit: options.limit ?? 50 },
      options.token,
    );
  }

  /**
   * Get posts by their AT URIs.
   * @param uris - List of AT URIs
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the list of posts
   * @throws XrpcError if the request fails
   */
  async getPosts(uris: string[], token?: string): Promise<any> {
    return await this.transport.get(
      "app.bsky.feed.getPosts",
      { uris: uris.join(",") },
      token,
    );
  }

  /**
   * Get actors who reposted a post.
   * @param uri - The post URI
   * @param options - Options for retrieving reposts
   * @returns A promise that resolves to the list of actors who reposted
   * @throws XrpcError if the request fails
   */
  async getRepostedBy(uri: string, options: { token?: string; limit?: number } = {}): Promise<any> {
    return await this.transport.get(
      "app.bsky.feed.getRepostedBy",
      { uri, limit: options.limit ?? 50 },
      options.token,
    );
  }

  /**
   * Get a custom feed generator's feed.
   * @param feedUri - The feed generator URI
   * @param token - The authentication bearer token
   * @param limit - The maximum number of results to return
   * @returns A promise that resolves to the feed content
   * @throws XrpcError if the request fails
   */
  async getFeed(feedUri: string, token: string, limit = 50): Promise<any> {
    return await this.transport.get(
      "app.bsky.feed.getFeed",
      { feed: feedUri, limit },
      token,
    );
  }

  /**
   * Get feed generator details by URIs.
   * @param uris - List of feed generator URIs
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the list of feed generators
   * @throws XrpcError if the request fails
   */
  async getFeedGenerators(uris: string[], token?: string): Promise<any> {
    return await this.transport.get(
      "app.bsky.feed.getFeedGenerators",
      { uris: uris.join(",") },
      token,
    );
  }
}
