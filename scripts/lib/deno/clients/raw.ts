import { TransportLayer } from "../transport.ts";

export class RawClient {
  constructor(private transport: TransportLayer) {}

  async httpGet(path: string, params?: Record<string, any>, token?: string) {
    return await this.transport.httpGet(path, params, token);
  }

  async httpPost(path: string, body?: any, token?: string) {
    return await this.transport.httpPost(path, body, token);
  }

  async xrpcGet(method: string, params?: Record<string, any>, token?: string) {
    return await this.transport.get(method, params, token);
  }

  async xrpcPost(method: string, body?: any, token?: string) {
    return await this.transport.post(method, body, token);
  }

  // Aliases for backward compatibility
  async get(method: string, params?: Record<string, any>, token?: string) {
    return await this.xrpcGet(method, params, token);
  }

  async post(method: string, body?: any, token?: string) {
    return await this.xrpcPost(method, body, token);
  }

  async postBinary(method: string, data: Uint8Array, contentType: string, token?: string) {
    return await this.transport.postBinary(method, data, contentType, token);
  }

  async postRaw(
    method: string,
    data: Uint8Array,
    contentType: string,
    options: { token?: string; params?: Record<string, any> } = {}
  ) {
    if (options.params && Object.keys(options.params).length > 0) {
      throw new Error("postRaw does not support params; use xrpcPost for parameterized requests");
    }
    return await this.transport.postBinary(method, data, contentType, options.token);
  }

  async xrpcGetBinary(
    method: string,
    options: { params?: Record<string, any>; token?: string; headers?: Record<string, string> } = {}
  ) {
    return await this.transport.getBinary(method, options.params, options.token, options.headers);
  }
}
