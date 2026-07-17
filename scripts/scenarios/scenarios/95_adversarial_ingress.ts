/**
 * @module scenarios/95_adversarial_ingress
 *
 * Scenario: Adversarial ingress through the live Objective-C boundary.
 *
 * Behavior:
 * - Sends genuinely malformed and oversized raw HTTP payloads directly at
 *   the live PDS's repo/blob XRPC endpoints (not the Deno-side firehose
 *   parser — see scenarios 65/66, which only ever exercise the client
 *   library's parser and never touch the wire).
 * - Asserts each malformed request is rejected with a 4xx (not a crash or
 *   5xx), then asserts the PDS is still healthy afterward.
 *
 * Prior art: scenario 64 (MST poisoning) is the one existing scenario that
 * hits a live endpoint with adversarial input, but its records are
 * well-formed JSON (just numerous/colliding); this scenario targets
 * malformed bytes at the transport/encoding level instead.
 */

import { getActor, PDS1 } from "../../lib/deno/config.ts";
import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { assert } from "../../lib/deno/assertions.ts";

/** Extract an HTTP status from a raw postRaw() rejection, if any. */
function statusFromError(e: unknown): number {
  if (e instanceof XrpcError) return e.status;
  if (typeof e === "object" && e !== null && "message" in e) {
    const message = (e as { message: unknown }).message;
    if (typeof message === "string") {
      const m = message.match(/\b(4\d\d|5\d\d)\b/);
      if (m) return Number(m[1]);
    }
  }
  return 0;
}

/** com.atproto.repo.applyWrites expects a JSON body; this is truncated
 * mid-object and cannot be parsed as JSON at all. */
const TRUNCATED_JSON = new TextEncoder().encode(
  '{"repo":"placeholder","writes":[{"$type":"com.atproto.repo.applyWrites#create","collection":"app.bsky.feed.post","value":{"text":"untermi',
);

/** Syntactically valid JSON, but a 10MB text field — far beyond any
 * reasonable post/record size limit. */
function oversizedCreateRecordBody(repo: string): Uint8Array {
  const hugeText = "A".repeat(10 * 1024 * 1024);
  const body = JSON.stringify({
    repo,
    collection: "app.bsky.feed.post",
    record: {
      $type: "app.bsky.feed.post",
      text: hugeText,
      createdAt: new Date().toISOString(),
    },
  });
  return new TextEncoder().encode(body);
}

/** com.atproto.repo.uploadBlob accepts a raw binary body; this is neither
 * a real image/video nor anything resembling a valid blob container, just
 * adversarial junk bytes at a size that exercises the ingest path. */
function junkBlobBytes(): Uint8Array {
  const bytes = new Uint8Array(2 * 1024 * 1024);
  crypto.getRandomValues(bytes.subarray(0, 65536));
  // Repeat the random prefix rather than calling getRandomValues on the
  // full 2MB (subarray size limits on some runtimes) — still non-trivial,
  // non-decodable junk from the server's point of view.
  for (let offset = 65536; offset < bytes.length; offset += 65536) {
    bytes.set(bytes.subarray(0, Math.min(65536, bytes.length - offset)), offset);
  }
  return bytes;
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Adversarial Ingress (Live Boundary)");
  result.start();

  const client = new XrpcClient(PDS1);
  const gremlin = getActor("troll");

  await timedCall(result, "Server health check", async () => {
    await client.waitForHealthy(30);
  });
  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const session = await timedCall(result, "Create account: gremlin", async () => {
    return await client.accounts.createAccount(
      gremlin.handle,
      gremlin.email,
      gremlin.password,
    );
  });
  if (!session) {
    result.finish();
    return result;
  }
  gremlin.did = session.did;
  gremlin.accessJwt = session.accessJwt;

  await timedCall(result, "Truncated/malformed JSON rejected", async () => {
    let status = 0;
    try {
      await client.raw.postRaw(
        "com.atproto.repo.applyWrites",
        TRUNCATED_JSON,
        "application/json",
        { token: gremlin.accessJwt },
      );
    } catch (e: unknown) {
      status = statusFromError(e);
    }
    assert.isTrue(
      status >= 400 && status < 500,
      `Expected a 4xx rejection for truncated JSON, observed status=${status}`,
    );
  });

  await timedCall(result, "PDS healthy after malformed JSON", async () => {
    await client.waitForHealthy(15);
  });

  await timedCall(result, "Oversized record body rejected", async () => {
    let status = 0;
    try {
      await client.raw.postRaw(
        "com.atproto.repo.createRecord",
        oversizedCreateRecordBody(gremlin.did!),
        "application/json",
        { token: gremlin.accessJwt },
      );
    } catch (e: unknown) {
      status = statusFromError(e);
    }
    assert.isTrue(
      status >= 400 && status < 500,
      `Expected a 4xx rejection for a 10MB record body, observed status=${status}`,
    );
  });

  await timedCall(result, "PDS healthy after oversized record", async () => {
    await client.waitForHealthy(15);
  });

  await timedCall(result, "Junk binary blob rejected", async () => {
    let status = 0;
    try {
      await client.raw.postRaw(
        "com.atproto.repo.uploadBlob",
        junkBlobBytes(),
        "application/octet-stream",
        { token: gremlin.accessJwt },
      );
    } catch (e: unknown) {
      status = statusFromError(e);
    }
    // A junk-but-plausible-size blob may legitimately be *accepted* (the
    // PDS doesn't necessarily validate blob content, only that it's
    // storable) — the real assertion is "did not crash the process",
    // covered by the health check below. Only flag a hard failure on an
    // actual 5xx (a real crash/exception path), not a 2xx/4xx either way.
    assert.isTrue(
      status < 500,
      `Expected no 5xx for a junk binary blob, observed status=${status}`,
    );
  });

  await timedCall(result, "PDS healthy after junk blob", async () => {
    await client.waitForHealthy(15);
  });

  result.finish();
  return result;
}

if (import.meta.main) {
  run().then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
