import { TransportLayer } from "../transport.ts";

export class RecordsClient {
  constructor(private transport: TransportLayer) {}

  async createRecord(
    repo: string,
    collection: string,
    record: Record<string, any>,
    token: string,
    options: { rkey?: string; validate?: boolean } = {}
  ) {
    const body: Record<string, any> = {
      repo,
      collection,
      record,
      validate: options.validate ?? true,
    };
    if (options.rkey) body.rkey = options.rkey;
    return await this.transport.post("com.atproto.repo.createRecord", body, token);
  }

  async getRecord(repo: string, collection: string, rkey: string) {
    return await this.transport.get("com.atproto.repo.getRecord", {
      repo,
      collection,
      rkey,
    });
  }

  async deleteRecord(repo: string, collection: string, rkey: string, token: string) {
    return await this.transport.post(
      "com.atproto.repo.deleteRecord",
      { repo, collection, rkey },
      token
    );
  }

  async putRecord(
    repo: string,
    collection: string,
    rkey: string,
    record: Record<string, any>,
    token: string
  ) {
    return await this.transport.post(
      "com.atproto.repo.putRecord",
      { repo, collection, rkey, record },
      token
    );
  }

  async listRecords(
    repo: string,
    collection: string,
    options: { limit?: number; token?: string } = {}
  ) {
    return await this.transport.get(
      "com.atproto.repo.listRecords",
      { repo, collection, limit: options.limit ?? 50 },
      options.token
    );
  }

  async applyWrites(repo: string, writes: Array<Record<string, any>>, token: string) {
    return await this.transport.post(
      "com.atproto.repo.applyWrites",
      { repo, writes },
      token
    );
  }
}
