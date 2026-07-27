/**
 * @module scenarios/98_network_partition_backfill
 *
 * Scenario: Network partition backfill for relay-PDS connectivity.
 *
 * Behavior:
 * - Creates a target account on PDS1 and posts several messages.
 * - Discovers the PDS and Relay Docker containers using PDS-anchored
 *   discovery (derives compose project prefix from the PDS container
 *   so multiple concurrent e2e stacks don't select the wrong relay).
 * - Disconnects the relay container from the PDS network to simulate
 *   a temporary network partition.
 * - During the partition, creates additional posts on the PDS.
 * - Reconnects the relay to the PDS network.
 * - Connects to the relay subscribeRepos firehose and asserts that
 *   the partition-era posts arrive via backfill.
 *
 * This exercises the relay's backfill mechanism: when a relay reconnects
 * to an upstream PDS after a disconnection, it must fetch any missed
 * events from the PDS's firehose repository.
 */

import { XrpcClient } from "../../lib/deno/client.ts";
import { getActor, PDS1, SERVICE_URLS } from "../../lib/deno/config.ts";
import {
  createAccountOrLogin,
  ScenarioResult,
  timedCall,
  now,
} from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { firehoseEventFromFrame, parseFirehoseFrame } from "../../lib/deno/firehose.ts";
import {
  discoverPdsContainer,
  discoverRelayContainer,
  dockerCli,
  disconnectFromNetwork,
  reconnectToNetwork,
} from "../../lib/deno/docker_discovery.ts";

// ---------------------------------------------------------------------------
// Minimal raw-WebSocket utilities (same pattern as scenarios 33, 96, 97)
// ---------------------------------------------------------------------------

async function connectRawWs(url: string): Promise<Deno.Conn> {
  const parsed = new URL(url);
  const host = parsed.hostname;
  const port = parseInt(parsed.port || "80");

  const conn = await Deno.connect({ hostname: host, port });
  const encoder = new TextEncoder();

  const key = btoa(
    String.fromCharCode(...crypto.getRandomValues(new Uint8Array(16))),
  );
  const request = `GET ${parsed.pathname}${parsed.search} HTTP/1.1\r\n` +
    `Host: ${host}:${port}\r\n` +
    `Upgrade: websocket\r\n` +
    `Connection: Upgrade\r\n` +
    `Sec-WebSocket-Key: ${key}\r\n` +
    `Sec-WebSocket-Version: 13\r\n\r\n`;

  await conn.write(encoder.encode(request));

  const buffer = new Uint8Array(4096);
  const n = await conn.read(buffer);
  const response = new TextDecoder().decode(buffer.subarray(0, n || 0));

  if (!response.includes("101")) {
    conn.close();
    throw new Error(`Upgrade failed: ${response}`);
  }

  return conn;
}

interface ParsedFrame {
  opcode: number;
  payload: Uint8Array;
}

class RawWsFrameReader {
  #conn: Deno.Conn;
  #buf: Uint8Array = new Uint8Array(0);

  constructor(conn: Deno.Conn) {
    this.#conn = conn;
  }

  #append(chunk: Uint8Array): void {
    const combined = new Uint8Array(this.#buf.length + chunk.length);
    combined.set(this.#buf, 0);
    combined.set(chunk, this.#buf.length);
    this.#buf = combined;
  }

  #tryParseFrame(): ParsedFrame | null {
    if (this.#buf.length < 2) return null;
    const opcode = this.#buf[0] & 0x0f;
    const masked = (this.#buf[1] & 0x80) !== 0;
    let payloadLen = this.#buf[1] & 0x7f;
    let offset = 2;

    if (payloadLen === 126) {
      if (this.#buf.length < 4) return null;
      payloadLen = (this.#buf[2] << 8) | this.#buf[3];
      offset = 4;
    } else if (payloadLen === 127) {
      if (this.#buf.length < 10) return null;
      payloadLen = (this.#buf[6] << 24) |
        (this.#buf[7] << 16) |
        (this.#buf[8] << 8) |
        this.#buf[9];
      offset = 10;
    }

    const maskLen = masked ? 4 : 0;
    const total = offset + maskLen + payloadLen;
    if (this.#buf.length < total) return null;

    let payload = this.#buf.slice(offset + maskLen, total);
    if (masked) {
      const mask = this.#buf.slice(offset, offset + 4);
      const unmasked = new Uint8Array(payload.length);
      for (let i = 0; i < payload.length; i++) {
        unmasked[i] = payload[i] ^ mask[i % 4];
      }
      payload = unmasked;
    }

    this.#buf = this.#buf.slice(total);
    return { opcode, payload };
  }

  async readUntil(
    deadlineMs: number,
    predicate: (frames: ParsedFrame[]) => boolean,
  ): Promise<{ frames: ParsedFrame[]; closed: boolean }> {
    const frames: ParsedFrame[] = [];
    let closed = false;
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      try {
        this.#conn.close();
      } catch {
        /* already closed */
      }
    }, deadlineMs);

    const readBuf = new Uint8Array(65536);
    try {
      while (!timedOut) {
        let frame = this.#tryParseFrame();
        while (frame) {
          frames.push(frame);
          if (frame.opcode === 0x8) closed = true;
          if (predicate(frames) || closed) {
            clearTimeout(timer);
            return { frames, closed };
          }
          frame = this.#tryParseFrame();
        }
        const n = await this.#conn.read(readBuf);
        if (n === null || n === 0) {
          closed = true;
          break;
        }
        this.#append(readBuf.subarray(0, n));
      }
    } catch {
      if (!timedOut) closed = true;
    } finally {
      clearTimeout(timer);
    }
    return { frames, closed };
  }
}

interface FirehoseEventLike {
  seq: number;
  type: string;
  body: Record<string, unknown>;
}

function decodeDataFrames(frames: ParsedFrame[]): FirehoseEventLike[] {
  const events: FirehoseEventLike[] = [];
  for (const f of frames) {
    if (f.opcode !== 0x2 && f.opcode !== 0x1) continue;
    try {
      const fe = firehoseEventFromFrame(parseFirehoseFrame(f.payload));
      events.push({ seq: fe.seq, type: fe.type, body: fe.body });
    } catch {
      // Not a decodable firehose frame; skip.
    }
  }
  return events;
}

// ---------------------------------------------------------------------------
// Scenario
// ---------------------------------------------------------------------------

const FIREHOSE_TIMEOUT_MS = 60_000;
const BACKFILL_POLL_INTERVAL_MS = 5_000;

/**
 * Collect firehose events from a subscribeRepos WebSocket until a predicate
 * is satisfied or the timeout expires.
 */
async function collectEvents(
  serviceUrl: string,
  timeoutMs: number,
  predicate: (events: FirehoseEventLike[]) => boolean,
): Promise<FirehoseEventLike[]> {
  const url = new URL(`${serviceUrl}/xrpc/com.atproto.sync.subscribeRepos`);
  const conn = await connectRawWs(url.toString());
  const reader = new RawWsFrameReader(conn);
  try {
    const { frames } = await reader.readUntil(timeoutMs, (seen) => {
      return predicate(decodeDataFrames(seen));
    });
    return decodeDataFrames(frames);
  } finally {
    try {
      conn.close();
    } catch {
      /* already closed */
    }
  }
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult(
    "Network Partition Backfill (Relay-PDS)",
  );
  result.start();

  const client = new XrpcClient(PDS1);

  // ── Step 1: Server health check ──────────────────────────────────
  await timedCall(result, "Server health check", async () => {
    await client.waitForHealthy(30);
  });
  if (result.failed > 0) { result.finish(); return result; }

  // ── Step 2: Create target account ────────────────────────────────
  const target = getActor("sasha");

  const session = await timedCall(
    result,
    "Create account: target",
    async () => {
      return await client.accounts.createAccount(
        target.handle,
        target.email,
        target.password,
      );
    },
  );
  if (!session) { result.finish(); return result; }
  target.did = session.did;
  target.accessJwt = session.accessJwt;

  if (!target.did) {
    result.stepFailed("Account creation", "No DID assigned to target");
    result.finish();
    return result;
  }

  // ── Step 3: Create pre-partition posts ───────────────────────────
  const prePartitionPosts: string[] = [];
  for (let i = 1; i <= 3; i++) {
    const postText = `pre-partition-post-${i}-${Date.now()}`;
    const ref = await timedCall(
      result,
      `Create pre-partition post ${i}`,
      async () => {
        return await client.records.createRecord(
          target.did!,
          "app.bsky.feed.post",
          {
            $type: "app.bsky.feed.post",
            text: postText,
            createdAt: now(),
          },
          target.accessJwt!,
        );
      },
      (ref) => `uri=${(ref as any)?.uri ?? "created"}`,
    );
    if (ref) prePartitionPosts.push((ref as any).uri);
  }

  // ── Step 4: Discover Docker containers (PDS-anchored) ────────────
  // Move discovery INSIDE timedCall so a failure is recorded as a
  // failed step instead of crashing the scenario unattributed.
  let pdsContainer: string | undefined;
  let relayContainer: string | undefined;

  const pdsDiscResult = await timedCall(
    result,
    "Discover PDS Docker container",
    async () => {
      return await discoverPdsContainer();
    },
  );
  pdsContainer = pdsDiscResult ?? undefined;

  if (pdsContainer) {
    const relayDiscResult = await timedCall(
      result,
      "Discover relay Docker container (PDS-anchored)",
      async () => {
        return await discoverRelayContainer(pdsContainer!);
      },
    );
    relayContainer = relayDiscResult ?? undefined;
  }

  // If docker discovery failed, skip the partition steps and
  // do a basic firehose verification instead
  if (!pdsContainer || !relayContainer) {
    result.stepSkipped(
      "Network partition simulation",
      "Docker containers not available — skipping partition steps",
    );

    // Fallback: verify firehose works with pre-partition posts
    const hasPrePartition = await timedCall(
      result,
      "Verify pre-partition posts appear on firehose (no partition)",
      async () => {
        const events = await collectEvents(
          PDS1,
          FIREHOSE_TIMEOUT_MS,
          (events) => {
            return events.some((e) =>
              e.type === "#commit" &&
              (e.body as any).ops?.some((op: any) =>
                op.path?.startsWith("app.bsky.feed.post/")
              )
            );
          },
        );
        const commitEvents = events.filter((e) => e.type === "#commit");
        if (commitEvents.length === 0) {
          throw new Error("No #commit events received on firehose");
        }
        return commitEvents.length;
      },
      (count) => `${count} commit events received`,
    );
    if (!hasPrePartition) {
      result.finish();
      return result;
    }
  }

  // ── Step 5: Get the Docker network name ─────────────────────────
  // We need to know which network the PDS is on so we can disconnect
  // the relay from it (not the PDS itself, which would lose our session).
  let networkName: string | undefined;

  if (pdsContainer) {
    await timedCall(
      result,
      "Get PDS Docker network name",
      async () => {
        // Docker Compose creates a network named <project>_default or
        // <project>_<network>. Inspect the PDS container for its networks.
        const inspectOutput = await dockerCli([
          "inspect", pdsContainer!,
          "--format", "{{json .NetworkSettings.Networks}}",
        ]);
        const networks = JSON.parse(inspectOutput.trim());
        const names = Object.keys(networks);
        if (names.length === 0) {
          throw new Error("PDS container has no networks");
        }
        // Prefer the topology network (not the default bridge)
        const topologyNet = names.find((n) => n.includes("topology"));
        networkName = topologyNet || names[0];
      },
      () => `network=${networkName}`,
    );
  }

  // ── Step 6: Disconnect relay from PDS network ────────────────────
  if (relayContainer && networkName) {
    await timedCall(
      result,
      "Disconnect relay from PDS network (simulate partition)",
      async () => {
        await disconnectFromNetwork(relayContainer!, networkName!);
      },
      () => `disconnected ${relayContainer} from ${networkName}`,
    );

    // Give the disconnection time to take effect
    await new Promise((r) => setTimeout(r, 2000));

    // ── Step 7: Create posts during partition ──────────────────────
    const partitionPosts: string[] = [];
    for (let i = 1; i <= 3; i++) {
      const postText = `partition-post-${i}-${Date.now()}`;
      const ref = await timedCall(
        result,
        `Create post during partition ${i}`,
        async () => {
          return await client.records.createRecord(
            target.did!,
            "app.bsky.feed.post",
            {
              $type: "app.bsky.feed.post",
              text: postText,
              createdAt: now(),
            },
            target.accessJwt!,
          );
        },
        (ref) => `uri=${(ref as any)?.uri ?? "created"}`,
      );
      if (ref) partitionPosts.push((ref as any).uri);
    }

    // ── Step 8: Reconnect relay to PDS network ────────────────────
    await timedCall(
      result,
      "Reconnect relay to PDS network",
      async () => {
        await reconnectToNetwork(relayContainer!, networkName!);
      },
      () => `reconnected ${relayContainer} to ${networkName}`,
    );

    // Give the reconnection time to establish and backfill to begin.
    // Increased from 3s to 12s to accommodate the relay's reconnect pipeline:
    //   TCP disconnect detection (~3s) + 5s base reconnect delay +
    //   WebSocket establishment + PDS cursor replay + event propagation ~4-5s
    await new Promise((r) => setTimeout(r, 12_000));

    // ── Step 9: Verify backfill via relay firehose ─────────────────
    const relayUrl = SERVICE_URLS.relay;
    if (relayUrl) {
      // Collect events from the relay's subscribeRepos and look for
      // the partition-era posts being re-broadcast.
      const allPostUris = [...prePartitionPosts, ...partitionPosts];

      await timedCall(
        result,
        "Relay backfill delivers partition-era posts",
        async () => {
          const events = await collectEvents(
            relayUrl,
            FIREHOSE_TIMEOUT_MS,
            (events) => {
              // Check if we've seen all partition-era posts
              const seenUris = new Set<string>();
              for (const e of events) {
                if (e.type === "#commit") {
                  const ops = (e.body as any).ops ?? [];
                  for (const op of ops) {
                    if (op.path?.startsWith("app.bsky.feed.post/")) {
                      seenUris.add(op.path);
                    }
                  }
                }
              }
              return allPostUris.every((uri) => {
                const path = uri.split("/").pop();
                return path && seenUris.has(`app.bsky.feed.post/${path}`);
              });
            },
          );
          const commitEvents = events.filter((e) => e.type === "#commit");
          if (commitEvents.length === 0) {
            throw new Error(
              "No #commit events received on relay firehose",
            );
          }
          // Check that partition-era posts arrived specifically
          const partitionOpPaths = new Set<string>();
          for (const e of events) {
            if (e.type === "#commit") {
              const ops = (e.body as any).ops ?? [];
              for (const op of ops) {
                if (op.path?.startsWith("app.bsky.feed.post/")) {
                  partitionOpPaths.add(op.path);
                }
              }
            }
          }
          const foundAllPartition = allPostUris.every((uri) => {
            const path = uri.split("/").pop();
            return path && partitionOpPaths.has(`app.bsky.feed.post/${path}`);
          });
          if (!foundAllPartition) {
            throw new Error(
              `Not all posts found in relay firehose. ` +
              `Expected ${allPostUris.length} posts, ` +
              `found ${partitionOpPaths.size} unique post ops.`,
            );
          }
          return;
        },
        () =>
          `verified ${allPostUris.length} posts (${prePartitionPosts.length} pre-partition + ${partitionPosts.length} partition-era)`,
      );

      result.recordArtifact("backfill_verification", {
        target_did: target.did,
        pre_partition_posts: prePartitionPosts,
        partition_posts: partitionPosts,
        all_verified: true,
      });
    } else {
      result.stepSkipped(
        "Relay backfill verification",
        "No relay URL configured — cannot verify backfill",
      );
    }
  } else {
    result.stepSkipped(
      "Network partition simulation",
      !relayContainer
        ? "Relay container not discovered — skipping partition steps"
        : "Network name not resolved — skipping partition steps",
    );
  }

  result.finish();
  return result;
}

if (import.meta.main) {
  run().then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
