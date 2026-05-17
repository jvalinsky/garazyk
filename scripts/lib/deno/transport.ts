/**
 * XRPC transport layer with retry, error handling, and binary support.
 * @module transport
 */

/**
 * Error returned by an XRPC method when the server responds with a non-2xx status.
 * @remarks This error includes the status code and the response body from the server.
 */
export class XrpcError extends Error {
  /**
   * Constructs an XrpcError.
   * @param method - The XRPC method name
   * @param status - The HTTP status code
   * @param body - The response body
   */
  constructor(public method: string, public status: number, public body: any) {
    super(
      `XRPC ${method} failed (${status}): ${
        typeof body === "object" ? JSON.stringify(body) : body
      }`,
    );
    this.name = "XrpcError";
  }
}

/**
 * Error thrown when a transport-level (network) failure occurs.
 */
export class TransportError extends Error {
  /**
   * Constructs a TransportError.
   * @param method - The XRPC method name
   * @param url - The URL of the request
   * @param originalCause - The underlying error
   * @param attempt - The attempt number that failed
   */
  constructor(
    public readonly method: string,
    public readonly url: string,
    originalCause: unknown,
    public readonly attempt: number,
  ) {
    const causeMsg = originalCause instanceof Error ? originalCause.message : String(originalCause);
    super(`Transport ${method} ${url} failed (attempt ${attempt}): ${causeMsg}`);
    this.name = "TransportError";
    this.cause = originalCause;
  }
}

/** HTTP status codes that are safe to retry on (server errors + rate limiting). */
const DEFAULT_RETRYABLE_STATUSES = [429, 502, 503, 504];

/** Options controlling retry behavior for a transport request. */
export interface RequestOptions {
  /** Maximum number of attempts. @defaultValue 3 for GET, 1 for mutations. */
  maxRetries?: number;
  /** HTTP status codes that trigger a retry. @defaultValue [429, 502, 503, 504]. */
  retryableStatuses?: number[];
}

/**
 * Append query parameters to a URL.
 * @param url - The URL object to append params to
 * @param params - The query parameters object
 */
function appendQueryParams(url: URL, params?: Record<string, any>) {
  if (!params) return;
  for (const [k, v] of Object.entries(params)) {
    if (v !== undefined && v !== null) {
      if (Array.isArray(v)) {
        v.forEach((item) => url.searchParams.append(k, String(item)));
      } else {
        url.searchParams.append(k, String(v));
      }
    }
  }
}

/**
 * Handles HTTP requests with retries and authentication headers.
 *
 * @example
 * ```ts
 * const transport = new TransportLayer("http://localhost:2583");
 * const profile = await transport.get("app.bsky.actor.getProfile", { actor: "did:plc:..." }, token);
 * ```
 */
export class TransportLayer {
  private _baseUrl: string;
  private _lastResponses: Array<{ method: string; status: number; body: any; time: number }> = [];
  private _maxAttempts = 3;
  private _baseDelay = 1000;

  /**
   * Constructs the transport layer.
   * @param baseUrl - Base URL of the PDS
   */
  constructor(baseUrl = "http://localhost:2583") {
    this._baseUrl = baseUrl.replace(/\/$/, "");
  }

  /** The configured PDS base URL */
  get baseUrl(): string {
    return this._baseUrl;
  }

  /** History of the last 20 responses */
  get lastResponses(): Array<{ method: string; status: number; body: any; time: number }> {
    return [...this._lastResponses];
  }

  /** The most recent response */
  get lastResponse(): { method: string; status: number; body: any; time: number } | null {
    return this._lastResponses.length > 0
      ? this._lastResponses[this._lastResponses.length - 1]
      : null;
  }

  /**
   * Records a response in the history.
   * @param method - The method name
   * @param status - The HTTP status code
   * @param body - The response body
   */
  private _record(method: string, status: number, body: any): void {
    this._lastResponses.push({ method, status, body, time: Date.now() / 1000 });
    if (this._lastResponses.length > 20) {
      this._lastResponses.shift();
    }
  }

  /**
   * Execute an HTTP request with retry logic.
   * @param method - The XRPC method name
   * @param url - The full request URL
   * @param options - Fetch request options
   * @param transportOptions - Transport-specific retry options
   * @typeParam T - The expected response body type
   * @returns The HTTP status and response body
   * @throws TransportError if the max number of retries is exceeded
   */
  async request<T = any>(
    method: string,
    url: string,
    options: RequestInit = {},
    transportOptions?: RequestOptions,
  ): Promise<{ status: number; body: T }> {
    const targetUrl = new URL(url, this._baseUrl);

    // Mutations (POST, PUT, DELETE, PATCH) are not idempotent — don't retry by default.
    const httpMethod = (options.method || "GET").toUpperCase();
    const isIdempotent = /^(GET|HEAD|OPTIONS)$/.test(httpMethod);
    const maxAttempts = transportOptions?.maxRetries ?? (isIdempotent ? this._maxAttempts : 1);
    const retryableStatuses = transportOptions?.retryableStatuses ?? DEFAULT_RETRYABLE_STATUSES;

    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
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

        // Retry on retryable HTTP statuses (e.g. 429, 502, 503, 504)
        if (retryableStatuses.includes(response.status) && attempt < maxAttempts) {
          await new Promise((r) => setTimeout(r, this._baseDelay * attempt));
          continue;
        }

        return { status: response.status, body };
      } catch (error) {
        if (attempt === maxAttempts) {
          throw new TransportError(method, targetUrl.toString(), error, attempt);
        }
        await new Promise((r) => setTimeout(r, this._baseDelay * attempt));
      }
    }
    // Unreachable: the loop always returns or throws.
    throw new Error(`request: unreachable (maxAttempts=${maxAttempts})`);
  }

  /**
   * Perform an XRPC GET request.
   * @param method - The XRPC method name
   * @param params - Query parameters
   * @param token - Optional authorization bearer token
   * @typeParam T - The expected response body type
   * @returns The JSON response body
   * @throws XrpcError if the response status is >= 400
   */
  async get<T = any>(method: string, params?: Record<string, any>, token?: string): Promise<T> {
    const url = new URL(`/xrpc/${method}`, this._baseUrl);
    appendQueryParams(url, params);
    const headers: Record<string, string> = {};
    if (token) headers["Authorization"] = `Bearer ${token}`;

    const res = await this.request<T>(method, url.toString(), { method: "GET", headers });
    if (res.status >= 400) {
      throw new XrpcError(method, res.status, res.body);
    }
    return res.body;
  }

  /**
   * Perform an XRPC POST request.
   * @param method - The XRPC method name
   * @param body - The request body object
   * @param token - Optional authorization bearer token
   * @typeParam T - The expected response body type
   * @returns The JSON response body
   * @throws XrpcError if the response status is >= 400
   */
  async post<T = any>(method: string, body?: any, token?: string): Promise<T> {
    const url = new URL(`/xrpc/${method}`, this._baseUrl);
    const headers: Record<string, string> = { "Content-Type": "application/json" };
    if (token) headers["Authorization"] = `Bearer ${token}`;

    const res = await this.request<T>(method, url.toString(), {
      method: "POST",
      headers,
      body: body ? JSON.stringify(body) : undefined,
    });
    if (res.status >= 400) {
      throw new XrpcError(method, res.status, res.body);
    }
    return res.body;
  }

  /**
   * Perform an XRPC POST request with binary data.
   * @param method - The XRPC method name
   * @param data - The binary data as a Uint8Array
   * @param contentType - The MIME type for the request
   * @param token - Optional authorization bearer token
   * @typeParam T - The expected response body type
   * @returns The JSON response body
   * @throws XrpcError if the response status is >= 400
   */
  async postBinary<T = any>(
    method: string,
    data: Uint8Array,
    contentType: string,
    token?: string,
  ): Promise<T> {
    const url = new URL(`/xrpc/${method}`, this._baseUrl);
    const headers: Record<string, string> = { "Content-Type": contentType };
    if (token) headers["Authorization"] = `Bearer ${token}`;

    const res = await this.request<T>(method, url.toString(), {
      method: "POST",
      headers,
      body: data as BodyInit,
    });
    if (res.status >= 400) {
      throw new XrpcError(method, res.status, res.body);
    }
    return res.body;
  }

  /**
   * HTTP GET to an arbitrary path (not namespaced under /xrpc/).
   * @param path - The URL path
   * @param params - Optional query parameters
   * @param token - Optional authorization bearer token
   * @typeParam T - The expected response body type
   * @returns The response body
   * @throws XrpcError if the status is >= 400
   */
  async httpGet<T = any>(path: string, params?: Record<string, any>, token?: string): Promise<T> {
    const url = new URL(path, this._baseUrl);
    appendQueryParams(url, params);
    const headers: Record<string, string> = {};
    if (token) headers["Authorization"] = `Bearer ${token}`;

    const res = await this.request<T>(path, url.toString(), { method: "GET", headers });
    if (res.status >= 400) {
      throw new XrpcError(path, res.status, res.body);
    }
    return res.body;
  }

  /**
   * HTTP POST to an arbitrary path (not namespaced under /xrpc/).
   * @param path - The URL path
   * @param body - The body object
   * @param token - Optional authorization bearer token
   * @typeParam T - The expected response body type
   * @returns The response body
   * @throws XrpcError if the status is >= 400
   */
  async httpPost<T = any>(path: string, body?: any, token?: string): Promise<T> {
    const url = new URL(path, this._baseUrl);
    const headers: Record<string, string> = { "Content-Type": "application/json" };
    if (token) headers["Authorization"] = `Bearer ${token}`;

    const res = await this.request<T>(path, url.toString(), {
      method: "POST",
      headers,
      body: body ? JSON.stringify(body) : undefined,
    });
    if (res.status >= 400) {
      throw new XrpcError(path, res.status, res.body);
    }
    return res.body;
  }

  /**
   * Perform an XRPC GET request for binary data.
   * @param method - The XRPC method name
   * @param params - Query parameters
   * @param token - Optional authorization bearer token
   * @param headers - Additional headers
   * @returns A tuple of status code, content-type, and binary data
   * @throws TransportError if network fails
   */
  async getBinary(
    method: string,
    params?: Record<string, any>,
    token?: string,
    headers?: Record<string, string>,
  ): Promise<[number, string, Uint8Array]> {
    const url = new URL(`/xrpc/${method}`, this._baseUrl);
    appendQueryParams(url, params);
    const mergedHeaders: Record<string, string> = { ...headers };
    if (token) mergedHeaders["Authorization"] = `Bearer ${token}`;

    const maxAttempts = this._maxAttempts; // GET is idempotent — safe to retry
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        const response = await fetch(url.toString(), { method: "GET", headers: mergedHeaders });
        const data = await response.arrayBuffer();
        this._record(method, response.status, `binary: ${data.byteLength} bytes`);

        // Retry on retryable HTTP statuses
        if (DEFAULT_RETRYABLE_STATUSES.includes(response.status) && attempt < maxAttempts) {
          await new Promise((r) => setTimeout(r, this._baseDelay * attempt));
          continue;
        }

        return [
          response.status,
          response.headers.get("Content-Type") || "",
          new Uint8Array(data),
        ] as [number, string, Uint8Array];
      } catch (error) {
        if (attempt === maxAttempts) {
          throw new TransportError(method, url.toString(), error, attempt);
        }
        await new Promise((r) => setTimeout(r, this._baseDelay * attempt));
      }
    }
    throw new Error("getBinary: max retries exceeded");
  }
}
