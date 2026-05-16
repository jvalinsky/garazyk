/**
 * @module scenarios/33_tortoise_consumer
 *
 * Scenario: 33 tortoise consumer
 *
 * Behavior:
 * - Executes the 33 tortoise consumer scenario.
 * - Validates core operations.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import { PDS1, getCharacter } from "../../lib/deno/config.ts";
import { ScenarioResult } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { timedCall } from "../../lib/deno/runner.ts";

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */


function now() {
  return new Date().toISOString();
}

async function connectRawWs(url: string) {
  const parsed = new URL(url);
  const host = parsed.hostname;
  const port = parseInt(parsed.port || "80");

  const conn = await Deno.connect({ hostname: host, port });
  const encoder = new TextEncoder();

  const key = btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(16))));
  const request = `GET /xrpc/com.atproto.sync.subscribeRepos HTTP/1.1\r\n` +
    `Host: ${host}:${port}\r\n` +
    `Upgrade: websocket\r\n` +
    `Connection: Upgrade\r\n` +
    `Sec-WebSocket-Key: ${key}\r\n` +
    `Sec-WebSocket-Version: 13\r\n\r\n`;

  await conn.write(encoder.encode(request));

  // Read upgrade response
  const buffer = new Uint8Array(4096);
  const n = await conn.read(buffer);
  const response = new TextDecoder().decode(buffer.subarray(0, n || 0));

  if (!response.includes("101")) {
    conn.close();
    throw new Error(`Upgrade failed: ${response}`);
  }

  return conn;
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Firehose Backpressure (Tortoise Consumer)");
  result.start();

  const client = new XrpcClient(PDS1);
  await timedCall(result, "Server health check", async () => {
    await client.waitForHealthy(30);
  });

  if (result.failed > 0) return result;

  const volt = getCharacter("volt");
  const session = await timedCall(result, "Create account: volt", async () => {
    return await client.accounts.createAccount(volt.handle, volt.email, volt.password);
  });

  if (!session) {
    result.finish();
    return result;
  }
  volt.did = session.did;
  volt.accessJwt = session.accessJwt;

  let conn: Deno.Conn;
  try {
    conn = await connectRawWs(PDS1);
    result.stepPassed("Connect to firehose");
  } catch (e) {
    result.stepFailed("Connect to firehose", String(e));
    result.finish();
    return result;
  }

  // Read a few initial bytes to confirm traffic
  const buf = new Uint8Array(1024);
  await conn.read(buf);

  // Now stop reading and generate traffic
  const POST_COUNT = 600;
  console.log(`Generating ${POST_COUNT} posts...`);
  for (let i = 0; i < POST_COUNT; i++) {
    try {
      await client.records.createRecord(volt.did, "app.bsky.feed.post", {
        $type: "app.bsky.feed.post", text: `backpressure test ${i}`, createdAt: now()
      }, volt.accessJwt);
    } catch { /* ignore */ }
    if (i % 100 === 0) console.log(`  Sent ${i} records...`);
  }

  console.log("Waiting for PDS to drop connection...");
  let closed = false;
  const deadline = Date.now() + 90000;

  while (Date.now() < deadline) {
    try {
      const n = await conn.read(buf);
      if (n === null) {
        closed = true;
        break;
      }
    } catch {
      closed = true;
      break;
    }
    await new Promise(r => setTimeout(r, 1000));
  }

  if (closed) {
    result.stepPassed("Firehose disconnected (slow consumer dropped)");
  } else {
    result.stepFailed("Firehose disconnected", "Connection still open or timed out");
  }

  try { conn.close(); } catch { /* ignore */ }
  result.finish();
  return result;
}

if (import.meta.main) {
  run().then(res => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}