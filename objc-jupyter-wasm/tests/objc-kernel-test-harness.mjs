import { readFile } from 'node:fs/promises';
import { WASI } from 'node:wasi';
import crypto from 'node:crypto';

export const TRANSPORT = {
  OK: 0,
  INVALID_ARGUMENT: 1,
  REQUEST_TOO_LARGE: 2,
  RESPONSE_TOO_LARGE: 3,
  OOM: 4,
  INTERNAL_ERROR: 5,
};

const encoder = new TextEncoder();
const decoder = new TextDecoder();
const base32Alphabet = 'abcdefghijklmnopqrstuvwxyz234567';
const base58Alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

function readCString(memory, ptr) {
  if (!ptr) return '';
  const bytes = new Uint8Array(memory.buffer);
  let end = ptr;
  while (end < bytes.length && bytes[end] !== 0) end++;
  return decoder.decode(bytes.subarray(ptr, end));
}

function writeBytes(memory, ptr, cap, bytes) {
  const out = new Uint8Array(memory.buffer);
  const n = Math.min(bytes.length, cap);
  out.set(bytes.subarray(0, n), ptr);
  return n;
}

function hexToBytes(hex) {
  const out = new Uint8Array(Math.floor(hex.length / 2));
  for (let i = 0; i < out.length; i++) {
    out[i] = Number.parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

function base32Encode(bytes) {
  let bits = 0;
  let value = 0;
  let output = '';
  for (const byte of bytes) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      output += base32Alphabet[(value >> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) output += base32Alphabet[(value << (5 - bits)) & 31];
  return output;
}

function base32Decode(input) {
  let bits = 0;
  let value = 0;
  const out = [];
  for (const raw of input.toLowerCase()) {
    const idx = base32Alphabet.indexOf(raw);
    if (idx < 0) continue;
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      out.push((value >> (bits - 8)) & 255);
      bits -= 8;
    }
  }
  return Uint8Array.from(out);
}

function base58Encode(bytes) {
  if (bytes.length === 0) return '';
  const digits = [0];
  for (const byte of bytes) {
    let carry = byte;
    for (let i = 0; i < digits.length; i++) {
      carry += digits[i] << 8;
      digits[i] = carry % 58;
      carry = (carry / 58) | 0;
    }
    while (carry > 0) {
      digits.push(carry % 58);
      carry = (carry / 58) | 0;
    }
  }
  let output = '';
  for (const byte of bytes) {
    if (byte === 0) output += base58Alphabet[0];
    else break;
  }
  for (let i = digits.length - 1; i >= 0; i--) output += base58Alphabet[digits[i]];
  return output;
}

function base58Decode(input) {
  if (!input) return new Uint8Array();
  const bytes = [0];
  for (const char of input) {
    const value = base58Alphabet.indexOf(char);
    if (value < 0) continue;
    let carry = value;
    for (let i = 0; i < bytes.length; i++) {
      carry += bytes[i] * 58;
      bytes[i] = carry & 0xff;
      carry >>= 8;
    }
    while (carry > 0) {
      bytes.push(carry & 0xff);
      carry >>= 8;
    }
  }
  for (const char of input) {
    if (char === base58Alphabet[0]) bytes.push(0);
    else break;
  }
  return Uint8Array.from(bytes.reverse());
}

export function runHostBridgeSelfTest(name) {
  if (name === 'base58') {
    const input = encoder.encode('hello');
    const encoded = base58Encode(input);
    const decoded = decoder.decode(base58Decode(encoded));
    return {
      name,
      output: `base58=${encoded} decoded=${decoded}`,
      passed: encoded === 'Cn8eVZg' && decoded === 'hello',
    };
  }

  if (name === 'cbor') {
    const json = '{"type":"commit","seq":1}';
    const encoded = encoder.encode(`fixture-cbor:${json}`);
    const decoded = decoder.decode(encoded).slice('fixture-cbor:'.length);
    return {
      name,
      output: `cbor=${encoded.length} decoded=${decoded}`,
      passed: decoded === json,
    };
  }

  return {
    name,
    output: `unknown host bridge self-test: ${name}`,
    passed: false,
  };
}

export function diagnoseUnsupportedApis(source) {
  const rules = [
    { pattern: /\bsqlite3_\w+\b|\bsqlite3\b/, api: 'sqlite3', supportClass: 'unsupported-production', message: 'SQLite APIs require a browser-safe repository shim for tutorials.' },
    { pattern: /\bdispatch_(?:queue|async|sync|after|once|semaphore|source|time|get_|main|global)\w*\b|\bdispatch_queue_t\b/, api: 'dispatch', supportClass: 'unsupported-production', message: 'GCD and libdispatch are production concurrency APIs; tutorial snippets should use synchronous in-memory models.' },
    { pattern: /\bNSFileManager\b|\bNSFileHandle\b|\bdataWithContentsOfFile:|\bwriteToFile:/, api: 'filesystem', supportClass: 'unsupported-production', message: 'Filesystem APIs are outside the browser kernel; use an in-memory blob/file shim.' },
    { pattern: /\bSec(?:Key|Item|Random|AccessControl)\w*\b|\bCommonCrypto\b|\bCC_(?:SHA|HMAC|Cryptor|KeyDerivation)\w*\b|\bEVP_\w+\b|\bOpenSSL\b/, api: 'security-crypto', supportClass: 'unsupported-production', message: 'Keychain, Security, CommonCrypto, and OpenSSL APIs require host bridges or deterministic tutorial fixtures.' },
    { pattern: /\bAVFoundation\b|\bAVAsset\b|\bAVAssetWriter\b|\bCGImage\b|\bCoreGraphics\b|\bCoreMedia\b|\bCVPixelBuffer\b/, api: 'media', supportClass: 'unsupported-production', message: 'Media frameworks are not browser-kernel tutorial APIs; use fixture metadata or generated sample bytes.' },
    { pattern: /\bNSOperationQueue\b|\bNSThread\b|\bNSLock\b/, api: 'threading', supportClass: 'unsupported-production', message: 'Threading primitives are not modeled in the tutorial kernel.' },
  ];

  return rules.filter(rule => rule.pattern.test(source)).map(({ api, supportClass, message }) => ({
    api,
    supportClass,
    message,
  }));
}

export function classifySnippet(source, fallback = {}) {
  const unsupported = diagnoseUnsupportedApis(source);
  if (unsupported.length > 0) {
    return {
      tags: ['unsupported-api', ...unsupported.map(item => item.api)],
      supportClass: 'unsupported-production',
      diagnostics: unsupported,
    };
  }

  const tags = new Set(fallback.tags ?? []);
  if (/@interface|@implementation/.test(source)) tags.add('classes');
  if (/@protocol/.test(source)) tags.add('protocols');
  if (/\^|__block|enumerateObjectsUsingBlock/.test(source)) tags.add('blocks');
  if (/@try|@catch|@throw/.test(source)) tags.add('exceptions');
  if (/NSDictionary|NSArray|NSMutableDictionary|NSMutableArray|NSSet/.test(source)) tags.add('collections');
  if (/NSData/.test(source)) tags.add('data');
  if (/NSURLSession|NSURLRequest|NSURL /.test(source)) tags.add('network-bridge');
  if (/NSJSONSerialization/.test(source)) tags.add('json-bridge');
  if (/sha256|base32|base58|CBOR/i.test(source)) tags.add('host-bridge');
  if (/ATURI|DID|handle|CID|Xrpc|Firehose|Repo|Record|Migration/.test(source)) tags.add('atproto-domain');

  return {
    tags: [...tags],
    supportClass: fallback.supportClass ?? 'direct',
    diagnostics: [],
  };
}

export async function createObjcKernel(wasmPath, options = {}) {
  const wasmBytes = await readFile(wasmPath);
  let instance;
  let exports;
  const streamBuf = [];
  const fetchFixtures = options.fetchFixtures ?? {
    'https://api.example.com/users/alice': { status: 200, body: JSON.stringify({ name: 'Alice', age: 30 }) },
  };

  const wasi = new WASI({ version: 'preview1' });
  const memoryBytes = () => new Uint8Array(instance.exports.memory.buffer);

  function withCString(str, fn) {
    if (str == null) return fn(0);
    const encoded = encoder.encode(`${str}\0`);
    const ptr = exports.objc_kernel_alloc(Math.max(encoded.length, 1));
    memoryBytes().set(encoded, ptr);
    try {
      return fn(ptr);
    } finally {
      exports.objc_kernel_free(ptr);
    }
  }

  function addValueToColl(collId, key, val) {
    withCString(key, keyPtr => {
      if (val === null) {
        withCString('null', valPtr => exports.coll_add_string_val(collId, keyPtr, valPtr));
      } else if (typeof val === 'string') {
        withCString(val, valPtr => exports.coll_add_string_val(collId, keyPtr, valPtr));
      } else if (typeof val === 'number') {
        if (Number.isInteger(val)) exports.coll_add_int_val(collId, keyPtr, val);
        else exports.coll_add_double_val(collId, keyPtr, val);
      } else if (typeof val === 'boolean') {
        exports.coll_add_bool_val(collId, keyPtr, val ? 1 : 0);
      } else if (typeof val === 'object') {
        const childMarker = buildObjcValue(val);
        if (childMarker) exports.coll_add_marker_val(collId, keyPtr, childMarker);
      }
    });
  }

  function buildObjcValue(val) {
    if (!exports) return 0;
    if (val === null) {
      let ptr = 0;
      withCString('NSNull:', p => { ptr = exports.coll_make_marker(p, 0); });
      return ptr;
    }
    if (typeof val === 'string') {
      const encoded = encoder.encode(`${val}\0`);
      const strPtr = exports.string_pool_alloc(encoded.length);
      if (strPtr) memoryBytes().set(encoded, strPtr);
      return strPtr || 0;
    }
    if (typeof val === 'number' || typeof val === 'boolean') return 0;

    const collId = exports.coll_create_new();
    if (Array.isArray(val)) {
      for (const item of val) addValueToColl(collId, null, item);
      let ptr = 0;
      withCString('NSArr:', p => { ptr = exports.coll_make_marker(p, collId); });
      return ptr;
    }

    for (const key of Object.keys(val)) addValueToColl(collId, key, val[key]);
    let ptr = 0;
    withCString('NSDict:', p => { ptr = exports.coll_make_marker(p, collId); });
    return ptr;
  }

  ({ instance } = await WebAssembly.instantiate(wasmBytes, {
    wasi_snapshot_preview1: wasi.wasiImport,
    objc_kernel_host: {
      stream(kind, ptr, len) {
        const name = kind === 2 ? 'stderr' : 'stdout';
        const text = decoder.decode(new Uint8Array(instance.exports.memory.buffer, ptr, len));
        streamBuf.push({ name, text });
      },
      should_interrupt() { return 0; },
      json_parse(ptr, len) {
        try {
          const json = decoder.decode(memoryBytes().subarray(ptr, ptr + len));
          return buildObjcValue(JSON.parse(json));
        } catch {
          return 0;
        }
      },
      json_stringify() { return 0; },
      fetch(taskId, urlPtr, methodPtr, headersJsonPtr, bodyPtr, bodyLen) {
        const url = readCString(instance.exports.memory, urlPtr);
        const fixture = fetchFixtures[url] ?? { status: 404, body: 'Not found' };
        const responseData = encoder.encode(fixture.body ?? '');
        const dataPtr = responseData.length > 0 ? exports.objc_kernel_alloc(responseData.length) : 0;
        if (dataPtr) memoryBytes().set(responseData, dataPtr);
        exports.objc_kernel_on_fetch_complete(taskId, fixture.status ?? 200, dataPtr, responseData.length);
        if (dataPtr) exports.objc_kernel_free(dataPtr);
        return 0;
      },
      sha256(dataPtr, dataLen, outPtr, outCap) {
        const data = memoryBytes().slice(dataPtr, dataPtr + dataLen);
        const hash = crypto.createHash('sha256').update(data).digest();
        return writeBytes(instance.exports.memory, outPtr, outCap, hash);
      },
      random_bytes(outPtr, count) {
        const bytes = crypto.createHash('sha256').update('garazyk-deterministic-random').digest();
        const out = new Uint8Array(instance.exports.memory.buffer, outPtr, count);
        for (let i = 0; i < count; i++) out[i] = bytes[i % bytes.length];
        return count;
      },
      hmac_sha256(keyPtr, keyLen, dataPtr, dataLen, outPtr, outCap) {
        const key = memoryBytes().slice(keyPtr, keyPtr + keyLen);
        const data = memoryBytes().slice(dataPtr, dataPtr + dataLen);
        const mac = crypto.createHmac('sha256', key).update(data).digest();
        return writeBytes(instance.exports.memory, outPtr, outCap, mac);
      },
      base32_encode(dataPtr, dataLen, outPtr, outCap) {
        const encoded = encoder.encode(base32Encode(memoryBytes().slice(dataPtr, dataPtr + dataLen)));
        return writeBytes(instance.exports.memory, outPtr, outCap, encoded);
      },
      base32_decode(strPtr, strLen, outPtr, outCap) {
        const decoded = base32Decode(decoder.decode(memoryBytes().subarray(strPtr, strPtr + strLen)));
        return writeBytes(instance.exports.memory, outPtr, outCap, decoded);
      },
      base58btc_encode(dataPtr, dataLen, outPtr, outCap) {
        const encoded = encoder.encode(base58Encode(memoryBytes().slice(dataPtr, dataPtr + dataLen)));
        return writeBytes(instance.exports.memory, outPtr, outCap, encoded);
      },
      base58btc_decode(strPtr, strLen, outPtr, outCap) {
        const decoded = base58Decode(decoder.decode(memoryBytes().subarray(strPtr, strPtr + strLen)));
        return writeBytes(instance.exports.memory, outPtr, outCap, decoded);
      },
      cbor_encode(jsonPtr, jsonLen, outPtr, outCap) {
        const json = decoder.decode(memoryBytes().subarray(jsonPtr, jsonPtr + jsonLen));
        const encoded = encoder.encode(`fixture-cbor:${json}`);
        return writeBytes(instance.exports.memory, outPtr, outCap, encoded);
      },
      cbor_decode(dataPtr, dataLen, outPtr, outCap) {
        const data = decoder.decode(memoryBytes().subarray(dataPtr, dataPtr + dataLen));
        const json = data.startsWith('fixture-cbor:') ? data.slice('fixture-cbor:'.length) : '{}';
        return writeBytes(instance.exports.memory, outPtr, outCap, encoder.encode(json));
      },
    },
  }));

  wasi.initialize(instance);
  exports = instance.exports;
  if (exports.objc_kernel_init() !== TRANSPORT.OK) {
    throw new Error('objc_kernel_init() failed');
  }

  function allocBytes(value) {
    const encoded = encoder.encode(typeof value === 'string' ? value : JSON.stringify(value));
    const ptr = exports.objc_kernel_alloc(Math.max(encoded.length, 1));
    if (!ptr) throw new Error('WASM allocator returned null');
    new Uint8Array(exports.memory.buffer).set(encoded, ptr);
    return { ptr, len: encoded.length };
  }

  function allocU32() {
    const ptr = exports.objc_kernel_alloc(4);
    if (!ptr) throw new Error('WASM allocator returned null');
    return ptr;
  }

  function readU32(ptr) {
    return new DataView(exports.memory.buffer).getUint32(ptr, true);
  }

  function callJson(exportName, payload) {
    const { ptr: reqPtr, len: reqLen } = allocBytes(payload);
    const outPtrPtr = allocU32();
    const outLenPtr = allocU32();
    try {
      const rc = exports[exportName](reqPtr, reqLen, outPtrPtr, outLenPtr);
      if (rc !== TRANSPORT.OK) {
        const name = Object.keys(TRANSPORT).find(key => TRANSPORT[key] === rc) ?? 'UNKNOWN';
        throw new Error(`Transport error ${rc} (${name}) from ${exportName}`);
      }
      const responsePtr = readU32(outPtrPtr);
      const responseLen = readU32(outLenPtr);
      const response = JSON.parse(decoder.decode(new Uint8Array(exports.memory.buffer, responsePtr, responseLen)));
      exports.objc_kernel_free(responsePtr);
      return response;
    } finally {
      exports.objc_kernel_free(reqPtr);
      exports.objc_kernel_free(outPtrPtr);
      exports.objc_kernel_free(outLenPtr);
    }
  }

  async function drainPendingTasks() {
    if (!exports.objc_kernel_has_pending_tasks) return;
    for (let i = 0; i < 100 && exports.objc_kernel_has_pending_tasks() > 0; i++) {
      await new Promise(resolve => setTimeout(resolve, 5));
    }
  }

  return {
    exports,
    execute(code, cellId = 'cell') {
      streamBuf.length = 0;
      const reply = callJson('objc_kernel_execute_json', { code, cell_id: cellId });
      return { ...reply, streams: streamBuf.splice(0) };
    },
    async executeAsync(code, cellId = 'cell') {
      streamBuf.length = 0;
      const reply = callJson('objc_kernel_execute_json', { code, cell_id: cellId });
      await drainPendingTasks();
      return { ...reply, streams: streamBuf.splice(0) };
    },
  };
}

export function streamText(result) {
  return (result.streams ?? []).map(stream => stream.text).join('');
}
