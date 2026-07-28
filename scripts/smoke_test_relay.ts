#!/usr/bin/env -S deno run --allow-net
import { extname } from "jsr:/@std/path/extname";

const RELAY = Deno.args[0] ?? "http://localhost:2584";
const PDS = Deno.args[1] ?? RELAY.replace(/:2584$/, ":2583");

let passed = 0;
let failed = 0;
const errors: string[] = [];

async function check(label: string, url: string, opts?: {
  expectStatus?: number;
  expectJson?: boolean;
  validate?: (body: unknown) => string | null;
}) {
  try {
    const res = await fetch(url);
    const status = res.status;
    const ct = res.headers.get("content-type") ?? "";
    const text = await res.text();

    const statusOk = opts?.expectStatus == null || status === opts.expectStatus;
    const jsonOk = !opts?.expectJson || ct.includes("json");
    let validationMsg: string | null = null;
    if (opts?.validate && jsonOk) {
      try {
        validationMsg = opts.validate(JSON.parse(text));
      } catch {
        validationMsg = "failed to parse JSON body";
      }
    }

    if (statusOk && jsonOk && !validationMsg) {
      passed++;
    } else {
      const bits = [];
      if (!statusOk) bits.push(`status=${status} (expected ${opts?.expectStatus})`);
      if (!jsonOk) bits.push(`content-type=${ct}`);
      if (validationMsg) bits.push(validationMsg);
      failed++;
      errors.push(`FAIL ${label}: ${bits.join(", ")}`);
    }
  } catch (e) {
    failed++;
    errors.push(`FAIL ${label}: ${(e as Error).message}`);
  }
}

// ── Relay XRPC endpoints ──
const relayEndpoints: [string, string][] = [
  ["listRepos", `${RELAY}/xrpc/com.atproto.sync.listRepos`],
  ["getRepo (no params → 400)", `${RELAY}/xrpc/com.atproto.sync.getRepo`],
  ["getLatestCommit (no params → 400)", `${RELAY}/xrpc/com.atproto.sync.getLatestCommit`],
  ["subscribeRepos (GET → 404)", `${RELAY}/xrpc/com.atproto.sync.subscribeRepos`],
];

// ── PDS endpoints ──
const pdsEndpoints: [string, string][] = [
  ["_health", `${PDS}/xrpc/_health`],
  ["describeServer", `${PDS}/xrpc/com.atproto.server.describeServer`],
  ["getServiceAuth (no params → 400)", `${PDS}/xrpc/com.atproto.server.getServiceAuth`],
  ["listRepos", `${PDS}/xrpc/com.atproto.sync.listRepos`],
];

console.log(`\n=== Relay smoke test ===`);
console.log(`Relay: ${RELAY}`);
console.log(`PDS:   ${PDS}\n`);

// Run all checks
for (const [label, url] of relayEndpoints) {
  if (label.includes("400")) {
    await check(label, url, { expectStatus: 400, expectJson: true });
  } else if (label.includes("404")) {
    await check(label, url, { expectStatus: 404 });
  } else if (label === "listRepos") {
    await check(label, url, {
      expectStatus: 200,
      expectJson: true,
      validate: (body) => {
        const b = body as Record<string, unknown>;
        if (!Array.isArray(b.repos)) return "missing repos array";
        if (b.repos.length === 0) return "empty repos array";
        const repo = b.repos[0] as Record<string, unknown>;
        if (typeof repo.did !== "string") return "repo missing did";
        if (typeof repo.rev !== "string") return "repo missing rev";
        if (typeof repo.head !== "string") return "repo missing head";
        return null;
      },
    });
  }
}

for (const [label, url] of pdsEndpoints) {
  if (label === "_health") {
    await check(label, url, {
      expectStatus: 200,
      expectJson: true,
      validate: (body) => {
        const b = body as Record<string, unknown>;
        if (b.status !== "healthy") return `status=${b.status}`;
        return null;
      },
    });
  } else if (label === "describeServer") {
    await check(label, url, {
      expectStatus: 200,
      expectJson: true,
      validate: (body) => {
        const b = body as Record<string, unknown>;
        if (typeof b.did !== "string") return "missing did";
        return null;
      },
    });
  } else if (label.includes("400")) {
    await check(label, url, { expectStatus: 400, expectJson: true });
  } else if (label === "listRepos") {
    await check(label, url, {
      expectStatus: 200,
      expectJson: true,
      validate: (body) => {
        const b = body as Record<string, unknown>;
        if (!Array.isArray(b.repos)) return "missing repos array";
        return null;
      },
    });
  }
}

// ── Summary ──
console.log(`\nResults: ${passed} passed, ${failed} failed\n`);
if (errors.length > 0) {
  for (const e of errors) console.error(e);
}
Deno.exit(failed > 0 ? 1 : 0);
