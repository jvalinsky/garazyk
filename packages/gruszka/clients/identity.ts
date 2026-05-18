/** Handle resolution and identity management @module identity */
import { TransportLayer } from "../transport.ts";

/** Client for handle resolution and identity-management XRPC methods. */
export class IdentityClient {
  /**
   * Constructs the identity client
   * @param transport - The transport layer for XRPC calls
   */
  constructor(private transport: TransportLayer) {}

  /**
   * Resolve a handle to a DID
   * @param handle - The handle to resolve
   * @returns A promise that resolves to the resolution response
   * @throws XrpcError if the request fails
   */
  async resolveHandle(handle: string): Promise<any> {
    return await this.transport.get("com.atproto.identity.resolveHandle", { handle });
  }

  /**
   * Update the authenticated user's handle
   * @param handle - The new handle to set
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the update response
   * @throws XrpcError if the request fails
   */
  async updateHandle(handle: string, token: string): Promise<any> {
    return await this.transport.post("com.atproto.identity.updateHandle", { handle }, token);
  }
}
