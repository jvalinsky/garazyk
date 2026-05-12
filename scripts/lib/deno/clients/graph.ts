import { TransportLayer } from "../transport.ts";

export class GraphClient {
  constructor(private transport: TransportLayer) {}

  async getFollows(actor: string, options: { token?: string; limit?: number } = {}) {
    return await this.transport.get(
      "app.bsky.graph.getFollows",
      { actor, limit: options.limit ?? 50 },
      options.token
    );
  }

  async getFollowers(actor: string, options: { token?: string; limit?: number } = {}) {
    return await this.transport.get(
      "app.bsky.graph.getFollowers",
      { actor, limit: options.limit ?? 50 },
      options.token
    );
  }

  async getBlocks(token: string, limit = 50) {
    return await this.transport.get("app.bsky.graph.getBlocks", { limit }, token);
  }

  async getMutes(token: string, limit = 50) {
    return await this.transport.get("app.bsky.graph.getMutes", { limit }, token);
  }

  async muteActor(actorDid: string, token: string) {
    return await this.transport.post("app.bsky.graph.muteActor", { actor: actorDid }, token);
  }

  async unmuteActor(actorDid: string, token: string) {
    return await this.transport.post("app.bsky.graph.unmuteActor", { actor: actorDid }, token);
  }

  async getRelationships(actor: string, targets: string[], token?: string) {
    return await this.transport.get(
      "app.bsky.graph.getRelationships",
      { actor, others: targets },
      token
    );
  }

  async getStarterPack(uri: string, token?: string) {
    return await this.transport.get("app.bsky.graph.getStarterPack", { uri }, token);
  }

  async getActorStarterPacks(actor: string, options: { token?: string; limit?: number } = {}) {
    return await this.transport.get(
      "app.bsky.graph.getActorStarterPacks",
      { actor, limit: options.limit ?? 50 },
      options.token
    );
  }

  async getStarterPacks(uris: string[], token?: string) {
    // Note: Python joins with comma, but XRPC usually expects repeated params.
    // However, some implementations might expect a single string.
    // I'll stick to what Python does if it's confirmed working.
    return await this.transport.get(
      "app.bsky.graph.getStarterPacks",
      { uris: uris.join(",") },
      token
    );
  }
}
