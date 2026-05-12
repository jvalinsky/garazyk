import { TransportLayer } from "../transport.ts";

export class DraftsClient {
  constructor(private transport: TransportLayer) {}

  async createDraft(content: Record<string, any>, token: string) {
    return await this.transport.post("app.bsky.draft.createDraft", { content }, token);
  }

  async updateDraft(draftId: string, content: Record<string, any>, token: string) {
    return await this.transport.post(
      "app.bsky.draft.updateDraft",
      { id: draftId, content },
      token
    );
  }

  async getDrafts(token: string) {
    return await this.transport.get("app.bsky.draft.getDrafts", undefined, token);
  }

  async deleteDraft(draftId: string, token: string) {
    return await this.transport.post("app.bsky.draft.deleteDraft", { id: draftId }, token);
  }
}
