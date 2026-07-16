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
    throw new Error(`HTTP ${response.status}${error ? ` (${error})` : ""}`);
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
  };
  const registerUrl = new URL("/oauth/register", base);
  const registerRes = await fetch(registerUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(clientMetadata),
  });
  const regBody = await registerRes.json() as Record<string, unknown>;

  const authUrl = new URL("/oauth/authorize", base);
  authUrl.searchParams.set("client_id", CLIENT_ID);
  authUrl.searchParams.set("redirect_uri", REDIRECT_URI);
  authUrl.searchParams.set("response_type", "code");
  authUrl.searchParams.set("state", state);
  authUrl.searchParams.set("code_challenge", codeChallenge);
  authUrl.searchParams.set("code_challenge_method", "S256");
  authUrl.searchParams.set("scope", scope);

  const authorizeRes = await fetch(authUrl, {
    method: "GET",
    headers: {
      "Cookie": `auth_token=${actor.accessJwt}`,
    },
    redirect: "manual",
  });
  const location = authorizeRes.headers.get("location") ?? "";
  const codeMatch = location.match(/[?&]code=([^&]+)/);
  if (!codeMatch) {
    throw new Error("authorization redirect did not contain a code");
  }
  const code = codeMatch[1];

  const tokenUrl = new URL("/oauth/token", base);
  const { body: tokenBody } = await postFormWithDPoP(
    tokenUrl,
    {
      grant_type: "authorization_code",
      code,
      redirect_uri: REDIRECT_URI,
      code_verifier: verifier,
      client_id: CLIENT_ID,
    },
    dpopKey,
  );
  const accessToken = typeof tokenBody.access_token === "string"
    ? tokenBody.access_token
    : "";
  if (!accessToken) throw new Error("token exchange did not return an access token");
  return { accessToken, dpopKey, did: actor.did };
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
): string {
  const parts = [
    `authority=${encodeURIComponent(authority)}`,
    `skey=${encodeURIComponent(skey)}`,
    `collection=${encodeURIComponent(COLLECTION)}`,
    ...actions.map((action) => `action=${action}`),
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

  // ── 1. Create accounts ────────────────────────────────────────────────
  await timedCall(
    result,
    `Create owner account on PDS1`,
    async () => {
      try {
        await pds1.agent.createAccount({
          handle: owner.handle,
          email: owner.email,
          password: owner.password,
        });
      } catch (e: unknown) {
        if (!(e instanceof Error) || !e.message?.includes("already exists")) throw e;
        await pds1.agent.login({
          identifier: owner.handle,
          password: owner.password,
        });
      }
    },
  );

  await timedCall(
    result,
    `Create writer account on PDS2`,
    async () => {
      try {
        await pds2.agent.createAccount({
          handle: writer.handle,
          email: writer.email,
          password: writer.password,
        });
      } catch (e: unknown) {
        if (!(e instanceof Error) || !e.message?.includes("already exists")) throw e;
        await pds2.agent.login({
          identifier: writer.handle,
          password: writer.password,
        });
      }
    },
  );

  const pds3 = new XrpcClient(readerPDS);
  await timedCall(
    result,
    `Create reader account on PDS3`,
    async () => {
      try {
        await pds3.agent.createAccount({
          handle: reader.handle,
          email: reader.email,
          password: reader.password,
        });
      } catch (e: unknown) {
        if (!(e instanceof Error) || !e.message?.includes("already exists")) throw e;
        await pds3.agent.login({
          identifier: reader.handle,
          password: reader.password,
        });
      }
    },
  );

  // ── 2. Owner obtains OAuth grant on PDS1 (authority) ─────────────────
  const ownerGrant = await timedCall(
    result,
    "Owner obtains OAuth grant on authority PDS",
    () =>
      obtainOAuthGrant(
        PDS1,
        getActor("nova"),
        spaceScope(owner.did, "owner", ["manage"]),
      ),
  );
  if (!ownerGrant) {
    result.finish();
    return result;
  }

  // ── 3. Create space ──────────────────────────────────────────────────
  const skey = `recon-${Date.now().toString(36)}`;
  const space = `${SPACE_TYPE}:${skey}`;
  await timedCall(
    result,
    "Owner creates space on authority PDS",
    () =>
      oauthXrpc(PDS1, "com.atproto.simplespace.createSpace", ownerGrant, {
        skey,
        type: SPACE_TYPE,
        joinability: "member-list",
      }),
  );

  // ── 4. Owner obtains writer and reader OAuth grants ───────────────────
  const writerGrant = await timedCall(
    result,
    "Writer obtains OAuth grant on PDS2",
    () =>
      obtainOAuthGrant(
        PDS2,
        getActor("luna"),
        spaceScope(owner.did, skey, ["create", "update", "delete"]),
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
        getActor("marcus"),
        spaceScope(owner.did, skey, []),
      ),
  );
  if (!readerGrant) {
    result.finish();
    return result;
  }

  // ── 5. Owner adds writer and reader as members ───────────────────────
  await timedCall(
    result,
    "Owner adds writer as space member",
    () =>
      oauthXrpc(PDS1, "com.atproto.simplespace.addMember", ownerGrant, {
        space,
        did: writer.did,
        role: "writer",
      }),
  );

  await timedCall(
    result,
    "Owner adds reader as space member",
    () =>
      oauthXrpc(PDS1, "com.atproto.simplespace.addMember", ownerGrant, {
        space,
        did: reader.did,
        role: "reader",
      }),
  );

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
            `reader did not get expected record for ${text}: got ${JSON.stringify(value)}`,
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
  const reconcileIntervalMs = 300_000;
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
            `reader did not get reconciled record for ${text}: got ${JSON.stringify(value)}`,
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
      const records = listed.records as Array<Record<string, unknown>> | undefined;
      if (!Array.isArray(records)) {
        throw new Error("listRecords did not return an array");
      }
      const rkeys = records.map((r) => r.rkey as string).sort();
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
        "com.atproto.space.updateRecord",
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
