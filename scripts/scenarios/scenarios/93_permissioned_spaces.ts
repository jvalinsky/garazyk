/**
 * @module scenarios/93_permissioned_spaces
 *
 * Exercises Proposal 0016's real OAuth → delegation → credential flow across
 * two PDS instances. Space content never enters a public repository API.
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
const CLIENT_ID = "http://127.0.0.1:3900/permissioned-space-scenario";
const REDIRECT_URI = "http://127.0.0.1:3900/permissioned-space-callback";

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

function base64UrlJSON(segment: string): Record<string, unknown> {
  const padded = segment.replaceAll("-", "+").replaceAll("_", "/") +
    "=".repeat((4 - segment.length % 4) % 4);
  const value = JSON.parse(atob(padded));
  if (!value || typeof value !== "object") {
    throw new Error("expected JWT JSON object");
  }
  return value as Record<string, unknown>;
}

function credentialKeyID(token: string): string {
  const header = token.split(".", 1)[0];
  if (!header) throw new Error("credential has no JWT header");
  const kid = base64UrlJSON(header).kid;
  if (typeof kid !== "string") throw new Error("credential JWT has no kid");
  return kid;
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

async function authenticatedXrpc(
  base: string,
  method: string,
  accessToken: string,
  body: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const response = await fetch(new URL(`/xrpc/${method}`, base), {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  return await readJSON(response);
}

async function prepareDedicatedSpaceKey(did: string): Promise<string> {
  const runDir = Deno.env.get("ATPROTO_E2E_RUN_DIR");
  if (!runDir) throw new Error("binary run directory is unavailable");
  const binDir = Deno.env.get("BUILD_DIR") || "build/bin";
  const command = new Deno.Command(`${binDir}/kaszlak`, {
    args: [
      "account",
      "--json",
      "--data-dir",
      `${runDir}/data/pds2`,
      "--config",
      `${runDir}/data/pds2/pds2-config.json`,
      "prepare-space-key",
      did,
    ],
    env: {
      ...Deno.env.toObject(),
      PDS_USE_KEYCHAIN: "false",
      PDS_MASTER_SECRET: "test-master-secret-123",
    },
    stdout: "piped",
    stderr: "piped",
  });
  const output = await command.output();
  if (!output.success) {
    throw new Error(
      `space-key preparation failed: ${
        new TextDecoder().decode(output.stderr).trim()
      }`,
    );
  }
  const rawOutput = new TextDecoder().decode(output.stdout);
  // The standalone CLI initializes the PDS and writes startup diagnostics before
  // its JSON result.  Its machine-readable payload is the final JSON document.
  const jsonStart = rawOutput.indexOf("\n{");
  const parsed = JSON.parse(
    jsonStart >= 0 ? rawOutput.slice(jsonStart + 1) : rawOutput.trimStart(),
  );
  const methods = parsed?.verificationMethods;
  const key = methods?.atproto_space;
  if (typeof key !== "string" || !key.startsWith("did:key:z")) {
    throw new Error("space-key preparation returned no public did:key");
  }
  return key;
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
      body: new URLSearchParams(fields),
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
    client_name: "Permissioned Spaces Scenario",
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
    body: new URLSearchParams({
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
  const did = typeof token.body.sub === "string" ? token.body.sub : "";
  if (!accessToken || !did) {
    throw new Error("OAuth token response was missing access_token or sub");
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

async function uploadSpaceBlob(
  base: string,
  grant: OAuthGrant,
  space: string,
  data: Uint8Array,
): Promise<string> {
  const url = new URL("/xrpc/com.atproto.repo.uploadBlob", base);
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Authorization": `DPoP ${grant.accessToken}`,
      "DPoP": await dpopProof(grant.dpopKey, "POST", url),
      "Content-Type": "text/plain",
      "X-Atproto-Space": space,
      "X-Atproto-Space-Collection": COLLECTION,
      "X-Atproto-Space-Action": "create",
    },
    body: data,
  });
  const body = await readJSON(response);
  const blob = body.blob as Record<string, unknown> | undefined;
  const ref = blob?.ref as Record<string, unknown> | undefined;
  const cid = typeof ref?.$link === "string" ? ref.$link : "";
  if (!cid) throw new Error("space blob upload did not return a CID");
  return cid;
}

async function expectPublicBlobRejected(
  url: URL,
  headers: HeadersInit = {},
): Promise<void> {
  const response = await fetch(url, { headers, redirect: "manual" });
  if (response.ok) {
    throw new Error(`public blob endpoint exposed ${url.pathname}`);
  }
}

async function expectRejected(
  operation: () => Promise<unknown>,
  message: string,
): Promise<void> {
  try {
    await operation();
  } catch {
    return;
  }
  throw new Error(message);
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

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Permissioned Spaces OAuth Cross-PDS");
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

  for (
    const [name, client] of [
      ["PDS A", pds1],
      ["PDS B", pds2],
      ["PDS C", new XrpcClient(readerPDS)],
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

  for (
    const [name, client, actor] of [
      ["writer", pds1, writer],
      ["reader", new XrpcClient(readerPDS), reader],
      ["space owner", pds2, owner],
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
  if (!writer.did || !reader.did || !owner.did) {
    result.stepFailed(
      "Account setup",
      "one or more accounts did not receive a DID",
    );
    result.finish();
    return result;
  }

  const skey = `s93-${crypto.randomUUID().replaceAll("-", "").slice(0, 16)}`;
  const space = `at://${owner.did}/space/${SPACE_TYPE}/${skey}`;
  const privateText = `permissioned-space-93-${crypto.randomUUID()}`;
  const ownerScope = spaceScope("self", skey, [
    "read",
    "create",
    "update",
    "delete",
  ], [
    "create",
    "update",
    "delete",
  ]);
  const memberScope = spaceScope(owner.did, skey, ["read", "create", "update"]);
  const readerScope = spaceScope(owner.did, skey, ["read"]);

  const ownerGrant = await timedCall(
    result,
    "Owner completes OAuth PAR, PKCE, and DPoP grant",
    () => obtainOAuthGrant(PDS2, owner, ownerScope),
    (grant) => `sub=${grant.did}`,
  );
  if (!ownerGrant) {
    result.finish();
    return result;
  }

  await timedCall(result, "Create member-list space on PDS B", async () => {
    const response = await oauthXrpc(
      PDS2,
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
  });

  await timedCall(result, "Grant writer and reader membership", async () => {
    await oauthXrpc(PDS2, "com.atproto.simplespace.addMember", ownerGrant, {
      space,
      did: writer.did,
    });
    await oauthXrpc(PDS2, "com.atproto.simplespace.addMember", ownerGrant, {
      space,
      did: reader.did,
    });
  });

  const writerGrant = await timedCall(
    result,
    "Writer completes scoped OAuth grant on PDS A",
    () => obtainOAuthGrant(PDS1, writer, memberScope),
    (grant) => `sub=${grant.did}`,
  );
  if (!writerGrant) {
    result.finish();
    return result;
  }

  const writerCredential = await timedCall(
    result,
    "Writer exchanges signed delegation for space credential on PDS B",
    () => delegationAndCredential(PDS1, PDS2, writerGrant, space),
    () => "credential issued",
  );
  if (!writerCredential) {
    result.finish();
    return result;
  }

  const written = await timedCall(
    result,
    "Writer stores a permissioned record on PDS A",
    () =>
      oauthXrpc(PDS1, "com.atproto.space.createRecord", writerGrant, {
        space,
        repo: writer.did,
        collection: COLLECTION,
        rkey: "scenario-93-private",
        record: {
          $type: COLLECTION,
          text: privateText,
          createdAt: new Date().toISOString(),
        },
      }),
  );
  if (!written) {
    result.finish();
    return result;
  }

  await timedCall(
    result,
    "Authority learns the remote writer through signed notification",
    async () => {
      for (let attempt = 0; attempt < 20; attempt++) {
        const repos = await credentialXrpc(
          PDS2,
          "com.atproto.space.listRepos",
          writerCredential,
          undefined,
          { space },
        );
        const entries = Array.isArray(repos.repos) ? repos.repos : [];
        if (
          entries.some((entry) =>
            typeof entry === "object" && entry !== null &&
            (entry as Record<string, unknown>).did === writer.did
          )
        ) return;
        await new Promise((resolve) => setTimeout(resolve, 250));
      }
      throw new Error(
        "authority never recorded the remote writer notification",
      );
    },
  );

  const readerGrant = await timedCall(
    result,
    "Reader completes whole-space OAuth grant on PDS C",
    () => obtainOAuthGrant(readerPDS, reader, readerScope),
    (grant) => `sub=${grant.did}`,
  );
  if (!readerGrant) {
    result.finish();
    return result;
  }

  const readerCredential = await timedCall(
    result,
    "Reader exchanges delegation for a credential on PDS B",
    () => delegationAndCredential(readerPDS, PDS2, readerGrant, space),
    () => "credential issued",
  );
  if (!readerCredential) {
    result.finish();
    return result;
  }

  await timedCall(
    result,
    "Reader retrieves the remote permissioned record",
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
          rkey: "scenario-93-private",
        },
      );
      const value = record.value as Record<string, unknown> | undefined;
      if (value?.text !== privateText) {
        throw new Error(
          "credential read did not return the private record",
        );
      }
    },
  );

  const dedicatedSpaceKey = await timedCall(
    result,
    "Authority prepares a dedicated space signing key",
    () => prepareDedicatedSpaceKey(owner.did),
    (key) => `public_key=${key.slice(0, 20)}…`,
  );
  if (!dedicatedSpaceKey || !owner.accessJwt) {
    result.finish();
    return result;
  }

  await timedCall(
    result,
    "Authority publishes the dedicated key through a signed PLC operation",
    async () => {
      const confirmation = await authenticatedXrpc(
        PDS2,
        "com.atproto.identity.requestPlcOperationSignature",
        owner.accessJwt,
        {},
      );
      const token = confirmation.token;
      if (typeof token !== "string") {
        throw new Error("PLC confirmation did not return a test token");
      }
      const signed = await authenticatedXrpc(
        PDS2,
        "com.atproto.identity.signPlcOperation",
        owner.accessJwt,
        {
          token,
          verificationMethods: { atproto_space: dedicatedSpaceKey },
        },
      );
      const operation = signed.operation;
      if (!operation || typeof operation !== "object") {
        throw new Error("PLC signing did not return an operation");
      }
      const methods = (operation as Record<string, unknown>)
        .verificationMethods as Record<string, unknown> | undefined;
      if (
        methods?.atproto_space !== dedicatedSpaceKey ||
        typeof methods?.atproto !== "string"
      ) {
        throw new Error(
          "PLC operation did not preserve both credential verification methods",
        );
      }
      await authenticatedXrpc(
        PDS2,
        "com.atproto.identity.submitPlcOperation",
        owner.accessJwt,
        { operation },
      );
    },
  );

  const dedicatedReaderCredential = await timedCall(
    result,
    "Reader receives a credential from the dedicated signing key",
    () => delegationAndCredential(readerPDS, PDS2, readerGrant, space),
    (token) => `kid=${credentialKeyID(token)}`,
  );
  if (!dedicatedReaderCredential) {
    result.finish();
    return result;
  }
  if (
    credentialKeyID(readerCredential) !== "#atproto" ||
    credentialKeyID(dedicatedReaderCredential) !== "#atproto_space"
  ) {
    result.stepFailed(
      "Credential key overlap",
      "expected old #atproto and new #atproto_space credentials",
    );
    result.finish();
    return result;
  }

  await timedCall(
    result,
    "Remote PDS accepts both account and dedicated credentials during overlap",
    async () => {
      for (const credential of [readerCredential, dedicatedReaderCredential]) {
        const record = await credentialXrpc(
          PDS1,
          "com.atproto.space.getRecord",
          credential,
          undefined,
          {
            space,
            repo: writer.did,
            collection: COLLECTION,
            rkey: "scenario-93-private",
          },
        );
        if (
          (record.value as Record<string, unknown> | undefined)?.text !==
            privateText
        ) {
          throw new Error(
            "overlap credential did not authorize the remote read",
          );
        }
      }
    },
  );

  const privateBlobText = `permissioned-blob-93-${crypto.randomUUID()}`;
  const privateBlobData = new TextEncoder().encode(privateBlobText);
  const privateBlobCID = await timedCall(
    result,
    "Writer uploads a private blob with scoped OAuth and space bindings",
    () => uploadSpaceBlob(PDS1, writerGrant, space, privateBlobData),
    (cid) => `cid=${cid}`,
  );
  if (!privateBlobCID) {
    result.finish();
    return result;
  }

  await timedCall(
    result,
    "Reader retrieves the remote private blob through a space credential",
    async () => {
      const url = new URL("/xrpc/com.atproto.space.getBlob", PDS1);
      url.searchParams.set("space", space);
      url.searchParams.set("repo", writer.did);
      url.searchParams.set("cid", privateBlobCID);
      const response = await fetch(url, {
        headers: { "Authorization": `Bearer ${readerCredential}` },
      });
      if (!response.ok) throw await responseError(response);
      const blobText = new TextDecoder().decode(await response.arrayBuffer());
      if (blobText !== privateBlobText) {
        throw new Error("space credential did not return the private blob");
      }
    },
  );

  await timedCall(
    result,
    "Public repository, sync, and blob APIs reject permissioned data",
    async () => {
      const url = new URL("/xrpc/com.atproto.repo.getRecord", PDS1);
      url.searchParams.set("repo", writer.did);
      url.searchParams.set("collection", COLLECTION);
      url.searchParams.set("rkey", "scenario-93-private");
      const publicRecord = await fetch(url);
      const publicBody = await publicRecord.text();
      if (publicRecord.ok) {
        if (publicBody.includes(privateText) || publicBody.includes(space)) {
          throw new Error("public repository returned permissioned data");
        }
        throw new Error("public repository lookup unexpectedly succeeded");
      }

      const exportURL = new URL("/xrpc/com.atproto.sync.getRepo", PDS1);
      exportURL.searchParams.set("did", writer.did);
      const exportResponse = await fetch(exportURL);
      if (!exportResponse.ok) throw await responseError(exportResponse);
      const exported = new TextDecoder().decode(
        await exportResponse.arrayBuffer(),
      );
      if (
        exported.includes(privateText) || exported.includes(privateBlobText) ||
        exported.includes(space)
      ) {
        throw new Error("public CAR export contained permissioned data");
      }

      const repoBlobURL = new URL("/xrpc/com.atproto.repo.getBlob", PDS1);
      repoBlobURL.searchParams.set("did", writer.did);
      repoBlobURL.searchParams.set("cid", privateBlobCID);
      await expectPublicBlobRejected(repoBlobURL, {
        "Authorization": `DPoP ${writerGrant.accessToken}`,
        "DPoP": await dpopProof(writerGrant.dpopKey, "GET", repoBlobURL),
      });

      const syncBlobURL = new URL("/xrpc/com.atproto.sync.getBlob", PDS1);
      syncBlobURL.searchParams.set("did", writer.did);
      syncBlobURL.searchParams.set("cid", privateBlobCID);
      await expectPublicBlobRejected(syncBlobURL);

      const listBlobsURL = new URL("/xrpc/com.atproto.sync.listBlobs", PDS1);
      listBlobsURL.searchParams.set("did", writer.did);
      const listBlobsResponse = await fetch(listBlobsURL, {
        headers: {
          "Authorization": `DPoP ${writerGrant.accessToken}`,
          "DPoP": await dpopProof(writerGrant.dpopKey, "GET", listBlobsURL),
        },
      });
      const listBlobs = await readJSON(listBlobsResponse);
      if (JSON.stringify(listBlobs.blobs).includes(privateBlobCID)) {
        throw new Error("public sync blob listing exposed a private blob");
      }
    },
  );

  await timedCall(
    result,
    "Owner revokes writer membership",
    () =>
      oauthXrpc(PDS2, "com.atproto.simplespace.removeMember", ownerGrant, {
        space,
        did: writer.did,
      }),
  );

  await timedCall(
    result,
    "Revoked writer cannot obtain a new credential",
    async () => {
      const delegation = await oauthXrpc(
        PDS1,
        "com.atproto.space.getDelegationToken",
        writerGrant,
        undefined,
        { space },
      );
      const token = typeof delegation.token === "string"
        ? delegation.token
        : "";
      if (!token) {
        throw new Error(
          "revoked writer delegation was not minted for negative test",
        );
      }
      await expectRejected(
        () =>
          credentialXrpc(PDS2, "com.atproto.space.getSpaceCredential", token, {
            space,
          }),
        "space host issued a new credential to a revoked member",
      );
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
