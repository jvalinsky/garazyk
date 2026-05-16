/** Social graph operations (follows, blocks, mutes, starter packs) @module graph */
import { TransportLayer } from "../transport.ts";

/** Client for social graph XRPC methods such as follows, blocks, mutes, and lists. */
export class GraphClient {
  /**
   * Constructs the graph client
   * @param transport - The transport layer for XRPC calls
   */
  constructor(private transport: TransportLayer) {}

  /**
   * Get actors followed by a given actor
   * @param actor - The actor's DID or handle
   * @param options - Options for retrieving follows
   * @returns A promise that resolves to the list of followed actors
   * @throws XrpcError if the request fails
   */
  async getFollows(actor: string, options: { token?: string; limit?: number } = {}): Promise<any> {
    return await this.transport.get(
      "app.bsky.graph.getFollows",
      { actor, limit: options.limit ?? 50 },
      options.token
    );
  }

  /**
   * Get followers of a given actor
   * @param actor - The actor's DID or handle
   * @param options - Options for retrieving followers
   * @returns A promise that resolves to the list of followers
   * @throws XrpcError if the request fails
   */
  async getFollowers(actor: string, options: { token?: string; limit?: number } = {}): Promise<any> {
    return await this.transport.get(
      "app.bsky.graph.getFollowers",
      { actor, limit: options.limit ?? 50 },
      options.token
    );
  }

  /**
   * Get actors blocked by the authenticated user
   * @param token - The authentication bearer token
   * @param limit - The maximum number of results to return
   * @returns A promise that resolves to the list of blocked actors
   * @throws XrpcError if the request fails
   */
  async getBlocks(token: string, limit = 50): Promise<any> {
    return await this.transport.get("app.bsky.graph.getBlocks", { limit }, token);
  }

  /**
   * Get actors muted by the authenticated user
   * @param token - The authentication bearer token
   * @param limit - The maximum number of results to return
   * @returns A promise that resolves to the list of muted actors
   * @throws XrpcError if the request fails
   */
  async getMutes(token: string, limit = 50): Promise<any> {
    return await this.transport.get("app.bsky.graph.getMutes", { limit }, token);
  }

  /**
   * Mute an actor by DID
   * @param actorDid - The actor's DID
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the mute response
   * @throws XrpcError if the request fails
   */
  async muteActor(actorDid: string, token: string): Promise<any> {
    return await this.transport.post("app.bsky.graph.muteActor", { actor: actorDid }, token);
  }

  /**
   * Unmute an actor by DID
   * @param actorDid - The actor's DID
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the unmute response
   * @throws XrpcError if the request fails
   */
  async unmuteActor(actorDid: string, token: string): Promise<any> {
    return await this.transport.post("app.bsky.graph.unmuteActor", { actor: actorDid }, token);
  }

  /**
   * Get relationships between an actor and target actors
   * @param actor - The actor's DID
   * @param targets - List of target actor DIDs
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the relationship object
   * @throws XrpcError if the request fails
   */
  async getRelationships(actor: string, targets: string[], token?: string): Promise<any> {
    return await this.transport.get(
      "app.bsky.graph.getRelationships",
      { actor, others: targets },
      token
    );
  }

  /**
   * Get a starter pack by URI
   * @param uri - The starter pack URI
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the starter pack object
   * @throws XrpcError if the request fails
   */
  async getStarterPack(uri: string, token?: string): Promise<any> {
    return await this.transport.get("app.bsky.graph.getStarterPack", { uri }, token);
  }

  /**
   * Get starter packs created by an actor
   * @param actor - The actor's DID
   * @param options - Options for retrieving starter packs
   * @returns A promise that resolves to the list of starter packs
   * @throws XrpcError if the request fails
   */
  async getActorStarterPacks(actor: string, options: { token?: string; limit?: number } = {}): Promise<any> {
    return await this.transport.get(
      "app.bsky.graph.getActorStarterPacks",
      { actor, limit: options.limit ?? 50 },
      options.token
    );
  }

  /**
   * Get multiple starter packs by URIs
   * @param uris - List of starter pack URIs
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the list of starter packs
   * @throws XrpcError if the request fails
   */
  async getStarterPacks(uris: string[], token?: string): Promise<any> {
    return await this.transport.get(
      "app.bsky.graph.getStarterPacks",
      { uris: uris.join(",") },
      token
    );
  }
}
