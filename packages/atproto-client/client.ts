/** XRPC client wrapper for ATProto service communication. @module client */
import { TransportLayer, XrpcError } from "./transport.ts";
import type {
  LexiconQueryIds,
  LexiconProcedureIds,
  QueryParams,
  QueryOutput,
  ProcedureInput,
  ProcedureOutput,
} from "./lexicons.ts";
import {
  AccountsClient,
  AdminClient,
  AgeAssuranceClient,
  BlobsClient,
  ContactClient,
  DraftsClient,
  FeedClient,
  GraphClient,
  IdentityClient,
  NotificationsClient,
  RawClient,
  RecordsClient,
  SearchClient,
} from "./clients/index.ts";

/** Response snapshot recorded by {@link TransportLayer}. */
export interface TransportResponse {
  /** XRPC method or HTTP path used for the request. */
  method: string;
  /** HTTP response status. */
  status: number;
  /** Parsed response body or binary summary. */
  body: unknown;
  /** Unix timestamp in seconds when the response was recorded. */
  time: number;
}

/**
 * High-level XRPC client exposing sub-clients for every ATProto namespace.
 *
 * @example
 * ```ts
 * const client = new XrpcClient("http://localhost:2583");
 * await client.waitForHealthy();
 * const { data } = await client.agent.createAccount({
 *   handle: "alice.test",
 *   email: "alice@test.com",
 *   password: "password123",
 * });
 * ```
 */
export class XrpcClient {
  /** Low-level transport shared by all namespace clients. */
  public rawTransport: TransportLayer;

  /** Account creation, login, session, and service-description operations. */
  public accounts: AccountsClient;
  /** Handle resolution and identity-management operations. */
  public identity: IdentityClient;
  /** Repository record CRUD and write-batch operations. */
  public records: RecordsClient;
  /** Blob upload and retrieval operations. */
  public blobs: BlobsClient;
  /** Social graph operations such as follows, blocks, mutes, and lists. */
  public graph: GraphClient;
  /** Feed, timeline, actor, and post-read operations. */
  public feed: FeedClient;
  /** Notification and push-preference operations. */
  public notifications: NotificationsClient;
  /** Draft post operations. */
  public drafts: DraftsClient;
  /** Search and suggestion operations. */
  public search: SearchClient;
  /** Phone contact verification and import operations. */
  public contact: ContactClient;
  /** Age-assurance flow operations. */
  public ageAssurance: AgeAssuranceClient;
  /** Admin and moderation operations. */
  public admin: AdminClient;
  /** Raw HTTP and XRPC access for endpoints without a typed helper. */
  public raw: RawClient;

  /**
   * Invoke a typed XRPC query.
   * @param method The XRPC query method id.
   * @param params Query parameters.
   * @param token Optional auth token.
   */
  async query<K extends LexiconQueryIds>(
    method: K,
    params?: QueryParams<K>,
    token?: string
  ): Promise<QueryOutput<K>> {
    return await this.raw.query(method, params, token);
  }

  /**
   * Invoke a typed XRPC procedure.
   * @param method The XRPC procedure method id.
   * @param input Procedure input payload.
   * @param token Optional auth token.
   */
  async procedure<K extends LexiconProcedureIds>(
    method: K,
    input?: ProcedureInput<K>,
    token?: string
  ): Promise<ProcedureOutput<K>> {
    return await this.raw.procedure(method, input, token);
  }

  /**
   * Create an XrpcClient targeting the given PDS base URL.
   * @param baseUrl - Base service URL
   */
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

  /**
   * Log in as the admin user
   * @param password - The admin password
   * @defaultValue "test-admin-password"
   * @returns The access JWT
   */
  async adminLogin(password = "test-admin-password"): Promise<string> {
    return await this.admin.login(password);
  }

  /** The most recent response */
  get lastResponse(): TransportResponse | null {
    return this.rawTransport.lastResponse;
  }
  /** History of the last 20 responses */
  get lastResponses(): TransportResponse[] {
    return this.rawTransport.lastResponses;
  }

  #agentSession = new AgentSession();

  /** Dynamic proxy for authenticated XRPC method calls */
  get agent(): AgentProxy {
    const self = this;
    return createAgentProxy([], self, this.#agentSession);
  }

  /** Check if the service is responding at the health endpoint. */
  async healthCheck(): Promise<boolean> {
    try {
      const res = await fetch(`${this.baseUrl}/_health`);
      return res.status === 200;
    } catch {
      return false;
    }
  }

  /** Poll health until the service responds or the timeout is reached. */
  async waitForHealthy(timeout = 30): Promise<void> {
    const start = Date.now();
    while (Date.now() - start < timeout * 1000) {
      if (await this.healthCheck()) return;
      await new Promise((r) => setTimeout(r, 500));
    }
    throw new Error(`Service at ${this.baseUrl} not healthy after ${timeout}s`);
  }
}

/** Session credentials stored by the agent proxy after login/account creation. */
class AgentSession {
  accessJwt?: string;
  refreshJwt?: string;
  did?: string;
  handle?: string;
}

/** Resolve the bearer token for an agent call
 * @param opts - Invocation options that may include an Authorization header
 * @param session - Stored agent session credentials
 * @returns The bearer token or undefined
 */
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
 *
 * @remarks Method paths are built dynamically via property access, so the
 * index signature and call signature use `any`. Typed helpers exist on the
 * namespace clients (e.g. `client.accounts`, `client.graph`) for
 * discoverability and IDE support. Use the agent proxy when you need
 * ad-hoc authenticated calls to endpoints that lack a typed helper.
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
  [namespace: string]: any;
  /** Invoke the accumulated method path. */
  (
    params?: Record<string, any>,
    opts?: { headers?: Record<string, string> },
  ): Promise<{ data: any }>;
}

/** Create a dynamic proxy for authenticated XRPC method calls
 * @param path - The accumulated XRPC namespace path
 * @param client - The owning XRPC client
 * @param session - Stored agent session credentials
 * @returns A proxy that dispatches authenticated XRPC calls
 */
function createAgentProxy(path: string[], client: XrpcClient, session: AgentSession): AgentProxy {
  return new Proxy(function () {} as unknown as AgentProxy, {
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
