import { TransportLayer } from "../transport.ts";

export class FeedClient {
  constructor(private transport: TransportLayer) {}

  async getProfile(actor: string, token?: string) {
    return await this.transport.get("app.bsky.actor.getProfile", { actor }, token);
  }

  async getTimeline(token: string, limit = 50) {
    return await this.transport.get("app.bsky.feed.getTimeline", { limit }, token);
  }

  async getAuthorFeed(actor: string, options: { token?: string; limit?: number } = {}) {
    return await this.transport.get(
      "app.bsky.feed.getAuthorFeed",
      { actor, limit: options.limit ?? 50 },
      options.token
    );
  }

  async getPostThread(uri: string, token?: string) {
    return await this.transport.get("app.bsky.feed.getPostThread", { uri }, token);
  }

  async getLikes(uri: string, options: { token?: string; limit?: number } = {}) {
    return await this.transport.get(
      "app.bsky.feed.getLikes",
      { uri, limit: options.limit ?? 50 },
      options.token
    );
  }

  async searchActors(query: string, options: { token?: string; limit?: number } = {}) {
    return await this.transport.get(
      "app.bsky.actor.searchActors",
      { q: query, limit: options.limit ?? 10 },
      options.token
    );
  }

  async getActorLikes(actor: string, options: { token?: string; limit?: number } = {}) {
    return await this.transport.get(
      "app.bsky.feed.getActorLikes",
      { actor, limit: options.limit ?? 50 },
      options.token
    );
  }

  async getPosts(uris: string[], token?: string) {
    return await this.transport.get(
      "app.bsky.feed.getPosts",
      { uris: uris.join(",") },
      token
    );
  }

  async getRepostedBy(uri: string, options: { token?: string; limit?: number } = {}) {
    return await this.transport.get(
      "app.bsky.feed.getRepostedBy",
      { uri, limit: options.limit ?? 50 },
      options.token
    );
  }

  async getFeed(feedUri: string, token: string, limit = 50) {
    return await this.transport.get(
      "app.bsky.feed.getFeed",
      { feed: feedUri, limit },
      token
    );
  }

  async getFeedGenerators(uris: string[], token?: string) {
    return await this.transport.get(
      "app.bsky.feed.getFeedGenerators",
      { uris: uris.join(",") },
      token
    );
  }
}
