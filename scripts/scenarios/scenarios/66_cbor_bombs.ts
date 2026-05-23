import { encode } from "cborg";
import { parseFirehoseFrame, FirehoseFrameParseError } from "../../lib/deno/firehose.ts";
import { getActor, PDS1 } from "../../lib/deno/config.ts";
import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { assert } from "../../lib/deno/assertions.ts";

function craftArrayLengthBomb(length: number): Uint8Array {
  const buf = new Uint8Array(9);
  buf[0] = 0x9b;
  buf[1] = (length >> 56) & 0xff;
  buf[2] = (length >> 48) & 0xff;
  buf[3] = (length >> 40) & 0xff;
  buf[4] = (length >> 32) & 0xff;
  buf[5] = (length >> 24) & 0xff;
  buf[6] = (length >> 16) & 0xff;
  buf[7] = (length >> 8) & 0xff;
  buf[8] = length & 0xff;
  return buf;
}

function craftArrayBombFrame(arrayLength: number): Uint8Array {
  const headerBytes = encode({ op: 1, t: "#commit" });
  const bodyBytes = craftArrayLengthBomb(arrayLength);
  return new Uint8Array([...headerBytes, ...bodyBytes]);
}

function buildNestedObject(depth: number): Record<string, unknown> {
  let obj: Record<string, unknown> = { a: 1 };
  for (let i = 0; i < depth; i++) {
    obj = { n: obj };
  }
  return obj;
}

function craftDeepNestFrame(depth: number): Uint8Array {
  const headerBytes = encode({ op: 1, t: "#commit" });
  const bodyNested = buildNestedObject(depth);
  const bodyBytes = encode(bodyNested);
  return new Uint8Array([...headerBytes, ...bodyBytes]);
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("CBOR Bombs");
  result.start();

  const client = new XrpcClient(PDS1);

  await timedCall(result, "PDS health check", async () => {
    await client.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const troll = getActor("troll");
  const session = await timedCall(result, "Create troll account", async () => {
    return await client.accounts.createAccount(troll.handle, troll.email, troll.password);
  });

  if (!session) {
    result.finish();
    return result;
  }
  troll.did = session.did;
  troll.accessJwt = session.accessJwt;

  // Phase A: CBOR Array Length Bomb
  await timedCall(result, "Phase A: CBOR Array Length Bomb", async () => {
    const frame = craftArrayBombFrame(100_000_000);
    let threw = false;
    try {
      parseFirehoseFrame(frame);
    } catch (e) {
      threw = true;
      assert.isTrue(
        e instanceof FirehoseFrameParseError,
        `Expected FirehoseFrameParseError, got ${(e as Error).name}: ${(e as Error).message}`,
      );
    }
    assert.isTrue(threw, "Expected parseFirehoseFrame to throw for array length bomb");
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  // Phase B: Deeply Nested CBOR
  await timedCall(result, "Phase B: Deeply Nested CBOR", async () => {
    const frame = craftDeepNestFrame(500);
    let threw = false;
    try {
      parseFirehoseFrame(frame);
    } catch (e) {
      threw = true;
      assert.isTrue(
        e instanceof FirehoseFrameParseError,
        `Expected FirehoseFrameParseError, got ${(e as Error).name}: ${(e as Error).message}`,
      );
    }
    assert.isTrue(threw, "Expected parseFirehoseFrame to throw for deep nest");
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  // Phase C: PDS Health Verification
  await timedCall(result, "Phase C: PDS Health Verification", async () => {
    await client.waitForHealthy(10);
  });

  result.finish();
  return result;
}

if (import.meta.main) {
  const res = await run();
  console.log(res.summary());
  Deno.exit(res.ok ? 0 : 1);
}
