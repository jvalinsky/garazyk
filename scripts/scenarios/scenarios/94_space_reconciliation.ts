/**
 * @module scenarios/94_space_reconciliation
 *
 * Exercises the multi-PDS reconciliation path: after a writer records state
 * on PDS A and a reader observes it on PDS C via a space credential, additional
 * writes are written and observed again — verifying that the inbound reconciliation
 * loop on the reader PDS eventually converges with the authority's state even
 * when notifications were delayed or pruned.
 *
 * This scenario uses a two-authority layout:
 *   PDS1: authority (space host)
 *   PDS2: writer PDS
 *   PDS3: reader PDS (must be independently operated, permissioned-spaces-enabled)
 */

import { XrpcClient } from "../../lib/deno/client.ts";
import { getActor, PDS1, PDS2, PDS3 } from "../../lib/deno/config.ts";
import {
  createAccountOrLogin,
  ScenarioResult,
  timedCall,
} from "../../lib/deno/runner.ts";

export {
  ScenarioResult,
  StepResult,
  StepStatus,
} from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";

const SPACE_TYPE = "com.garazyk.permissioned";
const COLLECTION = "app.bsky.feed.post";
const CLIENT_ID = "http://127.0.0.1:3900/space-reconciliation-scenario";
const REDIRECT_URI = "http://127.0.0.1:3900/space-reconciliation-callback";

interface DPoPKey {
  privateKey: CryptoKey;
  publicJwk: JsonWebKey;
}

interface OAuthGrant {
  accessToken: string;
  dpopKey: DPoPKey;
  did: string;
}

type ScenarioActor = ReturnType<typeof getActor>;

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll(
    "=",
    "",
  );
}

/** Encode form data with `%20` for spaces, accepted by the local GNUstep PDS. */
function formBody(fields: Record<string, string>): string {
  return new URLSearchParams(fields).toString().replaceAll("+", "%20");
}

function randomBase64Url(length = 32): string {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return base64Url(bytes);
}

async function sha256Base64Url(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  return base64Url(
    new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
  );
}

function canonicalHTU(url: URL): string {
  const protocol = url.protocol.toLowerCase();
  const hostname = url.hostname.toLowerCase();
  const isDefaultPort = (protocol === "http:" && url.port === "80") ||
    (protocol === "https:" && url.port === "443");
  const port = url.port && !isDefaultPort ? `:${url.port}` : "";
  return `${protocol}//${hostname}${port}${url.pathname || "/"}`;
}

async function makeDPoPKey(): Promise<DPoPKey> {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const exported = await crypto.subtle.exportKey("jwk", pair.publicKey);
  if (
    exported.kty !== "EC" || exported.crv !== "P-256" || !exported.x ||
    !exported.y
  ) {
    throw new Error("failed to generate a P-256 DPoP key");
  }
  return {
    privateKey: pair.privateKey,
    publicJwk: { kty: "EC", crv: "P-256", x: exported.x, y: exported.y },
  };
}

async function dpopProof(
  key: DPoPKey,
  method: string,
  url: URL,
  nonce?: string,
): Promise<string> {
  const header = base64Url(new TextEncoder().encode(JSON.stringify({
    typ: "dpop+jwt",
    alg: "ES256",
    jwk: key.publicJwk,
  })));
  const payload: Record<string, string | number> = {
    jti: crypto.randomUUID(),
    htm: method.toUpperCase(),
    htu: canonicalHTU(url),
    iat: Math.floor(Date.now() / 1000),
  };
  if (nonce) payload.nonce = nonce;
  const encodedPayload = base64Url(
    new TextEncoder().encode(JSON.stringify(payload)),
  );
  const signingInput = `${header}.${encodedPayload}`;
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      key.privateKey,
      new TextEncoder().encode(signingInput),
    ),
  );
  if (signature.length !== 64) {
    throw new Error(
      `WebCrypto returned a non-JOSE ECDSA signature (${signature.length} bytes)`,
    );
  }
  return `${signingInput}.${base64Url(signature)}`;
}

async function responseError(response: Response): Promise<Error> {
  let details = "";
  try {
    const body = await response.json();
    details = typeof body?.error === "string" ? body.error : "";
  } catch {
    // Do not attach arbitrary response content; it may contain private data.
  }
  return new Error(`HTTP ${response.status}${details ? ` (${details})` : ""}`);
}

async function readJSON(response: Response): Promise<Record<string, unknown>> {
  if (!response.ok) throw await responseError(response);
  const value = await response.json();
  if (!value || typeof value !== "object") {
    throw new Error("expected a JSON object response");
  }
  return value as Record<string, unknown>;
}

async function postFormWithDPoP(
  url: URL,
  fields: Record<string, string>,
  key: DPoPKey,
  initialNonce?: string,
): Promise<{ body: Record<string, unknown>; nonce?: string }> {
  let nonce = initialNonce;
  for (let attempt = 0; attempt < 2; attempt++) {
    const headers = new Headers({
      "Content-Type": "application/x-www-form-urlencoded",
      "DPoP": await dpopProof(key, "POST", url, nonce),
    });
    if (nonce) headers.set("DPoP-Nonce", nonce);
    const response = await fetch(url, {
      method: "POST",
      headers,
      // OAuth form bodies may encode spaces as either '+' or '%20'. The
      // local GNUstep server accepts percent-encoded spaces consistently,
      // including inside JSON client metadata.
      body: formBody(fields),
    });
    const responseNonce = response.headers.get("DPoP-Nonce") ?? undefined;
    const body = await response.json().catch(() => ({})) as Record<
      string,
      unknown
    >;
    if (response.ok) return { body, nonce: responseNonce };
    if (body.error === "use_dpop_nonce" && responseNonce && attempt === 0) {
      nonce = responseNonce;
      continue;
    }
    const error = typeof body.error === "string" ? body.error : "";
    const description = typeof body.error_description === "string"
      ? body.error_description
      : "";
    throw new Error(
      `HTTP ${response.status}${error ? ` (${error})` : ""}${
        description ? `: ${description}` : ""
      }`,
    );
  }
  throw new Error("OAuth server did not accept a DPoP nonce");
}

async function obtainOAuthGrant(
  base: string,
  actor: ScenarioActor,
  scope: string,
): Promise<OAuthGrant> {
  const dpopKey = await makeDPoPKey();
  const verifier = randomBase64Url();
  const codeChallenge = await sha256Base64Url(verifier);
  const state = randomBase64Url(16);
  const clientMetadata = {
    client_id: CLIENT_ID,
    client_name: "Space Reconciliation Scenario",
    redirect_uris: [REDIRECT_URI],
    grant_types: ["authorization_code", "refresh_token"],
    response_types: ["code"],
    scope,
    dpop_bound_access_tokens: true,
    token_endpoint_auth_method: "none",
    application_type: "web",
  };

  const par = await postFormWithDPoP(new URL("/oauth/par", base), {
    client_id: CLIENT_ID,
    client_metadata: JSON.stringify(clientMetadata),
    response_type: "code",
    redirect_uri: REDIRECT_URI,
    scope,
    state,
    code_challenge: codeChallenge,
    code_challenge_method: "S256",
  }, dpopKey);
  const requestURI = typeof par.body.request_uri === "string"
    ? par.body.request_uri
    : "";
  if (!requestURI) throw new Error("PAR response did not contain request_uri");

  const authorizeURL = new URL("/oauth/authorize", base);
  authorizeURL.searchParams.set("client_id", CLIENT_ID);
  authorizeURL.searchParams.set("request_uri", requestURI);
  const authorizePage = await fetch(authorizeURL, { redirect: "manual" });
  if (!authorizePage.ok) throw await responseError(authorizePage);
  const cookie = authorizePage.headers.get("set-cookie")?.match(
    /csrf_token=([^;]+)/,
  )?.[1];
  const html = await authorizePage.text();
  const csrfToken = html.match(/<meta name="csrf-token" content="([^"]+)">/)
    ?.[1];
  if (!cookie || !csrfToken) {
    throw new Error("authorization page did not establish a CSRF session");
  }

  const signIn = await fetch(new URL("/oauth/authorize/sign-in", base), {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      "X-CSRF-Token": csrfToken,
      "Cookie": `csrf_token=${cookie}`,
    },
    body: new URLSearchParams({
      handle: actor.handle,
      password: actor.password,
    }),
  });
  const signInBody = await readJSON(signIn);
  const sessionToken = typeof signInBody.session_token === "string"
    ? signInBody.session_token
    : "";
  if (!sessionToken) {
    throw new Error("authorization sign-in did not return a consent session");
  }

  const confirmation = await fetch(new URL("/oauth/authorize/confirm", base), {
    method: "POST",
    redirect: "manual",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: formBody({
      decision: "allow",
      client_id: CLIENT_ID,
      state,
      scope,
      redirect_uri: REDIRECT_URI,
      response_type: "code",
      code_challenge: codeChallenge,
      code_challenge_method: "S256",
      session_token: sessionToken,
    }),
  });
  if (confirmation.status !== 302) throw await responseError(confirmation);
  const location = confirmation.headers.get("location");
  const code = location ? new URL(location).searchParams.get("code") : null;
  if (!code) {
    throw new Error("authorization confirmation did not return a code");
  }

  const token = await postFormWithDPoP(
    new URL("/oauth/token", base),
    {
      grant_type: "authorization_code",
      client_id: CLIENT_ID,
      redirect_uri: REDIRECT_URI,
      code,
      code_verifier: verifier,
    },
    dpopKey,
    par.nonce,
  );
  const accessToken = typeof token.body.access_token === "string"
    ? token.body.access_token
    : "";
  const did = typeof token.body.sub === "string" ? token.body.sub : actor.did;
  if (!accessToken) {
    throw new Error("token exchange did not return an access token");
  }
  return { accessToken, dpopKey, did };
}

async function oauthXrpc(
  base: string,
  method: string,
  grant: OAuthGrant,
  input?: Record<string, unknown>,
  query?: Record<string, string>,
): Promise<Record<string, unknown>> {
  const url = new URL(`/xrpc/${method}`, base);
  for (const [key, value] of Object.entries(query ?? {})) {
    url.searchParams.set(key, value);
  }
  const headers = new Headers({
    "Authorization": `DPoP ${grant.accessToken}`,
    "DPoP": await dpopProof(grant.dpopKey, input ? "POST" : "GET", url),
  });
  if (input) headers.set("Content-Type", "application/json");
  const response = await fetch(url, {
    method: input ? "POST" : "GET",
    headers,
    body: input ? JSON.stringify(input) : undefined,
  });
  return await readJSON(response);
}

async function credentialXrpc(
  base: string,
  method: string,
  credential: string,
  input?: Record<string, unknown>,
  query?: Record<string, string>,
): Promise<Record<string, unknown>> {
  const url = new URL(`/xrpc/${method}`, base);
  for (const [key, value] of Object.entries(query ?? {})) {
    url.searchParams.set(key, value);
  }
  const response = await fetch(url, {
    method: input ? "POST" : "GET",
    headers: {
      "Authorization": `Bearer ${credential}`,
      ...(input ? { "Content-Type": "application/json" } : {}),
    },
    body: input ? JSON.stringify(input) : undefined,
  });
  return await readJSON(response);
}

function spaceScope(
  authority: string,
  skey: string,
  actions: string[],
  manage: string[] = [],
): string {
  const parts = [
    `authority=${encodeURIComponent(authority)}`,
    `skey=${encodeURIComponent(skey)}`,
    `collection=${encodeURIComponent(COLLECTION)}`,
    ...actions.map((action) => `action=${action}`),
    ...manage.map((operation) => `manage=${operation}`),
  ];
  return `atproto space:${SPACE_TYPE}?${parts.join("&")}`;
}

async function delegationAndCredential(
  userPDS: string,
  authorityPDS: string,
  grant: OAuthGrant,
  space: string,
): Promise<string> {
  const delegation = await oauthXrpc(
    userPDS,
    "com.atproto.space.getDelegationToken",
    grant,
    undefined,
    { space },
  );
  const token = typeof delegation.token === "string" ? delegation.token : "";
  if (!token) throw new Error("delegation response did not contain a token");
  const credential = await credentialXrpc(
    authorityPDS,
    "com.atproto.space.getSpaceCredential",
    token,
    { space },
  );
  const value = typeof credential.credential === "string"
    ? credential.credential
    : "";
  if (!value) {
    throw new Error("credential exchange did not return a credential");
  }
  return value;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Space Reconciliation After Pruning");
  result.start();

  const pds1 = new XrpcClient(PDS1);
  const pds2 = new XrpcClient(PDS2);
  const writer = getActor("luna");
  const reader = getActor("marcus");
  const owner = getActor("nova");
  const readerPDS = PDS3;

  if (!readerPDS) {
    result.stepFailed(
      "Independent reader PDS configuration",
      "Set PDS3_URL to an independently operated, permissioned-spaces-enabled PDS",
    );
    result.finish();
    return result;
  }

  const pds3 = new XrpcClient(readerPDS);
  for (
    const [name, client] of [
      ["PDS1", pds1],
      ["PDS2", pds2],
      ["PDS3", pds3],
    ] as const
  ) {
    await timedCall(
      result,
      `${name} health check`,
      () => client.waitForHealthy(30),
    );
  }
  if (result.failed > 0) {
    result.finish();
    return result;
  }

  // ── 1. Create accounts ────────────────────────────────────────────────
  for (
    const [name, client, actor] of [
      ["owner", pds1, owner],
      ["writer", pds2, writer],
      ["reader", pds3, reader],
    ] as const
  ) {
    const session = await timedCall(
      result,
      `Create ${name} account`,
      () => createAccountOrLogin(client, actor),
      (value) => `did=${value.did}`,
    );
    if (session) {
      actor.did = session.did;
      actor.accessJwt = session.accessJwt;
    }
  }
  if (!owner.did || !writer.did || !reader.did) {
    result.stepFailed(
      "Account setup",
      "one or more accounts did not receive a DID",
    );
    result.finish();
    return result;
  }

  // ── 2. Owner obtains OAuth grant on PDS1 (authority) ─────────────────
  const skey = `recon-${Date.now().toString(36)}`;
  const space = `at://${owner.did}/space/${SPACE_TYPE}/${skey}`;
  const ownerGrant = await timedCall(
    result,
    "Owner obtains OAuth grant on authority PDS",
    () =>
      obtainOAuthGrant(
        PDS1,
        owner,
        spaceScope("self", skey, ["read", "create", "update", "delete"], [
          "create",
          "update",
          "delete",
        ]),
      ),
  );
  if (!ownerGrant) {
    result.finish();
    return result;
  }

  // ── 3. Create space and grant memberships ────────────────────────────
  await timedCall(
    result,
    "Owner creates space on authority PDS",
    async () => {
      const response = await oauthXrpc(
        PDS1,
        "com.atproto.simplespace.createSpace",
        ownerGrant,
        {
          did: owner.did,
          type: SPACE_TYPE,
          skey,
          config: {
            policy: "member-list",
            appAccess: { $type: "com.atproto.simplespace.defs#open" },
          },
        },
      );
      if (response.uri !== space) {
        throw new Error("space host returned a different space URI");
      }
    },
  );

  // ── 4. Owner adds writer and reader as members ───────────────────────
  await timedCall(
    result,
    "Grant writer and reader membership",
    async () => {
      await oauthXrpc(PDS1, "com.atproto.simplespace.addMember", ownerGrant, {
        space,
        did: writer.did,
      });
      await oauthXrpc(PDS1, "com.atproto.simplespace.addMember", ownerGrant, {
        space,
        did: reader.did,
      });
    },
  );

  // ── 5. Owner obtains writer and reader OAuth grants ───────────────────
  const writerGrant = await timedCall(
    result,
    "Writer obtains OAuth grant on PDS2",
    () =>
      obtainOAuthGrant(
        PDS2,
        writer,
        spaceScope(owner.did, skey, ["read", "create", "update", "delete"]),
      ),
  );
  if (!writerGrant) {
    result.finish();
    return result;
  }

  const readerGrant = await timedCall(
    result,
    "Reader obtains OAuth grant on PDS3",
    () =>
      obtainOAuthGrant(
        readerPDS,
        reader,
        spaceScope(owner.did, skey, ["read"]),
      ),
  );
  if (!readerGrant) {
    result.finish();
    return result;
  }

  // ── 6. Writer obtains credential ─────────────────────────────────────
  const writerCredential = await timedCall(
    result,
    "Writer obtains delegation and space credential",
    () => delegationAndCredential(PDS2, PDS1, writerGrant, space),
  );
  if (!writerCredential) {
    result.finish();
    return result;
  }

  // ── 7. Writer writes initial batch of records ────────────────────────
  const initialTexts = ["recon-1", "recon-2", "recon-3"];
  await timedCall(
    result,
    `Writer creates ${initialTexts.length} initial records in space`,
    async () => {
      for (const text of initialTexts) {
        await credentialXrpc(
          PDS1,
          "com.atproto.space.createRecord",
          writerCredential,
          {
            space,
            repo: writer.did,
            collection: COLLECTION,
            rkey: `scenario-94-${text}`,
            record: {
              $type: COLLECTION,
              text,
              createdAt: new Date().toISOString(),
            },
          },
        );
      }
    },
  );

  // ── 8. Reader obtains credential ─────────────────────────────────────
  const readerCredential = await timedCall(
    result,
    "Reader obtains delegation and space credential",
    () => delegationAndCredential(readerPDS, PDS1, readerGrant, space),
  );
  if (!readerCredential) {
    result.finish();
    return result;
  }

  // ── 9. Reader reads initial records ──────────────────────────────────
  await timedCall(
    result,
    "Reader reads initial records via space credential",
    async () => {
      for (const text of initialTexts) {
        const record = await credentialXrpc(
          PDS1,
          "com.atproto.space.getRecord",
          readerCredential,
          undefined,
          {
            space,
            repo: writer.did,
            collection: COLLECTION,
            rkey: `scenario-94-${text}`,
          },
        );
        const value = record.value as Record<string, unknown> | undefined;
        if (value?.text !== text) {
          throw new Error(
            `reader did not get expected record for ${text}: got ${
              JSON.stringify(value)
            }`,
          );
        }
      }
    },
  );

  // ── 10. Writer writes additional records ─────────────────────────────
  const additionalTexts = ["recon-4", "recon-5"];
  await timedCall(
    result,
    `Writer creates ${additionalTexts.length} additional records`,
    async () => {
      for (const text of additionalTexts) {
        await credentialXrpc(
          PDS1,
          "com.atproto.space.createRecord",
          writerCredential,
          {
            space,
            repo: writer.did,
            collection: COLLECTION,
            rkey: `scenario-94-${text}`,
            record: {
              $type: COLLECTION,
              text,
              createdAt: new Date().toISOString(),
            },
          },
        );
      }
    },
  );

  // ── 11. Wait for reconciliation to propagate ─────────────────────────
  //    The reader PDS reconciler runs on a bounded interval. After writer
  //    notifies the authority, the reader PDS picks up the new state on
  //    its next reconciliation cycle. We wait long enough for two cycles.
  // Local-network PDS fixtures run their reconciler once per second. Wait for
  // several cycles so the scenario verifies propagation without a 15-minute
  // test runtime.
  const reconcileIntervalMs = 3_000;
  await timedCall(
    result,
    `Wait ${reconcileIntervalMs / 1000}s for reader reconciliation cycle`,
    () => sleep(reconcileIntervalMs),
  );

  // ── 12. Reader reads additional records (reconciled state) ───────────
  await timedCall(
    result,
    "Reader reads additional records after reconciliation",
    async () => {
      for (const text of additionalTexts) {
        const record = await credentialXrpc(
          PDS1,
          "com.atproto.space.getRecord",
          readerCredential,
          undefined,
          {
            space,
            repo: writer.did,
            collection: COLLECTION,
            rkey: `scenario-94-${text}`,
          },
        );
        const value = record.value as Record<string, unknown> | undefined;
        if (value?.text !== text) {
          throw new Error(
            `reader did not get reconciled record for ${text}: got ${
              JSON.stringify(value)
            }`,
          );
        }
      }
    },
  );

  // ── 13. Reader lists all records (verify full index) ─────────────────
  await timedCall(
    result,
    "Reader lists all space records via listRecords",
    async () => {
      const allTexts = [...initialTexts, ...additionalTexts];
      const listed = await credentialXrpc(
        PDS1,
        "com.atproto.space.listRecords",
        readerCredential,
        undefined,
        {
          space,
          repo: writer.did,
          collection: COLLECTION,
          excludeValues: "true",
        },
      );
      const records = listed.records as
        | Array<Record<string, unknown>>
        | undefined;
      if (!Array.isArray(records)) {
        throw new Error("listRecords did not return an array");
      }
      const rkeys = records
        .map((r) => {
          const uri = r.uri as string | undefined;
          if (!uri) {
            throw new Error("listRecords returned a record without a uri");
          }
          return uri.slice(uri.lastIndexOf("/") + 1);
        })
        .sort();
      const expectedRkeys = allTexts.map((t) => `scenario-94-${t}`).sort();
      if (JSON.stringify(rkeys) !== JSON.stringify(expectedRkeys)) {
        throw new Error(
          `listRecords returned unexpected rkeys: ${JSON.stringify(rkeys)}`,
        );
      }
    },
  );

  // ── 14. Writer updates an existing record ─────────────────────────────
  await timedCall(
    result,
    "Writer updates an existing record",
    async () => {
      await credentialXrpc(
        PDS1,
        "com.atproto.space.putRecord",
        writerCredential,
        {
          space,
          repo: writer.did,
          collection: COLLECTION,
          rkey: "scenario-94-recon-1",
          record: {
            $type: COLLECTION,
            text: "recon-1-updated",
            createdAt: new Date().toISOString(),
          },
        },
      );
    },
  );

  // ── 15. Wait for second reconciliation cycle ─────────────────────────
  await timedCall(
    result,
    `Wait ${reconcileIntervalMs / 1000}s for second reconciliation cycle`,
    () => sleep(reconcileIntervalMs),
  );

  // ── 16. Reader reads updated record (reconciled update) ──────────────
  await timedCall(
    result,
    "Reader reads updated record after second reconciliation",
    async () => {
      const record = await credentialXrpc(
        PDS1,
        "com.atproto.space.getRecord",
        readerCredential,
        undefined,
        {
          space,
          repo: writer.did,
          collection: COLLECTION,
          rkey: "scenario-94-recon-1",
        },
      );
      const value = record.value as Record<string, unknown> | undefined;
      if (value?.text !== "recon-1-updated") {
        throw new Error(
          `reader did not see updated record: got ${JSON.stringify(value)}`,
        );
      }
    },
  );

  // ── 17. Writer deletes a record ──────────────────────────────────────
  await timedCall(
    result,
    "Writer deletes a record from space",
    () =>
      credentialXrpc(
        PDS1,
        "com.atproto.space.deleteRecord",
        writerCredential,
        {
          space,
          repo: writer.did,
          collection: COLLECTION,
          rkey: "scenario-94-recon-5",
        },
      ),
  );

  // ── 18. Wait for third reconciliation cycle ──────────────────────────
  await timedCall(
    result,
    `Wait ${reconcileIntervalMs / 1000}s for third reconciliation cycle`,
    () => sleep(reconcileIntervalMs),
  );

  // ── 19. Verify deletion propagated ───────────────────────────────────
  await timedCall(
    result,
    "Verify deleted record is gone after reconciliation",
    async () => {
      try {
        await credentialXrpc(
          PDS1,
          "com.atproto.space.getRecord",
          readerCredential,
          undefined,
          {
            space,
            repo: writer.did,
            collection: COLLECTION,
            rkey: "scenario-94-recon-5",
          },
        );
        throw new Error(
          "deleted record was still accessible after reconciliation",
        );
      } catch (e: unknown) {
        if (
          e instanceof Error &&
          (e.message.includes("record not found") ||
            e.message.includes("HTTP 404") ||
            e.message.includes("not_found"))
        ) {
          return;
        }
        throw e;
      }
    },
  );

  result.recordArtifact("space", space);
  result.recordArtifact("writer_did", writer.did);
  result.recordArtifact("reader_did", reader.did);
  result.finish();
  return result;
}

if (import.meta.main) {
  const result = await run();
  console.log(result.summary());
  Deno.exit(result.ok ? 0 : 1);
}
