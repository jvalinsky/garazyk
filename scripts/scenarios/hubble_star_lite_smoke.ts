#!/usr/bin/env -S deno run -A
/**
 * hubble_star_lite_smoke.ts — verify Hubble backfills a Garazyk PDS via STAR-lite v0.
 *
 * Seeds a handful of accounts with varied record counts (including one empty
 * repo, which exercises the computed-empty-MST-root-CID behavior from
 * ADR 0034), then polls Hubble's blue.microcosm.hubble.getRepoInfo until each
 * one reports synchronized with a matching rev and record count. Also writes
 * one more record after the initial backfill converges and confirms Hubble's
 * live firehose consumption picks it up, and does its own direct STAR-lite v0
 * request against the PDS to confirm the server side independently of
 * whatever Hubble's client actually negotiated.
 *
 * Run against services already started with:
 *   ./scripts/scenarios/setup_local_network.sh --topology hubble-star-lite
 *
 * Usage:
 *   deno run -A scripts/scenarios/hubble_star_lite_smoke.ts
 *   PDS_URL=http://localhost:2583 BACKFILL_URL=http://localhost:3000 \
 *     deno run -A scripts/scenarios/hubble_star_lite_smoke.ts
 */

const PDS_URL = Deno.env.get("PDS_URL") ?? "http://localhost:2583";
const HUBBLE_URL = Deno.env.get("BACKFILL_URL") ?? "http://localhost:3000";
const DOMAIN = "test";
const PASSWORD = "hunter2-hunter2";

const BACKFILL_TIMEOUT_MS = 120_000;
const POLL_INTERVAL_MS = 2_000;

interface Seeded {
  label: string;
  handle: string;
  did: string;
  accessJwt: string;
  recordCount: number;
}

let passed = 0;
let failed = 0;

function ok(label: string, detail?: string) {
  passed++;
  console.log(`  ok  ${label}${detail ? ` (${detail})` : ""}`);
}

function fail(label: string, detail: string) {
  failed++;
  console.log(`FAIL  ${label}: ${detail}`);
}

async function xrpcGet(base: string, method: string, params?: Record<string, string>, headers?: Record<string, string>) {
  const url = new URL(`/xrpc/${method}`, base);
  for (const [k, v] of Object.entries(params ?? {})) url.searchParams.set(k, v);
  const res = await fetch(url, { headers });
  return res;
}

async function xrpcPost(base: string, method: string, body: unknown, accessJwt?: string) {
  const res = await fetch(new URL(`/xrpc/${method}`, base), {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(accessJwt ? { Authorization: `Bearer ${accessJwt}` } : {}),
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`${method} -> ${res.status}: ${text}`);
  }
  return await res.json();
}

async function healthCheck(name: string, base: string, path: string) {
  try {
    const res = await fetch(new URL(path, base));
    if (res.ok) {
      ok(`${name} reachable`);
      return true;
    }
    fail(`${name} reachable`, `HTTP ${res.status}`);
    return false;
  } catch (e) {
    fail(`${name} reachable`, String(e));
    return false;
  }
}

async function createSeededAccount(label: string, handleSlug: string, postCount: number): Promise<Seeded> {
  const handle = `${handleSlug}.${DOMAIN}`;
  const email = `${handleSlug}@garazyk-e2e.local`;
  const account = await xrpcPost(PDS_URL, "com.atproto.server.createAccount", {
    handle,
    email,
    password: PASSWORD,
  });

  for (let i = 0; i < postCount; i++) {
    await xrpcPost(PDS_URL, "com.atproto.repo.createRecord", {
      repo: account.did,
      collection: "app.bsky.feed.post",
      record: {
        $type: "app.bsky.feed.post",
        text: `hubble star-lite e2e smoke post ${i} for ${label}`,
        createdAt: new Date().toISOString(),
      },
    }, account.accessJwt);
  }

  ok(`seeded ${label}`, `did=${account.did} records=${postCount}`);
  return { label, handle, did: account.did, accessJwt: account.accessJwt, recordCount: postCount };
}

async function pdsLatestRev(did: string): Promise<string> {
  const res = await xrpcGet(PDS_URL, "com.atproto.sync.getLatestCommit", { did });
  if (!res.ok) throw new Error(`getLatestCommit -> ${res.status}`);
  const body = await res.json();
  return body.rev as string;
}

interface HubbleRepoInfo {
  syncState: { state: string; rev?: string };
  archive: { available: boolean; records?: number; formats?: string[] };
}

async function hubbleRepoInfo(did: string): Promise<HubbleRepoInfo | null> {
  const res = await xrpcGet(HUBBLE_URL, "blue.microcosm.hubble.getRepoInfo", { did });
  if (res.status === 400) return null; // RepoNotFound: hubble hasn't seen this DID yet
  if (!res.ok) throw new Error(`getRepoInfo -> ${res.status}: ${await res.text()}`);
  return await res.json();
}

async function waitForSync(
  seeded: Seeded,
  expectedRev: string,
  expectedRecords: number,
  timeoutMs = BACKFILL_TIMEOUT_MS,
): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  let lastState = "unknown";
  let lastRev: string | undefined;
  let lastRecords: number | undefined;

  while (Date.now() < deadline) {
    const info = await hubbleRepoInfo(seeded.did);
    if (info) {
      lastState = info.syncState.state;
      lastRev = info.syncState.rev;
      lastRecords = info.archive.records;
      if (
        lastState === "synchronized" &&
        lastRev === expectedRev &&
        lastRecords === expectedRecords
      ) {
        ok(`${seeded.label} synchronized`, `rev=${lastRev} records=${lastRecords}`);
        return true;
      }
    }
    await new Promise((r) => setTimeout(r, POLL_INTERVAL_MS));
  }

  fail(
    `${seeded.label} synchronized within ${timeoutMs}ms`,
    `last state=${lastState} rev=${lastRev} (want ${expectedRev}) records=${lastRecords} (want ${expectedRecords})`,
  );
  return false;
}

async function verifyDirectStarLiteExport(did: string, label: string) {
  const res = await fetch(
    new URL(`/xrpc/com.atproto.sync.getRepo?did=${encodeURIComponent(did)}`, PDS_URL),
    { headers: { Accept: "application/x.microcosm.star-lite" } },
  );
  if (!res.ok) {
    fail(`${label} direct STAR-lite v0 export`, `HTTP ${res.status}`);
    return;
  }
  const contentType = res.headers.get("content-type");
  const bytes = new Uint8Array(await res.arrayBuffer());
  const magicOk = bytes.length >= 3 && bytes[0] === 0x2a && bytes[1] === 0x6c && bytes[2] === 0x00;
  if (contentType === "application/x.microcosm.star-lite" && magicOk) {
    ok(`${label} direct STAR-lite v0 export`, `${bytes.length} bytes, magic ok`);
  } else {
    fail(
      `${label} direct STAR-lite v0 export`,
      `content-type=${contentType} magicOk=${magicOk} len=${bytes.length}`,
    );
  }
}

async function main() {
  console.log(`PDS: ${PDS_URL}`);
  console.log(`Hubble: ${HUBBLE_URL}`);
  console.log();

  console.log("== Health checks ==");
  const pdsUp = await healthCheck("PDS", PDS_URL, "/xrpc/com.atproto.server.describeServer");
  const hubbleUp = await healthCheck("Hubble", HUBBLE_URL, "/");
  if (!pdsUp || !hubbleUp) {
    console.log("\nAborting: a service is not reachable.");
    Deno.exit(1);
  }

  console.log("\n== Seeding accounts ==");
  const runId = Date.now().toString(36);
  const empty = await createSeededAccount("empty repo", `hb-empty-${runId}`, 0);
  const few = await createSeededAccount("few records", `hb-few-${runId}`, 3);
  const many = await createSeededAccount("many records", `hb-many-${runId}`, 50);
  const seeded = [empty, few, many];

  console.log("\n== Direct STAR-lite v0 export sanity (server side, independent of Hubble) ==");
  for (const s of seeded) {
    await verifyDirectStarLiteExport(s.did, s.label);
  }

  console.log("\n== Waiting for Hubble to backfill via STAR-lite v0 ==");
  for (const s of seeded) {
    const rev = await pdsLatestRev(s.did);
    await waitForSync(s, rev, s.recordCount);
  }

  console.log("\n== Incremental live-firehose pickup (post-backfill write) ==");
  await xrpcPost(PDS_URL, "com.atproto.repo.createRecord", {
    repo: few.did,
    collection: "app.bsky.feed.post",
    record: {
      $type: "app.bsky.feed.post",
      text: "hubble star-lite e2e smoke: post-backfill incremental write",
      createdAt: new Date().toISOString(),
    },
  }, few.accessJwt);
  const revAfterIncrement = await pdsLatestRev(few.did);
  await waitForSync(few, revAfterIncrement, few.recordCount + 1, 60_000);

  console.log(`\n== Summary: ${passed} passed, ${failed} failed ==`);
  Deno.exit(failed > 0 ? 1 : 0);
}

await main();
