/** Age verification flows (begin, config, state) @module age_assurance */
import type { TransportLayer } from "../transport.ts";

/** Client for age-assurance flow XRPC methods. */
export class AgeAssuranceClient {
  /**
   * Constructs the age assurance client
   * @param transport - The transport layer for XRPC calls
   */
  constructor(private transport: TransportLayer) {}

  /**
   * Start age verification for a user
   * @param email - The user email
   * @param language - The preferred language
   * @param countryCode - The country code
   * @param options - Age verification options
   * @returns A promise that resolves to the verification response
   * @throws XrpcError if the request fails
   */
  async beginAgeAssurance(
    email: string,
    language: string,
    countryCode: string,
    options: { regionCode?: string; token?: string } = {},
  ): Promise<unknown> {
    const body: Record<string, unknown> = {
      email,
      language,
      countryCode,
    };
    if (options.regionCode) body.regionCode = options.regionCode;
    return await this.transport.post(
      "app.bsky.ageassurance.begin",
      body,
      options.token,
    );
  }

  /**
   * Get age assurance configuration
   * @param token - The authentication bearer token
   * @returns A promise that resolves to the configuration object
   * @throws XrpcError if the request fails
   */
  async getAgeAssuranceConfig(token?: string): Promise<unknown> {
    return await this.transport.get(
      "app.bsky.ageassurance.getConfig",
      undefined,
      token,
    );
  }

  /**
   * Get age verification state for a country
   * @param countryCode - The country code
   * @param options - Age verification options
   * @returns A promise that resolves to the state object
   * @throws XrpcError if the request fails
   */
  async getAgeAssuranceState(
    countryCode: string,
    options: { regionCode?: string; token?: string } = {},
  ): Promise<unknown> {
    const params: Record<string, unknown> = { countryCode };
    if (options.regionCode) params.regionCode = options.regionCode;
    return await this.transport.get(
      "app.bsky.ageassurance.getState",
      params,
      options.token,
    );
  }
}
