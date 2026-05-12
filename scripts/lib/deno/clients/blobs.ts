import { TransportLayer } from "../transport.ts";

export class BlobsClient {
  constructor(private transport: TransportLayer) {}

  async uploadBlob(data: Uint8Array, contentType: string, token: string) {
    return await this.transport.postBinary("com.atproto.repo.uploadBlob", data, contentType, token);
  }
}
