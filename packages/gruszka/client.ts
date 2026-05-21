/** XRPC client wrapper for ATProto service communication. @module client */
import { TransportLayer, XrpcError } from "./transport.ts";
import type {
  GeneratedClient,
  LexiconProcedureIds,
  LexiconQueryIds,
  ProcedureInput,
  ProcedureOutput,
  QueryOutput,
  QueryParams,
  CallOptions,
  XrpcCaller,
} from "./generated_types.ts";
import {
  createGeneratedClient,
  LEXICON_METHOD_INPUT_ENCODINGS,
  LEXICON_METHOD_OUTPUT_ENCODINGS,
  LEXICON_METHOD_TYPES,
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
 * const { data } = await client.api.app.bsky.actor.getProfile({
 *   actor: "alice.test",
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
  /** Generated nested API client matching ATProto namespaces. */
  public api: GeneratedClient;

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
    this.api = createGeneratedClientHelper(t);
  }

  /**
   * Invoke a typed XRPC query.
   * @param method The XRPC query method id.
   * @param params Query parameters.
   * @param token Optional auth token.
   * @throws {XrpcError} If the service returns an error status.
   * @throws {TransportError} If a network or connection error occurs.
   */
  async query<K extends LexiconQueryIds>(
    method: K,
    params?: QueryParams<K>,
    token?: string,
  ): Promise<QueryOutput<K>>;
  async query(
    method: string,
    params?: Record<string, unknown>,
    token?: string,
  ): Promise<unknown>;
  async query(
    method: string,
    params?: Record<string, unknown>,
    token?: string,
  ): Promise<unknown> {
    return await this.raw.query(method, params, token);
  }

  /**
   * Invoke a typed XRPC procedure.
   * @param method The XRPC procedure method id.
   * @param input Procedure input payload.
   * @param token Optional auth token.
   * @throws {XrpcError} If the service returns an error status.
   * @throws {TransportError} If a network or connection error occurs.
   */
  async procedure<K extends LexiconProcedureIds>(
    method: K,
    input?: ProcedureInput<K>,
    token?: string,
  ): Promise<ProcedureOutput<K>>;
  async procedure(
    method: string,
    input?: unknown,
    token?: string,
  ): Promise<unknown>;
  async procedure(
    method: string,
    input?: unknown,
    token?: string,
  ): Promise<unknown> {
    return await this.raw.procedure(method, input, token);
  }

  /**
   * Returns a typed client instance that automatically includes the bearer token in every request.
   * @param token - The authentication bearer token
   * @returns A typed client instance
   */
  auth(token: string): GeneratedClient {
    return createGeneratedClientHelper(this.rawTransport, token);
  }

  /**
   * Log in as the admin user
   * @param password - The admin password
   * @defaultValue "test-admin-password"
   * @returns The access JWT
   * @throws {XrpcError} If the login fails.
   */
  async adminLogin(password = "test-admin-password"): Promise<string> {
    return await (this.admin as AdminClient).login(password);
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
    return createAgentProxy(self, this.#agentSession);
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

  /**
   * Poll health until the service responds or the timeout is reached.
   * @throws {Error} If the timeout is reached without a healthy response.
   */
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
function resolveToken(
  opts: { headers?: { Authorization?: string } } | undefined,
  session: AgentSession,
): string | undefined {
  if (opts?.headers?.Authorization) {
    return opts.headers.Authorization.replace(/^Bearer\s+/i, "");
  }
  return session.accessJwt;
}

function isQueryMethod(method: string): boolean {
  const methodType =
    LEXICON_METHOD_TYPES[method as keyof typeof LEXICON_METHOD_TYPES];
  if (methodType) return methodType === "query";
  return /^(get|list|resolve|describe)/i.test(method.split(".").pop() || "");
}

function outputEncodingFor(method: string): string {
  return LEXICON_METHOD_OUTPUT_ENCODINGS[
    method as keyof typeof LEXICON_METHOD_OUTPUT_ENCODINGS
  ] ?? "application/json";
}

function inputEncodingFor(method: string): string {
  return LEXICON_METHOD_INPUT_ENCODINGS[
    method as keyof typeof LEXICON_METHOD_INPUT_ENCODINGS
  ] ?? "application/json";
}

function isBinaryEncoding(encoding: string): boolean {
  return encoding !== "application/json";
}

function contentTypeForInputEncoding(encoding: string): string {
  return encoding === "*/*" ? "application/octet-stream" : encoding;
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
type WrapData<T> = T extends Promise<infer U> ? Promise<{ data: U }> : T;

type WrapClient<C> = {
  [K in keyof C]: C[K] extends (...args: infer A) => infer R
    ? (...args: A) => WrapData<R>
    : WrapClient<C[K]>;
};

export type AgentProxy = WrapClient<GeneratedClient> & {
  /** Allow dynamic namespace access for methods not yet in GeneratedClient. */
  [key: string]: any;
  /** Create a new account and store the session. */
  createAccount(params: {
    handle: string;
    email: string;
    password: string;
  }): Promise<{
    data: {
      accessJwt: string;
      refreshJwt: string;
      did: string;
      handle: string;
    };
  }>;
  /** Log in with existing credentials and store the session. */
  login(params: {
    identifier: string;
    password: string;
  }): Promise<{
    data: {
      accessJwt: string;
      refreshJwt: string;
      did: string;
      handle: string;
    };
  }>;
};

function extractToken(tokenOrOpts?: string | CallOptions): string | undefined {
  if (typeof tokenOrOpts === "string") return tokenOrOpts;
  return tokenOrOpts?.headers?.Authorization?.replace(/^Bearer\s+/i, "");
}

class RawCaller implements XrpcCaller {
  constructor(private transport: TransportLayer, private defaultToken?: string) {}

  async call(method: string, paramsOrInput?: any, tokenOrOpts?: string | CallOptions): Promise<any> {
    const finalToken = extractToken(tokenOrOpts) || this.defaultToken;
    const isQuery = isQueryMethod(method);

    if (isQuery) {
      if (isBinaryEncoding(outputEncodingFor(method))) {
        return await this.transport.getBinary(
          method,
          paramsOrInput as Record<string, unknown> | undefined,
          finalToken,
        );
      }
      return await this.transport.get(
        method,
        paramsOrInput as Record<string, unknown> | undefined,
        finalToken,
      );
    }

    const inputEncoding = inputEncodingFor(method);
    if (isBinaryEncoding(inputEncoding)) {
      return await this.transport.postBinary(
        method,
        paramsOrInput as Uint8Array,
        contentTypeForInputEncoding(inputEncoding),
        finalToken,
      );
    }
    return await this.transport.post(method, paramsOrInput, finalToken);
  }
}

class AgentCaller implements XrpcCaller {
  constructor(
    private transport: TransportLayer,
    private session: AgentSession,
  ) {}

  async call(method: string, paramsOrInput?: any, tokenOrOpts?: string | CallOptions): Promise<any> {
    const finalToken = extractToken(tokenOrOpts) || this.session.accessJwt;
    const isQuery = isQueryMethod(method);

    let data;
    if (isQuery) {
      if (isBinaryEncoding(outputEncodingFor(method))) {
        data = await this.transport.getBinary(
          method,
          paramsOrInput as Record<string, unknown> | undefined,
          finalToken,
        );
      } else {
        data = await this.transport.get(
          method,
          paramsOrInput as Record<string, unknown> | undefined,
          finalToken,
        );
      }
    } else {
      const inputEncoding = inputEncodingFor(method);
      if (isBinaryEncoding(inputEncoding)) {
        data = await this.transport.postBinary(
          method,
          paramsOrInput as Uint8Array,
          contentTypeForInputEncoding(inputEncoding),
          finalToken,
        );
      } else {
        data = await this.transport.post(method, paramsOrInput, finalToken);
      }
    }
    
    // Maintain the legacy `{ data }` wrapping for the AgentProxy
    return { data };
  }
}

/** Create a concrete client for authenticated XRPC method calls */
function createAgentProxy(
  client: XrpcClient,
  session: AgentSession,
): AgentProxy {
  const caller = new AgentCaller(client.rawTransport, session);
  const baseClient = createGeneratedClient(caller);
  
  return new Proxy(baseClient, {
    get(target, prop, receiver) {
      if (prop === "createAccount") {
        return async (params: {
          handle: string;
          email: string;
          password: string;
        }) => {
          const data = await (client.accounts as AccountsClient).createAccount(
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
          const data = await (client.accounts as AccountsClient).createSession(
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
      return Reflect.get(target, prop, receiver);
    },
    has(target, prop) {
      return prop === "createAccount" || prop === "login" || Reflect.has(target, prop);
    }
  }) as unknown as AgentProxy;
}

/** Create a nested concrete client that dispatches to the transport layer. */
function createGeneratedClientHelper(
  transport: TransportLayer,
  token?: string,
): GeneratedClient {
  const caller = new RawCaller(transport, token);
  return createGeneratedClient(caller);
}

export { XrpcError };

