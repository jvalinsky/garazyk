/** Search and suggestion operations (actors, posts, starter packs, preferences) @module search */
import type { ProcedureOutput, QueryOutput } from "../lexicons.ts";
import type { TransportLayer } from "../transport.ts";

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
  async searchActorsTypeahead(
    query: string,
    options: { token?: string; limit?: number } = {},
  ): Promise<QueryOutput<"app.bsky.actor.searchActorsTypeahead">> {
    return await this.transport.get<
      QueryOutput<"app.bsky.actor.searchActorsTypeahead">
    >(
      "app.bsky.actor.searchActorsTypeahead",
      { q: query, limit: options.limit ?? 10 },
      options.token,
    );
  }

  /**
   * Get suggested actors to follow
   * @param token - The authentication bearer token
   * @param limit - Max suggestions to return
   * @returns A promise that resolves to the actor suggestions
   * @throws XrpcError if the request fails
   */
  async getSuggestions(
    token: string,
    limit = 25,
  ): Promise<QueryOutput<"app.bsky.actor.getSuggestions">> {
    return await this.transport.get<
      QueryOutput<"app.bsky.actor.getSuggestions">
    >(
      "app.bsky.actor.getSuggestions",
      { limit },
      token,
    );
  }

  /**
   * Search actors using the skeleton search backend
   * @param query - Search query
   * @param options - Additional options (token, limit)
   * @returns A promise that resolves to the actor search skeleton results
   * @throws XrpcError if the request fails
   */
  async searchActorsSkeleton(
    query: string,
    options: { token?: string; limit?: number } = {},
  ): Promise<QueryOutput<"app.bsky.unspecced.searchActorsSkeleton">> {
    return await this.transport.get<
      QueryOutput<"app.bsky.unspecced.searchActorsSkeleton">
    >(
      "app.bsky.unspecced.searchActorsSkeleton",
      { q: query, limit: options.limit ?? 25 },
      options.token,
    );
  }

  /**
   * Search posts using the skeleton search backend
   * @param query - Search query
   * @param options - Additional options (token, limit)
   * @returns A promise that resolves to the post search skeleton results
   * @throws XrpcError if the request fails
   */
  async searchPostsSkeleton(
    query: string,
    options: { token?: string; limit?: number } = {},
  ): Promise<QueryOutput<"app.bsky.unspecced.searchPostsSkeleton">> {
    return await this.transport.get<
      QueryOutput<"app.bsky.unspecced.searchPostsSkeleton">
    >(
      "app.bsky.unspecced.searchPostsSkeleton",
      { q: query, limit: options.limit ?? 25 },
      options.token,
    );
  }

  /**
   * Search starter packs using the skeleton search backend
   * @param query - Search query
   * @param options - Additional options (token, limit)
   * @returns A promise that resolves to the starter packs search skeleton results
   * @throws XrpcError if the request fails
   */
  async searchStarterPacksSkeleton(
    query: string,
    options: { token?: string; limit?: number } = {},
  ): Promise<QueryOutput<"app.bsky.unspecced.searchStarterPacksSkeleton">> {
    return await this.transport.get<
      QueryOutput<"app.bsky.unspecced.searchStarterPacksSkeleton">
    >(
      "app.bsky.unspecced.searchStarterPacksSkeleton",
      { q: query, limit: options.limit ?? 25 },
      options.token,
    );
  }

  /**
   * Get actor preferences
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the actor preferences
   * @throws XrpcError if the request fails
   */
  async getPreferences(
    token: string,
  ): Promise<QueryOutput<"app.bsky.actor.getPreferences">> {
    return await this.transport.get<
      QueryOutput<"app.bsky.actor.getPreferences">
    >(
      "app.bsky.actor.getPreferences",
      undefined,
      token,
    );
  }

  /**
   * Set actor preferences
   * @param preferences - The list of preference objects
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the set preferences response
   * @throws XrpcError if the request fails
   */
  async putPreferences(
    preferences: Array<Record<string, unknown>>,
    token: string,
  ): Promise<ProcedureOutput<"app.bsky.actor.putPreferences">> {
    return await this.transport.post<
      ProcedureOutput<"app.bsky.actor.putPreferences">
    >(
      "app.bsky.actor.putPreferences",
      { preferences },
      token,
    );
  }
}
