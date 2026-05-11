import { BskyAgent } from "@atproto/api";

export class XrpcError extends Error {
  constructor(public method: string, public status: number, public body: any) {
    super(`XRPC ${method} failed (${status}): ${typeof body === 'object' ? JSON.stringify(body) : body}`);
    this.name = "XrpcError";
  }
}

export class TransportLayer {
  private _base_url: string;
  private _last_responses: Array<{method: string, status: number, body: any, time: number}> = [];
  private _max_attempts = 3;
  private _base_delay = 1000;

  constructor(base_url = "http://localhost:2583") {
    this._base_url = base_url.replace(/\/$/, "");
  }

  get last_responses() {
    return [...this._last_responses];
  }

  get last_response() {
    return this._last_responses.length > 0 ? this._last_responses[this._last_responses.length - 1] : null;
  }

  private _record(method: string, status: number, body: any) {
    this._last_responses.push({ method, status, body, time: Date.now() / 1000 });
    if (this._last_responses.length > 20) {
      this._last_responses.shift();
    }
  }

  async request(method: string, url: string, options: RequestInit = {}): Promise<any> {
    const targetUrl = new URL(url, this._base_url);
    
    for (let attempt = 1; attempt <= this._max_attempts; attempt++) {
      try {
        const response = await fetch(targetUrl.toString(), options);
        let body: any;
        const text = await response.text();
        try {
          body = JSON.parse(text);
        } catch {
          body = text;
        }

        this._record(method, response.status, body);
        return { status: response.status, body };
      } catch (error) {
        if (attempt === this._max_attempts) throw error;
        await new Promise(r => setTimeout(r, this._base_delay * attempt));
      }
    }
  }

  async get(method: string, params?: Record<string, any>, token?: string) {
    const url = new URL(`/xrpc/${method}`, this._base_url);
    if (params) {
      for (const [k, v] of Object.entries(params)) {
        if (v !== undefined && v !== null) {
          if (Array.isArray(v)) {
            v.forEach(item => url.searchParams.append(k, String(item)));
          } else {
            url.searchParams.append(k, String(v));
          }
        }
      }
    }
    const headers: Record<string, string> = {};
    if (token) headers["Authorization"] = `Bearer ${token}`;

    const res = await this.request(method, url.toString(), { method: "GET", headers });
    if (res.status >= 400) {
      throw new XrpcError(method, res.status, res.body);
    }
    return res.body;
  }

  async post(method: string, body?: any, token?: string) {
    const url = new URL(`/xrpc/${method}`, this._base_url);
    const headers: Record<string, string> = { "Content-Type": "application/json" };
    if (token) headers["Authorization"] = `Bearer ${token}`;

    const res = await this.request(method, url.toString(), {
      method: "POST",
      headers,
      body: body ? JSON.stringify(body) : undefined,
    });
    if (res.status >= 400) {
      throw new XrpcError(method, res.status, res.body);
    }
    return res.body;
  }

  async postBinary(method: string, data: Uint8Array, contentType: string, token?: string) {
    const url = new URL(`/xrpc/${method}`, this._base_url);
    const headers: Record<string, string> = { "Content-Type": contentType };
    if (token) headers["Authorization"] = `Bearer ${token}`;

    const res = await this.request(method, url.toString(), {
      method: "POST",
      headers,
      body: data,
    });
    if (res.status >= 400) {
      throw new XrpcError(method, res.status, res.body);
    }
    return res.body;
  }
}
