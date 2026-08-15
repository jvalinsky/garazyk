/**
 * @module scenarios/100_jelcz_iroh_peership
 *
 * Verifies the opt-in WS16 Track A Compose lab. The managed Hamownia
 * topologies do not launch this lab, so an operator must start it separately
 * and set JELCZ_PEERSHIP_LAB=1 before this scenario will mutate it.
 */

import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
export {
  ScenarioResult,
  StepResult,
  StepStatus,
} from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";

interface LabUrls {
  source: string;
  httpDestination: string;
  irohDestination: string;
  httpProvider: string;
  streamplace: string;
}

interface PullResult {
  cid?: string;
  status?: string;
  peerSource?: string;
  provider?: string;
  blake3Verified?: boolean | 0 | 1;
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

function jsonTrue(value: unknown): boolean {
  return value === true || value === 1;
}

function baseUrl(value: string): string {
  return value.replace(/\/+$/, "");
}

function mutationHeaders(contentType: string): Headers {
  const headers = new Headers({ "content-type": contentType });
  const token = Deno.env.get("JELCZ_DEMO_API_TOKEN");
  if (token) {
    headers.set("Authorization", `Bearer ${token}`);
  }
  return headers;
}

function labUrls(): LabUrls {
  return {
    source: baseUrl(Deno.env.get("JELCZ_A_URL") ?? "http://127.0.0.1:2596"),
    httpDestination: baseUrl(
      Deno.env.get("JELCZ_B_URL") ?? "http://127.0.0.1:2597",
    ),
    irohDestination: baseUrl(
      Deno.env.get("JELCZ_C_URL") ?? "http://127.0.0.1:2598",
    ),
    // This URL is dereferenced by jelcz-b inside the Compose network, not by
    // the host process that runs this scenario.
    httpProvider: baseUrl(
      Deno.env.get("JELCZ_A_PROVIDER_URL") ?? "http://jelcz-a:2596",
    ),
    streamplace: baseUrl(
      Deno.env.get("STREAMPLACE_URL") ?? "http://127.0.0.1:38080",
    ),
  };
}

async function jsonRequest<T>(
  url: string,
  init?: RequestInit,
): Promise<{ response: Response; body: T }> {
  const response = await fetch(url, init);
  const body = await response.json().catch(() => ({})) as T;
  return { response, body };
}

async function getVideoBlob(base: string, cid: string): Promise<Response> {
  const url = new URL("/xrpc/place.stream.playback.getVideoBlob", base);
  url.searchParams.set("did", "did:web:jelcz.local");
  url.searchParams.set("cid", cid);
  return await fetch(url);
}

async function pullFromProvider(
  destination: string,
  cid: string,
  provider: string,
): Promise<{ response: Response; body: PullResult }> {
  return await jsonRequest<PullResult>(
    `${destination}/demo/streamplace/api/pull-peer`,
    {
      method: "POST",
      headers: mutationHeaders("application/json"),
      body: JSON.stringify({
        cid,
        provider,
        did: "did:web:jelcz.local",
      }),
    },
  );
}

async function requireMutationCapability(
  source: string,
): Promise<void> {
  const token = Deno.env.get("JELCZ_DEMO_API_TOKEN");
  if (!token) return;
  const path = `${source}/demo/streamplace/api/seed?fanout=0`;
  const missing = await fetch(path, {
    method: "POST",
    headers: { "content-type": "application/octet-stream" },
    body: "missing-capability-must-not-seed",
  });
  if (missing.status !== 401) {
    throw new Error(
      `missing mutation capability returned HTTP ${missing.status}`,
    );
  }
  const wrong = await fetch(path, {
    method: "POST",
    headers: {
      "content-type": "application/octet-stream",
      Authorization: "Bearer wrong-demo-capability",
    },
    body: "wrong-capability-must-not-seed",
  });
  if (wrong.status !== 403) {
    throw new Error(`wrong mutation capability returned HTTP ${wrong.status}`);
  }
}

function requireTransport(
  pull: PullResult,
  expectedSource: "http-peer" | "https-peer" | "iroh-peer",
): void {
  if (pull.status !== "peered-verified") {
    throw new Error(
      `expected status=peered-verified, got ${pull.status ?? "missing"}; ` +
        "already-local is not transport proof",
    );
  }
  if (pull.peerSource !== expectedSource) {
    throw new Error(
      `expected peerSource=${expectedSource}, got ${
        pull.peerSource ?? "missing"
      }`,
    );
  }
  if (!jsonTrue(pull.blake3Verified)) {
    throw new Error("transport result did not report blake3Verified=true");
  }
}

async function requireMissingDestination(
  base: string,
  cid: string,
): Promise<void> {
  const response = await getVideoBlob(base, cid);
  if (response.status !== 404) {
    throw new Error(
      `expected an initially empty destination (HTTP 404), got HTTP ${response.status}`,
    );
  }
}

async function requireByteEquality(
  destination: string,
  cid: string,
  expected: Uint8Array,
): Promise<void> {
  const response = await getVideoBlob(destination, cid);
  if (!response.ok) {
    throw new Error(
      `destination getVideoBlob returned HTTP ${response.status}`,
    );
  }
  const actual = new Uint8Array(await response.arrayBuffer());
  if (actual.length !== expected.length) {
    throw new Error(
      `byte length mismatch: expected=${expected.length}, actual=${actual.length}`,
    );
  }
  for (let index = 0; index < expected.length; index++) {
    if (actual[index] !== expected[index]) {
      throw new Error(`byte mismatch at offset ${index}`);
    }
  }
}

/** Run the WS16 Track A iroh-blobs peership scenario against the external lab. */
export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Jelcz iroh-blobs Peership (WS16 Track A)");
  result.start();

  if (Deno.env.get("JELCZ_PEERSHIP_LAB") !== "1") {
    result.stepSkipped(
      "Lab topology readiness",
      "External Compose lab is not Hamownia-managed; start it separately and set JELCZ_PEERSHIP_LAB=1.",
    );
    result.recordArtifact("integration_blocker", {
      blocker:
        "Hamownia's standard topology does not launch docker/streamplace-peership.",
      invocation: "JELCZ_PEERSHIP_LAB=1 deno task hamownia run --no-setup 100",
    });
    result.finish();
    return result;
  }

  const urls = labUrls();
  result.recordArtifact("lab_urls", urls);

  const topology = await timedCall(
    result,
    "Lab topology readiness",
    async () => {
      const healthUrls = [
        `${urls.source}/_health`,
        `${urls.httpDestination}/_health`,
        `${urls.irohDestination}/_health`,
      ];
      for (const url of healthUrls) {
        const response = await fetch(url);
        if (!response.ok) {
          throw new Error(`${url} returned HTTP ${response.status}`);
        }
      }

      const streamplace = await fetch(`${urls.streamplace}/api/healthz`);
      if (!streamplace.ok) {
        const fallback = await fetch(`${urls.streamplace}/`);
        if (!fallback.ok) {
          throw new Error(
            `Streamplace health and fallback returned HTTP ${streamplace.status}/${fallback.status}`,
          );
        }
      }

      const { response, body } = await jsonRequest<Record<string, unknown>>(
        `${urls.irohDestination}/demo/streamplace/api/mesh`,
      );
      if (!response.ok) {
        throw new Error(`mesh endpoint returned HTTP ${response.status}`);
      }
      if (!jsonTrue(body.irohConfigured)) {
        throw new Error(
          "iroh sidecar is not configured on the iroh destination",
        );
      }
      return body;
    },
    (mesh) => `irohConfigured=${String(mesh.irohConfigured)}`,
  );
  if (!topology) {
    result.finish();
    return result;
  }

  await timedCall(
    result,
    "Mutation capability rejects missing and wrong values",
    () => requireMutationCapability(urls.source),
    () =>
      Deno.env.get("JELCZ_DEMO_API_TOKEN")
        ? "missing=401 wrong=403"
        : "capability unset; standalone compatibility mode",
  );

  const payload = new TextEncoder().encode(
    `hamownia-ws16-peership-${new Date().toISOString()}-${crypto.randomUUID()}`,
  );
  const seed = await timedCall(
    result,
    "Seed source object without mesh fanout",
    async () => {
      const { response, body } = await jsonRequest<SeedResult>(
        `${urls.source}/demo/streamplace/api/seed?fanout=0`,
        {
          method: "POST",
          headers: mutationHeaders("application/octet-stream"),
          body: payload,
        },
      );
      if (!response.ok || !body.cid) {
        throw new Error(`seed failed: HTTP ${response.status}`);
      }
      if (!jsonTrue(body.meshFanoutSuppressed)) {
        throw new Error("seed did not confirm mesh fanout suppression");
      }
      if (
        !jsonTrue(body.irohOffered) ||
        !body.irohProvider?.startsWith("iroh://")
      ) {
        throw new Error(
          "source did not offer an iroh provider for the seeded object",
        );
      }
      return body;
    },
    (value) => `cid=${value.cid} irohProvider=${value.irohProvider}`,
  );
  if (!seed?.cid || !seed.irohProvider) {
    result.finish();
    return result;
  }
  result.recordArtifact("seed", seed);

  await timedCall(
    result,
    "HTTP destination miss before transport",
    () => requireMissingDestination(urls.httpDestination, seed.cid!),
  );

  await timedCall(
    result,
    "Unconfigured provider is rejected without local fallback",
    async () => {
      const attempted = await pullFromProvider(
        urls.httpDestination,
        seed.cid!,
        "http://127.0.0.1:1",
      );
      if (
        attempted.response.status !== 403 || attempted.body.cid ||
        attempted.body.error !== "ProviderNotAllowed"
      ) {
        throw new Error(
          `expected unconfigured provider to return 403 ProviderNotAllowed, got HTTP ${attempted.response.status} ${
            JSON.stringify(attempted.body)
          }`,
        );
      }
      await requireMissingDestination(urls.httpDestination, seed.cid!);
      return attempted.body;
    },
    (value) => `error=${value.error}`,
  );

  const httpPull = await timedCall(
    result,
    "Bridge-network HTTP peering into initially-missing destination",
    async () => {
      const attempted = await pullFromProvider(
        urls.httpDestination,
        seed.cid!,
        urls.httpProvider,
      );
      if (!attempted.response.ok) {
        throw new Error(
          `HTTP pull endpoint returned HTTP ${attempted.response.status}`,
        );
      }
      requireTransport(attempted.body, "http-peer");
      return attempted.body;
    },
    (value) => `status=${value.status} source=${value.peerSource}`,
  );
  if (!httpPull) {
    result.finish();
    return result;
  }

  await timedCall(
    result,
    "Bridge-network HTTP source attribution",
    () => requireTransport(httpPull, "http-peer"),
    () => `peerSource=${httpPull.peerSource}`,
  );
  await timedCall(
    result,
    "HTTP byte equality after local serve",
    () => requireByteEquality(urls.httpDestination, seed.cid!, payload),
    () => `bytes=${payload.length}`,
  );

  await timedCall(
    result,
    "iroh destination miss before transport",
    () => requireMissingDestination(urls.irohDestination, seed.cid!),
  );

  const irohPull = await timedCall(
    result,
    "iroh peering into initially-missing destination",
    async () => {
      const attempted = await pullFromProvider(
        urls.irohDestination,
        seed.cid!,
        seed.irohProvider!,
      );
      if (!attempted.response.ok) {
        throw new Error(
          `iroh pull endpoint returned HTTP ${attempted.response.status}`,
        );
      }
      requireTransport(attempted.body, "iroh-peer");
      return attempted.body;
    },
    (value) => `status=${value.status} source=${value.peerSource}`,
  );
  if (!irohPull) {
    result.finish();
    return result;
  }

  await timedCall(
    result,
    "iroh source attribution",
    () => requireTransport(irohPull, "iroh-peer"),
    () => `peerSource=${irohPull.peerSource}`,
  );
  await timedCall(
    result,
    "iroh byte equality after local serve",
    () => requireByteEquality(urls.irohDestination, seed.cid!, payload),
    () => `bytes=${payload.length}`,
  );

  result.stepSkipped(
    "Streamplace-origin and ATProto federation scope",
    "Not asserted: this Track A lab sets SP_NO_FIREHOSE=true and does not validate Streamplace origin records or cross-PDS federation. Track B remains a separate compatibility decision.",
  );
  result.recordArtifact("transport_results", {
    http: httpPull,
    iroh: irohPull,
  });
  result.finish();
  return result;
}

if (import.meta.main) {
  const result = await run();
  console.log(result.summary());
  Deno.exit(result.ok ? 0 : 1);
}
