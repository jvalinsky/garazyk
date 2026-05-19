#!/usr/bin/env -S deno run -A
/**
 * validate_pds_config.ts
 * Validates PDS configuration for production security standards.
 */

import { parseArgs } from "@std/cli";
import { exists } from "@std/fs";

const args = parseArgs(Deno.args);
const configPath = args._[0] as string ?? "docker/pds/config.json";

if (!await exists(configPath)) {
  console.error(`Error: Config file not found at ${configPath}`);
  Deno.exit(1);
}

console.log(`Validating PDS config: ${configPath}`);

const text = await Deno.readTextFile(configPath);
// Strip C-style comments before parsing
const cleanJson = text.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");
const data = JSON.parse(cleanJson);

let ret = 0;

function check(key: string, value: any, expected: any) {
  if (value !== expected) {
    console.log(`FAIL: ${key} expected '${expected}', got '${value}'`);
    ret = 1;
    return false;
  }
  console.log(`PASS: ${key} is '${value}'`);
  return true;
}

// Secure Defaults — MANDATORY
check("session.invite_code_required", data.session?.invite_code_required, true);
check("plc.url", data.plc?.url, "https://plc.directory");
check("rate_limit.enabled", data.rate_limit?.enabled, true);

// Check for any debug flags enabled
const debugFlags = JSON.stringify(data.debug ?? {});
if (debugFlags.includes("true")) {
  console.log(`FAIL: Debug flags enabled in ${debugFlags}`);
  ret = 1;
}

if (ret === 0) {
  console.log("Config validation SUCCESS");
} else {
  console.log("Config validation FAILED");
}

Deno.exit(ret);
