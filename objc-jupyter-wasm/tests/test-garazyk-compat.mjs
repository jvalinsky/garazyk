#!/usr/bin/env node
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { dirname } from "node:path";
import {
  classifySnippet,
  createObjcKernel,
  diagnoseUnsupportedApis,
  runHostBridgeSelfTest,
  streamText,
} from "./objc-kernel-test-harness.mjs";
import { garazykCompatCorpus } from "./garazyk-compat-corpus.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);

let wasmPath = resolve(__dirname, "../result/wasm/kernel.wasm");
let jsonOutput = false;
let verbose = false;

for (let i = 0; i < args.length; i++) {
  const arg = args[i];
  if (arg === "--kernel") wasmPath = resolve(args[++i]);
  else if (arg === "--json") jsonOutput = true;
  else if (arg === "--verbose") verbose = true;
  else if (arg.endsWith(".wasm")) wasmPath = resolve(arg);
  else {
    console.error(`Unknown argument: ${arg}`);
    process.exit(2);
  }
}

const isTTY = process.stdout.isTTY;
const C = isTTY
  ? {
    reset: "\x1b[0m",
    bold: "\x1b[1m",
    dim: "\x1b[2m",
    green: "\x1b[32m",
    red: "\x1b[31m",
    yellow: "\x1b[33m",
    gray: "\x1b[90m",
  }
  : { reset: "", bold: "", dim: "", green: "", red: "", yellow: "", gray: "" };

function expectedStrings(test) {
  if (!test.expectedOutput) return [];
  return Array.isArray(test.expectedOutput) ? test.expectedOutput : [test.expectedOutput];
}

function diagnosticPass(test, diagnostics) {
  const expected = test.expectedDiagnosticApis ?? [];
  if (expected.length === 0) return diagnostics.length > 0;
  const actual = new Set(diagnostics.map((item) => item.api));
  return expected.every((api) => actual.has(api));
}

async function runCase(test, index) {
  const classification = classifySnippet(test.source, test);
  const unsupportedDiagnostics = diagnoseUnsupportedApis(test.source);
  const base = {
    index,
    name: test.name,
    category: test.category,
    supportClass: classification.supportClass,
    tags: [...new Set([...(test.tags ?? []), ...classification.tags])],
    expectedStatus: test.expectedStatus ?? "ok",
    diagnostics: unsupportedDiagnostics,
    source: test.source,
  };

  if ((test.expectedStatus ?? "ok") === "diagnostic") {
    return {
      ...base,
      status: diagnosticPass(test, unsupportedDiagnostics) ? "pass" : "fail",
      actualStatus: unsupportedDiagnostics.length > 0 ? "diagnostic" : "missing-diagnostic",
      output: unsupportedDiagnostics.map((item) => `${item.api}: ${item.message}`).join("\n"),
    };
  }

  if ((test.expectedStatus ?? "ok") === "host-check") {
    const check = runHostBridgeSelfTest(test.hostCheck);
    const missing = expectedStrings(test).filter((needle) => !check.output.includes(needle));
    return {
      ...base,
      status: check.passed && missing.length === 0 ? "pass" : "fail",
      actualStatus: "host-check",
      output: check.output,
      missingOutput: missing,
      failure: check.passed && missing.length === 0
        ? undefined
        : `Host bridge check failed: ${test.hostCheck}`,
    };
  }

  if (unsupportedDiagnostics.length > 0) {
    return {
      ...base,
      status: "fail",
      actualStatus: "diagnostic",
      output: unsupportedDiagnostics.map((item) => `${item.api}: ${item.message}`).join("\n"),
      failure: "Snippet uses unsupported production APIs but was expected to execute.",
    };
  }

  let reply;
  try {
    const kernel = await createObjcKernel(wasmPath);
    reply = await kernel.executeAsync(test.source, `garazyk-compat-${index}`);
  } catch (error) {
    return {
      ...base,
      status: "fail",
      actualStatus: "harness-error",
      output: "",
      failure: error.message,
    };
  }

  const output = streamText(reply);
  const missing = expectedStrings(test).filter((needle) => !output.includes(needle));
  const expectedStatus = test.expectedStatus ?? "ok";
  const statusMatches = reply.status === expectedStatus;
  const passed = statusMatches && missing.length === 0;

  return {
    ...base,
    status: passed ? "pass" : "fail",
    actualStatus: reply.status,
    output,
    missingOutput: missing,
    failure: passed ? undefined : [
      statusMatches ? null : `Expected status ${expectedStatus}, got ${reply.status}`,
      missing.length > 0 ? `Missing output: ${missing.join(", ")}` : null,
      reply.status === "error" ? `${reply.ename}: ${reply.evalue}` : null,
    ].filter(Boolean).join("; "),
    reply: verbose || !passed ? reply : undefined,
  };
}

const results = [];

for (let i = 0; i < garazykCompatCorpus.length; i++) {
  results.push(await runCase(garazykCompatCorpus[i], i));
}

if (jsonOutput) {
  console.log(JSON.stringify(
    {
      wasmPath,
      total: results.length,
      passed: results.filter((r) => r.status === "pass").length,
      failed: results.filter((r) => r.status === "fail").length,
      results,
    },
    null,
    2,
  ));
} else {
  for (const result of results) {
    const icon = result.status === "pass" ? `${C.green}PASS${C.reset}` : `${C.red}FAIL${C.reset}`;
    console.log(
      `${icon} ${C.bold}${result.name}${C.reset}  ${C.dim}[${result.category}, ${result.supportClass}]${C.reset}`,
    );
    if (verbose || result.status === "fail") {
      if (result.output.trim()) {
        console.log(
          result.output.trimEnd().split("\n").map((line) => `  ${C.gray}${line}${C.reset}`).join(
            "\n",
          ),
        );
      }
      if (result.failure) console.log(`  ${C.red}${result.failure}${C.reset}`);
    }
  }

  const passed = results.filter((r) => r.status === "pass").length;
  const failed = results.length - passed;
  console.log("");
  if (failed === 0) {
    console.log(
      `${C.green}${C.bold}Garazyk compatibility corpus passed${C.reset}  (${passed}/${results.length})`,
    );
  } else {
    console.log(
      `${C.red}${C.bold}Garazyk compatibility corpus failed${C.reset}  (${failed} failed, ${passed} passed)`,
    );
  }
}

process.exit(results.some((r) => r.status === "fail") ? 1 : 0);
