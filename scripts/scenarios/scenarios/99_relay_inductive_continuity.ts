/**
 * @module scenarios/99_relay_inductive_continuity
 *
 * Verifies that a relay forwards consecutive inductive commit events and that
 * each event links to the previous repository revision and MST data root,
 * rather than incorrectly linking prevData to the previous commit CID.
 */

import { XrpcClient } from "../../lib/deno/client.ts";
import { getActor, PDS1, SERVICE_URLS } from "../../lib/deno/config.ts";
import {
  createAccountOrLogin,
  now,
  ScenarioResult,
  timedCall,
} from "../../lib/deno/runner.ts";
export {
  ScenarioResult,
  StepResult,
  StepStatus,
} from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { FirehoseClient, type FirehoseEvent } from "../../lib/deno/firehose.ts";

function cidString(value: unknown): string {
  if (typeof value === "string") return value;
  if (value && typeof value === "object") {
    const rendered = String(value);
    if (rendered !== "[object Object]") return rendered;
  }
  return "";
}

function eventContainsRkey(event: FirehoseEvent, rkey: string): boolean {
  const ops = Array.isArray(event.body.ops) ? event.body.ops : [];
  return ops.some((op) => {
    if (!op || typeof op !== "object") return false;
    return (op as Record<string, unknown>).path ===
      `app.bsky.feed.post/${rkey}`;
  });
}

interface CreatedRecord {
  uri: string;
}

/** Runs the relay inductive-continuity scenario. */
export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Relay Inductive Commit Continuity");
  result.start();

  const pds = new XrpcClient(PDS1);
  const relay = new XrpcClient(SERVICE_URLS.relay);

  await timedCall(result, "PDS and relay health checks", async () => {
    await pds.waitForHealthy(30);
    await relay.raw.httpGet("/api/relay/health");
  });
  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const actor = getActor("nova");
  const session = await timedCall(
    result,
    "Create continuity test account",
    () => createAccountOrLogin(pds, actor),
    (value) => `did=${value.did}`,
  );
  if (!session) {
    result.finish();
    return result;
  }
  actor.did = session.did;
  actor.accessJwt = session.accessJwt;

  const firehose = new FirehoseClient(
    SERVICE_URLS.relay.replace(/^http/, "ws"),
  );
  const collection = firehose.collect(12);
  await new Promise((resolve) => setTimeout(resolve, 750));

  const recordRkeys: string[] = [];
  for (let index = 1; index <= 3; index++) {
    const created = await timedCall(
      result,
      `Create continuity post ${index}`,
      async (): Promise<CreatedRecord> =>
        await pds.records.createRecord(
          actor.did!,
          "app.bsky.feed.post",
          {
            $type: "app.bsky.feed.post",
            text: `relay-continuity-${index}-${Date.now()}`,
            createdAt: now(),
          },
          actor.accessJwt!,
        ) as CreatedRecord,
      (value) => `uri=${value.uri}`,
    );
    if (created?.uri) {
      recordRkeys.push(created.uri.split("/").pop()!);
    }
  }

  const events = await collection;
  const targetCommits = events
    .filter((event) =>
      event.type === "#commit" && event.body.repo === actor.did &&
      recordRkeys.some((rkey) => eventContainsRkey(event, rkey))
    )
    .sort((left, right) => left.seq - right.seq);

  await timedCall(
    result,
    "Verify consecutive relay commit links",
    () => {
      if (targetCommits.length < 3) {
        throw new Error(
          `Expected 3 target commits from relay, received ${targetCommits.length}`,
        );
      }
      for (let index = 1; index < targetCommits.length; index++) {
        const previous = targetCommits[index - 1];
        const current = targetCommits[index];
        if (current.body.since !== previous.body.rev) {
          throw new Error(
            `since mismatch at seq=${current.seq}: ` +
              `${String(current.body.since)} != ${String(previous.body.rev)}`,
          );
        }
        const prevData = cidString(current.body.prevData);
        const previousCommit = cidString(previous.body.commit);
        if (!prevData) {
          throw new Error(`Missing prevData at seq=${current.seq}`);
        }
        if (prevData === previousCommit) {
          throw new Error(
            `prevData incorrectly equals previous commit CID at seq=${current.seq}`,
          );
        }
      }
      return targetCommits;
    },
    (commits) =>
      `verified=${commits.length} seqs=${commits.map((e) => e.seq).join(",")}`,
  );

  result.recordArtifact("relay_continuity", {
    did: actor.did,
    record_rkeys: recordRkeys,
    commit_count: targetCommits.length,
    commits: targetCommits.map((event) => ({
      seq: event.seq,
      rev: event.body.rev,
      since: event.body.since,
      commit: cidString(event.body.commit),
      prev_data: cidString(event.body.prevData),
    })),
  });

  result.finish();
  return result;
}

if (import.meta.main) {
  const result = await run();
  result.printSummary();
  Deno.exit(result.ok ? 0 : 1);
}
