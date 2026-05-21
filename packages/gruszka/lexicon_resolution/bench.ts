/**
 * Lexicon resolution benchmark.
 *
 * Compares cold (uncached), warm InMemoryCache, and warm DiskCache resolution
 * of `app.bsky.feed.post` through the full DNS → DID → record fetch pipeline.
 *
 * Requires `--allow-net --allow-read --allow-write --allow-env` and
 * `GARAZYK_INTEGRATION=1` (same gating as integration tests).
 *
 * @example
 * ```bash
 * GARAZYK_INTEGRATION=1 deno run --allow-net --allow-read --allow-write --allow-env packages/gruszka/lexicon_resolution/bench.ts
 * ```
 *
 * @module lexicon_resolution
 */

import { resolveLexicon } from "./mod.ts";
import {
  DenoDnsResolver,
  HttpDidResolver,
  HttpRecordFetcher,
} from "./adapters.ts";
import { InMemoryCache, DiskCache } from "./cache.ts";
import type { DidDocument, LexiconDoc } from "./types.ts";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function shouldRun(): boolean {
  const env = Deno.env.get("GARAZYK_INTEGRATION");
  if (env === "1" || env === "true") return true;
  if (Deno.env.get("CI")) return false;
  return true;
}

function makeUncachedPorts() {
  return {
    dns: new DenoDnsResolver(),
    did: new HttpDidResolver(),
    record: new HttpRecordFetcher(),
  };
}

function makeMemoryCachedPorts() {
  return {
    ...makeUncachedPorts(),
    cache: {
      dns: new InMemoryCache<string[][]>({ ttlMs: 3600_000 }),
      did: new InMemoryCache<DidDocument>({ ttlMs: 3600_000 }),
      record: new InMemoryCache<LexiconDoc>({ ttlMs: 3600_000 }),
    },
  };
}

async function makeDiskCachedPorts() {
  const tmpDir = await Deno.makeTempDir({ prefix: "lexicon-bench-" });
  return {
    ports: {
      ...makeUncachedPorts(),
      cache: {
        dns: new DiskCache<string[][]>({ directory: `${tmpDir}/dns`, ttlMs: 3600_000 }),
        did: new DiskCache<DidDocument>({ directory: `${tmpDir}/did`, ttlMs: 3600_000 }),
        record: new DiskCache<LexiconDoc>({ directory: `${tmpDir}/record`, ttlMs: 3600_000 }),
      },
    },
    cleanup: async () => {
      await Deno.remove(tmpDir, { recursive: true }).catch(() => undefined);
    },
  };
}

async function bench(label: string, fn: () => Promise<void>): Promise<number> {
  const start = performance.now();
  await fn();
  const elapsed = performance.now() - start;
  console.log(`  ${label}: ${elapsed.toFixed(1)}ms`);
  return elapsed;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

if (import.meta.main) {
  if (!shouldRun()) {
    console.log("Skipping benchmark (set GARAZYK_INTEGRATION=1 to run).");
    Deno.exit(0);
  }

  const nsid = "app.bsky.feed.post";
  const iterations = 3;

  console.log(`\nBenchmark: resolveLexicon("${nsid}") — ${iterations} iterations per mode\n`);
  console.log("─".repeat(50));

  // ── Cold (no cache) ──────────────────────────────────────────
  console.log("\nCold (no cache)");
  const coldTimings: number[] = [];
  for (let i = 0; i < iterations; i++) {
    const ms = await bench(`  run ${i + 1}/${iterations}`, async () => {
      const result = await resolveLexicon(nsid, makeUncachedPorts());
      if (!result.ok) throw new Error(`Cold resolution failed: ${result.error.type}`);
    });
    coldTimings.push(ms);
  }
  const coldAvg = coldTimings.reduce((a, b) => a + b, 0) / coldTimings.length;
  console.log(`  Average: ${coldAvg.toFixed(1)}ms`);

  // ── Warm (InMemoryCache) ─────────────────────────────────────
  console.log("\nWarm (InMemoryCache)");
  const memPorts = makeMemoryCachedPorts();
  // Prime the cache.
  const memPrime = await resolveLexicon(nsid, memPorts);
  if (!memPrime.ok) throw new Error(`Memory cache prime failed: ${memPrime.error.type}`);
  console.log(`  Cache primed`);
  const memTimings: number[] = [];
  for (let i = 0; i < iterations; i++) {
    const ms = await bench(`  run ${i + 1}/${iterations}`, async () => {
      const result = await resolveLexicon(nsid, memPorts);
      if (!result.ok) throw new Error(`Memory-cached resolution failed: ${result.error.type}`);
    });
    memTimings.push(ms);
  }
  const memAvg = memTimings.reduce((a, b) => a + b, 0) / memTimings.length;
  console.log(`  Average: ${memAvg.toFixed(1)}ms`);

  // ── Warm (DiskCache) ─────────────────────────────────────────
  console.log("\nWarm (DiskCache)");
  const { ports: diskPorts, cleanup } = await makeDiskCachedPorts();
  let diskAvg = 0;
  try {
    // Prime the cache.
    const diskPrime = await resolveLexicon(nsid, diskPorts);
    if (!diskPrime.ok) throw new Error(`Disk cache prime failed: ${diskPrime.error.type}`);
    console.log(`  Cache primed`);
    const diskTimings: number[] = [];
    for (let i = 0; i < iterations; i++) {
      const ms = await bench(`  run ${i + 1}/${iterations}`, async () => {
        const result = await resolveLexicon(nsid, diskPorts);
        if (!result.ok) throw new Error(`Disk-cached resolution failed: ${result.error.type}`);
      });
      diskTimings.push(ms);
    }
    diskAvg = diskTimings.reduce((a, b) => a + b, 0) / diskTimings.length;
    console.log(`  Average: ${diskAvg.toFixed(1)}ms`);
  } finally {
    await cleanup();
  }

  // ── Summary ──────────────────────────────────────────────────
  console.log("\n" + "─".repeat(50));
  console.log("\nSummary:");
  console.log(`  Cold (no cache):     ${coldAvg.toFixed(1)}ms avg`);
  console.log(`  Warm (InMemoryCache): ${memAvg.toFixed(1)}ms avg (${(coldAvg / Math.max(memAvg, 0.1)).toFixed(1)}x faster)`);
  console.log(`  Warm (DiskCache):     ${diskAvg.toFixed(1)}ms avg (${(coldAvg / Math.max(diskAvg, 0.1)).toFixed(1)}x faster)`);
  console.log();
}
