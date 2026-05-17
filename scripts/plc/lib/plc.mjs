/**
 * Shared PLC protocol library.
 *
 * CBOR encoding, DID derivation, CID calculation, signature verification,
 * key classification, base64url codec, and export fetching.
 *
 * Used by: verify_plc_operation.mjs, simulate_plc_sync.mjs, audit_plc_export.mjs
 */

import { verifySignature } from "@atproto/crypto";
import { decode as cborDecode, encode as cborEncode } from "@ipld/dag-cbor";
import { sha256 } from "@noble/hashes/sha256";
import { base32 } from "multiformats/bases/base32";
import { base58btc } from "multiformats/bases/base58";

// ── Encoding helpers ─────────────────────────────────────────────

export function bytesToHex(bytes) {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

export function base64UrlDecode(str) {
  const b64 = str.replace(/-/g, "+").replace(/_/g, "/") +
    "=".repeat((4 - str.length % 4) % 4);
  const bin = atob(b64);
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

export function base64UrlEncode(bytes) {
  const bin = String.fromCharCode(...bytes);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// ── Operation data shaping ────────────────────────────────────────

/**
 * Build unsigned operation data (strip sig, did, cid).
 * Ensures prev is explicitly null for genesis operations.
 */
export function unsignedData(op) {
  const data = { ...op };
  delete data.sig;
  delete data.did;
  delete data.cid;
  if (data.prev === undefined) data.prev = null;
  return data;
}

/**
 * Build signed operation dict (for CID / DID derivation).
 * Includes sig and prev (if present), strips did and cid.
 */
export function signedData(op) {
  const data = { ...op };
  delete data.did;
  delete data.cid;
  if (data.prev === undefined) data.prev = null;
  return data;
}

// ── DID derivation ────────────────────────────────────────────────

/**
 * Derive did:plc from a signed operation.
 * Per did-method-plc spec: did:plc:<first 24 chars of base32(SHA-256(DAG-CBOR(signedOp)))>
 */
export function deriveDID(op) {
  const signed = signedData(op);
  const cborBytes = cborEncode(signed);
  const hash = sha256(cborBytes);
  const encoded = base32.encode(hash);
  const b32 = encoded.slice(1).toLowerCase();
  return "did:plc:" + b32.slice(0, 24);
}

// ── CID calculation ──────────────────────────────────────────────

/**
 * Calculate CIDv1 (dag-cbor codec, sha2-256 multihash) for a signed operation.
 * Returns the "b" prefixed base32 CID string used by plc.directory.
 */
export function calculateCID(op) {
  const signed = signedData(op);
  const cborBytes = cborEncode(signed);
  const hash = sha256(cborBytes);
  // CIDv1: 0x01, dag-cbor codec 0x71, sha2-256 multihash 0x12 0x20 <32 bytes>
  const cidBytes = new Uint8Array([0x01, 0x71, 0x12, 0x20, ...hash]);
  return "b" + base32.encode(cidBytes).slice(1);
}

// ── Rotation keys ────────────────────────────────────────────────

/**
 * Get rotation keys for an operation.
 * For genesis create: [recoveryKey, signingKey]
 * For plc_operation: rotationKeys array
 */
export function getRotationKeys(op) {
  if (op.type === "create") return [op.recoveryKey, op.signingKey];
  if (op.type === "plc_operation") return op.rotationKeys || [];
  return [];
}

// ── Signature verification ────────────────────────────────────────

/**
 * Verify a PLC operation's signature against its rotation keys.
 *
 * @param {object} op - The PLC operation (must have .sig)
 * @param {string[]} [rotationKeys] - Override rotation keys (defaults to op's own keys)
 * @returns {{ valid: boolean, validKey: string|null }}
 */
export async function verifyOperationSignature(op, rotationKeys) {
  const keys = rotationKeys || getRotationKeys(op);
  const unsigned = unsignedData(op);
  const cborBytes = cborEncode(unsigned);
  const sig = base64UrlDecode(op.sig);

  for (const key of keys) {
    try {
      if (await verifySignature(key, cborBytes, sig)) {
        return { valid: true, validKey: key };
      }
    } catch {
      // Unsupported key type or verification error — skip
    }
  }
  return { valid: false, validKey: null };
}

/**
 * Verify a non-genesis operation's signature against its predecessor's rotation keys.
 *
 * @param {object} op - The PLC operation to verify
 * @param {object} prevOp - The predecessor operation (used for rotation keys)
 * @returns {{ valid: boolean, validKey: string|null }}
 */
export async function verifyOperationSignatureWithPrev(op, prevOp) {
  return verifyOperationSignature(op, getRotationKeys(prevOp));
}

// ── CBOR round-trip ──────────────────────────────────────────────

/**
 * CBOR-encode unsigned data and return the bytes + SHA-256 hash.
 */
export function encodeUnsigned(op) {
  const unsigned = unsignedData(op);
  const cborBytes = cborEncode(unsigned);
  const hash = sha256(cborBytes);
  return { cborBytes, hash, unsigned };
}

/**
 * CBOR round-trip check: encode then decode, compare key order.
 * Returns warnings array (empty if round-trip matches).
 */
export function cborRoundTripCheck(op) {
  const unsigned = unsignedData(op);
  const cborBytes = cborEncode(unsigned);
  const decoded = cborDecode(cborBytes);
  const roundTrip = JSON.stringify(decoded, (k, v) => typeof v === "bigint" ? v.toString() : v);
  const original = JSON.stringify(unsigned, (k, v) => typeof v === "bigint" ? v.toString() : v);
  if (roundTrip !== original) {
    return ["CBOR round-trip produced different key order (non-fatal, DAG-CBOR sorts keys)"];
  }
  return [];
}

// ── Key type classification ───────────────────────────────────────

const MULTICODEC_SECP256K1 = 0xE7;
const MULTICODEC_P256 = 0x1200;

function readVarint(bytes, offset) {
  let value = 0, shift = 0;
  while (offset < bytes.length) {
    const byte = bytes[offset++];
    value |= (byte & 0x7F) << shift;
    if (!(byte & 0x80)) break;
    shift += 7;
  }
  return { value, length: offset };
}

/**
 * Classify a did:key as secp256k1, p256, or unknown.
 */
export function classifyDidKey(didKey) {
  if (!didKey || !didKey.startsWith("did:key:z")) return "unknown";
  try {
    const multibase = didKey.slice("did:key:z".length);
    const decoded = base58btc.decode("z" + multibase);
    const { value: multicodec } = readVarint(decoded, 0);
    if (multicodec === MULTICODEC_SECP256K1) return "secp256k1";
    if (multicodec === MULTICODEC_P256) return "p256";
    return `unknown-0x${multicodec.toString(16)}`;
  } catch {
    return "parse-error";
  }
}

// ── Field validation ──────────────────────────────────────────────

const REQUIRED_FIELDS = {
  create: ["sig", "prev", "type", "handle", "service", "signingKey", "recoveryKey"],
  plc_operation: [
    "sig",
    "prev",
    "type",
    "rotationKeys",
    "verificationMethods",
    "alsoKnownAs",
    "services",
  ],
  plc_tombstone: ["sig", "prev", "type"],
};

/**
 * Validate that an operation has all required fields for its type.
 * Returns array of missing field names (empty if valid).
 */
export function validateFields(op) {
  const required = REQUIRED_FIELDS[op.type];
  if (!required) return [`unknown-type:${op.type}`];
  return required.filter((f) => op[f] === undefined);
}

// ── Export fetching ───────────────────────────────────────────────

/**
 * Fetch a batch of operations from the PLC directory export endpoint.
 *
 * @param {string} server - PLC directory base URL
 * @param {string|null} after - Cursor (ISO timestamp) to start after
 * @param {number} count - Number of operations to fetch
 * @returns {Promise<Array<{did, cid, createdAt, operation, nullified}>>}
 */
export async function fetchExportBatch(server, after, count) {
  let url = `${server}/export?count=${count}`;
  if (after) url += `&after=${encodeURIComponent(after)}`;

  const res = await fetch(url);
  if (!res.ok) throw new Error(`Export returned ${res.status}: ${url}`);
  const text = await res.text();
  if (!text.trim()) return [];

  return text.trim().split("\n").filter((l) => l.trim()).map((line) => {
    const entry = JSON.parse(line);
    return {
      did: entry.did,
      cid: entry.cid,
      createdAt: entry.createdAt,
      operation: entry.operation,
      nullified: entry.nullified || false,
    };
  });
}

/**
 * Fetch the full operation log for a DID from the PLC directory.
 *
 * @param {string} did - The DID to fetch
 * @param {string} server - PLC directory base URL
 * @returns {Promise<{did, operations: object[], logLength: number}>}
 */
export async function fetchDIDLog(did, server) {
  const url = `${server}/${encodeURIComponent(did)}/log`;
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`PLC directory returned ${res.status} for ${url}`);
  }
  const log = await res.json();
  if (!Array.isArray(log) || log.length === 0) {
    throw new Error("No operations found in PLC directory response");
  }
  return { did, operations: log, logLength: log.length };
}

// ── In-memory DID store ──────────────────────────────────────────

export class DIDStore {
  constructor() {
    this.history = new Map();
  }

  getHistory(did) {
    return this.history.get(did) || [];
  }

  append(op, did, cid) {
    if (!this.history.has(did)) this.history.set(did, []);
    this.history.get(did).push({ ...op, cid, did });
  }

  get didCount() {
    return this.history.size;
  }
}
