import { TransportLayer } from "../transport.ts";

export class ContactClient {
  constructor(private transport: TransportLayer) {}

  async startPhoneVerification(phoneNumber: string, token: string) {
    return await this.transport.post(
      "app.bsky.contact.startPhoneVerification",
      { phoneNumber },
      token
    );
  }

  async verifyPhone(phoneNumber: string, code: string, token: string) {
    return await this.transport.post(
      "app.bsky.contact.verifyPhone",
      { phoneNumber, code },
      token
    );
  }

  async importContacts(contacts: any[], importToken: string, token: string) {
    return await this.transport.post(
      "app.bsky.contact.importContacts",
      { token: importToken, contacts },
      token
    );
  }

  async getContactMatches(token: string) {
    return await this.transport.get("app.bsky.contact.getMatches", undefined, token);
  }

  async dismissContactMatch(did: string, token: string) {
    return await this.transport.post("app.bsky.contact.dismissMatch", { did }, token);
  }

  async getContactSyncStatus(token: string) {
    return await this.transport.get("app.bsky.contact.getSyncStatus", undefined, token);
  }

  async removeContactData(token: string) {
    return await this.transport.post("app.bsky.contact.removeData", undefined, token);
  }
}
