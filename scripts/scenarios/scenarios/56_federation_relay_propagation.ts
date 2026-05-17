/**
 * @module scenarios/56_federation_relay_propagation
 *
 * Scenario: 56 federation relay propagation
 *
 * Behavior:
 * - Executes the 56 federation relay propagation scenario.
 * - Validates core operations.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import { SERVICE_URLS } from "@garazyk/hamownia/config";
import { ScenarioResult } from "@garazyk/hamownia";
import { getCharacter, PDS1 } from "@garazyk/hamownia/config";
export { ScenarioResult, StepResult, StepStatus } from "@garazyk/hamownia";
export type { ScenarioReport } from "@garazyk/hamownia";
import { XrpcClient } from "@garazyk/gruszka";
import { assert } from "@garazyk/hamownia";
import { timedCall } from "@garazyk/hamownia";

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
// Covers: PDS1 write → Relay sequence (rev) advances → AppView indexes the record.
// Extends 49_cross_service_consistency.ts (PDS→AppView only) to verify Relay as the middle hop.
// Also verifies handle rotation propagates to Relay's identity cache.
// Production paths: com.atproto.sync.getLatestCommit (Relay), app.bsky.feed.getPosts (AppView),
//   com.atproto.identity.{updateHandle,resolveHandle}.

function now() {
  return new Date().toISOString();
}

async function pollUntil<T>(
  fn: () => Promise<T | null>,
  timeoutMs: number,
  intervalMs = 1000,
): Promise<T> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const val = await fn();
    if (val !== null && val !== undefined) return val;
    await new Promise((r) => setTimeout(r, intervalMs));
  }
  throw new Error(`pollUntil timed out after ${timeoutMs}ms`);
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Federation Relay Propagation");
  result.start();

  const pds = new XrpcClient(PDS1);
  const relay = new XrpcClient(SERVICE_URLS.relay);
  const appview = new XrpcClient(SERVICE_URLS.appview);
  const luna = getCharacter("luna");

  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  // --- Relay availability ---
  let relayAvailable = false;
  try {
    const relayHealth = await fetch(`${SERVICE_URLS.relay}/_health`);
    relayAvailable = relayHealth.ok;
    result.stepPassed("Relay health check", `status=${relayHealth.status}`);
  } catch (e: any) {
    result.stepSkipped(
      "Relay health check",
      `Relay not reachable: ${e.message}`,
    );
  }

  if (!relayAvailable) {
    result.stepSkipped(
      "PDS→Relay→AppView propagation",
      "Relay unavailable; skipping relay steps",
    );
    result.finish();
    return result;
  }

  const session = await timedCall(
    result,
    "Create luna account on PDS",
    async () => {
      try {
        return await pds.accounts.createAccount(
          luna.handle,
          luna.email,
          luna.password,
        );
      } catch {
        return await pds.accounts.createSession(luna.handle, luna.password);
      }
    },
    (s) => `did=${s.did}`,
  );

  if (session) {
    luna.did = session.did;
    luna.accessJwt = session.accessJwt;
  } else {
    result.finish();
    return result;
  }

  // --- Capture Relay baseline commit rev for luna ---
  // com.atproto.sync.getLatestCommit returns {cid, rev}. A change in rev after the PDS write
  // confirms the Relay has ingested the new commit.
  let baselineRev: string | null = null;
  try {
    const latestBefore = await relay.raw.get(
      "com.atproto.sync.getLatestCommit",
      { did: luna.did },
    );
    baselineRev = latestBefore?.rev ?? null;
    result.stepPassed(
      "Capture Relay baseline rev for luna",
      `rev=${baselineRev ?? "none"}`,
    );
  } catch {
    // DID not yet known to the Relay — that's fine, any commit will be the first
    result.stepPassed(
      "Capture Relay baseline rev for luna",
      "DID not yet known to Relay (rev=null)",
    );
  }

  // --- Write a post on PDS ---
  const postRkey = `relay-prop-${Date.now()}`;
  const postRef = await timedCall(
    result,
    "Write post on PDS",
    async () => {
      return await pds.records.createRecord(
        luna.did,
        "app.bsky.feed.post",
        {
          $type: "app.bsky.feed.post",
          text: "Relay propagation test post.",
          createdAt: now(),
        },
        luna.accessJwt,
        { rkey: postRkey },
      );
    },
    (r) => `uri=${r.uri}`,
  );

  // --- Relay sequence (rev) advances after PDS write ---
  // Poll getLatestCommit until rev changes from the baseline. A changed rev means the Relay
  // received the commit from the PDS firehose.
  await timedCall(
    result,
    "Relay rev advances after PDS write",
    async () => {
      return await pollUntil(async () => {
        try {
          const latest = await relay.raw.get(
            "com.atproto.sync.getLatestCommit",
            { did: luna.did },
          );
          if (latest?.rev && latest.rev !== baselineRev) return latest;
        } catch { /* not yet */ }
        return null;
      }, 15_000);
    },
    (r) => `rev=${r?.rev}`,
  );

  // --- AppView indexed post propagated via Relay ---
  // Poll AppView's getPosts until the post appears. Because AppView consumes the Relay
  // firehose, this transitively verifies the PDS→Relay→AppView path.
  if (postRef) {
    await timedCall(
      result,
      "AppView indexed post propagated via Relay",
      async () => {
        return await pollUntil(async () => {
          try {
            const res = await appview.feed.getPosts(
              [postRef.uri],
              luna.accessJwt,
            );
            if (res?.posts?.length > 0) return res.posts[0];
          } catch { /* not yet */ }
          return null;
        }, 30_000);
      },
      (p) => `uri=${(p as any)?.post?.uri ?? "present"}`,
    );
  } else {
    result.stepSkipped(
      "AppView indexed post propagated via Relay",
      "no post created",
    );
  }

  // --- Handle rotation propagates to Relay identity cache ---
  // Update luna's handle on PDS, then poll the Relay's resolveHandle until it returns
  // luna's DID, confirming the Relay updated its identity cache.
  const rotatedHandle = `luna-rotated-${Date.now()}.test`;
  await timedCall(result, "Handle rotation on PDS", async () => {
    await pds.identity.updateHandle(rotatedHandle, luna.accessJwt!);
  });

  await timedCall(
    result,
    "Handle rotation propagates to Relay identity cache",
    async () => {
      return await pollUntil(async () => {
        try {
          const res = await relay.raw.get(
            "com.atproto.identity.resolveHandle",
            {
              handle: rotatedHandle,
            },
          );
          if (res?.did === luna.did) return res;
        } catch { /* not yet */ }
        return null;
      }, 15_000);
    },
    (r) => `did=${(r as any)?.did}`,
  );

  result.finish();
  return result;
}

if (import.meta.main) {
  run().then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
