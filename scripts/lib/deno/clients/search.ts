import { TransportLayer } from "../transport.ts";

export class SearchClient {
  constructor(private transport: TransportLayer) {}

  async searchActorsTypeahead(query: string, options: { token?: string; limit?: number } = {}) {
    return await this.transport.get(
      "app.bsky.actor.searchActorsTypeahead",
      { q: query, limit: options.limit ?? 10 },
      options.token
    );
  }

  async getSuggestions(token: string, limit = 25) {
    return await this.transport.get("app.bsky.actor.getSuggestions", { limit }, token);
  }

  async searchActorsSkeleton(query: string, options: { token?: string; limit?: number } = {}) {
    return await this.transport.get(
      "app.bsky.unspecced.searchActorsSkeleton",
      { q: query, limit: options.limit ?? 25 },
      options.token
    );
  }

  async searchPostsSkeleton(query: string, options: { token?: string; limit?: number } = {}) {
    return await this.transport.get(
      "app.bsky.unspecced.searchPostsSkeleton",
      { q: query, limit: options.limit ?? 25 },
      options.token
    );
  }

  async searchStarterPacksSkeleton(query: string, options: { token?: string; limit?: number } = {}) {
    return await this.transport.get(
      "app.bsky.unspecced.searchStarterPacksSkeleton",
      { q: query, limit: options.limit ?? 25 },
      options.token
    );
  }

  async getPreferences(token: string) {
    return await this.transport.get("app.bsky.actor.getPreferences", undefined, token);
  }

  async putPreferences(preferences: any[], token: string) {
    return await this.transport.post("app.bsky.actor.putPreferences", { preferences }, token);
  }
}
