/**
 * Collect a narrow, reproducible WS16 Track A measurement from an already
 * running project-scoped Compose lab.  It never creates or starts containers.
 *
 * Usage:
 *   set -a; source docker/streamplace-peership/.env.<project>.runtime; set +a
 *   deno run --allow-env --allow-net --allow-write \
 *     scripts/demo/jelcz_track_a_s10_measurement.ts
 */

interface PullResult {
  cid?: string;
  status?: string;
  peerSource?: string;
  provider?: string;
  blake3Verified?: boolean | 0 | 1;
  size?: number;
  error?: string;
  message?: string;
}

interface SeedResult {
  cid?: string;
  size?: number;
  irohOffered?: boolean | 0 | 1;
  irohProvider?: string;
  meshFanoutSuppressed?: boolean | 0 | 1;
}

interface Timed<T> {
  elapsedMs: number;
  value: T;
}

interface Arguments {
  output?: string;
  payloadBytes: number;
}

const DID = "did:web:jelcz.local";
const DEFAULT_PAYLOAD_BYTES = 1024 * 1024;
const MAX_PAYLOAD_BYTES = 16 * 1024 * 1024;

function jsonTrue(value: unknown): boolean {
  return value === true || value === 1;
}

function baseUrl(value: string): string {
  return value.replace(/\/+$/, "");
}

function parseArguments(args: string[]): Arguments {
  const parsed: Arguments = { payloadBytes: DEFAULT_PAYLOAD_BYTES };
  for (let index = 0; index < args.length; index++) {
    const argument = args[index];
    if (argument === "--output") {
      parsed.output = args[++index];
    } else if (argument === "--payload-bytes") {
      parsed.payloadBytes = Number(args[++index]);
    } else {
      throw new Error(
        `unknown argument ${argument}; use --output PATH or --payload-bytes N`,
      );
    }
  }
  if (
    !Number.isSafeInteger(parsed.payloadBytes) ||
    parsed.payloadBytes < 1024 || parsed.payloadBytes > MAX_PAYLOAD_BYTES
  ) {
    throw new Error(
      `--payload-bytes must be an integer from 1024 through ${MAX_PAYLOAD_BYTES}`,
    );
  }
  if (parsed.output === "") throw new Error("--output requires a path");
  return parsed;
}

function mutationHeaders(contentType: string): Headers {
  const headers = new Headers({ "content-type": contentType });
  const token = Deno.env.get("JELCZ_DEMO_API_TOKEN");
  if (token) headers.set("authorization", `Bearer ${token}`);
  return headers;
}

async function timed<T>(action: () => Promise<T>): Promise<Timed<T>> {
  const start = performance.now();
  const value = await action();
  return { elapsedMs: performance.now() - start, value };
}

async function requestJson<T>(url: string, init: RequestInit): Promise<{
  response: Response;
  body: T;
}> {
  const response = await fetch(url, init);
  const body = await response.json().catch(() => ({})) as T;
  return { response, body };
}

async function getBlob(base: string, cid: string): Promise<Response> {
  const url = new URL("/xrpc/place.stream.playback.getVideoBlob", base);
  url.searchParams.set("did", DID);
  url.searchParams.set("cid", cid);
  return await fetch(url);
}

function bytesEqual(left: Uint8Array, right: Uint8Array): boolean {
  if (left.length !== right.length) return false;
  for (let index = 0; index < left.length; index++) {
    if (left[index] !== right[index]) return false;
  }
  return true;
}

function randomPayload(length: number): Uint8Array {
  const payload = new Uint8Array(length);
  for (let offset = 0; offset < payload.length; offset += 65_536) {
    crypto.getRandomValues(
      payload.subarray(offset, Math.min(offset + 65_536, payload.length)),
    );
  }
  return payload;
}

function defaultOutputPath(): string {
  const stamp = new Date().toISOString().replace(/[:.]/g, "").replace("Z", "z");
  return `scripts/scenarios/reports/measurements/${stamp}-jelcz-track-a-s10.json`;
}

function requireFreshPull(
  response: Response,
  pull: PullResult,
  expectedSource: "http-peer" | "iroh-peer",
): void {
  if (
    !response.ok || pull.status !== "peered-verified" ||
    pull.peerSource !== expectedSource || !jsonTrue(pull.blake3Verified)
  ) {
    throw new Error(
      `fresh ${expectedSource} pull was not verified: HTTP ${response.status} ${
        JSON.stringify(pull)
      }`,
    );
  }
}

function requireWarmHit(response: Response, pull: PullResult): void {
  if (
    !response.ok || pull.status !== "already-local" ||
    pull.peerSource !== "ca-store"
  ) {
    throw new Error(
      `warm cache pull was not local: HTTP ${response.status} ${
        JSON.stringify(pull)
      }`,
    );
  }
}

async function measureTransport(
  transport: "http" | "iroh",
  source: string,
  destination: string,
  httpProvider: string,
  payloadBytes: number,
): Promise<Record<string, unknown>> {
  const payload = randomPayload(payloadBytes);
  const seed = await requestJson<SeedResult>(
    `${source}/demo/streamplace/api/seed?fanout=0`,
    {
      method: "POST",
      headers: mutationHeaders("application/octet-stream"),
      // Uint8Array is a Fetch body at runtime; Deno's ambient BodyInit type
      // currently omits its generic ArrayBufferLike form.
      body: payload as unknown as BodyInit,
    },
  );
  if (
    !seed.response.ok || !seed.body.cid ||
    !jsonTrue(seed.body.meshFanoutSuppressed)
  ) {
    throw new Error(
      `seed failed for ${transport}: HTTP ${seed.response.status} ${
        JSON.stringify(seed.body)
      }`,
    );
  }
  if (seed.body.size !== payload.length) {
    throw new Error(
      `seed size mismatch for ${transport}: expected ${payload.length}, got ${seed.body.size}`,
    );
  }

  const provider = transport === "http" ? httpProvider : seed.body.irohProvider;
  if (!provider || (transport === "iroh" && !jsonTrue(seed.body.irohOffered))) {
    throw new Error(`source did not offer a usable ${transport} provider`);
  }

  const miss = await getBlob(destination, seed.body.cid);
  if (miss.status !== 404) {
    throw new Error(
      `destination was not a fresh miss for ${transport}: getVideoBlob HTTP ${miss.status}`,
    );
  }

  const fresh = await timed(() =>
    requestJson<PullResult>(
      `${destination}/demo/streamplace/api/pull-peer`,
      {
        method: "POST",
        headers: mutationHeaders("application/json"),
        body: JSON.stringify({ cid: seed.body.cid, provider, did: DID }),
      },
    )
  );
  const expectedSource = transport === "http" ? "http-peer" : "iroh-peer";
  requireFreshPull(fresh.value.response, fresh.value.body, expectedSource);
  if (fresh.value.body.size !== payload.length) {
    throw new Error(
      `fresh ${transport} pull size mismatch: expected ${payload.length}, got ${fresh.value.body.size}`,
    );
  }

  const warm = await timed(() =>
    requestJson<PullResult>(
      `${destination}/demo/streamplace/api/pull-peer`,
      {
        method: "POST",
        headers: mutationHeaders("application/json"),
        body: JSON.stringify({ cid: seed.body.cid, provider, did: DID }),
      },
    )
  );
  requireWarmHit(warm.value.response, warm.value.body);

  const localRead = await timed(() => getBlob(destination, seed.body.cid!));
  if (!localRead.value.ok) {
    throw new Error(
      `warm ${transport} local read returned HTTP ${localRead.value.status}`,
    );
  }
  const localBytes = new Uint8Array(await localRead.value.arrayBuffer());
  if (!bytesEqual(payload, localBytes)) {
    throw new Error(
      `warm ${transport} local bytes do not equal the seeded payload`,
    );
  }

  return {
    transport,
    cid: seed.body.cid,
    provider,
    fresh_miss: {
      preflight_getVideoBlob_status: miss.status,
      pull_latency_ms: fresh.elapsedMs,
      status: fresh.value.body.status,
      peer_source: fresh.value.body.peerSource,
      blake3_verified: jsonTrue(fresh.value.body.blake3Verified),
      application_payload_bytes: payload.length,
      wire_transfer_bytes: null,
      wire_transfer_bytes_note:
        "The public pull-peer contract reports payload size but exposes no transport or protocol-byte counter.",
    },
    warm_hit: {
      pull_latency_ms: warm.elapsedMs,
      status: warm.value.body.status,
      peer_source: warm.value.body.peerSource,
      local_read_latency_ms: localRead.elapsedMs,
      local_read_bytes: localBytes.length,
      byte_equality_verified: true,
      wire_transfer_bytes: null,
      wire_transfer_bytes_note:
        "The public pull-peer contract exposes no network-byte counter; already-local/ca-store is the observed cache attribution.",
    },
    direct_vs_relay: {
      value: "not-observable",
      reason:
        "The demo pull result exposes peerSource but no iroh connection-path, relay, or directness field.",
    },
  };
}

async function main(): Promise<void> {
  const args = parseArguments(Deno.args);
  const source = baseUrl(
    Deno.env.get("JELCZ_A_URL") ?? "http://127.0.0.1:2596",
  );
  const httpDestination = baseUrl(
    Deno.env.get("JELCZ_B_URL") ?? "http://127.0.0.1:2597",
  );
  const irohDestination = baseUrl(
    Deno.env.get("JELCZ_C_URL") ?? "http://127.0.0.1:2598",
  );
  const httpProvider = baseUrl(
    Deno.env.get("JELCZ_A_PROVIDER_URL") ?? "http://jelcz-a:2596",
  );
  const output = args.output ?? defaultOutputPath();

  for (const url of [source, httpDestination, irohDestination]) {
    const health = await fetch(`${url}/_health`);
    if (!health.ok) {
      throw new Error(`${url}/_health returned HTTP ${health.status}`);
    }
  }

  const artifact = {
    schema: "garazyk.ws16.track-a-s10.v1",
    measured_at: new Date().toISOString(),
    lab: {
      source,
      http_destination: httpDestination,
      iroh_destination: irohDestination,
      http_provider: httpProvider,
      payload_bytes_per_transport: args.payloadBytes,
    },
    observations: [
      await measureTransport(
        "http",
        source,
        httpDestination,
        httpProvider,
        args.payloadBytes,
      ),
      await measureTransport(
        "iroh",
        source,
        irohDestination,
        httpProvider,
        args.payloadBytes,
      ),
    ],
    limits: {
      tls: "not-measured; the Track A Compose lab is plain HTTP internally",
      direct_vs_relay:
        "not-observable from the demo or sidecar public results; no inference is made",
      wire_bytes:
        "not-observable from the demo or sidecar public results; application payload bytes are separately recorded",
    },
  };
  const outputDirectory = output.includes("/")
    ? output.slice(0, output.lastIndexOf("/"))
    : ".";
  if (outputDirectory) await Deno.mkdir(outputDirectory, { recursive: true });
  await Deno.writeTextFile(output, JSON.stringify(artifact, null, 2) + "\n");
  console.log(`S10 measurement written: ${output}`);
}

if (import.meta.main) {
  await main();
}
