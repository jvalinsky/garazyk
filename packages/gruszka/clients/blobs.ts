import { TransportLayer } from "../transport.ts";

/**
 * Binary blob upload operations.
 * @module blobs
 */
export class BlobsClient {
  /**
   * Constructs the blobs client.
   * @param transport - The transport layer for XRPC calls
   */
  constructor(private transport: TransportLayer) {}

  /**
   * Upload a binary blob.
   * @param data - The binary data to upload
   * @param contentType - The content type of the blob
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the blob upload response
   * @throws XrpcError if the request fails
   */
  async uploadBlob(data: Uint8Array, contentType: string, token: string): Promise<any> {
    return await this.transport.postBinary("com.atproto.repo.uploadBlob", data, contentType, token);
  }
}
