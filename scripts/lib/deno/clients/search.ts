/** Search and suggestion operations (actors, posts, starter packs, preferences) @module search */
import { TransportLayer } from "../transport.ts";

/** Client for search, typeahead, and suggestion XRPC methods. */
export class SearchClient {
  /**
   * Constructs the search client
   * @param transport - The transport layer for XRPC calls
   */
  constructor(private transport: TransportLayer) {}

  /**
   * Typeahead search for actors by query
   * @param query - Search query
   * @param options - Additional options (token, limit)
   * @returns A promise that resolves to the typeahead search results
   * @throws XrpcError if the request fails
   */
  async searchActorsTypeahead(query: string, options: { token?: string; limit?: number } = {}): Promise<any> {
    return await this.transport.get(
      "app.bsky.actor.searchActorsTypeahead",
      { q: query, limit: options.limit ?? 10 },
      options.token
    );
  }

  /**
   * Get suggested actors to follow
   * @param token - The authentication bearer token
   * @param limit - Max suggestions to return
   * @returns A promise that resolves to the actor suggestions
   * @throws XrpcError if the request fails
   */
  async getSuggestions(token: string, limit = 25): Promise<any> {
    return await this.transport.get("app.bsky.actor.getSuggestions", { limit }, token);
  }

  /**
   * Search actors using the skeleton search backend
   * @param query - Search query
   * @param options - Additional options (token, limit)
   * @returns A promise that resolves to the actor search skeleton results
   * @throws XrpcError if the request fails
   */
  async searchActorsSkeleton(query: string, options: { token?: string; limit?: number } = {}): Promise<any> {
    return await this.transport.get(
      "app.bsky.unspecced.searchActorsSkeleton",
      { q: query, limit: options.limit ?? 25 },
      options.token
    );
  }

  /**
   * Search posts using the skeleton search backend
   * @param query - Search query
   * @param options - Additional options (token, limit)
   * @returns A promise that resolves to the post search skeleton results
   * @throws XrpcError if the request fails
   */
  async searchPostsSkeleton(query: string, options: { token?: string; limit?: number } = {}): Promise<any> {
    return await this.transport.get(
      "app.bsky.unspecced.searchPostsSkeleton",
      { q: query, limit: options.limit ?? 25 },
      options.token
    );
  }

  /**
   * Search starter packs using the skeleton search backend
   * @param query - Search query
   * @param options - Additional options (token, limit)
   * @returns A promise that resolves to the starter packs search skeleton results
   * @throws XrpcError if the request fails
   */
  async searchStarterPacksSkeleton(query: string, options: { token?: string; limit?: number } = {}): Promise<any> {
    return await this.transport.get(
      "app.bsky.unspecced.searchStarterPacksSkeleton",
      { q: query, limit: options.limit ?? 25 },
      options.token
    );
  }

  /**
   * Get actor preferences
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the actor preferences
   * @throws XrpcError if the request fails
   */
  async getPreferences(token: string): Promise<any> {
    return await this.transport.get("app.bsky.actor.getPreferences", undefined, token);
  }

  /**
   * Set actor preferences
   * @param preferences - The list of preference objects
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the set preferences response
   * @throws XrpcError if the request fails
   */
  async putPreferences(preferences: any[], token: string): Promise<any> {
    return await this.transport.post("app.bsky.actor.putPreferences", { preferences }, token);
  }
}
