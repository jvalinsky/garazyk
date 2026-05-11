import { BskyAgent } from "@atproto/api";
import { TransportLayer, XrpcError } from "./transport.ts";

export class XrpcClient {
  public agent: BskyAgent;
  public raw: TransportLayer;

  constructor(baseUrl = "http://localhost:2583") {
    this.agent = new BskyAgent({ service: baseUrl });
    this.raw = new TransportLayer(baseUrl);
  }

  get last_response() { return this.raw.last_response; }
  get last_responses() { return this.raw.last_responses; }
}

export { XrpcError };
