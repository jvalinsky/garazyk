import { TransportLayer } from "../transport.ts";

export class AgeAssuranceClient {
  constructor(private transport: TransportLayer) {}

  async beginAgeAssurance(
    email: string,
    language: string,
    countryCode: string,
    options: { regionCode?: string; token?: string } = {}
  ) {
    const body: Record<string, any> = {
      email,
      language,
      countryCode,
    };
    if (options.regionCode) body.regionCode = options.regionCode;
    return await this.transport.post("app.bsky.ageassurance.begin", body, options.token);
  }

  async getAgeAssuranceConfig(token?: string) {
    return await this.transport.get("app.bsky.ageassurance.getConfig", undefined, token);
  }

  async getAgeAssuranceState(
    countryCode: string,
    options: { regionCode?: string; token?: string } = {}
  ) {
    const params: Record<string, any> = { countryCode };
    if (options.regionCode) params.regionCode = options.regionCode;
    return await this.transport.get("app.bsky.ageassurance.getState", params, options.token);
  }
}
