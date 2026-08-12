/**
 * Helpers for comparing STAR-lite v0 and CAR repository exports.
 */

import { decode } from "cborg";
import { CarReader } from "@ipld/car";
import {
  parseStarLiteV0,
  starLitePostKeys,
  type StarLiteV0Archive,
} from "./star_lite_v0.ts";

export const CAR_MEDIA_TYPE = "application/vnd.ipld.car";
export const STAR_LITE_V0_MEDIA_TYPE = "application/x.microcosm.star-lite";

export interface RepoRecordGroundTruth {
  keys: string[];
  texts: string[];
}

export interface ProcessSample {
  rssKb: number;
  cpuPercent: number;
  atMs: number;
}

export interface ExportResourceStats {
  peakRssKb: number;
  avgCpuPercent: number;
  diskDataDirKbBefore: number;
  diskDataDirKbAfter: number;
  diskDeltaKb: number;
}

export interface ExportBenchmarkResult {
  format: "car" | "star-lite-v0";
  bytes: number;
  generationAndTransferMs: number;
  contentType: string | null;
  contentEncoding: string | null;
  resources: ExportResourceStats;
}

export interface ExportComparisonRow {
  did: string;
  pdsLabel: string;
  groundTruthPosts: number;
  car: ExportBenchmarkResult;
  starLite: ExportBenchmarkResult;
  correctnessOk: boolean;
  correctnessDetail: string;
}

export interface ExportBenchmarkSummary {
  targetBytes: number;
  totalExportedBytes: { car: number; starLite: number };
  totalGenerationMs: { car: number; starLite: number };
  starLiteVsCar: {
    sizeRatio: number;
    sizeSavingsPercent: number;
    timeRatio: number;
  };
  peakRssKb: { car: number; starLite: number };
  rows: ExportComparisonRow[];
}

function decodePostText(recordBytes: Uint8Array): string | null {
  try {
    const value = decode(recordBytes) as { $type?: string; text?: string };
    if (value?.$type !== "app.bsky.feed.post") return null;
    return typeof value.text === "string" ? value.text : null;
  } catch {
    return null;
  }
}

export function groundTruthFromStarLite(bytes: Uint8Array): RepoRecordGroundTruth {
  const archive = parseStarLiteV0(bytes);
  const posts = archive.records.filter((r) => r.key.startsWith("app.bsky.feed.post/"));
  return {
    keys: posts.map((r) => r.key).sort(),
    texts: posts
      .map((r) => decodePostText(r.recordBytes))
      .filter((t): t is string => t != null)
      .sort(),
  };
}

export async function verifyExportsMatch(
  carBytes: Uint8Array,
  starLiteBytes: Uint8Array,
): Promise<{ ok: boolean; detail: string; postCount: number }> {
  let starArchive: StarLiteV0Archive;
  try {
    starArchive = parseStarLiteV0(starLiteBytes);
  } catch (err) {
    return { ok: false, detail: `STAR-lite parse failed: ${err}`, postCount: 0 };
  }

  const starKeys = starLitePostKeys(starArchive);
  const starTexts = groundTruthFromStarLite(starLiteBytes).texts;
  const carTexts = await extractCarPostTexts(carBytes);

  if (starTexts.length !== carTexts.length) {
    return {
      ok: false,
      detail: `post count mismatch: star-lite=${starTexts.length} car=${carTexts.length}`,
      postCount: Math.max(starTexts.length, carTexts.length),
    };
  }
  for (let i = 0; i < starTexts.length; i++) {
    if (starTexts[i] !== carTexts[i]) {
      return {
        ok: false,
        detail: `post text mismatch at sorted index ${i}`,
        postCount: starTexts.length,
      };
    }
  }

  return {
    ok: true,
    detail:
      `${starTexts.length} posts match between formats; star-lite header=${starArchive.headerBytes}B total=${starLiteBytes.length}B; car=${carBytes.length}B; keys=${starKeys.length}`,
    postCount: starTexts.length,
  };
}

export function verifyStarLiteAgainstGroundTruth(
  archiveBytes: Uint8Array,
  truth: RepoRecordGroundTruth,
): { ok: boolean; detail: string } {
  let archive: StarLiteV0Archive;
  try {
    archive = parseStarLiteV0(archiveBytes);
  } catch (err) {
    return { ok: false, detail: `parse failed: ${err}` };
  }

  const keys = starLitePostKeys(archive);
  if (keys.length !== truth.keys.length) {
    return {
      ok: false,
      detail: `post key count mismatch: export=${keys.length} listRecords=${truth.keys.length}`,
    };
  }
  for (let i = 0; i < keys.length; i++) {
    if (keys[i] !== truth.keys[i]) {
      return {
        ok: false,
        detail: `post key mismatch at ${i}: export=${keys[i]} truth=${truth.keys[i]}`,
      };
    }
  }

  const texts = archive.records
    .filter((r) => r.key.startsWith("app.bsky.feed.post/"))
    .map((r) => decodePostText(r.recordBytes))
    .filter((t): t is string => t != null)
    .sort();

  if (texts.length !== truth.texts.length) {
    return {
      ok: false,
      detail: `post text count mismatch: export=${texts.length} listRecords=${truth.texts.length}`,
    };
  }
  for (let i = 0; i < texts.length; i++) {
    if (texts[i] !== truth.texts[i]) {
      return {
        ok: false,
        detail: `post text mismatch at ${i}`,
      };
    }
  }

  return {
    ok: true,
    detail: `${keys.length} posts, header=${archive.headerBytes} bytes, total=${archiveBytes.length} bytes`,
  };
}

export async function extractCarPostTexts(bytes: Uint8Array): Promise<string[]> {
  const reader = await CarReader.fromBytes(bytes);
  const texts: string[] = [];
  for await (const block of reader.blocks()) {
    try {
      const value = decode(block.bytes) as { $type?: string; text?: string };
      if (value?.$type === "app.bsky.feed.post" && typeof value.text === "string") {
        texts.push(value.text);
      }
    } catch {
      // not a record block
    }
  }
  texts.sort();
  return texts;
}

export async function verifyCarAgainstGroundTruth(
  archiveBytes: Uint8Array,
  truth: RepoRecordGroundTruth,
): Promise<{ ok: boolean; detail: string }> {
  const texts = await extractCarPostTexts(archiveBytes);
  if (texts.length !== truth.texts.length) {
    return {
      ok: false,
      detail: `CAR post count mismatch: car=${texts.length} listRecords=${truth.texts.length}`,
    };
  }
  for (let i = 0; i < texts.length; i++) {
    if (texts[i] !== truth.texts[i]) {
      return {
        ok: false,
        detail: `CAR post text mismatch at ${i}`,
      };
    }
  }
  return {
    ok: true,
    detail: `${texts.length} post blocks, total=${archiveBytes.length} bytes`,
  };
}

export async function duKb(path: string): Promise<number> {
  const cmd = new Deno.Command("du", {
    args: ["-sk", path],
    stdout: "piped",
    stderr: "null",
  });
  const { code, stdout } = await cmd.output();
  if (code !== 0) return 0;
  const line = new TextDecoder().decode(stdout).trim();
  const kb = Number.parseInt(line.split(/\s+/)[0] ?? "0", 10);
  return Number.isFinite(kb) ? kb : 0;
}

export async function sampleProcess(pid: number): Promise<ProcessSample | null> {
  if (!Number.isFinite(pid) || pid <= 0) return null;
  const cmd = new Deno.Command("ps", {
    args: ["-p", String(pid), "-o", "rss=,pcpu="],
    stdout: "piped",
    stderr: "null",
  });
  const { code, stdout } = await cmd.output();
  if (code !== 0) return null;
  const parts = new TextDecoder().decode(stdout).trim().split(/\s+/);
  if (parts.length < 2) return null;
  const rssKb = Number.parseFloat(parts[0] ?? "0");
  const cpuPercent = Number.parseFloat(parts[1] ?? "0");
  if (!Number.isFinite(rssKb) || !Number.isFinite(cpuPercent)) return null;
  return { rssKb, cpuPercent, atMs: Date.now() };
}

export class ProcessSampler {
  private intervalId?: number;
  private samples: ProcessSample[] = [];

  start(pid: number, intervalMs = 100): void {
    this.stop();
    this.samples = [];
    this.intervalId = setInterval(() => {
      sampleProcess(pid).then((sample) => {
        if (sample) this.samples.push(sample);
      });
    }, intervalMs);
  }

  stop(): ProcessSample[] {
    if (this.intervalId != null) {
      clearInterval(this.intervalId);
      this.intervalId = undefined;
    }
    return this.samples;
  }

  static summarize(samples: ProcessSample[], diskBeforeKb: number, diskAfterKb: number): ExportResourceStats {
    const peakRssKb = samples.reduce((max, s) => Math.max(max, s.rssKb), 0);
    const avgCpuPercent = samples.length === 0
      ? 0
      : samples.reduce((sum, s) => sum + s.cpuPercent, 0) / samples.length;
    return {
      peakRssKb,
      avgCpuPercent,
      diskDataDirKbBefore: diskBeforeKb,
      diskDataDirKbAfter: diskAfterKb,
      diskDeltaKb: diskAfterKb - diskBeforeKb,
    };
  }
}

export async function fetchRepoExport(
  pdsUrl: string,
  did: string,
  accept: string,
  options: {
    pid?: number;
    dataDir?: string;
    sampleIntervalMs?: number;
    /** Optional Accept-Encoding (e.g. "zstd"). Wire bytes may be compressed. */
    acceptEncoding?: string;
  } = {},
): Promise<{
  bytes: Uint8Array;
  contentType: string | null;
  contentEncoding: string | null;
  elapsedMs: number;
  resources: ExportResourceStats;
}> {
  const sampler = new ProcessSampler();
  const diskBeforeKb = options.dataDir ? await duKb(options.dataDir) : 0;
  const extraSamples: ProcessSample[] = [];
  if (options.pid) {
    sampler.start(options.pid, options.sampleIntervalMs ?? 50);
    const warm = await sampleProcess(options.pid);
    if (warm) extraSamples.push(warm);
  }

  const url = new URL("/xrpc/com.atproto.sync.getRepo", pdsUrl);
  url.searchParams.set("did", did);
  const headers: Record<string, string> = { Accept: accept };
  if (options.acceptEncoding) {
    headers["Accept-Encoding"] = options.acceptEncoding;
  }
  const start = performance.now();
  const res = await fetch(url, { headers });
  const bytes = new Uint8Array(await res.arrayBuffer());
  const elapsedMs = performance.now() - start;

  if (options.pid) {
    const tail = await sampleProcess(options.pid);
    if (tail) extraSamples.push(tail);
  }
  const samples = [...sampler.stop(), ...extraSamples];
  const diskAfterKb = options.dataDir ? await duKb(options.dataDir) : 0;

  if (!res.ok) {
    throw new Error(`getRepo (${accept}) -> ${res.status}: ${new TextDecoder().decode(bytes)}`);
  }

  return {
    bytes,
    contentType: res.headers.get("content-type"),
    contentEncoding: res.headers.get("content-encoding"),
    elapsedMs,
    resources: ProcessSampler.summarize(samples, diskBeforeKb, diskAfterKb),
  };
}

export function summarizeExportBenchmark(
  targetBytes: number,
  rows: ExportComparisonRow[],
): ExportBenchmarkSummary {
  const totalCarBytes = rows.reduce((n, r) => n + r.car.bytes, 0);
  const totalStarBytes = rows.reduce((n, r) => n + r.starLite.bytes, 0);
  const totalCarMs = rows.reduce((n, r) => n + r.car.generationAndTransferMs, 0);
  const totalStarMs = rows.reduce((n, r) => n + r.starLite.generationAndTransferMs, 0);
  const peakCarRss = rows.reduce((n, r) => Math.max(n, r.car.resources.peakRssKb), 0);
  const peakStarRss = rows.reduce((n, r) => Math.max(n, r.starLite.resources.peakRssKb), 0);

  return {
    targetBytes,
    totalExportedBytes: { car: totalCarBytes, starLite: totalStarBytes },
    totalGenerationMs: { car: totalCarMs, starLite: totalStarMs },
    starLiteVsCar: {
      sizeRatio: totalCarBytes === 0 ? 0 : totalStarBytes / totalCarBytes,
      sizeSavingsPercent: totalCarBytes === 0
        ? 0
        : ((totalCarBytes - totalStarBytes) / totalCarBytes) * 100,
      timeRatio: totalCarMs === 0 ? 0 : totalStarMs / totalCarMs,
    },
    peakRssKb: { car: peakCarRss, starLite: peakStarRss },
    rows,
  };
}

export function formatBytes(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(2)} MB`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)} KB`;
  return `${n} B`;
}

export function formatBenchmarkSummary(summary: ExportBenchmarkSummary): string {
  const lines = [
    "",
    "== STAR-lite v0 vs CAR export benchmark ==",
    `Target repo payload (approx): ${formatBytes(summary.targetBytes)}`,
    `Total export bytes: CAR ${formatBytes(summary.totalExportedBytes.car)}, STAR-lite ${formatBytes(summary.totalExportedBytes.starLite)}`,
    `STAR-lite size ratio: ${(summary.starLiteVsCar.sizeRatio * 100).toFixed(1)}% of CAR (${summary.starLiteVsCar.sizeSavingsPercent.toFixed(1)}% smaller)`,
    `Total generation+transfer: CAR ${summary.totalGenerationMs.car.toFixed(0)} ms, STAR-lite ${summary.totalGenerationMs.starLite.toFixed(0)} ms (ratio ${summary.starLiteVsCar.timeRatio.toFixed(2)}x)`,
    `Peak RSS during export: CAR ${summary.peakRssKb.car} KB, STAR-lite ${summary.peakRssKb.starLite} KB`,
    "",
    "Per-repo (size / latency / peak RSS / avg CPU / disk Δ):",
  ];

  for (const row of summary.rows) {
    lines.push(
      `  ${row.pdsLabel} ${row.did.slice(0, 24)}… posts=${row.groundTruthPosts}`,
    );
    lines.push(
      `    CAR:       ${formatBytes(row.car.bytes)} / ${row.car.generationAndTransferMs.toFixed(0)} ms / ` +
        `${row.car.resources.peakRssKb} KB RSS / ${row.car.resources.avgCpuPercent.toFixed(1)}% CPU / ` +
        `${row.car.resources.diskDeltaKb} KB disk Δ`,
    );
    lines.push(
      `    STAR-lite: ${formatBytes(row.starLite.bytes)} / ${row.starLite.generationAndTransferMs.toFixed(0)} ms / ` +
        `${row.starLite.resources.peakRssKb} KB RSS / ${row.starLite.resources.avgCpuPercent.toFixed(1)}% CPU / ` +
        `${row.starLite.resources.diskDeltaKb} KB disk Δ`,
    );
    lines.push(`    correctness: ${row.correctnessOk ? "OK" : "FAIL"} — ${row.correctnessDetail}`);
  }

  return lines.join("\n");
}
