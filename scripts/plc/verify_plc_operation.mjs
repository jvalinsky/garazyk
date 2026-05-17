#!/usr/bin/env node
/**
 * PLC Operation Signature Verification Tool
 *
 * Verifies a single PLC operation against the ATProto specification:
 *   1. CBOR encoding (DAG-CBOR, sorted keys)
 *   2. SHA-256 hash of unsigned CBOR data
 *   3. DID derivation (base32 encoding of SHA-256 of signed CBOR)
 *   4. CID calculation (CIDv1 + dag-cbor + sha2-256)
 *   5. Signature verification against rotation keys (secp256k1 and P-256)
 *
 * Usage:
 *   node verify_plc_operation.mjs <did>
 *   node verify_plc_operation.mjs --json '<operation json>'
 *   echo '<operation json>' | node verify_plc_operation.mjs --stdin
 *
 * Dependencies: npm install (from scripts/plc/)
 */

import { option, parseArgs, printHelpAndExit } from "./lib/args.mjs";
import {
  bytesToHex,
  calculateCID,
  cborRoundTripCheck,
  deriveDID,
  encodeUnsigned,
  fetchDIDLog,
  getRotationKeys,
  verifyOperationSignature,
} from "./lib/plc.mjs";

// ── Option definitions ────────────────────────────────────────────

const OPTIONS = [
  option({
    name: "server",
    flag: "--server",
    type: "string",
    default: "https://plc.directory",
    env: "PLC_SERVER",
    description: "PLC directory URL",
  }),
  option({
    name: "json",
    flag: "--json",
    type: "string",
    default: null,
    description: "Raw JSON operation to verify",
  }),
  option({
    name: "stdin",
    flag: "--stdin",
    type: "boolean",
    default: false,
    description: "Read JSON operation from stdin",
  }),
  option({
    name: "verbose",
    flag: "--verbose",
    short: "-v",
    type: "boolean",
    default: false,
    description: "Print CBOR hex, hash hex, and CID",
  }),
];

// ── Verification ──────────────────────────────────────────────────

async function verifyOperation(op, did, cid, verbose) {
  const errors = [];
  const warnings = [];

  // 1. CBOR encoding + round-trip check
  const { cborBytes, hash } = encodeUnsigned(op);
  warnings.push(...cborRoundTripCheck(op));

  // 2. DID derivation
  const derivedDid = deriveDID(op);
  if (did && derivedDid !== did) {
    errors.push(`DID derivation mismatch: derived=${derivedDid}, expected=${did}`);
  }

  // 3. CID calculation
  const calculatedCid = calculateCID(op);
  if (cid && calculatedCid !== cid) {
    errors.push(`CID mismatch: calculated=${calculatedCid}, expected=${cid}`);
  }

  // 4. Signature verification
  const sig = op.sig ? new TextEncoder().encode(op.sig) : null;
  if (!op.sig) {
    errors.push("Missing sig field");
  }

  const rotationKeys = getRotationKeys(op);
  if (rotationKeys.length === 0) {
    errors.push("No rotation keys found");
  }

  let sigValid = false;
  let validKey = null;
  if (op.sig) {
    const result = await verifyOperationSignature(op);
    sigValid = result.valid;
    validKey = result.validKey;
  }

  if (!sigValid && op.sig) {
    errors.push("Signature verification failed against all rotation keys");
  }

  // 5. Genesis check
  if (op.prev !== null && op.prev !== undefined) {
    warnings.push(`Operation has prev=${op.prev} (non-genesis)`);
  }

  // ── Report ──────────────────────────────────────────────────────

  const ok = errors.length === 0;

  if (verbose) {
    console.log(`DID:          ${did || derivedDid}`);
    console.log(`CID:          ${cid || calculatedCid}`);
    console.log(`Type:         ${op.type}`);
    console.log(`CBOR bytes:   ${cborBytes.length}`);
    console.log(`CBOR hex:     ${bytesToHex(cborBytes)}`);
    console.log(`SHA-256:      ${bytesToHex(hash)}`);
    console.log(`Signature:    ${op.sig}`);
    console.log(`Rotation keys:${rotationKeys.length > 0 ? "" : " (none)"}`);
    for (const key of rotationKeys) {
      console.log(`  ${key}${key === validKey ? " (signed)" : ""}`);
    }
    console.log(`DID derived:  ${derivedDid}`);
    console.log(`CID calc:     ${calculatedCid}`);
    console.log(`Signature:    ${sigValid ? "VALID" : "INVALID"}`);
  } else {
    console.log(
      `${ok ? "PASS" : "FAIL"}  ${did || derivedDid}  type=${op.type}  sig=${
        sigValid ? "valid" : "INVALID"
      }`,
    );
  }

  for (const w of warnings) console.log(`  WARN: ${w}`);
  for (const e of errors) console.log(`  FAIL: ${e}`);

  return ok;
}

// ── Main ──────────────────────────────────────────────────────────

async function main() {
  const { args, rest, helpRequested } = parseArgs(process.argv, OPTIONS);

  if (helpRequested) {
    printHelpAndExit(
      "PLC Operation Signature Verification Tool",
      "node verify_plc_operation.mjs [options] <did>",
      OPTIONS,
      `  # Verify a DID from plc.directory
  node verify_plc_operation.mjs did:plc:ragtjsm2j2vknwkz3zp4oxrd

  # Verify with verbose output
  node verify_plc_operation.mjs -v did:plc:ragtjsm2j2vknwkz3zp4oxrd

  # Verify a raw JSON operation
  node verify_plc_operation.mjs --json '{"sig":"...","prev":null,"type":"create",...}'

  # Pipe from stdin
  echo '{"sig":"..."}' | node verify_plc_operation.mjs --stdin

  # Use a local PLC server
  PLC_SERVER=http://localhost:2582 node verify_plc_operation.mjs did:plc:xyz`,
    );
  }

  let op, did, cid;

  if (args.json) {
    op = JSON.parse(args.json);
    did = op.did || null;
    cid = op.cid || null;
  } else if (args.stdin) {
    const chunks = [];
    for await (const chunk of process.stdin) chunks.push(chunk);
    op = JSON.parse(Buffer.concat(chunks).toString());
    did = op.did || null;
    cid = op.cid || null;
  } else if (rest.length === 1) {
    did = rest[0];
    console.log(`Fetching ${did} from ${args.server}...`);
    const { operations } = await fetchDIDLog(did, args.server);
    op = operations[0];
    cid = calculateCID(op);
  } else {
    console.error("Error: provide a DID, --json, or --stdin. Use --help for usage.");
    process.exit(2);
  }

  const ok = await verifyOperation(op, did, cid, args.verbose);
  process.exit(ok ? 0 : 1);
}

main().catch((err) => {
  console.error(`Fatal: ${err.message}`);
  process.exit(2);
});
