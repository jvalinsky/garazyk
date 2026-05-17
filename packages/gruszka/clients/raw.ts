/** Raw HTTP/XRPC access (get, post, binary) for advanced use cases. @module raw */
import { TransportLayer } from "../transport.ts";
import type {
  LexiconQueryIds,
  LexiconProcedureIds,
  QueryParams,
  QueryOutput,
  ProcedureInput,
  ProcedureOutput,
} from "../lexicons.ts";

/** Client for raw HTTP and XRPC calls without a namespace-specific helper. */
export class RawClient {
  /**
   * Create a raw XRPC client
   * @param transport - The transport layer for XRPC calls
   */
  constructor(private transport: TransportLayer) {}

  /**
   * Invoke a typed XRPC query.
   * @param method The XRPC query method id.
   * @param params Query parameters.
   * @param token Optional auth token.
   */
  async query<K extends LexiconQueryIds>(
    method: K,
    params?: QueryParams<K>,
    token?: string
  ): Promise<QueryOutput<K>> {
    return (await this.transport.get(method, params as Record<string, any> | undefined, token)) as QueryOutput<K>;
  }

  /**
   * Invoke a typed XRPC procedure.
   * @param method The XRPC procedure method id.
   * @param input Procedure input payload.
   * @param token Optional auth token.
   */
  async procedure<K extends LexiconProcedureIds>(
    method: K,
    input?: ProcedureInput<K>,
    token?: string
  ): Promise<ProcedureOutput<K>> {
    return (await this.transport.post(method, input, token)) as ProcedureOutput<K>;
  }

  /**
   * Send a raw HTTP GET request
   * @param path - The request path
   * @param params - Optional query parameters
   * @param token - Optional bearer token
   * @returns The parsed response body
   * @throws Error if the request fails
   */
  async httpGet(path: string, params?: Record<string, any>, token?: string): Promise<unknown> {
    return await this.transport.httpGet(path, params, token);
  }

  /**
   * Send a raw HTTP POST request
   * @param path - The request path
   * @param body - Optional request body
   * @param token - Optional bearer token
   * @returns The parsed response body
   * @throws Error if the request fails
   */
  async httpPost(path: string, body?: any, token?: string): Promise<unknown> {
    return await this.transport.httpPost(path, body, token);
  }

  /**
   * Send an XRPC GET request
   * @param method - The XRPC method name
   * @param params - Optional query parameters
   * @param token - Optional bearer token
   * @returns The parsed response body
   * @throws Error if the request fails
   */
  async xrpcGet(method: string, params?: Record<string, any>, token?: string): Promise<unknown> {
    return await this.transport.get(method, params, token);
  }

  /**
   * Send an XRPC POST request
   * @param method - The XRPC method name
   * @param body - Optional request body
   * @param token - Optional bearer token
   * @returns The parsed response body
   * @throws Error if the request fails
   */
  async xrpcPost(method: string, body?: any, token?: string): Promise<unknown> {
    return await this.transport.post(method, body, token);
  }

  /**
   * Send an XRPC GET request
   * @deprecated Use {@link RawClient#xrpcGet} instead
   * @param method - The XRPC method name
   * @param params - Optional query parameters
   * @param token - Optional bearer token
   * @returns The parsed response body
   * @throws Error if the request fails
   */
  async get(method: string, params?: Record<string, any>, token?: string): Promise<unknown> {
    return await this.xrpcGet(method, params, token);
  }

  /**
   * Send an XRPC POST request
   * @deprecated Use {@link RawClient#xrpcPost} instead
   * @param method - The XRPC method name
   * @param body - Optional request body
   * @param token - Optional bearer token
   * @returns The parsed response body
   * @throws Error if the request fails
   */
  async post(method: string, body?: any, token?: string): Promise<unknown> {
    return await this.xrpcPost(method, body, token);
  }

  /**
   * Send an XRPC binary POST request
   * @param method - The XRPC method name
   * @param data - The binary payload
   * @param contentType - The payload content type
   * @param token - Optional bearer token
   * @returns The parsed response body
   * @throws Error if the request fails
   */
  async postBinary(
    method: string,
    data: Uint8Array,
    contentType: string,
    token?: string,
  ): Promise<unknown> {
    return await this.transport.postBinary(method, data, contentType, token);
  }

  /**
   * Send an XRPC binary POST request with raw options
   * @param method - The XRPC method name
   * @param data - The binary payload
   * @param contentType - The payload content type
   * @param options - Optional request options
   * @defaultValue {}
   * @returns The parsed response body
   * @throws Error if params are provided or the request fails
   */
  async postRaw(
    method: string,
    data: Uint8Array,
    contentType: string,
    options: { token?: string; params?: Record<string, any> } = {},
  ): Promise<unknown> {
    if (options.params && Object.keys(options.params).length > 0) {
      throw new Error("postRaw does not support params; use xrpcPost for parameterized requests");
    }
    return await this.transport.postBinary(method, data, contentType, options.token);
  }

  /**
   * Send an XRPC GET request that returns binary data
   * @param method - The XRPC method name
   * @param options - Optional request options
   * @defaultValue {}
   * @returns The binary response tuple
   * @throws Error if the request fails
   */
  async xrpcGetBinary(
    method: string,
    options: { params?: Record<string, any>; token?: string; headers?: Record<string, string> } =
      {},
  ): Promise<[number, string, Uint8Array]> {
    return await this.transport.getBinary(method, options.params, options.token, options.headers);
  }
}
