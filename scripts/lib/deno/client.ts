import { BskyAgent } from "@atproto/api";
import { TransportLayer, XrpcError } from "./transport.ts";
import {
  AccountsClient,
  IdentityClient,
  RecordsClient,
  BlobsClient,
  GraphClient,
  FeedClient,
  NotificationsClient,
  DraftsClient,
  SearchClient,
  ContactClient,
  AgeAssuranceClient,
  AdminClient,
  RawClient,
} from "./clients/index.ts";

export class XrpcClient {
  public agent: BskyAgent;
  public raw_transport: TransportLayer;

  public accounts: AccountsClient;
  public identity: IdentityClient;
  public records: RecordsClient;
  public blobs: BlobsClient;
  public graph: GraphClient;
  public feed: FeedClient;
  public notifications: NotificationsClient;
  public drafts: DraftsClient;
  public search: SearchClient;
  public contact: ContactClient;
  public age_assurance: AgeAssuranceClient;
  public admin: AdminClient;
  public raw: RawClient;

  constructor(public baseUrl = "http://localhost:2583") {
    const t = new TransportLayer(baseUrl);
    this.raw_transport = t;
    this.agent = new BskyAgent({ service: baseUrl });
    
    this.accounts = new AccountsClient(t);
    this.identity = new IdentityClient(t);
    this.records = new RecordsClient(t);
    this.blobs = new BlobsClient(t);
    this.graph = new GraphClient(t);
    this.feed = new FeedClient(t);
    this.notifications = new NotificationsClient(t);
    this.drafts = new DraftsClient(t);
    this.search = new SearchClient(t);
    this.contact = new ContactClient(t);
    this.age_assurance = new AgeAssuranceClient(t);
    this.admin = new AdminClient(t);
    this.raw = new RawClient(t);
  }

  async adminLogin(password = "test-admin-password"): Promise<string> {
    return await this.accounts.adminLogin(password);
  }

  get last_response() { return this.raw_transport.last_response; }
  get last_responses() { return this.raw_transport.last_responses; }

  async health_check(): Promise<boolean> {
    try {
      const res = await fetch(`${this.baseUrl}/_health`);
      return res.status === 200;
    } catch {
      return false;
    }
  }

  async wait_for_healthy(timeout = 30): Promise<void> {
    const start = Date.now();
    while (Date.now() - start < timeout * 1000) {
      if (await this.health_check()) return;
      await new Promise(r => setTimeout(r, 500));
    }
    throw new Error(`Service at ${this.baseUrl} not healthy after ${timeout}s`);
  }
}

export { XrpcError };
