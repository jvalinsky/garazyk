/** Phone contact verification, import, and sync @module contact */
import { TransportLayer } from "../transport.ts";

/** Client for phone contact verification, import, and sync XRPC methods. */
export class ContactClient {
  /**
   * Constructs the contact client
   * @param transport - The transport layer for XRPC calls
   */
  constructor(private transport: TransportLayer) {}

  /**
   * Start phone number verification (sends code)
   * @param phoneNumber - The phone number to verify
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the verification response
   * @throws XrpcError if the request fails
   */
  async startPhoneVerification(phoneNumber: string, token: string): Promise<any> {
    return await this.transport.post(
      "app.bsky.contact.startPhoneVerification",
      { phoneNumber },
      token,
    );
  }

  /**
   * Verify a phone number with the received code
   * @param phoneNumber - The phone number to verify
   * @param code - The verification code
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the verification response
   * @throws XrpcError if the request fails
   */
  async verifyPhone(phoneNumber: string, code: string, token: string): Promise<any> {
    return await this.transport.post(
      "app.bsky.contact.verifyPhone",
      { phoneNumber, code },
      token,
    );
  }

  /**
   * Import device contacts for social discovery
   * @param contacts - The list of contacts to import
   * @param importToken - The import token
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the import response
   * @throws XrpcError if the request fails
   */
  async importContacts(contacts: any[], importToken: string, token: string): Promise<any> {
    return await this.transport.post(
      "app.bsky.contact.importContacts",
      { token: importToken, contacts },
      token,
    );
  }

  /**
   * Get contact matches (imported contacts who are on the platform)
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the contact matches response
   * @throws XrpcError if the request fails
   */
  async getContactMatches(token: string): Promise<any> {
    return await this.transport.get("app.bsky.contact.getMatches", undefined, token);
  }

  /**
   * Dismiss a contact match suggestion
   * @param did - The DID of the contact to dismiss
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the dismissal response
   * @throws XrpcError if the request fails
   */
  async dismissContactMatch(did: string, token: string): Promise<any> {
    return await this.transport.post("app.bsky.contact.dismissMatch", { did }, token);
  }

  /**
   * Get contact sync status
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the sync status response
   * @throws XrpcError if the request fails
   */
  async getContactSyncStatus(token: string): Promise<any> {
    return await this.transport.get("app.bsky.contact.getSyncStatus", undefined, token);
  }

  /**
   * Remove all uploaded contact data
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the removal response
   * @throws XrpcError if the request fails
   */
  async removeContactData(token: string): Promise<any> {
    return await this.transport.post("app.bsky.contact.removeData", undefined, token);
  }
}
