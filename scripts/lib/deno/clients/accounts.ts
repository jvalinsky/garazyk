import { TransportLayer, XrpcError } from "../transport.ts";

export class AccountsClient {
  constructor(private transport: TransportLayer) {}

  async createAccount(handle: string, email: string, password: string, options: { retries?: number } = {}) {
    const retries = options.retries ?? 3;
    let lastError: any = null;

    for (let attempt = 1; attempt <= retries; attempt++) {
      try {
        return await this.transport.post("com.atproto.server.createAccount", {
          email,
          handle,
          password,
        });
      } catch (exc) {
        lastError = exc;
        if (exc instanceof XrpcError && exc.status === 400 && typeof exc.body === "object") {
          const msg = String(exc.body.message || "").toLowerCase();
          if (["network connection", "could not connect", "timed out"].some(s => msg.includes(s))) {
            if (attempt < retries) {
              await new Promise(r => setTimeout(r, 1000 * attempt));
              continue;
            }
          }
        }
        throw exc;
      }
    }
    throw lastError;
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

  async adminLogin(password: string): Promise<string> {
    const url = `${this.transport["_base_url"]}/admin/login`;
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ password }),
    });
    
    if (!res.ok) {
      throw new XrpcError("/admin/login", res.status, await res.text());
    }
    
    const data = await res.json();
    const token = data.token || data.ui_admin_token;
    if (!token) {
      throw new XrpcError("/admin/login", 200, { error: "missing token in response" });
    }
    return token;
  }
}
