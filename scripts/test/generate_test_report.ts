#!/usr/bin/env -S deno run -A
/**
 * Generate a standalone HTML test-run report from raw suite logs.
 *
 * Inputs (defaults point at reports_out/):
 *   - ObjC AllTests log   (looks for "Tests run:" / "FAIL: -[" markers)
 *   - Deno packages log   (looks for "<n> passed | <m> failed" + leak line)
 *   - Dashboard log       (same Deno-style summary)
 *
 * Output: reports_out/test_report.html
 */
import { join } from "jsr:@std/path";

interface Failure {
  suite: string;
  method: string;
  file: string;
  line: string;
  detail: string;
}

interface SuiteResult {
  name: string;
  run: number;
  failures: number;
  skipped?: number;
  duration?: string;
  status: "pass" | "fail" | "warn";
  note?: string;
  failuresList: Failure[];
}

function readOrEmpty(p: string): string {
  try {
    return Deno.readTextFileSync(p);
  } catch {
    return "";
  }
}

function parseObjC(log: string): SuiteResult {
  const run = Number(log.match(/Tests run:\s*(\d+)/)?.[1] ?? 0);
  const failures = Number(log.match(/Failures:\s*(\d+)/)?.[1] ?? 0);
  const skipped = Number(log.match(/Skipped gated test classes:\s*(\d+)/)?.[1] ?? 0);
  const dur = log.match(/Duration:\s*([\d.]+s)/)?.[1];

  const failuresList: Failure[] = [];
  const re = /FAIL: -\[(\w+)\s+(\w+)\]\s+at\s+(\/[^:]+):(\d+):\s*(.*)/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(log))) {
    failuresList.push({
      suite: m[1],
      method: m[2],
      file: m[3],
      line: m[4],
      detail: m[5].trim(),
    });
  }
  return {
    name: "ObjC AllTests",
    run,
    failures: failuresList.length || failures,
    skipped,
    duration: dur,
    status: failures > 0 ? "fail" : "pass",
    failuresList,
  };
}

function parseDeno(log: string, name: string): SuiteResult {
  const summary = log.match(/ok\s*\|\s*(\d+)\s+passed[^\n]*\|\s*(\d+)\s+failed/);
  const run = summary ? Number(summary[1]) : 0;
  const failures = summary ? Number(summary[2]) : 0;
  const leak = /Promise resolution is still pending/.test(log);
  const ignored = Number(log.match(/(\d+)\s+ignored/)?.[1] ?? 0);
  const dur = log.match(/\(([\dms]+)\)\s*$/m)?.[1];
  return {
    name,
    run,
    failures,
    skipped: ignored || undefined,
    duration: dur,
    status: leak ? "warn" : failures > 0 ? "fail" : "pass",
    note: leak ? "process exited 1 — leaked pending promise (WS4)" : undefined,
    failuresList: [],
  };
}

function esc(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function relPath(p: string): string {
  const i = p.indexOf("Garazyk/");
  return i >= 0 ? p.slice(i) : p;
}

function failureCard(f: Failure): string {
  const loc = `${relPath(f.file)}:${f.line}`;
  return `<div class="failure">
    <div class="failure-head">
      <span class="badge badge-fail">FAIL</span>
      <code class="test-name">-[${esc(f.suite)} ${esc(f.method)}]</code>
    </div>
    <div class="failure-loc">${esc(loc)}</div>
    <div class="failure-detail">${esc(f.detail)}</div>
  </div>`;
}

function suiteCard(s: SuiteResult): string {
  const statusClass =
    s.status === "pass" ? "ok" : s.status === "warn" ? "warn" : "bad";
  const statusLabel = s.status === "pass" ? "GREEN" : s.status === "warn" ? "WARN" : "RED";
  const failuresHtml = s.failuresList.length
    ? `<div class="failures">${s.failuresList.map(failureCard).join("")}</div>`
    : "";
  const meta = [
    `${s.run} run`,
    `${s.failures} failed`,
    s.skipped !== undefined ? `${s.skipped} skipped/ignored` : "",
    s.duration ? `⏱ ${s.duration}` : "",
  ].filter(Boolean).join(" &middot; ");
  const note = s.note ? `<div class="suite-note">${esc(s.note)}</div>` : "";
  return `<section class="suite suite-${statusClass}">
    <div class="suite-head">
      <h2>${esc(s.name)}</h2>
      <span class="badge badge-${statusClass}">${statusLabel}</span>
    </div>
    <div class="suite-meta">${meta}</div>
    ${note}
    ${failuresHtml}
  </section>`;
}

function render(suites: SuiteResult[], generated: string): string {
  const totalFail = suites.reduce((a, s) => a + s.failures, 0);
  const overall = totalFail === 0 && !suites.some((s) => s.status === "warn")
    ? "pass"
    : totalFail === 0
    ? "warn"
    : "fail";
  const overallLabel = overall === "pass"
    ? "ALL GREEN"
    : overall === "warn"
    ? "GREEN (1 WARN)"
    : `${totalFail} FAILURE(S)`;
  const cards = suites.map(suiteCard).join("\n");
  return `<!DOCTYPE html>
<html lang="en" data-theme="auto">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>Garazyk — Test Run Report</title>
<style>
  :root {
    --bg-primary: oklch(96% 0.004 15);
    --bg-secondary: oklch(99% 0.003 15);
    --bg-tertiary: oklch(93% 0.005 15);
    --text-primary: oklch(13% 0.005 200);
    --text-secondary: oklch(45% 0.005 200);
    --text-tertiary: oklch(60% 0.003 200);
    --accent: oklch(52% 0.18 15);
    --success: oklch(60% 0.18 145);
    --warning: oklch(68% 0.16 70);
    --destructive: oklch(58% 0.22 25);
    --info: oklch(60% 0.15 210);
    --separator: oklch(85% 0.003 200);
    --separator-secondary: oklch(91% 0.002 200);
    --log-bg: oklch(12% 0.005 200);
    --log-text: oklch(80% 0.01 200);
    --font: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    --mono: "SF Mono", Menlo, Monaco, Consolas, monospace;
    --r-sm: 4px; --r-md: 6px; --r-lg: 8px;
  }
  [data-theme="dark"] {
    --bg-primary: oklch(18% 0.008 15);
    --bg-secondary: oklch(24% 0.012 15);
    --bg-tertiary: oklch(28% 0.012 15);
    --text-primary: oklch(95% 0.005 200);
    --text-secondary: oklch(72% 0.006 200);
    --text-tertiary: oklch(58% 0.004 200);
    --separator: oklch(35% 0.01 200);
    --separator-secondary: oklch(30% 0.01 200);
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; background: var(--bg-primary); color: var(--text-primary);
    font-family: var(--font); line-height: 1.5; padding: 2rem 1rem;
  }
  .wrap { max-width: 920px; margin: 0 auto; }
  header.page { margin-bottom: 1.5rem; }
  h1 { font-size: 1.5rem; margin: 0 0 .25rem; letter-spacing: -0.02em; }
  .sub { color: var(--text-secondary); font-size: .9rem; }
  .overall {
    display: inline-flex; align-items: center; gap: .5rem; margin-top: 1rem;
    padding: .5rem .9rem; border-radius: var(--r-md); font-weight: 600;
    font-size: .95rem; border: 1px solid var(--separator);
  }
  .overall.pass { background: color-mix(in oklch, var(--success) 14%, transparent); color: var(--success); }
  .overall.warn { background: color-mix(in oklch, var(--warning) 14%, transparent); color: var(--warning); }
  .overall.fail { background: color-mix(in oklch, var(--destructive) 14%, transparent); color: var(--destructive); }
  .suite {
    background: var(--bg-secondary); border: 1px solid var(--separator);
    border-radius: var(--r-lg); padding: 1.1rem 1.2rem; margin-top: 1rem;
  }
  .suite-head { display: flex; justify-content: space-between; align-items: center; }
  .suite-head h2 { font-size: 1.05rem; margin: 0; }
  .suite-meta { color: var(--text-secondary); font-size: .85rem; margin-top: .25rem; }
  .suite-note {
    margin-top: .6rem; padding: .5rem .7rem; border-radius: var(--r-sm);
    background: color-mix(in oklch, var(--warning) 12%, transparent);
    color: var(--warning); font-size: .85rem;
  }
  .badge {
    font-size: .72rem; font-weight: 700; letter-spacing: .04em;
    padding: .2rem .55rem; border-radius: 999px; text-transform: uppercase;
  }
  .badge-ok { background: color-mix(in oklch, var(--success) 18%, transparent); color: var(--success); }
  .badge-warn { background: color-mix(in oklch, var(--warning) 18%, transparent); color: var(--warning); }
  .badge-bad { background: color-mix(in oklch, var(--destructive) 18%, transparent); color: var(--destructive); }
  .badge-fail { background: color-mix(in oklch, var(--destructive) 20%, transparent); color: var(--destructive); margin-right: .5rem; }
  .failures { margin-top: .9rem; display: grid; gap: .7rem; }
  .failure {
    background: var(--bg-tertiary); border: 1px solid var(--separator-secondary);
    border-radius: var(--r-md); padding: .8rem .9rem;
  }
  .failure-head { display: flex; align-items: center; }
  .test-name { font-family: var(--mono); font-size: .85rem; }
  .failure-loc { font-family: var(--mono); font-size: .78rem; color: var(--text-tertiary); margin: .35rem 0; }
  .failure-detail { font-size: .85rem; color: var(--text-secondary); }
  footer { margin-top: 2rem; color: var(--text-tertiary); font-size: .8rem; }
  a { color: var(--info); }
</style>
</head>
<body>
<div class="wrap">
  <header class="page">
    <h1>Garazyk — Test Run Report</h1>
    <div class="sub">Generated ${esc(generated)} &middot; rebuilt from current HEAD</div>
    <div class="overall ${overall}">${overallLabel}</div>
  </header>
  ${cards}
  <footer>
    Source logs: <code>reports_out/objc_alltests_HEAD_2026-07-13.log</code>,
    <code>reports_out/deno_packages_2026-07-13.log</code>,
    <code>reports_out/dashboard_2026-07-13.log</code>.
    Plan: <code>docs/plans/remediation-test-regressions-2026-07-13.md</code>.
  </footer>
</div>
</body>
</html>`;
}

const outDir = "reports_out";
const objcLog = readOrEmpty(join(outDir, "objc_alltests_HEAD_2026-07-13.log"));
const denoLog = readOrEmpty(join(outDir, "deno_packages_2026-07-13.log"));
const dashLog = readOrEmpty(join(outDir, "dashboard_2026-07-13.log"));

const suites: SuiteResult[] = [
  parseObjC(objcLog),
  parseDeno(denoLog, "Deno packages"),
  parseDeno(dashLog, "Scenario dashboard"),
];

const generated = new Date().toISOString().slice(0, 19).replace("T", " ");
const html = render(suites, generated);
await Deno.writeTextFile(join(outDir, "test_report.html"), html);
console.log(`Wrote reports_out/test_report.html (${suites.map((s) => s.name + ":" + s.failures).join(", ")})`);
