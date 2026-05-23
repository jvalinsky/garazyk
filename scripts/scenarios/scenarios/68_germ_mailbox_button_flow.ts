/**
 * @module scenarios/68_germ_mailbox_button_flow
 *
 * Scenario: Germ declaration buttons and mailbox exchange between two accounts.
 *
 * Behavior:
 * - Creates or logs in two local PDS accounts.
 * - Publishes com.germnetwork.declaration/self records with messageMe URLs on the local Germ service.
 * - Completes the Germ button URL fragments for both account-viewer directions.
 * - Claims Germ mailbox addresses and delivers opaque ciphertext in both directions.
 *
 * Expectations:
 * - Both accounts expose a valid Germ button declaration.
 * - Both accounts can receive and poll a Germ mailbox ciphertext from the other account.
 */

import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { Actor, getActor, PDS1, serviceUrl } from "../../lib/deno/config.ts";
import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
export {
  ScenarioResult,
  StepResult,
  StepStatus,
} from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";


const GERM_URL = (Deno.env.get("GERM_URL") || serviceUrl("germ")).replace(
  /\/$/,
  "",
);
const GERM_SERVICE_DID = Deno.env.get("GERM_SERVICE_DID") ||
  germServiceDidForUrl(GERM_URL);
const DECLARATION_COLLECTION = "com.germnetwork.declaration";
const DECLARATION_RKEY = "self";

interface Session {
  did: string;
  accessJwt: string;
  refreshJwt?: string;
}

interface GermDeclaration {
  $type: "com.germnetwork.declaration";
  version: string;
  currentKey: { $bytes: string };
  messageMe: {
    showButtonTo: "everyone";
    messageMeUrl: string;
  };
}

interface ClaimResponse {
  addresses: string[];
}

interface DeliveryResponse {
  delivered: boolean;
}

interface PollResponse {
  messages: Array<{
    address: string;
    ciphertext: { $bytes: string };
  }>;
}

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Germ Mailbox Button Flow");
  result.start();

  const pds = new XrpcClient(PDS1);
  const germ = new XrpcClient(GERM_URL);
  const luna = getActor("luna");
  const marcus = getActor("marcus");

  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
    return PDS1;
  }, (url) => `url=${url}`);

  await timedCall(result, "Germ health check", async () => {
    await germ.waitForHealthy(30);
    return GERM_URL;
  }, (url) => `url=${url}`);

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const lunaSession = await timedCall(
    result,
    `Create or login account: ${luna.handle}`,
    () => ensureAccount(pds, luna),
    (session) => `did=${session.did}`,
  );
  const marcusSession = await timedCall(
    result,
    `Create or login account: ${marcus.handle}`,
    () => ensureAccount(pds, marcus),
    (session) => `did=${session.did}`,
  );

  if (!lunaSession || !marcusSession) {
    result.finish();
    return result;
  }

  const messageMeUrl = localMessageMeUrl(GERM_URL);
  await timedCall(result, "Publish Luna Germ declaration", async () => {
    const declaration = createDeclaration(messageMeUrl);
    await putDeclaration(pds, luna, declaration);
    return declaration;
  }, (record) => `showButtonTo=${record.messageMe.showButtonTo}`);

  await timedCall(result, "Publish Marcus Germ declaration", async () => {
    const declaration = createDeclaration(messageMeUrl);
    await putDeclaration(pds, marcus, declaration);
    return declaration;
  }, (record) => `showButtonTo=${record.messageMe.showButtonTo}`);

  const buttonUrls = await timedCall(
    result,
    "Resolve Germ button URLs",
    async () => {
      const [lunaRecord, marcusRecord] = await Promise.all([
        getDeclaration(pds, luna.did),
        getDeclaration(pds, marcus.did),
      ]);

      const messageLunaAsMarcus = completedButtonUrl(
        lunaRecord.messageMe.messageMeUrl,
        luna.did,
        marcus.did,
      );
      const messageMarcusAsLuna = completedButtonUrl(
        marcusRecord.messageMe.messageMeUrl,
        marcus.did,
        luna.did,
      );

      assert.equal(lunaRecord.messageMe.showButtonTo, "everyone");
      assert.equal(marcusRecord.messageMe.showButtonTo, "everyone");
      assertButtonFragment(messageLunaAsMarcus, luna.did, marcus.did);
      assertButtonFragment(messageMarcusAsLuna, marcus.did, luna.did);

      return { messageLunaAsMarcus, messageMarcusAsLuna };
    },
    () => "directions=2",
  );

  const runNonce = crypto.randomUUID();
  const lunaAgentRef = `luna-${runNonce}`;
  const marcusAgentRef = `marcus-${runNonce}`;

  const claims = await timedCall(
    result,
    "Claim Germ mailbox addresses",
    async () => {
      const method = "com.germnetwork.mailbox.claimAddresses";
      const [lunaToken, marcusToken] = await Promise.all([
        serviceAuthForMethod(pds, luna.accessJwt, method),
        serviceAuthForMethod(pds, marcus.accessJwt, method),
      ]);
      const [lunaClaim, marcusClaim] = await Promise.all([
        germ.raw.post(
          method,
          { agentRef: lunaAgentRef, count: 2 },
          lunaToken,
        ) as Promise<ClaimResponse>,
        germ.raw.post(
          method,
          { agentRef: marcusAgentRef, count: 2 },
          marcusToken,
        ) as Promise<ClaimResponse>,
      ]);

      assert.isTrue(
        lunaClaim.addresses.length >= 1,
        "Luna did not receive a mailbox address",
      );
      assert.isTrue(
        marcusClaim.addresses.length >= 1,
        "Marcus did not receive a mailbox address",
      );
      return {
        lunaAddress: lunaClaim.addresses[0],
        marcusAddress: marcusClaim.addresses[0],
      };
    },
    (claim) =>
      `luna=${shortId(claim.lunaAddress)}, marcus=${
        shortId(claim.marcusAddress)
      }`,
  );

  if (!claims) {
    result.finish();
    return result;
  }

  const lunaToMarcusCiphertext = randomBytesBase64(96);
  const marcusToLunaCiphertext = randomBytesBase64(112);

  await timedCall(
    result,
    "Deliver Germ ciphertext both directions",
    async () => {
      const method = "com.germnetwork.mailbox.deliver";
      const [lunaToken, marcusToken] = await Promise.all([
        serviceAuthForMethod(pds, luna.accessJwt, method),
        serviceAuthForMethod(pds, marcus.accessJwt, method),
      ]);
      const [lunaToMarcus, marcusToLuna] = await Promise.all([
        germ.raw.post(
          method,
          {
            address: claims.marcusAddress,
            ciphertext: { $bytes: lunaToMarcusCiphertext },
          },
          lunaToken,
        ) as Promise<DeliveryResponse>,
        germ.raw.post(
          method,
          {
            address: claims.lunaAddress,
            ciphertext: { $bytes: marcusToLunaCiphertext },
          },
          marcusToken,
        ) as Promise<DeliveryResponse>,
      ]);

      assert.isTrue(lunaToMarcus.delivered, "Luna -> Marcus delivery failed");
      assert.isTrue(marcusToLuna.delivered, "Marcus -> Luna delivery failed");
      return { lunaToMarcus, marcusToLuna };
    },
    () => "delivered=2",
  );

  await timedCall(result, "Poll Germ mailbox ciphertexts", async () => {
    const method = "com.germnetwork.mailbox.poll";
    const [marcusToken, lunaToken] = await Promise.all([
      serviceAuthForMethod(pds, marcus.accessJwt, method),
      serviceAuthForMethod(pds, luna.accessJwt, method),
    ]);
    const [marcusPoll, lunaPoll] = await Promise.all([
      germ.raw.get(
        method,
        { agentRef: marcusAgentRef },
        marcusToken,
      ) as Promise<PollResponse>,
      germ.raw.get(
        method,
        { agentRef: lunaAgentRef },
        lunaToken,
      ) as Promise<PollResponse>,
    ]);

    assert.isTrue(
      containsCiphertext(marcusPoll, lunaToMarcusCiphertext),
      "Marcus did not receive Luna's ciphertext",
    );
    assert.isTrue(
      containsCiphertext(lunaPoll, marcusToLunaCiphertext),
      "Luna did not receive Marcus's ciphertext",
    );
    return {
      marcusMessages: marcusPoll.messages.length,
      lunaMessages: lunaPoll.messages.length,
    };
  }, (poll) => `marcus=${poll.marcusMessages}, luna=${poll.lunaMessages}`);

  await timedCall(
    result,
    "Verify Germ mailbox single-read semantics",
    async () => {
      const method = "com.germnetwork.mailbox.poll";
      const [marcusToken, lunaToken] = await Promise.all([
        serviceAuthForMethod(pds, marcus.accessJwt, method),
        serviceAuthForMethod(pds, luna.accessJwt, method),
      ]);
      const [marcusPoll, lunaPoll] = await Promise.all([
        germ.raw.get(
          method,
          { agentRef: marcusAgentRef },
          marcusToken,
        ) as Promise<PollResponse>,
        germ.raw.get(
          method,
          { agentRef: lunaAgentRef },
          lunaToken,
        ) as Promise<PollResponse>,
      ]);

      assert.equal(marcusPoll.messages.length, 0);
      assert.equal(lunaPoll.messages.length, 0);
      return { marcusMessages: 0, lunaMessages: 0 };
    },
    () => "remaining=0",
  );

  if (buttonUrls) {
    result.recordArtifact("germ_button_urls", buttonUrls);
  }
  result.recordArtifact("germ_mailbox", {
    germUrl: GERM_URL,
    germServiceDid: GERM_SERVICE_DID,
    messageMeUrl,
    lunaAddress: shortId(claims.lunaAddress),
    marcusAddress: shortId(claims.marcusAddress),
  });

  result.finish();
  return result;
}

async function ensureAccount(
  pds: XrpcClient,
  character: Actor,
): Promise<Session> {
  const session = await pds.accounts.createAccount(
    character.handle,
    character.email,
    character.password,
  ) as Session;
  character.did = session.did;
  character.accessJwt = session.accessJwt;
  character.refreshJwt = session.refreshJwt || "";
  return session;
}

async function serviceAuthForMethod(
  pds: XrpcClient,
  accessJwt: string,
  method: string,
): Promise<string> {
  const response = await pds.as({ accessJwt }).raw.xrpcGet(
    "com.atproto.server.getServiceAuth",
    { aud: GERM_SERVICE_DID, lxm: method },
  ) as { token?: string };
  if (!response.token) {
    throw new Error(
      `com.atproto.server.getServiceAuth did not return a token for ${method}`,
    );
  }
  return response.token;
}

function createDeclaration(messageMeUrl: string): GermDeclaration {
  return {
    $type: DECLARATION_COLLECTION,
    version: "1.0.0",
    currentKey: { $bytes: typedAnchorKeyBase64() },
    messageMe: {
      showButtonTo: "everyone",
      messageMeUrl,
    },
  };
}

async function putDeclaration(
  pds: XrpcClient,
  character: Actor,
  declaration: GermDeclaration,
): Promise<void> {
  await pds.as(character).raw.post(
    "com.atproto.repo.putRecord",
    {
      repo: character.did,
      collection: DECLARATION_COLLECTION,
      rkey: DECLARATION_RKEY,
      validate: true,
      record: declaration,
    },
  );
}

async function getDeclaration(
  pds: XrpcClient,
  did: string,
): Promise<GermDeclaration> {
  const response = await pds.records.getRecord(
    did,
    DECLARATION_COLLECTION,
    DECLARATION_RKEY,
  );
  const value = (response as { value?: unknown }).value;
  if (!isGermDeclaration(value)) {
    throw new Error(`Invalid Germ declaration for ${did}`);
  }
  return value;
}

function isGermDeclaration(value: unknown): value is GermDeclaration {
  if (!value || typeof value !== "object") return false;
  const record = value as Partial<GermDeclaration>;
  return record.$type === DECLARATION_COLLECTION &&
    typeof record.version === "string" &&
    typeof record.currentKey?.$bytes === "string" &&
    record.messageMe?.showButtonTo === "everyone" &&
    typeof record.messageMe.messageMeUrl === "string";
}

function localMessageMeUrl(germUrl: string): string {
  const url = new URL("/mailbox/message-me", `${germUrl}/`);
  url.hash = "";
  return url.toString();
}

function germServiceDidForUrl(germUrl: string): string {
  const url = new URL(germUrl);
  const hostname = url.hostname === "127.0.0.1" || url.hostname === "::1"
    ? "localhost"
    : url.hostname;
  const isDefaultPort = !url.port ||
    (url.protocol === "https:" && url.port === "443") ||
    (url.protocol === "http:" && url.port === "80");
  const didHost = isDefaultPort ? hostname : `${hostname}%3A${url.port}`;
  return `did:web:${didHost}#germ_mailbox`;
}

function completedButtonUrl(
  messageMeUrl: string,
  profileDid: string,
  viewerDid: string,
): string {
  const url = new URL(messageMeUrl);
  if (url.hash) {
    throw new Error(
      `messageMeUrl must not include a fragment: ${messageMeUrl}`,
    );
  }
  url.hash = `${profileDid}+${viewerDid}`;
  return url.toString();
}

function assertButtonFragment(
  buttonUrl: string,
  profileDid: string,
  viewerDid: string,
): void {
  const url = new URL(buttonUrl);
  assert.equal(url.hash.slice(1), `${profileDid}+${viewerDid}`);
}

function containsCiphertext(poll: PollResponse, ciphertext: string): boolean {
  return poll.messages.some((message) =>
    message.ciphertext.$bytes === ciphertext
  );
}

function typedAnchorKeyBase64(): string {
  const bytes = new Uint8Array(33);
  bytes[0] = 0x03;
  crypto.getRandomValues(bytes.subarray(1));
  return bytesToBase64(bytes);
}

function randomBytesBase64(length: number): string {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return bytesToBase64(bytes);
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

function shortId(value: string): string {
  return value.length <= 12
    ? value
    : `${value.slice(0, 6)}...${value.slice(-6)}`;
}

if (import.meta.main) {
  const result = await run();
  console.log(result.summary());
  Deno.exit(result.ok ? 0 : 1);
}
