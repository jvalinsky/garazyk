import { type TransportLayer, XrpcError } from "../transport.ts";
import type { ProcedureOutput } from "../generated_types.ts";

/**
 * AT Protocol account management (create, session, deactivation).
 * @module accounts
 */
export class AccountsClient {
  /**
   * Constructs the accounts client.
   * @param transport - The transport layer for XRPC calls
   */
  constructor(private transport: TransportLayer) {}

  /**
   * Create a new account, falling back to session creation if already exists.
   * @param handle - The user handle
   * @param email - The user email
   * @param password - The user password
   * @returns A promise that resolves to the account creation response or session object
   * @throws XrpcError if the request fails
   */
  async createAccount(
    handle: string,
    email: string,
    password: string,
  ): Promise<ProcedureOutput<"com.atproto.server.createAccount">> {
    try {
      return await this.transport.post<
        ProcedureOutput<"com.atproto.server.createAccount">
      >("com.atproto.server.createAccount", {
        email,
        handle,
        password,
      });
    } catch (exc) {
      // If account already exists, just login to get a session
      if (exc instanceof XrpcError && exc.status === 400) {
        const body = exc.body as { message?: unknown } | null;
        const msg = String(body?.message || "").toLowerCase();
        if (msg.includes("already exists")) {
          return await this.createSession(handle, password);
        }
      }
      throw exc;
    }
  }

  /**
   * Create an authentication session with identifier and password.
   * @param identifier - The user handle or email
   * @param password - The user password
   * @returns A promise that resolves to the session object
   * @throws XrpcError if the request fails
   */
  async createSession(
    identifier: string,
    password: string,
  ): Promise<ProcedureOutput<"com.atproto.server.createSession">> {
    return await this.transport.post<
      ProcedureOutput<"com.atproto.server.createSession">
    >("com.atproto.server.createSession", {
      identifier,
      password,
    });
  }

  /**
   * Get current session info using an auth token.
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the session info object
   * @throws XrpcError if the request fails
   */
  async getSession(token: string): Promise<unknown> {
    return await this.transport.get(
      "com.atproto.server.getSession",
      undefined,
      token,
    );
  }

  /**
   * Refresh an expiring session using a refresh JWT.
   * @param refreshJwt - The refresh token
   * @returns A promise that resolves to the new session object
   * @throws XrpcError if the request fails
   */
  async refreshSession(refreshJwt: string): Promise<unknown> {
    return await this.transport.post(
      "com.atproto.server.refreshSession",
      undefined,
      refreshJwt,
    );
  }

  /**
   * Delete a session (logout). Best-effort; ignores errors.
   * @param token - The authentication bearer token
   * @returns A promise that resolves to void
   */
  async deleteSession(token: string): Promise<void> {
    try {
      await this.transport.post(
        "com.atproto.server.deleteSession",
        undefined,
        token,
      );
    } catch {
      // Best effort
    }
  }

  /**
   * Deactivate the authenticated account.
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the deactivation response
   * @throws XrpcError if the request fails
   */
  async deactivateAccount(token: string): Promise<unknown> {
    return await this.transport.post(
      "com.atproto.server.deactivateAccount",
      undefined,
      token,
    );
  }

  /**
   * Get server description (available methods, invited URLs, etc.).
   * @returns A promise that resolves to the server description object
   * @throws XrpcError if the request fails
   */
  async describeServer(): Promise<unknown> {
    return await this.transport.get("com.atproto.server.describeServer");
  }
}
