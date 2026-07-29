#!/usr/bin/env -S deno run -A

/**
 * Connect to a relay's com.atproto.sync.subscribeRepos firehose, record the
 * stream for a short window, and pretty-print a summary report.
 *
 * Usage:
 *   deno run -A scripts/relay_stream_report.ts [options]
 *   deno run -A scripts/relay_stream_report.ts --relay-url http://127.0.0.1:2584 --duration 15
 */
import { Command } from "@cliffy/command";
import { Table } from "@cliffy/table";
import { bold, cyan, dim, green, magenta, yellow } from "@std/fmt/colors";
import { FirehoseClient, type FirehoseEvent } from "@garazyk/gruszka";

interface RepoOp {
  action?: string;
  path?: string;
  cid?: unknown;
}

function commitOps(event: FirehoseEvent): RepoOp[] {
  const ops = event.body.ops;
  return Array.isArray(ops) ? (ops as RepoOp[]) : [];
}

function collectionOf(path: string | undefined): string {
  if (!path) return "(unknown)";
  const slash = path.indexOf("/");
  return slash === -1 ? path : path.slice(0, slash);
}

function bump(map: Map<string, number>, key: string, by = 1): void {
  map.set(key, (map.get(key) ?? 0) + by);
}

function topEntries(
  map: Map<string, number>,
  limit: number,
): [string, number][] {
  return [...map.entries()].sort((a, b) => b[1] - a[1]).slice(0, limit);
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KiB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MiB`;
}

function shortDid(did: string | undefined): string {
  if (!did) return "(unknown)";
  return did.length > 28 ? `${did.slice(0, 25)}...` : did;
}

interface Analysis {
  totalEvents: number;
  totalBytes: number;
  byType: Map<string, number>;
  commitActions: Map<string, number>;
  collections: Map<string, number>;
  repos: Set<string>;
  minSeq: number | undefined;
  maxSeq: number | undefined;
  sampleOps: {
    repo: string;
    action: string;
    collection: string;
    rkey: string;
  }[];
}

function analyze(events: FirehoseEvent[]): Analysis {
  const analysis: Analysis = {
    totalEvents: events.length,
    totalBytes: 0,
    byType: new Map(),
    commitActions: new Map(),
    collections: new Map(),
    repos: new Set(),
    minSeq: undefined,
    maxSeq: undefined,
    sampleOps: [],
  };

  for (const event of events) {
    analysis.totalBytes += event.payload.byteLength;
    bump(analysis.byType, event.type);

    if (event.seq > 0) {
      analysis.minSeq = analysis.minSeq === undefined
        ? event.seq
        : Math.min(analysis.minSeq, event.seq);
      analysis.maxSeq = analysis.maxSeq === undefined
        ? event.seq
        : Math.max(analysis.maxSeq, event.seq);
    }

    const repo = typeof event.body.repo === "string"
      ? event.body.repo
      : typeof event.body.did === "string"
      ? event.body.did
      : undefined;
    if (repo) analysis.repos.add(repo);

    if (event.type === "#commit") {
      for (const op of commitOps(event)) {
        const action = op.action ?? "(unknown)";
        const collection = collectionOf(op.path);
        bump(analysis.commitActions, action);
        bump(analysis.collections, collection);

        if (analysis.sampleOps.length < 8) {
          const rkey = op.path?.includes("/")
            ? op.path.slice(op.path.indexOf("/") + 1)
            : "";
          analysis.sampleOps.push({
            repo: shortDid(repo),
            action,
            collection,
            rkey,
          });
        }
      }
    }
  }

  return analysis;
}

function actionColor(action: string): (s: string) => string {
  if (action === "create") return green;
  if (action === "delete") return yellow;
  if (action === "update") return cyan;
  return dim;
}

function printReport(
  relayUrl: string,
  durationS: number,
  elapsedMs: number,
  analysis: Analysis,
): void {
  const elapsedS = elapsedMs / 1000;
  const rate = elapsedS > 0 ? analysis.totalEvents / elapsedS : 0;
  const byteRate = elapsedS > 0 ? analysis.totalBytes / elapsedS : 0;

  console.log("");
  console.log(bold(magenta("=".repeat(60))));
  console.log(bold(magenta(`  Relay Firehose Snapshot`)));
  console.log(bold(magenta("=".repeat(60))));
  console.log(`  ${bold("Relay:")}      ${relayUrl}`);
  console.log(
    `  ${bold("Window:")}     ${
      elapsedS.toFixed(1)
    }s (requested ${durationS}s)`,
  );
  console.log(
    `  ${bold("Seq range:")}  ${analysis.minSeq ?? "-"} .. ${
      analysis.maxSeq ?? "-"
    }`,
  );
  console.log("");

  console.log(bold("Summary"));
  new Table()
    .body([
      ["Total events", cyan(String(analysis.totalEvents))],
      ["Events/sec", cyan(rate.toFixed(1))],
      ["Total bytes", cyan(formatBytes(analysis.totalBytes))],
      ["Bytes/sec", cyan(formatBytes(byteRate))],
      ["Unique repos seen", cyan(String(analysis.repos.size))],
    ])
    .border(true)
    .render();

  if (analysis.totalEvents === 0) {
    console.log("");
    console.log(yellow("No events received in the recording window."));
    return;
  }

  console.log("");
  console.log(bold("Event Types"));
  new Table()
    .header([bold("TYPE"), bold("COUNT"), bold("SHARE")])
    .body(
      topEntries(analysis.byType, 20).map(([type, count]) => [
        type,
        String(count),
        `${((count / analysis.totalEvents) * 100).toFixed(1)}%`,
      ]),
    )
    .border(true)
    .render();

  if (analysis.commitActions.size > 0) {
    console.log("");
    console.log(bold("Commit Ops by Action"));
    new Table()
      .header([bold("ACTION"), bold("COUNT")])
      .body(
        topEntries(analysis.commitActions, 10).map(([action, count]) => [
          actionColor(action)(action),
          String(count),
        ]),
      )
      .border(true)
      .render();
  }

  if (analysis.collections.size > 0) {
    console.log("");
    console.log(bold("Top Collections (NSIDs)"));
    new Table()
      .header([bold("COLLECTION"), bold("OPS")])
      .body(
        topEntries(analysis.collections, 15).map(([collection, count]) => [
          collection,
          String(count),
        ]),
      )
      .border(true)
      .render();
  }

  if (analysis.sampleOps.length > 0) {
    console.log("");
    console.log(bold(`Sample Ops (first ${analysis.sampleOps.length})`));
    new Table()
      .header([bold("REPO"), bold("ACTION"), bold("COLLECTION"), bold("RKEY")])
      .body(
        analysis.sampleOps.map((op) => [
          dim(op.repo),
          actionColor(op.action)(op.action),
          op.collection,
          op.rkey,
        ]),
      )
      .border(true)
      .render();
  }

  console.log("");
}

const { options } = await new Command()
  .name("relay_stream_report")
  .description(
    "Connect to a relay firehose, record it for a short window, and print a pretty summary report.",
  )
  .option("--relay-url <url:string>", "Relay HTTP(S) or WebSocket URL.", {
    default: Deno.env.get("RELAY_URL") || "http://127.0.0.1:2584",
  })
  .option("--duration <seconds:number>", "How long to record, in seconds.", {
    default: 10,
  })
  .option("--cursor <seq:number>", "Resume after this relay sequence number.")
  .parse(Deno.args);

const client = new FirehoseClient(options.relayUrl);
console.log(
  dim(
    `Recording firehose from ${options.relayUrl} for ${options.duration}s...`,
  ),
);

const startedAt = performance.now();
const events = await client.collect(options.duration, options.cursor);
const elapsedMs = performance.now() - startedAt;

printReport(options.relayUrl, options.duration, elapsedMs, analyze(events));
