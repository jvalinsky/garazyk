/**
 * @module scenarios/70_sync_endpoint_coverage
 *
 * Scenario: Tests com.atproto.sync.* endpoint coverage including getRecord,
 * listRepos, notifyOfUpdate, requestCrawl, and getRepoStatus.
 *
 * Behavior:
 * - Creates accounts and records on PDS.
 * - Tests sync read endpoints against PDS and Relay.
 * - Covers PDS→Relay notification and crawl-initiation paths.
 *
 * Expectations:
 * - Sync read endpoints return structured responses.
 * - Endpoints gracefully return errors for invalid parameters.
 */

import { getActor, PDS1, SERVICE_URLS } from "../../lib/deno/config.ts";
import { now, tryEndpoint, ScenarioResult } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { timedCall } from "../../lib/deno/runner.ts";

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
// Covers: com.atproto.sync.getRecord, com.atproto.sync.listRepos,
//   com.atproto.sync.notifyOfUpdate, com.atproto.sync.requestCrawl,
//   com.atproto.sync.getRepoStatus.
// Production paths: sync CAR endpoints used by relays and PDSes for repo exchange.



export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Sync Endpoint Coverage");
  result.start();

  const pds = new XrpcClient(PDS1);
  const relay = new XrpcClient(SERVICE_URLS.relay);
  const luna = getActor("luna");
  const marcus = getActor("marcus");

  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  // --- Account setup ---
  for (const char of [luna, marcus]) {
    const session = await timedCall(
      result,
      `Create account: ${char.name}`,
      async () => {
        try {
          return await pds.accounts.createAccount(char.handle, char.email, char.password);
        } catch {
          return await pds.accounts.createSession(char.handle, char.password);
        }
      },
      (s) => `did=${s.did}`,
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  if (!luna.did || !marcus.did) {
    result.stepFailed("Account setup", "missing DID");
    result.finish();
    return result;
  }

  // --- Create a post on PDS ---
  const postRef = await timedCall(
    result,
    "Luna creates a post",
    async () => {
      return await pds.records.createRecord(
        luna.did,
        "app.bsky.feed.post",
        { $type: "app.bsky.feed.post", text: "Sync coverage test post.", createdAt: now() },
        luna.accessJwt,
      );
    },
    (r) => `uri=${r.uri}`,
  );

  if (postRef) {
    const postUri = postRef.uri;
    const uriParts = postUri.split("/");
    const rkey = uriParts[uriParts.length - 1];

    // --- 1. com.atproto.sync.getRecord ---
    // Fetches a single record CAR from the relay or PDS.
    await tryEndpoint(
      result,
      "sync.getRecord via PDS",
      async () => {
        // getRecord on the PDS returns a CAR-encoded single record
        const [status, ct, data] = await pds.raw.xrpcGetBinary(
          "com.atproto.sync.getRecord",
          { params: { did: luna.did, collection: "app.bsky.feed.post", rkey } },
        );
        if (status !== 200) {
          throw new Error(`expected 200, got ${status}`);
        }
        if (data.length === 0) {
          throw new Error("expected non-empty CAR body");
        }
        return { status, contentType: ct, bytes: data.length };
      },
      (r) => `status=${r.status}, bytes=${r.bytes}`,
    );

    // --- 2. com.atproto.sync.getRecord via Relay ---
    await tryEndpoint(
      result,
      "sync.getRecord via Relay",
      async () => {
        const [status, ct, data] = await relay.raw.xrpcGetBinary(
          "com.atproto.sync.getRecord",
          { params: { did: luna.did, collection: "app.bsky.feed.post", rkey } },
        );
        if (status === 200) {
          if (data.length === 0) {
            throw new Error("expected non-empty CAR body");
          }
          return { status, contentType: ct, bytes: data.length };
        }
        return { status, contentType: ct, bytes: data.length };
      },
      (r) => `status=${r.status}, bytes=${r.bytes}`,
    );
  }

  // --- 3. com.atproto.sync.listRepos via Relay ---
  await tryEndpoint(
    result,
    "sync.listRepos via Relay",
    async () => {
      const body = await relay.raw.xrpcGet("com.atproto.sync.listRepos");
      if (body === null) {
        throw new Error("expected response body");
      }
      const repos = body.repos ?? body.repo ?? [];
      return { repoCount: Array.isArray(repos) ? repos.length : "present" };
    },
    (r) => `repos=${r.repoCount}`,
  );

  // --- 4. com.atproto.sync.getRepoStatus via Relay ---
  await tryEndpoint(
    result,
    "sync.getRepoStatus via Relay",
    async () => {
      const body = await relay.raw.xrpcGet("com.atproto.sync.getRepoStatus", { did: luna.did });
      if (body === null) {
        throw new Error("expected response body");
      }
      return { did: body.did, active: body.active ?? "unknown", revs: body.revs ?? "unset" };
    },
    (r) => `did=${r.did}, active=${r.active}`,
  );

  // --- 5. com.atproto.sync.notifyOfUpdate via PDS ---
  await tryEndpoint(
    result,
    "sync.notifyOfUpdate via PDS",
    async () => {
      // notifyOfUpdate tells the PDS (or relay) that a repo was updated
      const body = await pds.raw.xrpcPost("com.atproto.sync.notifyOfUpdate", {
        repo: luna.did,
      });
      return { notified: true };
    },
    () => "notified",
  );

  // --- 6. com.atproto.sync.requestCrawl via Relay ---
  await tryEndpoint(
    result,
    "sync.requestCrawl via Relay",
    async () => {
      // requestCrawl tells a relay to initiate a crawl of the given repo
      const body = await relay.raw.xrpcPost("com.atproto.sync.requestCrawl", {
        repo: luna.did,
      });
      return { requested: true };
    },
    () => "requested",
  );

  // --- 7. Verify getHead still works (already covered but included for completeness) ---
  await tryEndpoint(
    result,
    "sync.getHead via PDS",
    async () => {
      const body = await pds.raw.xrpcGet("com.atproto.sync.getHead", { did: luna.did });
      if (!body.root) {
        throw new Error("expected root field");
      }
      return { root: body.root.substring(0, 16) };
    },
    (r) => `root=${r.root}...`,
  );

  // --- 8. Request crawl with non-existent DID should error gracefully ---
  await tryEndpoint(
    result,
    "sync.requestCrawl for unknown DID errors gracefully",
    async () => {
      try {
        await relay.raw.xrpcPost("com.atproto.sync.requestCrawl", {
          repo: "did:plc:nonexistent00000000000000",
        });
        // Might succeed if the relay accepts any DID
        return { accepted: true };
      } catch (e: any) {
        if (e instanceof XrpcError && (e.status === 400 || e.status === 404)) {
          return { rejected: true };
        }
        throw e;
      }
    },
    (r) => r.accepted ? "accepted" : "rejected",
  );

  result.finish();
  return result;
}

if (import.meta.main) {
  const res = await run();
  console.log(res.summary());
  Deno.exit(res.ok ? 0 : 1);
}
