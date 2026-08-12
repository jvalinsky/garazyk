#!/usr/bin/env -S deno run -A
/**
 * STAR-lite v0 vs CAR export benchmark (size, latency, resource use, correctness).
 *
 * Spins up PLC + multiple PDS binaries, seeds accounts with large post repos,
 * exports each repo as CAR and STAR-lite v0, and reports comparative stats.
 *
 * Usage:
 *   deno run -A scripts/test/star_lite_export_benchmark.ts
 *   STAR_LITE_BENCH_TARGET_BYTES=100000000 deno run -A scripts/test/star_lite_export_benchmark.ts
 *   STAR_LITE_BENCH_QUICK=1 deno run -A scripts/test/star_lite_export_benchmark.ts
 *
 * Environment:
 *   STAR_LITE_BENCH_TARGET_BYTES  Approx total repo payload across all accounts (default 10_000_000)
 *   STAR_LITE_BENCH_PDS_COUNT       Number of PDS instances (default 3, max 3)
 *   STAR_LITE_BENCH_ACCOUNTS_PER_PDS Accounts per PDS (default 5)
 *   STAR_LITE_BENCH_QUICK           When "1", use ~1 MB / 1 PDS / 2 accounts for dev smoke
 *   STAR_LITE_BENCH_JSON_OUT        Optional path to write machine-readable summary JSON
 *   BUILD_DIR                       Binary directory (default build/bin)
 */

import { join } from "@std/path";
import {
  initRunDir,
  repoRoot,
  stopLocalNetwork,
} from "../../packages/hamownia/atproto_network.ts";
import {
  startBinaryServices,
  stopBinaryServices,
  type BinaryServiceName,
} from "../../packages/hamownia/binary_services.ts";
import {
  CAR_MEDIA_TYPE,
  fetchRepoExport,
  formatBenchmarkSummary,
  formatBytes,
  STAR_LITE_V0_MEDIA_TYPE,
  summarizeExportBenchmark,
  verifyExportsMatch,
  type ExportComparisonRow,
} from "../lib/deno/repo_export_benchmark.ts";

const HOST = "127.0.0.1";
const PASSWORD = "star-lite-bench-hunter2";
const DOMAIN = "test";

interface BenchConfig {
  targetBytes: number;
  pdsCount: number;
  accountsPerPds: number;
}

interface SeededAccount {
  label: string;
  pdsUrl: string;
  pdsName: BinaryServiceName;
  did: string;
  accessJwt: string;
  refreshJwt: string;
  postCount: number;
}

interface BenchSession {
  did: string;
  accessJwt: string;
  refreshJwt: string;
}

function readConfig(): BenchConfig {
  if (Deno.env.get("STAR_LITE_BENCH_QUICK") === "1") {
    return { targetBytes: 500_000, pdsCount: 1, accountsPerPds: 2 };
  }
  return {
    targetBytes: Number(Deno.env.get("STAR_LITE_BENCH_TARGET_BYTES") ?? "10000000"),
    pdsCount: Math.min(3, Math.max(1, Number(Deno.env.get("STAR_LITE_BENCH_PDS_COUNT") ?? "3"))),
    accountsPerPds: Math.max(1, Number(Deno.env.get("STAR_LITE_BENCH_ACCOUNTS_PER_PDS") ?? "5")),
  };
}

function pdsServices(count: number): BinaryServiceName[] {
  const services: BinaryServiceName[] = ["plc", "pds"];
  if (count >= 2) services.push("pds2");
  if (count >= 3) services.push("pds3");
  return services;
}

function pdsUrlFor(name: BinaryServiceName, ports: Record<string, number>): string {
  return `http://${HOST}:${ports[name]}`;
}

async function readServicePid(pidFile: string, label: string): Promise<number | undefined> {
  const content = await Deno.readTextFile(pidFile).catch(() => "");
  const re = new RegExp(`^${label}_PID=(\\d+)$`, "m");
  const match = content.match(re);
  return match ? Number.parseInt(match[1], 10) : undefined;
}

const PDS_BENCH_ENV = {
  PDS_RATELIMIT_ENABLED: "0",
  PDS_RATELIMIT_DID_LIMIT: "1000000",
  PDS_RATELIMIT_DID_WINDOW: "1",
};

async function xrpcPost(base: string, method: string, body: unknown, accessJwt?: string) {
  for (let attempt = 0; attempt < 5; attempt++) {
    const res = await fetch(new URL(`/xrpc/${method}`, base), {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(accessJwt ? { Authorization: `Bearer ${accessJwt}` } : {}),
      },
      body: JSON.stringify(body),
    });
    if (res.status === 429 && attempt < 4) {
      await new Promise((r) => setTimeout(r, 500 * (attempt + 1)));
      continue;
    }
    if (!res.ok) throw new Error(`${method} -> ${res.status}: ${await res.text()}`);
    return await res.json();
  }
  throw new Error(`${method} failed after retries`);
}

const MAX_POST_TEXT = 280; // app.bsky.feed.post: maxGraphemes 300
const SEED_BATCH_SIZE = 50;
const SEED_SAMPLE_POSTS = 24;
const MAX_POSTS_PER_BATCH = 100;
const POSTS_PER_SESSION_REFRESH = 100;

function payloadText(accountLabel: string, index: number, payloadChars: number): string {
  const prefix = `star-lite-bench ${accountLabel} post ${index} `;
  if (payloadChars <= prefix.length) return prefix.slice(0, payloadChars);
  return prefix + "x".repeat(payloadChars - prefix.length);
}

function estimateSeedingPlan(config: BenchConfig): { targetBytesPerAccount: number; payloadChars: number } {
  const totalAccounts = config.pdsCount * config.accountsPerPds;
  return {
    targetBytesPerAccount: Math.ceil(config.targetBytes / totalAccounts),
    payloadChars: MAX_POST_TEXT,
  };
}

async function measureStarLiteExportBytes(pdsUrl: string, did: string): Promise<number> {
  const url = new URL("/xrpc/com.atproto.sync.getRepo", pdsUrl);
  url.searchParams.set("did", did);
  const res = await fetch(url, {
    headers: { Accept: "application/x.microcosm.star-lite" },
  });
  if (!res.ok) {
    throw new Error(`sample getRepo -> ${res.status}: ${await res.text()}`);
  }
  const bytes = await res.arrayBuffer();
  return bytes.byteLength;
}

async function refreshBenchSession(pdsUrl: string, session: BenchSession): Promise<void> {
  const body = await xrpcPost(
    pdsUrl,
    "com.atproto.server.refreshSession",
    {},
    session.refreshJwt,
  );
  session.accessJwt = body.accessJwt as string;
  if (body.refreshJwt) session.refreshJwt = body.refreshJwt as string;
}

async function createRecord(
  pdsUrl: string,
  session: BenchSession,
  label: string,
  index: number,
  payloadChars: number,
): Promise<void> {
  const postBody = {
    repo: session.did,
    collection: "app.bsky.feed.post",
    record: {
      $type: "app.bsky.feed.post",
      text: payloadText(label, index, payloadChars),
      createdAt: new Date().toISOString(),
    },
  };

  try {
    await xrpcPost(pdsUrl, "com.atproto.repo.createRecord", postBody, session.accessJwt);
  } catch (err) {
    const msg = String(err);
    if (!msg.includes("401") || !msg.includes("ExpiredToken")) throw err;
    await refreshBenchSession(pdsUrl, session);
    await xrpcPost(pdsUrl, "com.atproto.repo.createRecord", postBody, session.accessJwt);
  }
}

async function createPostBatch(
  pdsUrl: string,
  session: BenchSession,
  label: string,
  startIndex: number,
  count: number,
  payloadChars: number,
): Promise<void> {
  for (let i = 0; i < count; i++) {
    if (i > 0 && i % POSTS_PER_SESSION_REFRESH === 0) {
      await refreshBenchSession(pdsUrl, session);
    }
    await createRecord(pdsUrl, session, label, startIndex + i, payloadChars);
  }
}

async function seedAccount(
  pdsUrl: string,
  pdsName: BinaryServiceName,
  label: string,
  targetBytesPerAccount: number,
  payloadChars: number,
): Promise<SeededAccount> {
  const handle = `${label}.${DOMAIN}`;
  const account = await xrpcPost(pdsUrl, "com.atproto.server.createAccount", {
    handle,
    email: `${label}@star-lite-bench.local`,
    password: PASSWORD,
  });
  if (!account.accessJwt || !account.refreshJwt) {
    throw new Error("createAccount did not return accessJwt and refreshJwt");
  }
  const session: BenchSession = {
    did: account.did as string,
    accessJwt: account.accessJwt as string,
    refreshJwt: account.refreshJwt as string,
  };

  let postCount = 0;
  await createPostBatch(
    pdsUrl,
    session,
    label,
    postCount,
    SEED_SAMPLE_POSTS,
    payloadChars,
  );
  postCount += SEED_SAMPLE_POSTS;

  let exportBytes = await measureStarLiteExportBytes(pdsUrl, session.did);
  let bytesPerPost = exportBytes / postCount;

  while (exportBytes < targetBytesPerAccount) {
    const remainingBytes = targetBytesPerAccount - exportBytes;
    const estimatedPosts = Math.min(
      MAX_POSTS_PER_BATCH,
      Math.max(
        SEED_BATCH_SIZE,
        Math.ceil(remainingBytes / Math.max(bytesPerPost, 1)),
      ),
    );
    await createPostBatch(
      pdsUrl,
      session,
      label,
      postCount,
      estimatedPosts,
      payloadChars,
    );
    postCount += estimatedPosts;
    exportBytes = await measureStarLiteExportBytes(pdsUrl, session.did);
    bytesPerPost = exportBytes / postCount;
    console.log(
      `    ${label}: ${postCount} posts, export≈${formatBytes(exportBytes)} (target ${formatBytes(targetBytesPerAccount)})`,
    );
    if (estimatedPosts === SEED_BATCH_SIZE && exportBytes < targetBytesPerAccount) {
      // Guard against zero growth (should not happen).
      break;
    }
  }

  console.log(
    `  seeded ${label} on ${pdsName}: did=${session.did} posts=${postCount} export≈${formatBytes(exportBytes)}`,
  );
  return {
    label,
    pdsUrl,
    pdsName,
    did: session.did,
    accessJwt: session.accessJwt,
    refreshJwt: session.refreshJwt,
    postCount,
  };
}

async function benchmarkAccount(
  account: SeededAccount,
  pidFile: string,
  dataDir: string,
): Promise<ExportComparisonRow> {
  const pid = await readServicePid(pidFile, account.pdsName.toUpperCase());
  const acceptEncoding = Deno.env.get("STAR_LITE_BENCH_ACCEPT_ENCODING")?.trim() || undefined;

  // Correctness always compares identity archives.
  const carIdentity = await fetchRepoExport(account.pdsUrl, account.did, CAR_MEDIA_TYPE, {
    pid,
    dataDir,
  });
  const starIdentity = await fetchRepoExport(
    account.pdsUrl,
    account.did,
    STAR_LITE_V0_MEDIA_TYPE,
    { pid, dataDir },
  );
  const match = await verifyExportsMatch(carIdentity.bytes, starIdentity.bytes);

  const carFetch = acceptEncoding
    ? await fetchRepoExport(account.pdsUrl, account.did, CAR_MEDIA_TYPE, {
      pid,
      dataDir,
      acceptEncoding,
    })
    : carIdentity;
  const starFetch = acceptEncoding
    ? await fetchRepoExport(account.pdsUrl, account.did, STAR_LITE_V0_MEDIA_TYPE, {
      pid,
      dataDir,
      acceptEncoding,
    })
    : starIdentity;

  return {
    did: account.did,
    pdsLabel: account.pdsName,
    groundTruthPosts: match.postCount,
    car: {
      format: "car",
      bytes: carFetch.bytes.length,
      generationAndTransferMs: carFetch.elapsedMs,
      contentType: carFetch.contentType,
      contentEncoding: carFetch.contentEncoding,
      resources: carFetch.resources,
    },
    starLite: {
      format: "star-lite-v0",
      bytes: starFetch.bytes.length,
      generationAndTransferMs: starFetch.elapsedMs,
      contentType: starFetch.contentType,
      contentEncoding: starFetch.contentEncoding,
      resources: starFetch.resources,
    },
    correctnessOk: match.ok,
    correctnessDetail: match.detail,
  };
}

async function main(): Promise<void> {
  const config = readConfig();
  const { targetBytesPerAccount, payloadChars } = estimateSeedingPlan(config);
  const root = await repoRoot();
  const buildBin = Deno.env.get("BUILD_DIR") ?? join(root, "build/bin");
  for (const bin of ["campagnola", "kaszlak"]) {
    try {
      Deno.statSync(join(buildBin, bin));
    } catch {
      throw new Error(`Missing ${bin}; build binaries first`);
    }
  }

  const services = pdsServices(config.pdsCount);
  const ports: Record<string, number> = {
    plc: 2582,
    pds: 2583,
    pds2: 2587,
    pds3: 2588,
  };
  const runId = `star-lite-bench-${Date.now()}`;
  const ctx = initRunDir(runId);

  console.log("STAR-lite v0 vs CAR export benchmark");
  console.log(
    `  target≈${formatBytes(config.targetBytes)} (~${formatBytes(targetBytesPerAccount)}/account) pds=${config.pdsCount} accounts/pds=${config.accountsPerPds} postText=${payloadChars} chars`,
  );

  try {
    await startBinaryServices(ctx, {
      services,
      isolation: "legacy-fixed",
      servicePorts: ports,
      serviceUrls: Object.fromEntries(
        services.map((s) => [s, `http://${HOST}:${ports[s]}`]),
      ),
      env: {
        pds: PDS_BENCH_ENV,
        pds2: PDS_BENCH_ENV,
        pds3: PDS_BENCH_ENV,
      },
    });

    console.log("\n== Seeding accounts ==");
    const accounts: SeededAccount[] = [];
    let accountIndex = 0;
    for (const pdsName of services.filter((s) => s.startsWith("pds"))) {
      const pdsUrl = pdsUrlFor(pdsName, ports);
      for (let i = 0; i < config.accountsPerPds; i++) {
        const label = `slb-${pdsName}-${accountIndex++}-${Date.now().toString(36)}`;
        accounts.push(
          await seedAccount(pdsUrl, pdsName, label, targetBytesPerAccount, payloadChars),
        );
      }
    }

    console.log("\n== Export benchmark ==");
    const rows: ExportComparisonRow[] = [];
    for (const account of accounts) {
      console.log(`  benchmarking ${account.label} (${account.pdsName})…`);
      const dataDir = join(ctx.runDir, "data", account.pdsName);
      rows.push(await benchmarkAccount(account, ctx.pidFile, dataDir));
    }

    const summary = summarizeExportBenchmark(config.targetBytes, rows);
    console.log(formatBenchmarkSummary(summary));

    const jsonOut = Deno.env.get("STAR_LITE_BENCH_JSON_OUT");
    if (jsonOut) {
      await Deno.writeTextFile(jsonOut, JSON.stringify(summary, null, 2) + "\n");
      console.log(`\nWrote JSON summary to ${jsonOut}`);
    }

    const failures = rows.filter((r) => !r.correctnessOk);
    if (failures.length > 0) {
      console.error(`\n❌ ${failures.length} repo(s) failed correctness checks`);
      Deno.exit(1);
    }
    console.log("\n✅ STAR-lite export benchmark completed");
  } finally {
    await stopBinaryServices(ctx, services);
    await stopLocalNetwork({ runId, useBinary: true });
  }
}

if (import.meta.main) {
  await main();
}
