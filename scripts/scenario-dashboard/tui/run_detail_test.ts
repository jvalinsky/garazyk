/**
 * Unit tests for run detail overlay pure helpers.
 *
 * Tests `formatRunMetadataLine` in isolation — no ScreenBuffer, no DOM.
 *
 * @module tui/run_detail_test
 */

import { assertEquals } from "@std/assert";
import { formatRunMetadataLine } from "./panels/run_detail.ts";
import type { Run } from "../services/types.ts";

function makeRun(overrides: Partial<Run> = {}): Run {
  return {
    id: "run-test-1",
    startedAt: 0,
    status: "completed",
    totalScenarios: 1,
    passed: 1,
    failed: 0,
    skipped: 0,
    ...overrides,
  };
}

// ── agent badge ──────────────────────────────────────────────────────

Deno.test("formatRunMetadataLine: includes 'agent: yes' when agentMode is true", () => {
  const run = makeRun({ agentMode: true });
  const line = formatRunMetadataLine(run);
  assertEquals(line.includes("agent: yes"), true, `Expected 'agent: yes' in: ${line}`);
});

Deno.test("formatRunMetadataLine: includes 'agent: no' when agentMode is false", () => {
  const run = makeRun({ agentMode: false });
  const line = formatRunMetadataLine(run);
  assertEquals(line.includes("agent: no"), true, `Expected 'agent: no' in: ${line}`);
});

Deno.test("formatRunMetadataLine: includes 'agent: no' when agentMode is undefined", () => {
  const run = makeRun({ agentMode: undefined });
  const line = formatRunMetadataLine(run);
  assertEquals(line.includes("agent: no"), true, `Expected 'agent: no' in: ${line}`);
});

// ── topology ─────────────────────────────────────────────────────────

Deno.test("formatRunMetadataLine: includes topology when present", () => {
  const run = makeRun({ topology: "garazyk-default" });
  const line = formatRunMetadataLine(run);
  assertEquals(line.includes("topology: garazyk-default"), true);
});

Deno.test("formatRunMetadataLine: omits topology when absent", () => {
  const run = makeRun({ topology: undefined });
  const line = formatRunMetadataLine(run);
  assertEquals(line.includes("topology:"), false);
});

// ── runner ───────────────────────────────────────────────────────────

Deno.test("formatRunMetadataLine: includes runner when present", () => {
  const run = makeRun({ runner: "docker" });
  const line = formatRunMetadataLine(run);
  assertEquals(line.includes("runner: docker"), true);
});

Deno.test("formatRunMetadataLine: omits runner when absent", () => {
  const run = makeRun({ runner: undefined });
  const line = formatRunMetadataLine(run);
  assertEquals(line.includes("runner:"), false);
});

// ── pds2 ─────────────────────────────────────────────────────────────

Deno.test("formatRunMetadataLine: includes 'pds2: yes' when true", () => {
  const run = makeRun({ pds2: true });
  const line = formatRunMetadataLine(run);
  assertEquals(line.includes("pds2: yes"), true);
});

Deno.test("formatRunMetadataLine: includes 'pds2: no' when false", () => {
  const run = makeRun({ pds2: false });
  const line = formatRunMetadataLine(run);
  assertEquals(line.includes("pds2: no"), true);
});

// ── binary ───────────────────────────────────────────────────────────

Deno.test("formatRunMetadataLine: includes 'binary: yes' when true", () => {
  const run = makeRun({ binaryMode: true });
  const line = formatRunMetadataLine(run);
  assertEquals(line.includes("binary: yes"), true);
});

Deno.test("formatRunMetadataLine: includes 'binary: no' when false", () => {
  const run = makeRun({ binaryMode: false });
  const line = formatRunMetadataLine(run);
  assertEquals(line.includes("binary: no"), true);
});

// ── full output ──────────────────────────────────────────────────────

Deno.test("formatRunMetadataLine: all fields present with values", () => {
  const run = makeRun({
    topology: "garazyk-default",
    runner: "host",
    pds2: true,
    binaryMode: false,
    agentMode: true,
  });
  const line = formatRunMetadataLine(run);
  assertEquals(line, "topology: garazyk-default  runner: host  pds2: yes  binary: no  agent: yes");
});

Deno.test("formatRunMetadataLine: minimal fields (no topology, no runner)", () => {
  const run = makeRun({
    topology: undefined,
    runner: undefined,
    pds2: false,
    binaryMode: false,
    agentMode: false,
  });
  const line = formatRunMetadataLine(run);
  assertEquals(line, "pds2: no  binary: no  agent: no");
});
