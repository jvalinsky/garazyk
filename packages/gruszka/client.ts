/** XRPC client wrapper for ATProto service communication. @module client */
import { TransportLayer, XrpcError } from "./transport.ts";
import type {
  CallOptions,
  GeneratedClient,
  LexiconProcedureIds,
  LexiconQueryIds,
  ProcedureInput,
  ProcedureOutput,
  QueryOutput,
  QueryParams,
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

/** Raw XRPC/HTTP methods bound to an actor's bearer token. */
export interface ActorRawClient {
  /** Send an XRPC GET (deprecated — prefer xrpcGet). */
  get(method: string, params?: Record<string, unknown>): Promise<unknown>;
  /** Send an XRPC POST (deprecated — prefer xrpcPost). */
  post(method: string, body?: unknown): Promise<unknown>;
  /** Send an XRPC query. */
  query(method: string, params?: Record<string, unknown>): Promise<unknown>;
  /** Send an XRPC procedure. */
  procedure(method: string, body?: unknown): Promise<unknown>;
  /** Send a raw HTTP GET request. */
  httpGet(path: string, params?: Record<string, unknown>): Promise<unknown>;
  /** Send a raw HTTP POST request. */
  httpPost(path: string, body?: unknown): Promise<unknown>;
  /** Send an XRPC GET request. */
  xrpcGet(method: string, params?: Record<string, unknown>): Promise<unknown>;
  /** Send an XRPC POST request. */
  xrpcPost(method: string, body?: unknown): Promise<unknown>;
  /** Send an XRPC binary POST request. */
  postBinary(
    method: string,
    data: Uint8Array,
    contentType: string,
  ): Promise<unknown>;
}

/** Repository record CRUD operations bound to an actor's DID and token. */
export interface ActorRepoClient {
  /** Create a record in the actor's repo. */
  createRecord(params: Record<string, unknown>): Promise<unknown>;
  /** Get a record from the actor's repo. */
  getRecord(params: Record<string, unknown>): Promise<unknown>;
  /** Put (replace) a record in the actor's repo. */
  putRecord(params: Record<string, unknown>): Promise<unknown>;
  /** Delete a record from the actor's repo. */
  deleteRecord(params: Record<string, unknown>): Promise<unknown>;
  /** Apply batch writes to the actor's repo. */
  applyWrites(params: Record<string, unknown>): Promise<unknown>;
  /** List records in the actor's repo collection. */
  listRecords(params: Record<string, unknown>): Promise<unknown>;
  /** Describe the actor's repo. */
  describeRepo(params?: Record<string, unknown>): Promise<unknown>;
  /** List missing blobs in the actor's repo. */
  listMissingBlobs(params?: Record<string, unknown>): Promise<unknown>;
  /** Upload a blob to the actor's repo. */
  uploadBlob(data: Uint8Array): Promise<unknown>;
}

/** Social graph operations bound to an actor's bearer token. */
export interface ActorGraphClient {
  /** Get actors followed by a given actor. */
  getFollows(actor: string, options?: { limit?: number }): Promise<unknown>;
  /** Get followers of a given actor. */
  getFollowers(actor: string, options?: { limit?: number }): Promise<unknown>;
  /** Get actors blocked by the authenticated user. */
  getBlocks(limit?: number): Promise<unknown>;
  /** Get actors muted by the authenticated user. */
  getMutes(limit?: number): Promise<unknown>;
  /** Mute an actor by DID. */
  muteActor(actorDid: string): Promise<unknown>;
  /** Unmute an actor by DID. */
  unmuteActor(actorDid: string): Promise<unknown>;
  /** Get relationships between an actor and targets. */
  getRelationships(actor: string, targets: string[]): Promise<unknown>;
  /** Get a starter pack by URI. */
  getStarterPack(uri: string): Promise<unknown>;
  /** Get starter packs created by an actor. */
  getActorStarterPacks(
    actor: string,
    options?: { limit?: number },
  ): Promise<unknown>;
  /** Get multiple starter packs by URIs. */
  getStarterPacks(uris: string[]): Promise<unknown>;
  /** Get a list by URI. */
  getList(
    listUri: string,
    options?: { limit?: number; cursor?: string },
  ): Promise<unknown>;
  /** Get lists created by an actor. */
  getLists(
    actor: string,
    options?: { limit?: number; cursor?: string },
  ): Promise<unknown>;
}

/** Feed and timeline operations bound to an actor's bearer token. */
export interface ActorFeedClient {
  /** Get an actor's profile. */
  getProfile(actor: string): Promise<unknown>;
  /** Get the authenticated user's timeline. */
  getTimeline(limit?: number): Promise<unknown>;
  /** Get an actor's authored feed. */
  getAuthorFeed(actor: string, options?: { limit?: number }): Promise<unknown>;
  /** Get a post thread by URI. */
  getPostThread(uri: string): Promise<unknown>;
  /** Get likes for a record. */
  getLikes(uri: string, options?: { limit?: number }): Promise<unknown>;
  /** Search actors by query. */
  searchActors(query: string, options?: { limit?: number }): Promise<unknown>;
  /** Get posts liked by an actor. */
  getActorLikes(actor: string, options?: { limit?: number }): Promise<unknown>;
  /** Get posts by their AT URIs. */
  getPosts(uris: string[]): Promise<unknown>;
  /** Get actors who reposted a post. */
  getRepostedBy(uri: string, options?: { limit?: number }): Promise<unknown>;
  /** Get a custom feed generator's feed. */
  getFeed(feedUri: string, limit?: number): Promise<unknown>;
  /** Get feed generator details by URIs. */
  getFeedGenerators(uris: string[]): Promise<unknown>;
}

/**
 * Scoped client bound to an actor's identity credentials.
 *
 * Returned by {@link XrpcClient.as} and {@link XrpcClient.asAdmin}.
 * Every request automatically includes the actor's bearer token and
 * repo-scoped parameters.
 */
export interface ActorScopedClient {
  /** Raw XRPC/HTTP methods with the actor's token pre-attached. */
  raw: ActorRawClient;
  /** Generated nested API client with the actor's token. */
  api: GeneratedClient;
  /** Repository record CRUD with the actor's DID auto-injected. */
  repo: ActorRepoClient;
  /** Social graph operations with the actor's token. */
  graph: ActorGraphClient;
  /** Feed and timeline operations with the actor's token. */
  feed: ActorFeedClient;
}

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
   * @typeParam K - The lexicon query ID type.
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

  /**
   * Invoke an untyped generic XRPC query by method string.
   * @param method The XRPC query method string.
   * @param params Query parameters.
   * @param token Optional auth token.
   */
  async query(
    method: string,
    params?: Record<string, unknown>,
    token?: string,
  ): Promise<unknown>;

  /**
   * Main query execution implementation.
   */
  async query(
    method: string,
    params?: Record<string, unknown>,
    token?: string,
  ): Promise<unknown> {
    return await this.raw.query(method, params, token);
  }

  /**
   * Invoke a typed XRPC procedure.
   * @typeParam K - The lexicon procedure ID type.
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

  /**
   * Invoke an untyped generic XRPC procedure by method string.
   * @param method The XRPC procedure method string.
   * @param input Procedure input payload.
   * @param token Optional auth token.
   */
  async procedure(
    method: string,
    input?: unknown,
    token?: string,
  ): Promise<unknown>;

  /**
   * Main procedure execution implementation.
   */
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
   * Returns a scoped client bound to an actor's identity credentials.
   * @param actor - An object providing an accessJwt and did (e.g. an Actor instance)
   */
  as(
    actor: { accessJwt?: string; token?: string; did?: string },
  ): ActorScopedClient {
    const token = actor.accessJwt || actor.token;
    const did = actor.did;
    const wrap = <T extends Record<string, unknown>>(
      params?: T,
    ): T | { repo: string } & T => {
      const merged = { ...params } as { repo: string } & T;
      if (did) merged.repo = did;
      return merged;
    };
    return {
      raw: {
        get: (method: string, params?: Record<string, unknown>) =>
          this.raw.get(method, params, token),
        post: (method: string, body?: unknown) =>
          this.raw.post(method, body, token),
        query: (method: string, params?: Record<string, unknown>) =>
          this.raw.query(method, params, token),
        procedure: (method: string, body?: unknown) =>
          this.raw.procedure(method, body, token),
        httpGet: (path: string, params?: Record<string, unknown>) =>
          this.raw.httpGet(path, params, token),
        httpPost: (path: string, body?: unknown) =>
          this.raw.httpPost(path, body, token),
        xrpcGet: (method: string, params?: Record<string, unknown>) =>
          this.raw.xrpcGet(method, params, token),
        xrpcPost: (method: string, body?: unknown) =>
          this.raw.xrpcPost(method, body, token),
        postBinary: (method: string, data: Uint8Array, contentType: string) =>
          this.raw.postBinary(method, data, contentType, token),
      },
      api: token ? this.auth(token) : this.api,
      repo: {
        createRecord: (params: Record<string, unknown>) =>
          this.raw.post("com.atproto.repo.createRecord", wrap(params), token),
        getRecord: (params: Record<string, unknown>) =>
          this.raw.get("com.atproto.repo.getRecord", wrap(params), token),
        putRecord: (params: Record<string, unknown>) =>
          this.raw.post("com.atproto.repo.putRecord", wrap(params), token),
        deleteRecord: (params: Record<string, unknown>) =>
          this.raw.post("com.atproto.repo.deleteRecord", wrap(params), token),
        applyWrites: (params: Record<string, unknown>) =>
          this.raw.post("com.atproto.repo.applyWrites", wrap(params), token),
        listRecords: (params: Record<string, unknown>) =>
          this.raw.get("com.atproto.repo.listRecords", wrap(params), token),
        describeRepo: (params?: Record<string, unknown>) =>
          this.raw.get("com.atproto.repo.describeRepo", wrap(params), token),
        listMissingBlobs: (params?: Record<string, unknown>) =>
          this.raw.get(
            "com.atproto.repo.listMissingBlobs",
            wrap(params),
            token,
          ),
        uploadBlob: (data: Uint8Array) =>
          this.raw.postBinary(
            "com.atproto.repo.uploadBlob",
            data,
            "application/octet-stream",
            token,
          ),
      },
      graph: {
        getFollows: (actor: string, options?: { limit?: number }) =>
          this.graph.getFollows(actor, { ...options, token }),
        getFollowers: (actor: string, options?: { limit?: number }) =>
          this.graph.getFollowers(actor, { ...options, token }),
        getBlocks: (limit?: number) => this.graph.getBlocks(token!, limit),
        getMutes: (limit?: number) => this.graph.getMutes(token!, limit),
        muteActor: (actorDid: string) => this.graph.muteActor(actorDid, token!),
        unmuteActor: (actorDid: string) =>
          this.graph.unmuteActor(actorDid, token!),
        getRelationships: (actor: string, targets: string[]) =>
          this.graph.getRelationships(actor, targets, token),
        getStarterPack: (uri: string) => this.graph.getStarterPack(uri, token),
        getActorStarterPacks: (actor: string, options?: { limit?: number }) =>
          this.graph.getActorStarterPacks(actor, { ...options, token }),
        getStarterPacks: (uris: string[]) =>
          this.graph.getStarterPacks(uris, token),
        getList: (
          listUri: string,
          options?: { limit?: number; cursor?: string },
        ) => this.graph.getList(listUri, { ...options, token }),
        getLists: (
          actor: string,
          options?: { limit?: number; cursor?: string },
        ) => this.graph.getLists(actor, { ...options, token }),
      },
      feed: {
        getProfile: (actor: string) => this.feed.getProfile(actor, token),
        getTimeline: (limit?: number) => this.feed.getTimeline(token!, limit),
        getAuthorFeed: (actor: string, options?: { limit?: number }) =>
          this.feed.getAuthorFeed(actor, { ...options, token }),
        getPostThread: (uri: string) => this.feed.getPostThread(uri, token),
        getLikes: (uri: string, options?: { limit?: number }) =>
          this.feed.getLikes(uri, { ...options, token }),
        searchActors: (query: string, options?: { limit?: number }) =>
          this.feed.searchActors(query, { ...options, token }),
        getActorLikes: (actor: string, options?: { limit?: number }) =>
          this.feed.getActorLikes(actor, { ...options, token }),
        getPosts: (uris: string[]) => this.feed.getPosts(uris, token),
        getRepostedBy: (uri: string, options?: { limit?: number }) =>
          this.feed.getRepostedBy(uri, { ...options, token }),
        getFeed: (feedUri: string, limit?: number) =>
          this.feed.getFeed(feedUri, token!, limit),
        getFeedGenerators: (uris: string[]) =>
          this.feed.getFeedGenerators(uris, token),
      },
    };
  }

  /**
   * Returns a scoped client bound to an admin bearer token.
   *
   * This is equivalent to `client.as({ accessJwt: token })` but provides
   * a shorter, intent-revealing API for admin/moderation operations.
   *
   * @param token - The admin bearer token
   */
  asAdmin(token: string): ActorScopedClient {
    return this.as({ accessJwt: token });
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
    return createAgentProxy(this, this.#agentSession);
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

/**
 * Dynamic proxy type wrapping the generated client to provide both standard
 * schema methods and custom session-helper operations (like createAccount and login).
 */
export type AgentProxy = WrapClient<GeneratedClient> & {
  /**
   * Allow dynamic namespace access for methods not yet in GeneratedClient.
   * `any` is required here (rather than `unknown`) so that arbitrary
   * `client.agent.<namespace>.<method>(...)` chains type-check without a
   * cast — an index signature of `unknown` would make both the property
   * access and the subsequent call fail to type-check.
   */
  // deno-lint-ignore no-explicit-any -- intentional passthrough for dynamic proxy access
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
  constructor(
    private transport: TransportLayer,
    private defaultToken?: string,
  ) {}

  async call(
    method: string,
    paramsOrInput?: unknown,
    tokenOrOpts?: string | CallOptions,
  ): Promise<unknown> {
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

  async call(
    method: string,
    paramsOrInput?: unknown,
    tokenOrOpts?: string | CallOptions,
  ): Promise<unknown> {
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
      return prop === "createAccount" || prop === "login" ||
        Reflect.has(target, prop);
    },
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
