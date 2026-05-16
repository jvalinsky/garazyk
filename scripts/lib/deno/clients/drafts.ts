/** Draft post CRUD operations @module drafts */
import { TransportLayer } from "../transport.ts";

/** Client for draft post XRPC methods. */
export class DraftsClient {
  /**
   * Constructs the drafts client
   * @param transport - The transport layer for XRPC calls
   */
  constructor(private transport: TransportLayer) {}

  /**
   * Create a new draft post
   * @param content - The draft content
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the creation response
   * @throws XrpcError if the request fails
   */
  async createDraft(content: Record<string, any>, token: string): Promise<any> {
    return await this.transport.post("app.bsky.draft.createDraft", { content }, token);
  }

  /**
   * Update an existing draft
   * @param draftId - The ID of the draft to update
   * @param content - The updated draft content
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the update response
   * @throws XrpcError if the request fails
   */
  async updateDraft(draftId: string, content: Record<string, any>, token: string): Promise<any> {
    return await this.transport.post(
      "app.bsky.draft.updateDraft",
      { id: draftId, content },
      token
    );
  }

  /**
   * List all drafts for the authenticated user
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the list of drafts
   * @throws XrpcError if the request fails
   */
  async getDrafts(token: string): Promise<any> {
    return await this.transport.get("app.bsky.draft.getDrafts", undefined, token);
  }

  /**
   * Delete a draft by ID
   * @param draftId - The ID of the draft to delete
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the deletion response
   * @throws XrpcError if the request fails
   */
  async deleteDraft(draftId: string, token: string): Promise<any> {
    return await this.transport.post("app.bsky.draft.deleteDraft", { id: draftId }, token);
  }
}
