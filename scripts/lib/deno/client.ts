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
  public rawTransport: TransportLayer;

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
  public ageAssurance: AgeAssuranceClient;
  public admin: AdminClient;
  public raw: RawClient;

  constructor(public baseUrl = "http://localhost:2583") {
    const t = new TransportLayer(baseUrl);
    this.rawTransport = t;

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
    this.ageAssurance = new AgeAssuranceClient(t);
    this.admin = new AdminClient(t);
    this.raw = new RawClient(t);
  }

  async adminLogin(password = "test-admin-password"): Promise<string> {
    return await this.admin.login(password);
  }

  get lastResponse() { return this.rawTransport.lastResponse; }
  get lastResponses() { return this.rawTransport.lastResponses; }

  #agentSession = new AgentSession();

  get agent() {
    const self = this;
    return createAgentProxy([], self, this.#agentSession);
  }

  async healthCheck(): Promise<boolean> {
    try {
      const res = await fetch(`${this.baseUrl}/_health`);
      return res.status === 200;
    } catch {
      return false;
    }
  }

  async waitForHealthy(timeout = 30): Promise<void> {
    const start = Date.now();
    while (Date.now() - start < timeout * 1000) {
      if (await this.healthCheck()) return;
      await new Promise(r => setTimeout(r, 500));
    }
    throw new Error(`Service at ${this.baseUrl} not healthy after ${timeout}s`);
  }
}

class AgentSession {
  accessJwt?: string;
  refreshJwt?: string;
  did?: string;
  handle?: string;
}

function resolveToken(opts: any, session: AgentSession): string | undefined {
  if (opts?.headers?.Authorization) {
    return opts.headers.Authorization.replace(/^Bearer\s+/i, "");
  }
  return session.accessJwt;
}

/**
 * A dynamic proxy for XRPC method calls on an authenticated agent.
 *
 * Usage:
 *   await client.agent.createAccount({ handle, email, password });
 *   await client.agent.login({ identifier, password });
 *   await client.agent.com.atproto.repo.createRecord({ ... });
 *
 * The proxy builds method paths via property access and invokes them
 * via function call. Returns `{ data }` on success, throws on error.
 */
export interface AgentProxy {
  /** Create a new account and store the session. */
  createAccount(params: {
    handle: string;
    email: string;
    password: string;
  }): Promise<{ data: { accessJwt: string; refreshJwt: string; did: string; handle: string } }>;
  /** Log in with existing credentials and store the session. */
  login(params: {
    identifier: string;
    password: string;
  }): Promise<{ data: { accessJwt: string; refreshJwt: string; did: string; handle: string } }>;
  /** Access nested XRPC methods. */
  [namespace: string]: AgentProxy;
  /** Invoke the accumulated method path. */
  (params?: Record<string, any>, opts?: { headers?: Record<string, string> }): Promise<{ data: any }>;
}

function createAgentProxy(path: string[], client: XrpcClient, session: AgentSession): AgentProxy {
  return new Proxy(function () {}, {
    get(_target, prop: string) {
      if (typeof prop !== "string") return undefined;
      // Prevent the proxy from becoming accidentally thenable.
      // If code accesses .then on the proxy (e.g. await proxy or
      // Promise.resolve(proxy)), returning undefined ensures the
      // proxy is not treated as a Promise.
      if (prop === "then") return undefined;
      if (prop === "toJSON") return undefined;

      if (prop === "createAccount") {
        return async (params: {
          handle: string;
          email: string;
          password: string;
        }) => {
          const data = await client.accounts.createAccount(
            params.handle,
            params.email,
            params.password,
          );
          session.accessJwt = data.accessJwt;
          session.refreshJwt = data.refreshJwt;
          session.did = data.did;
          session.handle = data.handle;
          return { data };
        };
      }

      if (prop === "login") {
        return async (params: {
          identifier: string;
          password: string;
        }) => {
          const data = await client.accounts.createSession(
            params.identifier,
            params.password,
          );
          session.accessJwt = data.accessJwt;
          session.refreshJwt = data.refreshJwt;
          session.did = data.did;
          session.handle = data.handle;
          return { data };
        };
      }

      return createAgentProxy([...path, prop], client, session);
    },
    async apply(_target, _thisArg, args: any[]) {
      const method = path.join(".");
      const [params, opts] = args;
      const token = resolveToken(opts, session);

      const isQuery = /^(get|list|resolve|describe)/i.test(
        method.split(".").pop() || "",
      );

      const data = isQuery
        ? await client.rawTransport.get(method, params, token)
        : await client.rawTransport.post(method, params, token);
      return { data };
    },
  });
}

export { XrpcError };
