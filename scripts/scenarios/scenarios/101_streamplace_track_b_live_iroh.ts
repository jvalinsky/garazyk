/**
 * @module scenarios/101_streamplace_track_b_live_iroh
 *
 * External-lifecycle acceptance for Streamplace's live iroh protocol. Track A
 * iroh-blobs sidecars never count as evidence here.
 */

import { CarReader } from "@ipld/car";
import { decode } from "cborg";
import { firehoseEventFromFrame, parseFirehoseFrame } from "@garazyk/gruszka";
import { ScenarioResult, timedCallChecked } from "../../lib/deno/runner.ts";
export {
  ScenarioResult,
  StepResult,
  StepStatus,
} from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";

const REVISION = "5ba597dbedda8f2fdb84b815ee633301212f5f51";
const BRIDGE = "streamplace-track-b-bridge";
const ORIGIN_COLLECTION = "place.stream.broadcast.origin";

interface CommandResult {
  code: number;
  stdout: string;
  stderr: string;
}
interface Origin {
  recordUri: string;
  recordCid: string;
  streamer: string;
  server: string;
  updatedAt: string;
  ticketFingerprint: string;
  ticketLength: number;
  /** Process-only; redact() strips this from ScenarioResult artifacts. */
  ticket: string;
  seq: number;
}
interface BridgeSession {
  sessionId: string;
  requestedStreamer: string;
  ticketFingerprint: string;
  ticketNodeId: string;
  alpn: string;
  dialAttempts: number;
  reconnectAttempts: number;
  reconnectAttemptLimit: number;
  subscribeAcknowledged: boolean;
  authenticatedRemoteNodeId?: string;
  segment?: { bytes: number; fromNodeId: string; contentSha256: string };
  jelczAttestation?: {
    muxlStructuralValidation: string;
    contentBytes: number;
    contentSha256: string;
  };
  observedRejections?: string[];
}
interface BridgeReport {
  contractVersion?: string;
  bridgeOwnedEvidenceComplete?: boolean;
  sessions?: Record<string, BridgeSession>;
}
interface FaultPeerState {
  contractVersion: string;
  mode: string;
  nodeId: string;
  irohTicket: string;
  advertisedAlpn: string;
  configuredSegmentLimit: number;
}

const FAULT_CASES = [
  {
    service: "streamplace-track-b-fault-wrong-streamer",
    mode: "wrong-streamer",
    status: 502,
    error: "BridgeSubscriptionFailed",
    rejection: "wrong_streamer",
  },
  {
    service: "streamplace-track-b-fault-wrong-alpn",
    mode: "wrong-alpn",
    status: 502,
    error: "BridgeSubscriptionFailed",
    retries: true,
  },
  {
    service: "streamplace-track-b-fault-wrong-from",
    mode: "wrong-from",
    status: 502,
    error: "BridgeSubscriptionFailed",
    rejection: "peer_identity_mismatch",
  },
  {
    service: "streamplace-track-b-fault-corrupt",
    mode: "corrupt-muxl",
    status: 422,
    error: "MUXLInvalid",
    segmentWithoutAttestation: true,
  },
  {
    service: "streamplace-track-b-fault-oversize",
    mode: "oversize-segment",
    status: 502,
    error: "BridgeSubscriptionFailed",
    rejection: "segment_size_rejected",
  },
  {
    service: "streamplace-track-b-fault-drop-subscribe",
    mode: "drop-subscribe",
    status: 502,
    error: "BridgeSubscriptionFailed",
    retries: true,
  },
] as const;

function output(bytes: Uint8Array): string {
  return new TextDecoder().decode(bytes).trim();
}
async function command(args: string[]): Promise<CommandResult> {
  const result = await new Deno.Command(args[0], {
    args: args.slice(1),
    stdout: "piped",
    stderr: "piped",
  }).output();
  return {
    code: result.code,
    stdout: output(result.stdout),
    stderr: output(result.stderr),
  };
}
function composeArgs(): string[] {
  return [
    "docker",
    "compose",
    "--env-file",
    Deno.env.get("TRACK_B_COMPOSE_ENV_FILE") ??
      "docker/streamplace-peership/.env",
    "--env-file",
    Deno.env.get("TRACK_B_COMPOSE_TRACK_B_ENV_FILE") ??
      "docker/streamplace-peership/track-b.env",
    "-f",
    "docker/streamplace-peership/docker-compose.yml",
    "-f",
    "docker/streamplace-peership/docker-compose.track-b.yml",
    "--project-name",
    Deno.env.get("COMPOSE_PROJECT_NAME") ?? "streamplace-peership-track-b",
    "--profile",
    "track-b",
  ];
}
function requireString(value: unknown, label: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`missing ${label}`);
  }
  return value;
}
function requireDigestPinnedImage(value: unknown, label: string): string {
  const image = requireString(value, label);
  if (!/^[^\s@]+@sha256:[a-f0-9]{64}$/i.test(image)) {
    throw new Error(`${label} is not digest-pinned`);
  }
  return image;
}
function errorFor(label: string, result: CommandResult): Error {
  return new Error(
    `${label} exited ${result.code}: ${
      [result.stderr, result.stdout].filter(Boolean).join("; ")
    }`,
  );
}
function redact(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(redact);
  if (!value || typeof value !== "object") return value;
  return Object.fromEntries(
    Object.entries(value).map(([key, child]) => [
      /(?:ticket|token|authorization)/i.test(key) && !/fingerprint/i.test(key)
        ? "[redacted]"
        : redact(child),
    ]),
  );
}
async function sha256Fingerprint(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return `sha256:${
    Array.from(new Uint8Array(digest)).map((byte) =>
      byte.toString(16).padStart(2, "0")
    ).join("")
  }`;
}

async function waitForOpen(url: string): Promise<WebSocket> {
  const socket = new WebSocket(url);
  socket.binaryType = "arraybuffer";
  await new Promise<void>((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error(`firehose did not open: ${url}`)),
      15_000,
    );
    socket.onopen = () => {
      clearTimeout(timer);
      resolve();
    };
    socket.onerror = () => {
      clearTimeout(timer);
      reject(new Error(`firehose failed to open: ${url}`));
    };
  });
  return socket;
}
async function baselineCursor(endpoint: string): Promise<number> {
  const socket = await waitForOpen(endpoint);
  try {
    return await new Promise<number>((resolve, reject) => {
      const timer = setTimeout(
        () => reject(new Error("baseline firehose cursor was not observed")),
        15_000,
      );
      socket.onmessage = (message) => {
        try {
          const frame = parseFirehoseFrame(
            new Uint8Array(message.data as ArrayBuffer),
          );
          const event = firehoseEventFromFrame(frame);
          if (event.seq > 0) {
            clearTimeout(timer);
            resolve(event.seq);
          }
        } catch { /* wait for a valid event */ }
      };
      socket.onerror = () => {
        clearTimeout(timer);
        reject(new Error("baseline firehose error"));
      };
    });
  } finally {
    socket.close();
  }
}
async function originFromCommit(
  body: Record<string, unknown>,
  seq: number,
  expectedStreamer: string,
): Promise<Origin | null> {
  const blocks = body.blocks;
  const ops = body.ops;
  if (
    body.tooBig === true || !(blocks instanceof Uint8Array) ||
    !Array.isArray(ops)
  ) {
    throw new Error("#commit is missing CAR blocks or ops");
  }
  const reader = await CarReader.fromBytes(blocks);
  const records = new Map<string, Record<string, unknown>>();
  for await (const block of reader.blocks()) {
    try {
      const record = decode(block.bytes) as Record<string, unknown>;
      records.set(block.cid.toString(), record);
    } catch { /* non-record blocks are expected in a repo CAR */ }
  }
  for (const op of ops) {
    if (!op || typeof op !== "object") continue;
    const candidate = op as Record<string, unknown>;
    const path = candidate.path;
    if (typeof path !== "string" || !path.startsWith(`${ORIGIN_COLLECTION}/`)) {
      continue;
    }
    if (candidate.action !== "create" && candidate.action !== "update") {
      throw new Error("origin commit is not a live create/update");
    }
    const cid = candidate.cid;
    const cidString = typeof cid === "string"
      ? cid
      : cid && typeof cid === "object" && "toString" in cid
      ? String(cid)
      : "";
    if (!cidString || !records.has(cidString)) {
      throw new Error("origin op CID has no corresponding CAR block");
    }
    const record = records.get(cidString)!;
    const streamer = requireString(record.streamer, "origin.streamer");
    if (record.$type !== ORIGIN_COLLECTION) {
      throw new Error("origin CAR block has a mismatched $type");
    }
    if (streamer !== expectedStreamer) continue;
    const server = requireString(record.server, "origin.server");
    const updatedAt = requireString(record.updatedAt, "origin.updatedAt");
    const ticket = requireString(record.irohTicket, "origin.irohTicket");
    const ticketBytes = new TextEncoder().encode(ticket);
    if (ticketBytes.length > 2048) {
      throw new Error("origin ticket exceeds 2048 bytes");
    }
    const repo = requireString(body.repo, "commit.repo");
    if (!repo.startsWith("did:")) {
      throw new Error("origin commit repo is not a DID");
    }
    const fingerprint = await sha256Fingerprint(ticket);
    return {
      recordUri: `at://${repo}/${path}`,
      recordCid: cidString,
      streamer,
      server,
      updatedAt,
      ticketFingerprint: fingerprint,
      ticketLength: ticketBytes.length,
      ticket,
      seq,
    };
  }
  return null;
}
async function observeOrigin(
  endpoint: string,
  cursor: number,
  expectedStreamer: string,
): Promise<{ result: Promise<Origin>; cancel: () => void }> {
  const url = new URL(endpoint);
  url.searchParams.set("cursor", String(cursor));
  const socket = await waitForOpen(url.toString());
  let cancel = () => socket.close();
  const result = new Promise<Origin>((resolve, reject) => {
    const timer = setTimeout(
      () => {
        socket.close();
        reject(
          new Error(
            "no refreshed origin commit arrived after baseline cursor",
          ),
        );
      },
      45_000,
    );
    cancel = () => {
      clearTimeout(timer);
      socket.close();
      reject(new Error("origin observation cancelled"));
    };
    socket.onmessage = async (message) => {
      try {
        const event = firehoseEventFromFrame(
          parseFirehoseFrame(new Uint8Array(message.data as ArrayBuffer)),
        );
        if (event.seq <= cursor) return;
        if (event.type === "#sync") {
          throw new Error(
            "firehose returned #sync instead of a live #commit",
          );
        }
        if (event.type !== "#commit") return;
        const origin = await originFromCommit(
          event.body,
          event.seq,
          expectedStreamer,
        );
        if (origin) {
          clearTimeout(timer);
          socket.close();
          resolve(origin);
        }
      } catch (error) {
        clearTimeout(timer);
        socket.close();
        reject(error);
      }
    };
    socket.onerror = () => {
      clearTimeout(timer);
      socket.close();
      reject(new Error("refreshed firehose errored"));
    };
  });
  return { result, cancel };
}
async function requestJelcz(
  base: string,
  token: string,
  path: string,
  body: unknown,
): Promise<{ status: number; json: Record<string, unknown> }> {
  const response = await fetch(new URL(path, base), {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  const json = await response.json() as Record<string, unknown>;
  return { status: response.status, json };
}
async function replaceOrigins(
  base: string,
  token: string,
  origins: Array<Record<string, unknown>>,
): Promise<{ status: number; json: Record<string, unknown> }> {
  return await requestJelcz(
    base,
    token,
    "/demo/streamplace/api/origins",
    { origins, replace: true },
  );
}
async function readBridgeReport(
  requireComplete: boolean,
): Promise<BridgeReport> {
  const reportCommand = await command([
    ...composeArgs(),
    "exec",
    "-T",
    BRIDGE,
    "/usr/local/bin/jelcz-streamplace-iroh-bridge",
    "acceptance-report",
    "--json",
  ]);
  if (!reportCommand.stdout) {
    throw errorFor("bridge acceptance-report", reportCommand);
  }
  let report: BridgeReport;
  try {
    report = JSON.parse(reportCommand.stdout) as BridgeReport;
  } catch {
    throw new Error("bridge acceptance-report did not emit JSON");
  }
  if (requireComplete && reportCommand.code !== 0) {
    throw errorFor("bridge acceptance-report", reportCommand);
  }
  return report;
}
async function readFaultPeerState(service: string): Promise<FaultPeerState> {
  let last: CommandResult | null = null;
  for (let attempt = 0; attempt < 40; attempt++) {
    last = await command([
      ...composeArgs(),
      "exec",
      "-T",
      service,
      "/usr/local/bin/jelcz-streamplace-iroh-bridge",
      "fault-ticket",
      "--json",
    ]);
    if (last.code === 0 && last.stdout) {
      const state = JSON.parse(last.stdout) as FaultPeerState;
      if (
        state.contractVersion !==
          "jelcz-streamplace-track-b-fault-peer/v1" ||
        !state.irohTicket || !state.nodeId || !state.mode
      ) throw new Error(`${service} emitted an invalid fault-peer contract`);
      return state;
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw errorFor(`${service} fault-ticket`, last!);
}
async function exerciseFaultCase(
  jelczBase: string,
  jelczToken: string,
  streamer: string,
  fault: typeof FAULT_CASES[number],
): Promise<Record<string, unknown>> {
  const before = await readBridgeReport(false);
  const beforeIds = new Set(Object.keys(before.sessions ?? {}));
  const peer = await readFaultPeerState(fault.service);
  if (peer.mode !== fault.mode) {
    throw new Error(
      `${fault.service} mode is ${peer.mode}, expected ${fault.mode}`,
    );
  }
  const expectedPeerAlpn = fault.mode === "wrong-alpn"
    ? "/iroh/streamplace/fault/1"
    : "/iroh/streamplace/1";
  if (peer.advertisedAlpn !== expectedPeerAlpn) {
    throw new Error(
      `${fault.mode} advertised ${peer.advertisedAlpn}, expected ${expectedPeerAlpn}`,
    );
  }
  const ticketFingerprint = await sha256Fingerprint(peer.irohTicket);
  const ingest = await replaceOrigins(jelczBase, jelczToken, [{
    $type: ORIGIN_COLLECTION,
    streamer,
    server: `did:web:${fault.mode}.invalid`,
    updatedAt: new Date().toISOString(),
    irohTicket: peer.irohTicket,
  }]);
  if (ingest.status !== 200 || ingest.json.replaced !== true) {
    throw new Error(
      `${fault.mode} fixture replacement returned ${ingest.status}`,
    );
  }
  const pull = await requestJelcz(
    jelczBase,
    jelczToken,
    "/demo/streamplace/api/pull-streamplace-iroh",
    { streamer },
  );
  if (pull.status !== fault.status || pull.json.error !== fault.error) {
    throw new Error(
      `${fault.mode} returned ${pull.status}/${pull.json.error}; expected ${fault.status}/${fault.error}`,
    );
  }
  const after = await readBridgeReport(false);
  const added = Object.entries(after.sessions ?? {}).filter(([id]) =>
    !beforeIds.has(id)
  );
  if (added.length !== 1) {
    throw new Error(`${fault.mode} created ${added.length} bridge sessions`);
  }
  const [sessionId, session] = added[0];
  if (
    session.requestedStreamer !== streamer ||
    session.ticketFingerprint !== ticketFingerprint ||
    session.ticketNodeId !== peer.nodeId ||
    session.alpn !== "/iroh/streamplace/1"
  ) {
    throw new Error(
      `${fault.mode} session is not bound to its ticket/streamer`,
    );
  }
  if ("rejection" in fault) {
    if (!session.observedRejections?.includes(fault.rejection)) {
      throw new Error(`${fault.mode} did not record ${fault.rejection}`);
    }
  }
  if ("retries" in fault && fault.retries) {
    if (
      session.reconnectAttempts !== session.reconnectAttemptLimit ||
      session.dialAttempts !== session.reconnectAttemptLimit + 1
    ) throw new Error(`${fault.mode} did not exhaust its bounded retry budget`);
  }
  if (
    "segmentWithoutAttestation" in fault && fault.segmentWithoutAttestation &&
    (!session.segment?.bytes || session.jelczAttestation !== undefined ||
      session.authenticatedRemoteNodeId !== peer.nodeId ||
      session.segment.fromNodeId !== peer.nodeId)
  ) {
    throw new Error(
      "corrupt MUXL was not isolated between transport and Jelcz",
    );
  }
  return {
    mode: fault.mode,
    service: fault.service,
    status: pull.status,
    error: pull.json.error,
    sessionId,
    ticketFingerprint,
    ticketNodeId: peer.nodeId,
    advertisedAlpn: peer.advertisedAlpn,
    configuredSegmentLimit: peer.configuredSegmentLimit,
    dialAttempts: session.dialAttempts,
    reconnectAttempts: session.reconnectAttempts,
    reconnectAttemptLimit: session.reconnectAttemptLimit,
    subscribeAcknowledged: session.subscribeAcknowledged,
    segmentBytes: session.segment?.bytes ?? 0,
    observedRejections: session.observedRejections ?? [],
  };
}
function validateBridge(
  report: BridgeReport,
  origin: Origin,
  sessionId: string,
  pullBytes: number,
  pullContentSha256: string,
): void {
  if (
    report.contractVersion !== "jelcz-streamplace-iroh-bridge-evidence/v1" ||
    report.bridgeOwnedEvidenceComplete !== true
  ) throw new Error("bridge did not provide complete persistent evidence");
  const session = report.sessions?.[sessionId];
  if (
    !session || session.requestedStreamer !== origin.streamer ||
    session.ticketFingerprint !== origin.ticketFingerprint ||
    session.alpn !== "/iroh/streamplace/1" || session.dialAttempts < 1 ||
    !session.subscribeAcknowledged ||
    session.authenticatedRemoteNodeId !== session.ticketNodeId ||
    session.segment?.fromNodeId !== session.ticketNodeId ||
    !session.segment.bytes ||
    session.segment.bytes !== pullBytes ||
    session.jelczAttestation?.muxlStructuralValidation !== "valid" ||
    session.jelczAttestation.contentBytes !== session.segment.bytes ||
    !/^sha256:[0-9a-f]{64}$/.test(session.segment.contentSha256) ||
    session.jelczAttestation.contentSha256 !== session.segment.contentSha256 ||
    session.segment.contentSha256 !== pullContentSha256
  ) {
    throw new Error(
      "bridge persistent session evidence does not corroborate Jelcz's live pull",
    );
  }
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult(
    "Streamplace live iroh bridge (WS16 Track B)",
  );
  result.start();
  if (Deno.env.get("JELCZ_STREAMPLACE_TRACK_B_LAB") !== "1") {
    result.stepSkipped(
      "Track B external topology readiness",
      "Set JELCZ_STREAMPLACE_TRACK_B_LAB=1; standard Hamownia does not own this topology.",
    );
    result.finish();
    return result;
  }
  const endpoint = Deno.env.get("STREAMPLACE_TRACK_B_HOST_FIREHOSE_URL") ??
    "ws://127.0.0.1:2584/xrpc/com.atproto.sync.subscribeRepos";
  const jelczBase = requireString(
    Deno.env.get("JELCZ_TRACK_B_HOST_URL"),
    "JELCZ_TRACK_B_HOST_URL",
  );
  const jelczToken = requireString(
    Deno.env.get("JELCZ_TRACK_B_API_TOKEN"),
    "JELCZ_TRACK_B_API_TOKEN",
  );
  const streamer = requireString(
    Deno.env.get("STREAMPLACE_TRACK_B_STREAMER_DID"),
    "STREAMPLACE_TRACK_B_STREAMER_DID",
  );
  const config = await command([
    ...composeArgs(),
    "config",
    "--format",
    "json",
  ]);
  if (config.code !== 0) throw errorFor("Track B compose config", config);
  const parsedConfig = JSON.parse(config.stdout) as {
    services?: Record<
      string,
      { environment?: Record<string, string>; image?: string }
    >;
  };
  for (const name of ["jelcz-a", "jelcz-b", "jelcz-c"]) {
    const environment = parsedConfig.services?.[name]?.environment;
    if (
      environment?.JELCZ_P2P !== "0" ||
      environment.JELCZ_IROH_SIDECAR_URL !== "" ||
      environment.JELCZ_IROH_PEER_SIDECARS !== ""
    ) throw new Error(`${name} still has Track A P2P wiring`);
  }
  const streamplaceImage = requireDigestPinnedImage(
    parsedConfig.services?.streamplace?.image,
    "pinned Streamplace image",
  );
  const publisherImage = requireDigestPinnedImage(
    parsedConfig.services?.["streamplace-track-b-publisher"]?.image,
    "pinned Track B publisher image",
  );
  const bridgeImage = requireDigestPinnedImage(
    parsedConfig.services?.[BRIDGE]?.image,
    "pinned Track B bridge image",
  );
  const running = await command([
    ...composeArgs(),
    "ps",
    "--services",
    "--status",
    "running",
  ]);
  if (running.code !== 0) throw errorFor("Track B compose ps", running);
  if (/^iroh-[abc]$/m.test(running.stdout)) {
    throw new Error(
      "Track A iroh-blobs container is running in a Track B acceptance",
    );
  }
  for (
    const service of [
      "streamplace",
      BRIDGE,
      "streamplace-track-b-publisher",
      "jelcz-a",
      ...FAULT_CASES.map((fault) => fault.service),
    ]
  ) {
    if (!new RegExp(`^${service}$`, "m").test(running.stdout)) {
      throw new Error(`required Track B service is not running: ${service}`);
    }
  }
  const streamplaceId = await command([
    ...composeArgs(),
    "ps",
    "-q",
    "streamplace",
  ]);
  if (streamplaceId.code !== 0 || !streamplaceId.stdout) {
    throw new Error("cannot inspect running Streamplace container");
  }
  const imageId = await command([
    "docker",
    "inspect",
    "--format",
    "{{.Image}}",
    streamplaceId.stdout,
  ]);
  if (imageId.code !== 0 || !imageId.stdout) {
    throw errorFor("running Streamplace image ID inspection", imageId);
  }
  const labels = await command([
    "docker",
    "image",
    "inspect",
    "--format",
    "{{json .Config.Labels}}",
    imageId.stdout,
  ]);
  if (labels.code !== 0) {
    throw errorFor("running Streamplace OCI label inspection", labels);
  }
  const sourceLabels = JSON.parse(labels.stdout || "{}") as Record<
    string,
    string
  >;
  if (sourceLabels["org.opencontainers.image.revision"] !== REVISION) {
    throw new Error(
      "running Streamplace OCI source revision is not the required Track B revision",
    );
  }
  result.recordArtifact("streamplace_source_provenance", {
    image: streamplaceImage,
    imageId: imageId.stdout,
    revision: sourceLabels["org.opencontainers.image.revision"],
  });
  result.recordArtifact("track_b_auxiliary_image_provenance", {
    publisherImage,
    bridgeImage,
  });
  const sessionsBeforeDenial = Object.keys(
    (await readBridgeReport(false)).sessions ?? {},
  );
  const denied = await timedCallChecked(
    result,
    "Reject nonallowed streamer before any bridge request",
    async () => {
      const ingest = await replaceOrigins(
        jelczBase,
        jelczToken,
        [{
          $type: ORIGIN_COLLECTION,
          streamer: "did:plc:not-allowed-track-b",
          server: "did:web:denied.invalid",
          updatedAt: new Date().toISOString(),
          // The real ticket is process-only and remains redacted from artifacts.
          // Jelcz must reject the streamer before it submits this ticket.
          irohTicket: Deno.env.get("STREAMPLACE_TRACK_B_DENIED_TEST_TICKET") ??
            "not-submitted-because-streamer-is-denied",
        }],
      );
      if (ingest.status !== 200) {
        throw new Error(`denied-origin ingest returned ${ingest.status}`);
      }
      const response = await requestJelcz(
        jelczBase,
        jelczToken,
        "/demo/streamplace/api/pull-streamplace-iroh",
        { streamer: "did:plc:not-allowed-track-b" },
      );
      if (
        response.status !== 403 || response.json.error !== "StreamerNotAllowed"
      ) {
        throw new Error(
          `consent denial was ${response.status}/${response.json.error}`,
        );
      }
      const sessionsAfterDenial = Object.keys(
        (await readBridgeReport(false)).sessions ?? {},
      );
      if (
        sessionsAfterDenial.length !== sessionsBeforeDenial.length ||
        sessionsAfterDenial.some((id) => !sessionsBeforeDenial.includes(id))
      ) {
        throw new Error("consent denial created bridge session evidence");
      }
      return response;
    },
  );
  if (denied.ok) result.recordArtifact("consent_denial", denied.value);
  const stale = await timedCallChecked(
    result,
    "Reject isolated stale origin before any bridge request",
    async () => {
      const ingest = await replaceOrigins(jelczBase, jelczToken, [{
        $type: ORIGIN_COLLECTION,
        streamer,
        server: "did:web:stale.invalid",
        updatedAt: new Date(Date.now() - 3_600_000).toISOString(),
        irohTicket: "not-submitted-because-origin-is-stale",
      }]);
      if (ingest.status !== 200 || ingest.json.replaced !== true) {
        throw new Error(`stale-origin replacement returned ${ingest.status}`);
      }
      const response = await requestJelcz(
        jelczBase,
        jelczToken,
        "/demo/streamplace/api/pull-streamplace-iroh",
        { streamer },
      );
      if (response.status !== 422 || response.json.error !== "OriginStale") {
        throw new Error(
          `stale origin was ${response.status}/${response.json.error}`,
        );
      }
      const sessionsAfter = Object.keys(
        (await readBridgeReport(false)).sessions ?? {},
      );
      if (
        sessionsAfter.length !== sessionsBeforeDenial.length ||
        sessionsAfter.some((id) => !sessionsBeforeDenial.includes(id))
      ) throw new Error("stale origin created bridge session evidence");
      return response;
    },
  );
  const malformed = await timedCallChecked(
    result,
    "Reject isolated malformed NodeTicket without bridge session evidence",
    async () => {
      const ingest = await replaceOrigins(jelczBase, jelczToken, [{
        $type: ORIGIN_COLLECTION,
        streamer,
        server: "did:web:malformed.invalid",
        updatedAt: new Date().toISOString(),
        irohTicket: "not-a-streamplace-node-ticket",
      }]);
      if (ingest.status !== 200 || ingest.json.replaced !== true) {
        throw new Error(
          `malformed-origin replacement returned ${ingest.status}`,
        );
      }
      const response = await requestJelcz(
        jelczBase,
        jelczToken,
        "/demo/streamplace/api/pull-streamplace-iroh",
        { streamer },
      );
      if (
        response.status !== 502 ||
        response.json.error !== "BridgeSubscriptionFailed"
      ) {
        throw new Error(
          `malformed ticket was ${response.status}/${response.json.error}`,
        );
      }
      const sessionsAfter = Object.keys(
        (await readBridgeReport(false)).sessions ?? {},
      );
      if (
        sessionsAfter.length !== sessionsBeforeDenial.length ||
        sessionsAfter.some((id) => !sessionsBeforeDenial.includes(id))
      ) throw new Error("malformed ticket created bridge session evidence");
      return response;
    },
  );
  if (stale.ok && malformed.ok) {
    result.recordArtifact("isolated_origin_rejections", {
      stale: stale.value,
      malformed: malformed.value,
      bridgeSessionsUnchanged: true,
    });
  }
  const faultEvidence: Record<string, unknown>[] = [];
  for (const fault of FAULT_CASES) {
    const exercised = await timedCallChecked(
      result,
      `Exercise Track B fault peer: ${fault.mode}`,
      () => exerciseFaultCase(jelczBase, jelczToken, streamer, fault),
      (evidence) =>
        `session=${evidence.sessionId} dials=${evidence.dialAttempts} reconnects=${evidence.reconnectAttempts}`,
    );
    if (exercised.ok) faultEvidence.push(exercised.value);
  }
  result.recordArtifact("peer_fault_injection", faultEvidence);
  const baseline = await timedCallChecked(
    result,
    "Open host relay and establish same-endpoint cursor baseline",
    () => baselineCursor(endpoint),
    (seq) => `seq=${seq}`,
  );
  if (!baseline.ok) {
    result.finish();
    return result;
  }
  const observer = await timedCallChecked(
    result,
    "Open cursor-resume observer before publisher refresh",
    () => observeOrigin(endpoint, baseline.value, streamer),
    () => `cursor=${baseline.value}`,
  );
  if (!observer.ok) {
    result.finish();
    return result;
  }
  const refresh = await timedCallChecked(
    result,
    "Causally restart publisher after cursor baseline",
    async () => {
      const restarted = await command([
        ...composeArgs(),
        "restart",
        "streamplace-track-b-publisher",
      ]);
      if (restarted.code !== 0) throw errorFor("publisher restart", restarted);
    },
    () => "publisher restarted",
  );
  if (!refresh.ok) {
    observer.value.cancel();
    await observer.value.result.catch(() => undefined);
    result.finish();
    return result;
  }
  const observed = await timedCallChecked(
    result,
    "Decode refreshed broadcast.origin #commit CAR from host firehose",
    () => observer.value.result,
    (origin) =>
      `uri=${origin.recordUri} cid=${origin.recordCid} seq=${origin.seq}`,
  );
  if (!observed.ok) {
    result.finish();
    return result;
  }
  result.recordArtifact("observed_origin", redact(observed.value));
  const positive = await timedCallChecked(
    result,
    "Ingest exact observed origin and pull it through Jelcz",
    async () => {
      const ingest = await replaceOrigins(
        jelczBase,
        jelczToken,
        [{
          $type: ORIGIN_COLLECTION,
          streamer: observed.value.streamer,
          server: observed.value.server,
          updatedAt: observed.value.updatedAt,
          irohTicket: observed.value.ticket,
        }],
      );
      if (ingest.status !== 200) {
        throw new Error(
          `origin ingest returned ${ingest.status}/${ingest.json.error}`,
        );
      }
      const pull = await requestJelcz(
        jelczBase,
        jelczToken,
        "/demo/streamplace/api/pull-streamplace-iroh",
        { streamer },
      );
      if (
        pull.status !== 200 || pull.json.validation !== true ||
        pull.json.ticketFingerprint !== observed.value.ticketFingerprint ||
        typeof pull.json.sessionId !== "string" ||
        !Number.isSafeInteger(pull.json.bytes) ||
        Number(pull.json.bytes) <= 0 ||
        typeof pull.json.contentSha256 !== "string" ||
        !/^sha256:[0-9a-f]{64}$/.test(pull.json.contentSha256)
      ) {
        throw new Error(
          `Jelcz pull did not return concrete session evidence: ${pull.status}/${
            pull.json.error ?? "invalid response"
          }`,
        );
      }
      const report = await readBridgeReport(true);
      validateBridge(
        report,
        observed.value,
        pull.json.sessionId,
        Number(pull.json.bytes),
        String(pull.json.contentSha256),
      );
      return { ingest, pull, report };
    },
  );
  if (positive.ok) {
    result.recordArtifact("track_b_acceptance", redact(positive.value));
  }
  result.finish();
  return result;
}

if (import.meta.main) {
  const result = await run();
  console.log(result.summary());
  Deno.exit(result.ok ? 0 : 1);
}
