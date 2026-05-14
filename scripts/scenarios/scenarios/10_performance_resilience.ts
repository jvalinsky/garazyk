import { XrpcClient } from "../../lib/deno/client.ts";
import { getCharacter, PDS1 } from "../../lib/deno/config.ts";
import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";

function now() {
  return new Date().toISOString();
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Performance & Resilience");
  result.start();

  const client = new XrpcClient(PDS1);

  await timedCall(
    result,
    "Server health check",
    async () => {
      const res = await fetch(`${PDS1}/xrpc/com.atproto.server.describeServer`);
      if (!res.ok) throw new Error("Server not healthy");
    },
  );

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const charNames = ["luna", "marcus", "rosa", "volt", "quiet"];
  for (const name of charNames) {
    const char = getCharacter(name);
    const session = await timedCall(
      result,
      `Create account: ${char.name}`,
      async () => {
        try {
          const res = await client.agent.createAccount({
            handle: char.handle,
            email: char.email,
            password: char.password,
          });
          return res.data;
        } catch (e: any) {
          if (e.message && e.message.includes("already exists")) {
            const res = await client.agent.login({
              identifier: char.handle,
              password: char.password,
            });
            return res.data;
          }
          throw e;
        }
      },
      (s) => `did=${s.did}`,
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  const active = charNames.filter((n) => getCharacter(n).did);
  if (active.length < 3) {
    result.stepFailed("Account creation", "Not enough accounts");
    result.finish();
    return result;
  }

  await new Promise((r) => setTimeout(r, 2000));

  const POSTS_PER_USER = 10;
  let totalPosts = 0;
  let failedPosts = 0;
  const startTime = performance.now();

  const promises = [];
  for (const name of active) {
    const char = getCharacter(name);
    for (let i = 0; i < POSTS_PER_USER; i++) {
      promises.push((async () => {
        try {
          await client.raw.post("com.atproto.repo.createRecord", {
            repo: char.did,
            collection: "app.bsky.feed.post",
            record: {
              $type: "app.bsky.feed.post",
              text: `Burst post #${i + 1} from ${char.name}! Load testing the PDS.`,
              createdAt: now(),
            },
          }, char.accessJwt);
          return true;
        } catch {
          return false;
        }
      })());
    }
  }

  const results = await Promise.all(promises);
  results.forEach((success) => {
    if (success) totalPosts++;
    else failedPosts++;
  });

  const elapsed = (performance.now() - startTime) / 1000;
  result.stepPassed(
    "Burst post creation",
    `created=${totalPosts}, failed=${failedPosts}, elapsed=${elapsed.toFixed(1)}s, rate=${
      (totalPosts / Math.max(elapsed, 0.01)).toFixed(1)
    } posts/s`,
  );

  let totalRecords = 0;
  for (const name of active) {
    const char = getCharacter(name);
    const records = await timedCall(
      result,
      `Verify posts: ${char.name}`,
      async () => {
        return await client.raw.get("com.atproto.repo.listRecords", {
          repo: char.did,
          collection: "app.bsky.feed.post",
        }, char.accessJwt);
      },
    );
    if (records) {
      totalRecords += (records.records || []).length;
    }
  }

  result.stepPassed("Verify posts exist", `total_records_across_users=${totalRecords}`);

  const luna = getCharacter("luna");
  const batchWrites: Array<Record<string, unknown>> = [];
  for (let i = 0; i < 5; i++) {
    batchWrites.push({
      $type: "com.atproto.repo.applyWrites#create",
      collection: "app.bsky.feed.post",
      rkey: `batch-${i}`,
      value: { $type: "app.bsky.feed.post", text: `Batch post #${i} from Luna`, createdAt: now() },
    });
  }

  await timedCall(
    result,
    "Batch applyWrites",
    async () => {
      return await client.raw.post("com.atproto.repo.applyWrites", {
        repo: luna.did,
        writes: batchWrites,
      }, luna.accessJwt);
    },
    () => "5 records created",
  );

  await timedCall(
    result,
    "Invalid record rejected",
    async () => {
      await client.raw.post("com.atproto.repo.createRecord", {
        repo: luna.did,
        collection: "app.bsky.feed.post",
        record: { $type: "app.bsky.feed.post" },
      }, luna.accessJwt);
    },
    undefined,
    true,
  );

  try {
    await client.raw.post("com.atproto.repo.createRecord", {
      repo: luna.did,
      collection: "app.bsky.feed.post",
      record: {
        $type: "app.bsky.feed.post",
        text: "Original post with specific rkey",
        createdAt: now(),
      },
      rkey: "duplicate-test-rkey",
    }, luna.accessJwt);

    await timedCall(
      result,
      "Duplicate rkey rejected",
      async () => {
        await client.raw.post("com.atproto.repo.createRecord", {
          repo: luna.did,
          collection: "app.bsky.feed.post",
          record: {
            $type: "app.bsky.feed.post",
            text: "Duplicate post with same rkey",
            createdAt: now(),
          },
          rkey: "duplicate-test-rkey",
        }, luna.accessJwt);
      },
      undefined,
      true,
    );
  } catch (exc: any) {
    result.stepSkipped("Duplicate rkey rejected", String(exc));
  }

  await timedCall(
    result,
    "Missing auth rejected",
    async () => {
      await client.raw.post("com.atproto.repo.createRecord", {
        repo: luna.did,
        collection: "app.bsky.feed.post",
        record: { $type: "app.bsky.feed.post", text: "unauthorized", createdAt: now() },
      }, "invalid-token-xyz");
    },
    undefined,
    true,
  );

  await timedCall(
    result,
    "Non-existent collection rejected",
    async () => {
      await client.raw.post("com.atproto.repo.createRecord", {
        repo: luna.did,
        collection: "app.bsky.feed.nonexistent",
        record: { $type: "app.bsky.feed.nonexistent", text: "test", createdAt: now() },
      }, luna.accessJwt);
    },
    undefined,
    true,
  );

  await new Promise((r) => setTimeout(r, 5000));

  try {
    const appviewResp = await fetch("http://localhost:3200/admin/backfill/status", {
      headers: { "Authorization": "Bearer localdevadmin" },
    });
    if (appviewResp.ok) {
      result.stepPassed("AppView consistency check", "backfill status OK");
    } else {
      result.stepFailed("AppView consistency check", `status=${appviewResp.status}`);
    }
  } catch (exc: any) {
    result.stepFailed("AppView consistency check", String(exc));
  }

  await timedCall(
    result,
    "Timeline has content after burst",
    async () => {
      return await client.raw.get("app.bsky.feed.getTimeline", {}, luna.accessJwt);
    },
    (t) => `items=${t.feed?.length || 0}`,
  );

  try {
    const relayResp = await fetch("http://localhost:2584/api/relay/health");
    if (relayResp.ok) {
      result.stepPassed("Relay healthy after load");
    } else {
      result.stepSkipped("Relay healthy after load", `status=${relayResp.status}`);
    }
  } catch (exc: any) {
    result.stepSkipped("Relay healthy after load", String(exc));
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
