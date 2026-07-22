/** AT Protocol repository record operations (CRUD, list, applyWrites) @module records */
import type { TransportLayer } from "../transport.ts";

/** Client for repository record CRUD, listing, and write-batch XRPC methods. */
export class RecordsClient {
  /**
   * Constructs the records client
   * @param transport - The transport layer for XRPC calls
   */
  constructor(private transport: TransportLayer) {}

  /**
   * Create a new record in a repository collection
   * @param repo - The repo DID
   * @param collection - The collection name
   * @param record - The record data
   * @param token - The authentication bearer token
   * @param options - Additional options (rkey, validate)
   * @returns A promise that resolves to the record creation response
   * @throws XrpcError if the request fails
   */
  async createRecord(
    repo: string,
    collection: string,
    record: Record<string, any>,
    token: string,
    options: { rkey?: string; validate?: boolean } = {},
  ): Promise<any> {
    const body: Record<string, any> = {
      repo,
      collection,
      record,
      validate: options.validate ?? true,
    };
    if (options.rkey) body.rkey = options.rkey;
    return await this.transport.post(
      "com.atproto.repo.createRecord",
      body,
      token,
    );
  }

  /**
   * Get a record by repo, collection, and record key
   * @param repo - The repo DID
   * @param collection - The collection name
   * @param rkey - The record key
   * @returns A promise that resolves to the record
   * @throws XrpcError if the request fails
   */
  async getRecord(
    repo: string,
    collection: string,
    rkey: string,
  ): Promise<any> {
    return await this.transport.get("com.atproto.repo.getRecord", {
      repo,
      collection,
      rkey,
    });
  }

  /**
   * Delete a record
   * @param repo - The repo DID
   * @param collection - The collection name
   * @param rkey - The record key
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the deletion response
   * @throws XrpcError if the request fails
   */
  async deleteRecord(
    repo: string,
    collection: string,
    rkey: string,
    token: string,
  ): Promise<any> {
    return await this.transport.post(
      "com.atproto.repo.deleteRecord",
      { repo, collection, rkey },
      token,
    );
  }

  /**
   * Put (overwrite) a record at a specific rkey
   * @param repo - The repo DID
   * @param collection - The collection name
   * @param rkey - The record key
   * @param record - The record data
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the put record response
   * @throws XrpcError if the request fails
   */
  async putRecord(
    repo: string,
    collection: string,
    rkey: string,
    record: Record<string, any>,
    token: string,
  ): Promise<any> {
    return await this.transport.post(
      "com.atproto.repo.putRecord",
      { repo, collection, rkey, record },
      token,
    );
  }

  /**
   * List records in a collection
   * @param repo - The repo DID
   * @param collection - The collection name
   * @param options - Additional options (limit, token)
   * @returns A promise that resolves to the record list response
   * @throws XrpcError if the request fails
   */
  async listRecords(
    repo: string,
    collection: string,
    options: { limit?: number; token?: string } = {},
  ): Promise<any> {
    return await this.transport.get(
      "com.atproto.repo.listRecords",
      { repo, collection, limit: options.limit ?? 50 },
      options.token,
    );
  }

  /**
   * Apply a batch of writes (create, update, delete) to a repo
   * @param repo - The repo DID
   * @param writes - The list of write operations
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the batch write response
   * @throws XrpcError if the request fails
   */
  async applyWrites(
    repo: string,
    writes: Array<Record<string, any>>,
    token: string,
  ): Promise<any> {
    return await this.transport.post(
      "com.atproto.repo.applyWrites",
      { repo, writes },
      token,
    );
  }
}
