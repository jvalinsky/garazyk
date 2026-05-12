import { TransportLayer } from "../transport.ts";

export class IdentityClient {
  constructor(private transport: TransportLayer) {}

  async resolveHandle(handle: string) {
    return await this.transport.get("com.atproto.identity.resolveHandle", { handle });
  }

  async updateHandle(handle: string, token: string) {
    return await this.transport.post("com.atproto.identity.updateHandle", { handle }, token);
  }
}
