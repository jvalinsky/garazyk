import { BskyAgent } from "@atproto/api";

export class XrpcError extends Error {
  constructor(public method: string, public status: number, public body: any) {
    super(`XRPC ${method} failed (${status}): ${typeof body === 'object' ? JSON.stringify(body) : body}`);
    this.name = "XrpcError";
  }
}

export class TransportLayer {
  private _baseUrl: string;
  private _lastResponses: Array<{method: string, status: number, body: any, time: number}> = [];
  private _maxAttempts = 3;
  private _baseDelay = 1000;

  constructor(baseUrl = "http://localhost:2583") {
    this._baseUrl = baseUrl.replace(/\/$/, "");
  }

  get baseUrl(): string {
    return this._baseUrl;
  }

  get lastResponses() {
    return [...this._lastResponses];
  }

  get lastResponse() {
    return this._lastResponses.length > 0 ? this._lastResponses[this._lastResponses.length - 1] : null;
  }

  private _record(method: string, status: number, body: any) {
    this._lastResponses.push({ method, status, body, time: Date.now() / 1000 });
    if (this._lastResponses.length > 20) {
      this._lastResponses.shift();
    }
  }

  async request(method: string, url: string, options: RequestInit = {}): Promise<any> {
    const targetUrl = new URL(url, this._baseUrl);

    for (let attempt = 1; attempt <= this._maxAttempts; attempt++) {
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
        if (attempt === this._maxAttempts) throw error;
        await new Promise(r => setTimeout(r, this._baseDelay * attempt));
      }
    }
  }

  async get(method: string, params?: Record<string, any>, token?: string) {
    const url = new URL(`/xrpc/${method}`, this._baseUrl);
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
    const url = new URL(`/xrpc/${method}`, this._baseUrl);
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
    const url = new URL(`/xrpc/${method}`, this._baseUrl);
    const headers: Record<string, string> = { "Content-Type": contentType };
    if (token) headers["Authorization"] = `Bearer ${token}`;

    const res = await this.request(method, url.toString(), {
      method: "POST",
      headers,
      body: data as BodyInit,
    });
    if (res.status >= 400) {
      throw new XrpcError(method, res.status, res.body);
    }
    return res.body;
  }

  async httpGet(path: string, params?: Record<string, any>, token?: string) {
    const url = new URL(path, this._baseUrl);
    if (params) {
      for (const [k, v] of Object.entries(params)) {
        if (v !== undefined && v !== null) {
          url.searchParams.append(k, String(v));
        }
      }
    }
    const headers: Record<string, string> = {};
    if (token) headers["Authorization"] = `Bearer ${token}`;

    const res = await this.request(path, url.toString(), { method: "GET", headers });
    if (res.status >= 400) {
      throw new XrpcError(path, res.status, res.body);
    }
    return res.body;
  }

  async httpPost(path: string, body?: any, token?: string) {
    const url = new URL(path, this._baseUrl);
    const headers: Record<string, string> = { "Content-Type": "application/json" };
    if (token) headers["Authorization"] = `Bearer ${token}`;

    const res = await this.request(path, url.toString(), {
      method: "POST",
      headers,
      body: body ? JSON.stringify(body) : undefined,
    });
    if (res.status >= 400) {
      throw new XrpcError(path, res.status, res.body);
    }
    return res.body;
  }

  async getBinary(method: string, params?: Record<string, any>, token?: string, headers?: Record<string, string>) {
    const url = new URL(`/xrpc/${method}`, this._baseUrl);
    if (params) {
      for (const [k, v] of Object.entries(params)) {
        if (v !== undefined && v !== null) {
          url.searchParams.append(k, String(v));
        }
      }
    }
    const mergedHeaders: Record<string, string> = { ...headers };
    if (token) mergedHeaders["Authorization"] = `Bearer ${token}`;

    for (let attempt = 1; attempt <= this._maxAttempts; attempt++) {
      try {
        const response = await fetch(url.toString(), { method: "GET", headers: mergedHeaders });
        const data = await response.arrayBuffer();
        this._record(method, response.status, `binary: ${data.byteLength} bytes`);
        return [response.status, response.headers.get("Content-Type") || "", new Uint8Array(data)] as [number, string, Uint8Array];
      } catch (error) {
        if (attempt === this._maxAttempts) throw error;
        await new Promise(r => setTimeout(r, this._baseDelay * attempt));
      }
    }
    throw new Error("getBinary: max retries exceeded");
  }
}
