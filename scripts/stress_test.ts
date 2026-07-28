#!/usr/bin/env -npx deno run --allow-net
const RELAY = Deno.args[0] ?? "https://relay.garazyk.xyz";
const PDS = Deno.args[1] ?? "https://pds.garazyk.xyz";
const CONCURRENCY = parseInt(Deno.args[2] ?? "20");
const REQUESTS = parseInt(Deno.args[3] ?? "200");

type Result = {
  label: string; ok: boolean; status: number; durationMs: number; size: number;
};

const endpoints = [
  { label: "relay  listRepos",          url: `${RELAY}/xrpc/com.atproto.sync.listRepos` },
  { label: "relay  getRepo (400)",      url: `${RELAY}/xrpc/com.atproto.sync.getRepo` },
  { label: "relay  getLatestCommit",    url: `${RELAY}/xrpc/com.atproto.sync.getLatestCommit` },
  { label: "relay  subscribeRepos",     url: `${RELAY}/xrpc/com.atproto.sync.subscribeRepos` },
  { label: "pds    _health",            url: `${PDS}/xrpc/_health` },
  { label: "pds    describeServer",     url: `${PDS}/xrpc/com.atproto.server.describeServer` },
  { label: "pds    listRepos",          url: `${PDS}/xrpc/com.atproto.sync.listRepos` },
];

function pickEndpoint(): { label: string; url: string } {
  return endpoints[Math.floor(Math.random() * endpoints.length)];
}

async function hit(label: string, url: string): Promise<Result> {
  const t0 = performance.now();
  try {
    const res = await fetch(url);
    const text = await res.text();
    const dur = performance.now() - t0;
    return { label, ok: true, status: res.status, durationMs: dur, size: text.length };
  } catch (e) {
    return { label, ok: false, status: 0, durationMs: performance.now() - t0, size: 0 };
  }
}

const allResults: Result[] = [];
let inflight = 0;

console.log(`Stress test: ${REQUESTS} requests, concurrency=${CONCURRENCY}\n`);
const barW = 40;
const bar = "█";

const tStart = performance.now();
let next = 0;

async function worker() {
  while (next < REQUESTS) {
    const i = next++;
    const ep = pickEndpoint();
    const r = await hit(ep.label, ep.url);
    allResults.push(r);
    inflight--;

    if (i < 3 || i % 50 === 49 || i === REQUESTS - 1) {
      const pct = ((i + 1) / REQUESTS * 100).toFixed(0);
      const filled = Math.round((i + 1) / REQUESTS * barW);
      const empty = barW - filled;
      const elapsed = ((performance.now() - tStart) / 1000).toFixed(1);
      const rps = ((i + 1) / parseFloat(elapsed)).toFixed(1);
      const fails = allResults.filter(x => !x.ok).length;
      const label = r.label.padEnd(22);
      const code = r.ok ? `${r.status}`.padStart(3) : "ERR";
      const ms = r.durationMs.toFixed(0).padStart(6);
      const kb = (r.size / 1024).toFixed(1).padStart(7);
      console.log(`[${elapsed}s] [${bar.repeat(filled)}${".".repeat(empty)}] ${pct}%  ${fails} err  ${rps} r/s  ${label} ${code} ${ms}ms ${kb}KB`);
    }
  }
}

const workers: Promise<void>[] = [];
for (let w = 0; w < CONCURRENCY; w++) workers.push(worker());
await Promise.all(workers);

const totalMs = performance.now() - tStart;
const ok = allResults.filter(r => r.ok).length;
const fail = allResults.filter(r => !r.ok).length;

console.log(`\n${"=".repeat(70)}`);
console.log(`Total: ${totalMs.toFixed(0)}ms  OK: ${ok}  Fail: ${fail}  RPS: ${(REQUESTS / (totalMs / 1000)).toFixed(1)}`);

// per-endpoint stats
const byEndpoint = new Map<string, { durations: number[]; statuses: number[] }>();
for (const r of allResults) {
  const e = byEndpoint.get(r.label) ?? { durations: [], statuses: [] };
  e.durations.push(r.durationMs);
  e.statuses.push(r.ok ? r.status : -1);
  byEndpoint.set(r.label, e);
}

console.log(`\nPer-endpoint:`);
console.log(`  ${"endpoint".padEnd(22)} ${"count".padStart(5)} ${"p50".padStart(7)} ${"p95".padStart(7)} ${"p99".padStart(7)} ${"min".padStart(6)} ${"max".padStart(6)} ${"err".padStart(4)}`);
for (const [label, e] of byEndpoint) {
  const sorted = e.durations.sort((a, b) => a - b);
  const n = sorted.length;
  const p50 = sorted[Math.floor(n * 0.5)];
  const p95 = sorted[Math.floor(n * 0.95)];
  const p99 = sorted[Math.floor(n * 0.99)];
  const min = sorted[0];
  const max = sorted[n - 1];
  const errs = e.statuses.filter(s => s === -1).length;
  console.log(`  ${label.padEnd(22)} ${String(n).padStart(5)} ${String(p50.toFixed(0)).padStart(7)} ${String(p95.toFixed(0)).padStart(7)} ${String(p99.toFixed(0)).padStart(7)} ${String(min.toFixed(0)).padStart(6)} ${String(max.toFixed(0)).padStart(6)} ${String(errs).padStart(4)}`);
}

Deno.exit(fail > 0 ? 1 : 0);
