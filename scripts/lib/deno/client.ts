import { BskyAgent } from "@atproto/api";
import { TransportLayer, XrpcError } from "./transport.ts";

export class XrpcClient {
  public agent: BskyAgent;
  public raw: TransportLayer;

  constructor(public baseUrl = "http://localhost:2583") {
    this.agent = new BskyAgent({ service: baseUrl });
    this.raw = new TransportLayer(baseUrl);
  }

  async adminLogin(password = "test-admin-password"): Promise<string> {
    const url = new URL("/admin/login", this.baseUrl);
    const res = await fetch(url.toString(), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ password })
    });
    if (!res.ok) {
      throw new Error(`Admin login failed: ${res.status} ${await res.text()}`);
    }
    const data = await res.json();
    return data.token;
  }

  get last_response() { return this.raw.last_response; }
  get last_responses() { return this.raw.last_responses; }
}

export { XrpcError };
