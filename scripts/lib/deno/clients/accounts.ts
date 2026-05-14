import { TransportLayer, XrpcError } from "../transport.ts";

export class AccountsClient {
  constructor(private transport: TransportLayer) {}

  async createAccount(handle: string, email: string, password: string) {
    try {
      return await this.transport.post("com.atproto.server.createAccount", {
        email,
        handle,
        password,
      });
    } catch (exc) {
      // If account already exists, just login to get a session
      if (exc instanceof XrpcError && exc.status === 400) {
        const msg = String(exc.body?.message || "").toLowerCase();
        if (msg.includes("already exists")) {
          return await this.createSession(handle, password);
        }
      }
      throw exc;
    }
  }

  async createSession(identifier: string, password: string) {
    return await this.transport.post("com.atproto.server.createSession", {
      identifier,
      password,
    });
  }

  async getSession(token: string) {
    return await this.transport.get("com.atproto.server.getSession", undefined, token);
  }

  async refreshSession(refreshJwt: string) {
    return await this.transport.post("com.atproto.server.refreshSession", undefined, refreshJwt);
  }

  async deleteSession(token: string) {
    try {
      await this.transport.post("com.atproto.server.deleteSession", undefined, token);
    } catch {
      // Best effort
    }
  }

  async deactivateAccount(token: string) {
    return await this.transport.post("com.atproto.server.deactivateAccount", undefined, token);
  }

  async describeServer() {
    return await this.transport.get("com.atproto.server.describeServer");
  }
}
