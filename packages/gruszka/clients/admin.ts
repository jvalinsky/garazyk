/** Admin/moderation operations (subject status, reports, labels, login) @module admin */
import { TransportLayer, XrpcError } from "../transport.ts";

/** Client for admin and moderation XRPC methods. */
export class AdminClient {
  /**
   * Constructs the admin client
   * @param transport - The transport layer for XRPC calls
   */
  constructor(private transport: TransportLayer) {}

  /**
   * Get moderation status for a subject (DID)
   * @param did - The DID of the subject
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the subject status object
   * @throws XrpcError if the request fails
   */
  async getSubjectStatus(did: string, token: string): Promise<any> {
    return await this.transport.get("com.atproto.admin.getSubjectStatus", {
      did,
    }, token);
  }

  /**
   * Update moderation status (e.g. takedown) for a subject
   * @param subject - The subject record
   * @param options - Moderation update options
   * @returns A promise that resolves to the update response
   * @throws XrpcError if the request fails
   */
  async updateSubjectStatus(
    subject: Record<string, any>,
    options: { takedown?: Record<string, any>; token?: string } = {},
  ): Promise<any> {
    const body: Record<string, any> = { subject };
    if (options.takedown) body.takedown = options.takedown;
    return await this.transport.post(
      "com.atproto.admin.updateSubjectStatus",
      body,
      options.token,
    );
  }

  /**
   * Create a moderation report
   * @param reasonType - The type of report
   * @param subject - The subject record
   * @param reason - The reason for the report
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the report response
   * @throws XrpcError if the request fails
   */
  async createReport(
    reasonType: string,
    subject: Record<string, any>,
    reason: string,
    token: string,
  ): Promise<any> {
    return await this.transport.post(
      "com.atproto.moderation.createReport",
      { reasonType, subject, reason },
      token,
    );
  }

  /**
   * Get labels for the given AT URIs
   * @param uris - List of AT URIs
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the labels response
   * @throws XrpcError if the request fails
   */
  async getLabels(uris: string[], token?: string): Promise<any> {
    // Preserve repeated URI parameters for this legacy XRPC shape.
    const params: Record<string, any> = { "uris[]": uris };
    return await this.transport.get(
      "com.atproto.label.getLabels",
      params,
      token,
    );
  }

  /**
   * Authenticate as admin and return a session token
   * @param password - The admin password
   * @returns A promise that resolves to the admin token string
   * @throws XrpcError if the request fails
   */
  async login(password: string): Promise<string> {
    const url = `${this.transport.baseUrl}/admin/login`;
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ password }),
    });

    if (!res.ok) {
      throw new XrpcError("/admin/login", res.status, await res.text());
    }

    const data = await res.json();
    const token = data.token || data.ui_admin_token;
    if (!token) {
      throw new XrpcError("/admin/login", 200, {
        error: "missing token in response",
      });
    }
    return token;
  }
}
