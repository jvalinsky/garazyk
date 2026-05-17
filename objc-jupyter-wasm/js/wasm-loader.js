// WebAssembly loading and transport v2 marshalling for objc-jupyter-wasm.

const ABI_EXPORTS = [
  "memory",
  "objc_kernel_init",
  "objc_kernel_max_request_bytes",
  "objc_kernel_max_response_bytes",
  "objc_kernel_alloc",
  "objc_kernel_free",
  "objc_kernel_info_json",
  "objc_kernel_execute_json",
  "objc_kernel_complete_json",
  "objc_kernel_inspect_json",
];

const TRANSPORT_CODE = {
  OK: 0,
  INVALID_ARGUMENT: 1,
  REQUEST_TOO_LARGE: 2,
  RESPONSE_TOO_LARGE: 3,
  OOM: 4,
  INTERNAL_ERROR: 5,
};

const DEFAULT_RUNTIME_MANIFEST = {
  kernelWasmUrl: "./kernel/kernel.wasm",
  runtimeVersion: "dev",
  sha256: "",
  maxRequestBytes: 64 * 1024,
  maxResponseBytes: 1024 * 1024,
  softTimeoutMs: 30_000,
  hardTimeoutMs: 35_000,
};

const WASI_ERRNO = {
  SUCCESS: 0,
  BADF: 8,
  NOSYS: 52,
  SPIPE: 70,
};

const WASI_FILETYPE_CHARACTER_DEVICE = 2;
const STREAM_FLUSH_THRESHOLD = 4096;

/* ── Pure JS crypto/encoding helpers for host bridges ─────────── */

/**
 * Pure JavaScript SHA-256 implementation for WASM host bridge.
 * Returns Uint8Array of 32 bytes.
 */
function jsSha256(data) {
  // SHA-256 constants
  const K = new Uint32Array([
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ]);

  const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
  const len = bytes.length;

  // Pre-processing: adding padding bits
  const bitLen = len * 8;
  const paddedLen = Math.ceil((len + 9) / 64) * 64;
  const padded = new Uint8Array(paddedLen);
  padded.set(bytes);
  padded[len] = 0x80;
  const view = new DataView(padded.buffer);
  view.setUint32(paddedLen - 4, bitLen, false);

  // Initialize hash values
  let h0 = 0x6a09e667, h1 = 0xbb67ae85, h2 = 0x3c6ef372, h3 = 0xa54ff53a;
  let h4 = 0x510e527f, h5 = 0x9b05688c, h6 = 0x1f83d9ab, h7 = 0x5be0cd19;

  const rotr = (x, n) => (x >>> n) | (x << (32 - n));
  const ch = (x, y, z) => (x & y) ^ (~x & z);
  const maj = (x, y, z) => (x & y) ^ (x & z) ^ (y & z);
  const ep0 = (x) => rotr(x, 2) ^ rotr(x, 13) ^ rotr(x, 22);
  const ep1 = (x) => rotr(x, 6) ^ rotr(x, 11) ^ rotr(x, 25);
  const sig0 = (x) => rotr(x, 7) ^ rotr(x, 18) ^ (x >>> 3);
  const sig1 = (x) => rotr(x, 17) ^ rotr(x, 19) ^ (x >>> 10);

  // Process each 64-byte chunk
  for (let offset = 0; offset < paddedLen; offset += 64) {
    const w = new Uint32Array(64);
    for (let i = 0; i < 16; i++) {
      w[i] = view.getUint32(offset + i * 4, false);
    }
    for (let i = 16; i < 64; i++) {
      w[i] = (sig1(w[i - 2]) + w[i - 7] + sig0(w[i - 15]) + w[i - 16]) | 0;
    }

    let a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;
    for (let i = 0; i < 64; i++) {
      const t1 = (h + ep1(e) + ch(e, f, g) + K[i] + w[i]) | 0;
      const t2 = (ep0(a) + maj(a, b, c)) | 0;
      h = g;
      g = f;
      f = e;
      e = (d + t1) | 0;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) | 0;
    }
    h0 = (h0 + a) | 0;
    h1 = (h1 + b) | 0;
    h2 = (h2 + c) | 0;
    h3 = (h3 + d) | 0;
    h4 = (h4 + e) | 0;
    h5 = (h5 + f) | 0;
    h6 = (h6 + g) | 0;
    h7 = (h7 + h) | 0;
  }

  const result = new Uint8Array(32);
  const rv = new DataView(result.buffer);
  rv.setUint32(0, h0, false);
  rv.setUint32(4, h1, false);
  rv.setUint32(8, h2, false);
  rv.setUint32(12, h3, false);
  rv.setUint32(16, h4, false);
  rv.setUint32(20, h5, false);
  rv.setUint32(24, h6, false);
  rv.setUint32(28, h7, false);
  return result;
}

/**
 * HMAC-SHA256 using jsSha256.
 */
function jsHmacSha256(key, data) {
  const blockSize = 64;
  let k = key instanceof Uint8Array ? key : new Uint8Array(key);
  if (k.length > blockSize) k = jsSha256(k);
  const paddedKey = new Uint8Array(blockSize);
  paddedKey.set(k);

  const ipad = new Uint8Array(blockSize);
  const opad = new Uint8Array(blockSize);
  for (let i = 0; i < blockSize; i++) {
    ipad[i] = paddedKey[i] ^ 0x36;
    opad[i] = paddedKey[i] ^ 0x5c;
  }

  const innerData = new Uint8Array(blockSize + data.length);
  innerData.set(ipad);
  innerData.set(data, blockSize);
  const innerHash = jsSha256(innerData);

  const outerData = new Uint8Array(blockSize + 32);
  outerData.set(opad);
  outerData.set(innerHash, blockSize);
  return jsSha256(outerData);
}

/**
 * Base32 encode (RFC 4648 lowercase, used for CID multibase 'b').
 */
function base32Encode(data) {
  const alphabet = "abcdefghijklmnopqrstuvwxyz234567";
  const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
  let bits = 0, buffer = 0, result = "";
  for (let i = 0; i < bytes.length; i++) {
    buffer = (buffer << 8) | bytes[i];
    bits += 8;
    while (bits >= 5) {
      result += alphabet[(buffer >>> (bits - 5)) & 0x1f];
      bits -= 5;
    }
  }
  if (bits > 0) {
    result += alphabet[(buffer << (5 - bits)) & 0x1f];
  }
  return result;
}

/**
 * Base32 decode (RFC 4648 lowercase).
 */
function base32Decode(str) {
  const alphabet = "abcdefghijklmnopqrstuvwxyz234567";
  const lookup = {};
  for (let i = 0; i < alphabet.length; i++) lookup[alphabet[i]] = i;
  // Also accept uppercase
  for (let i = 0; i < alphabet.length; i++) lookup[alphabet[i].toUpperCase()] = i;

  let bits = 0, buffer = 0;
  const result = [];
  for (let i = 0; i < str.length; i++) {
    const val = lookup[str[i]];
    if (val === undefined) continue; // skip padding
    buffer = (buffer << 5) | val;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      result.push((buffer >>> bits) & 0xff);
    }
  }
  return new Uint8Array(result);
}

/**
 * Base58btc encode (Bitcoin alphabet).
 */
function base58btcEncode(data) {
  const alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
  const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
  let num = 0n;
  for (let i = 0; i < bytes.length; i++) {
    num = num * 256n + BigInt(bytes[i]);
  }
  let result = "";
  while (num > 0n) {
    result = alphabet[Number(num % 58n)] + result;
    num = num / 58n;
  }
  // Leading zeros
  for (let i = 0; i < bytes.length && bytes[i] === 0; i++) {
    result = "1" + result;
  }
  return result;
}

/**
 * Base58btc decode (Bitcoin alphabet).
 */
function base58btcDecode(str) {
  const alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
  const lookup = {};
  for (let i = 0; i < alphabet.length; i++) lookup[alphabet[i]] = BigInt(i);

  let num = 0n;
  for (let i = 0; i < str.length; i++) {
    const val = lookup[str[i]];
    if (val === undefined) return new Uint8Array(0);
    num = num * 58n + val;
  }
  const result = [];
  while (num > 0n) {
    result.unshift(Number(num % 256n));
    num = num / 256n;
  }
  // Leading '1's = leading zero bytes
  for (let i = 0; i < str.length && str[i] === "1"; i++) {
    result.unshift(0);
  }
  return new Uint8Array(result);
}

/**
 * DAG-CBOR encode (simplified — handles common JSON types).
 * For production, use @ipld/dag-cbor npm package.
 */
function dagCborEncode(obj) {
  const parts = [];
  function encode(value) {
    if (value === null || value === undefined) {
      parts.push(new Uint8Array([0xf6])); // null
    } else if (typeof value === "number") {
      if (Number.isInteger(value) && value >= 0) {
        encodeUint(value);
      } else {
        // Float64
        const buf = new ArrayBuffer(9);
        buf[0] = 0xfb;
        new DataView(buf).setFloat64(1, value);
        parts.push(new Uint8Array(buf));
      }
    } else if (typeof value === "string") {
      const encoded = new TextEncoder().encode(value);
      encodeHead(3, encoded.length);
      parts.push(encoded);
    } else if (value instanceof Uint8Array) {
      encodeHead(2, value.length);
      parts.push(value);
    } else if (Array.isArray(value)) {
      encodeHead(4, value.length);
      value.forEach(encode);
    } else if (typeof value === "object") {
      const keys = Object.keys(value).sort();
      encodeHead(5, keys.length);
      for (const k of keys) {
        encode(k);
        encode(value[k]);
      }
    } else if (typeof value === "boolean") {
      parts.push(new Uint8Array([value ? 0xf5 : 0xf4]));
    }
  }
  function encodeUint(n) {
    if (n < 24) {
      parts.push(new Uint8Array([n]));
    } else if (n < 256) {
      parts.push(new Uint8Array([0x18, n]));
    } else if (n < 65536) {
      const buf = new Uint8Array(3);
      buf[0] = 0x19;
      new DataView(buf.buffer).setUint16(1, n, false);
      parts.push(buf);
    } else if (n < 4294967296) {
      const buf = new Uint8Array(5);
      buf[0] = 0x1a;
      new DataView(buf.buffer).setUint32(1, n, false);
      parts.push(buf);
    } else {
      const buf = new Uint8Array(9);
      buf[0] = 0x1b;
      new DataView(buf.buffer).setBigUint64(1, BigInt(n), false);
      parts.push(buf);
    }
  }
  function encodeHead(major, count) {
    if (count < 24) {
      parts.push(new Uint8Array([(major << 5) | count]));
    } else if (count < 256) {
      parts.push(new Uint8Array([(major << 5) | 24, count]));
    } else if (count < 65536) {
      const buf = new Uint8Array(3);
      buf[0] = (major << 5) | 25;
      new DataView(buf.buffer).setUint16(1, count, false);
      parts.push(buf);
    } else {
      const buf = new Uint8Array(5);
      buf[0] = (major << 5) | 26;
      new DataView(buf.buffer).setUint32(1, count, false);
      parts.push(buf);
    }
  }
  encode(obj);
  // Concatenate parts
  let totalLen = 0;
  for (const p of parts) totalLen += p.length;
  const result = new Uint8Array(totalLen);
  let offset = 0;
  for (const p of parts) {
    result.set(p, offset);
    offset += p.length;
  }
  return result;
}

/**
 * DAG-CBOR decode (simplified — handles common CBOR types).
 */
function dagCborDecode(data) {
  const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
  let offset = 0;
  function decode() {
    if (offset >= bytes.length) throw new Error("Unexpected end of CBOR data");
    const byte = bytes[offset++];
    const major = byte >> 5;
    const minor = byte & 0x1f;
    const count = decodeCount(major, minor);
    switch (major) {
      case 0:
        return count; // unsigned int
      case 1:
        return -1 - count; // negative int
      case 2: { // byte string
        const result = bytes.slice(offset, offset + count);
        offset += count;
        return result;
      }
      case 3: { // text string
        const result = new TextDecoder().decode(bytes.slice(offset, offset + count));
        offset += count;
        return result;
      }
      case 4: { // array
        const result = [];
        for (let i = 0; i < count; i++) result.push(decode());
        return result;
      }
      case 5: { // map
        const result = {};
        for (let i = 0; i < count; i++) {
          const key = decode();
          const value = decode();
          result[key] = value;
        }
        return result;
      }
      case 6: { // tag
        const value = decode();
        // Tag 42 = CID
        if (count === 42 && value instanceof Uint8Array) {
          return { "$link": base58btcEncode(value.slice(1)) }; // Skip 0x00 identity prefix
        }
        return value;
      }
      case 7: { // simple/float
        if (minor === 20) return false;
        if (minor === 21) return true;
        if (minor === 22) return null;
        if (minor === 25) {
          const val = new DataView(bytes.buffer, bytes.byteOffset + offset - 0, 2).getFloat16(
            0,
            false,
          );
          offset += 2;
          return val;
        }
        if (minor === 26) {
          const val = new DataView(bytes.buffer, bytes.byteOffset + offset).getFloat32(0, false);
          offset += 4;
          return val;
        }
        if (minor === 27) {
          const val = new DataView(bytes.buffer, bytes.byteOffset + offset).getFloat64(0, false);
          offset += 8;
          return val;
        }
        return count;
      }
    }
  }
  function decodeCount(major, minor) {
    if (minor < 24) return minor;
    if (minor === 24) return bytes[offset++];
    if (minor === 25) {
      const val = new DataView(bytes.buffer, bytes.byteOffset + offset).getUint16(0, false);
      offset += 2;
      return val;
    }
    if (minor === 26) {
      const val = new DataView(bytes.buffer, bytes.byteOffset + offset).getUint32(0, false);
      offset += 4;
      return val;
    }
    if (minor === 27) {
      const val = new DataView(bytes.buffer, bytes.byteOffset + offset).getBigUint64(0, false);
      offset += 8;
      return Number(val);
    }
    return 0;
  }
  return decode();
}

/* ── End of crypto/encoding helpers ───────────────────────────── */

export class WasiProcExitError extends Error {
  constructor(code) {
    super(`WASI proc_exit(${code})`);
    this.name = "WasiProcExitError";
    this.code = code;
  }
}

class ObjcKernelTransportError extends Error {
  constructor(code, context) {
    super(transportErrorMessage(code, context));
    this.name = "ObjcKernelTransportError";
    this.code = code;
  }
}

export class ObjcWasmKernel {
  static async create(runtimeManifestOrUrl = DEFAULT_RUNTIME_MANIFEST, options = {}) {
    const runtimeManifest = normalizeRuntimeManifest(runtimeManifestOrUrl);
    const response = await fetch(runtimeManifest.kernelWasmUrl);
    if (!response.ok) {
      throw new Error(`Failed to fetch ${runtimeManifest.kernelWasmUrl}: ${response.status}`);
    }

    const host = ObjcWasmKernel._createHostImports(options.onStream || null);
    const wasi = ObjcWasmKernel._createWasiImports(host);
    const importObject = {
      wasi_snapshot_preview1: wasi.imports,
      objc_kernel_host: host.imports,
    };

    let instance;
    if (typeof WebAssembly.instantiateStreaming === "function") {
      /* Streaming compilation: the browser compiles WASM bytes as they
       * arrive over the network, reducing time-to-first-execution.
       * Falls back to buffered compilation if streaming fails (e.g.
       * wrong MIME type from a simple HTTP server, or CORS issues). */
      try {
        const { instance: inst } = await WebAssembly.instantiateStreaming(
          response,
          importObject,
        );
        instance = inst;
      } catch {
        /* Streaming failed — likely a MIME type mismatch (server sent
         * application/octet-stream instead of application/wasm).
         * Fall back to buffered compilation. */
        const fallbackResponse = await fetch(runtimeManifest.kernelWasmUrl);
        const bytes = new Uint8Array(await fallbackResponse.arrayBuffer());
        await verifySha256(runtimeManifest, bytes);
        const { instance: inst } = await WebAssembly.instantiate(bytes, importObject);
        instance = inst;
      }
    } else {
      const bytes = new Uint8Array(await response.arrayBuffer());
      await verifySha256(runtimeManifest, bytes);
      const { instance: inst } = await WebAssembly.instantiate(bytes, importObject);
      instance = inst;
    }

    host.bindMemory(instance.exports.memory);
    host.bindExports(instance.exports);
    wasi.bindMemory(instance.exports.memory);

    if (instance.exports._start) {
      try {
        instance.exports._start();
      } catch (error) {
        if (!(error instanceof WasiProcExitError) || error.code !== 0) {
          throw error;
        }
      }
    }

    return new ObjcWasmKernel(instance, runtimeManifest, host, wasi);
  }

  static _createHostImports(onStream) {
    const encoder = new TextEncoder();
    const decoder = new TextDecoder();
    let memory = null;
    let exports = null;
    let interruptView = null;
    let localInterrupt = false;
    let bufferedStreams = [];
    const pending = {
      stdout: "",
      stderr: "",
    };

    const memoryBytes = () => {
      if (!memory) {
        throw new Error("Objective-C host imports have no memory binding");
      }
      return new Uint8Array(memory.buffer);
    };

    let streamListener = onStream;

    const emit = (name, text, force = false) => {
      if (text === "") {
        if (!force || pending[name] === "") {
          return;
        }
      } else {
        pending[name] += text;
      }

      if (
        !force && !pending[name].includes("\n") && pending[name].length < STREAM_FLUSH_THRESHOLD
      ) {
        return;
      }

      const chunk = pending[name];
      pending[name] = "";
      const stream = { name, text: chunk };
      if (streamListener) {
        streamListener(stream);
      } else {
        bufferedStreams.push(stream);
      }
    };

    function withCString(str, fn) {
      if (str == null) return fn(0);
      const encoded = encoder.encode(str + "\0");
      const ptr = exports.objc_kernel_alloc(Math.max(encoded.length, 1));
      memoryBytes().set(encoded, ptr);
      try {
        return fn(ptr);
      } finally {
        exports.objc_kernel_free(ptr);
      }
    }

    function buildObjcValue(val) {
      if (!exports) return 0;
      if (val === null) {
        let ptr = 0;
        withCString("NSNull:", (p) => {
          ptr = exports.coll_make_marker(p, 0);
        });
        return ptr;
      }
      if (typeof val === "string") {
        const encoded = encoder.encode(val + "\0");
        const strPtr = exports.string_pool_alloc(encoded.length);
        if (strPtr) {
          memoryBytes().set(encoded, strPtr);
          return strPtr;
        }
        return 0;
      }
      if (typeof val === "number") {
        // Return nil for primitive root number.
        // It's handled correctly when inside collections.
        return 0;
      }

      // It's an array or object
      const coll_id = exports.coll_create_new();
      if (Array.isArray(val)) {
        for (let i = 0; i < val.length; i++) {
          addValueToColl(coll_id, null, val[i]);
        }
        let ptr = 0;
        withCString("NSArr:", (p) => {
          ptr = exports.coll_make_marker(p, coll_id);
        });
        return ptr;
      } else if (typeof val === "object") {
        for (const key in val) {
          addValueToColl(coll_id, key, val[key]);
        }
        let ptr = 0;
        withCString("NSDict:", (p) => {
          ptr = exports.coll_make_marker(p, coll_id);
        });
        return ptr;
      }
      return 0;
    }

    function addValueToColl(coll_id, key, val) {
      withCString(key, (keyPtr) => {
        if (val === null) {
          withCString("null", (valPtr) => exports.coll_add_string_val(coll_id, keyPtr, valPtr));
        } else if (typeof val === "string") {
          withCString(val, (valPtr) => exports.coll_add_string_val(coll_id, keyPtr, valPtr));
        } else if (typeof val === "number") {
          if (Number.isInteger(val)) {
            exports.coll_add_int_val(coll_id, keyPtr, val);
          } else {
            exports.coll_add_double_val(coll_id, keyPtr, val);
          }
        } else if (typeof val === "boolean") {
          exports.coll_add_bool_val(coll_id, keyPtr, val ? 1 : 0);
        } else if (typeof val === "object") {
          const childMarker = buildObjcValue(val);
          if (childMarker) {
            exports.coll_add_marker_val(coll_id, keyPtr, childMarker);
          }
        }
      });
    }

    return {
      imports: {
        stream(kind, ptr, len) {
          const name = kind === 2 ? "stderr" : "stdout";
          const bytes = memoryBytes().subarray(ptr, ptr + len);
          emit(name, decoder.decode(bytes));
        },
        should_interrupt() {
          if (interruptView) {
            return Atomics.load(interruptView, 0) === 1 ? 1 : 0;
          }
          return localInterrupt ? 1 : 0;
        },
        json_parse(ptr, len) {
          const bytes = memoryBytes().subarray(ptr, ptr + len);
          const str = decoder.decode(bytes);
          let obj;
          try {
            obj = JSON.parse(str);
          } catch (e) {
            return 0; // return nil
          }
          return buildObjcValue(obj);
        },
        json_stringify(objMarker, outPtr, outLen) {
          // Placeholder for phase A completion
          return 0;
        },
        fetch(taskId, urlPtr, methodPtr, headersJsonPtr, bodyPtr, bodyLen) {
          const readCString = (ptr) => {
            if (!ptr) return "";
            const bytes = memoryBytes();
            let end = ptr;
            while (bytes[end] !== 0) end++;
            return decoder.decode(bytes.subarray(ptr, end));
          };

          const url = readCString(urlPtr);
          const method = readCString(methodPtr);
          const headersJson = readCString(headersJsonPtr);

          let body = null;
          if (bodyPtr && bodyLen > 0) {
            body = new Uint8Array(memoryBytes().buffer, bodyPtr, bodyLen).slice();
          }

          let headers = {};
          if (headersJson) {
            try {
              headers = JSON.parse(headersJson);
            } catch (e) {
              // ignore
            }
          }

          // Actually do the fetch
          // In Node.js testing, we might need a fetch polyfill or Node 18+
          const fetchOptions = {
            method: method || "GET",
            headers: headers,
          };

          if (method !== "GET" && method !== "HEAD" && body) {
            fetchOptions.body = body;
          }

          Promise.resolve().then(async () => {
            let status = 0;
            let responseData = null;
            try {
              const response = await fetch(url, fetchOptions);
              status = response.status;
              const buffer = await response.arrayBuffer();
              responseData = new Uint8Array(buffer);
            } catch (error) {
              status = 0; // Error status
              const errorText = error.message || String(error);
              responseData = encoder.encode(errorText);
            }

            // Allocate memory for response data
            let dataPtr = 0;
            if (responseData && responseData.length > 0) {
              dataPtr = exports.objc_kernel_alloc(responseData.length);
              memoryBytes().set(responseData, dataPtr);
            }

            // Call C callback
            exports.objc_kernel_on_fetch_complete(
              taskId,
              status,
              dataPtr,
              responseData ? responseData.length : 0,
            );

            if (dataPtr) {
              exports.objc_kernel_free(dataPtr);
            }
          }).catch(console.error);

          return 0;
        },

        /* ── Crypto host functions ────────────────────────────────── */

        sha256(dataPtr, dataLen, outPtr, outCap) {
          const data = memoryBytes().subarray(dataPtr, dataPtr + dataLen);
          // Use SubtleCrypto if available (browser), else Node.js crypto
          let hash;
          try {
            if (typeof crypto !== "undefined" && crypto.subtle) {
              // SubtleCrypto is async, so we use a sync fallback
              // For WASM host imports we need sync, so use a pure JS SHA-256
              hash = jsSha256(data);
            } else {
              hash = jsSha256(data);
            }
          } catch (e) {
            return 0;
          }
          if (hash.length > outCap) return 0;
          memoryBytes().set(hash, outPtr);
          return hash.length; // 32 bytes
        },

        random_bytes(outPtr, count) {
          const bytes = new Uint8Array(count);
          if (typeof crypto !== "undefined" && crypto.getRandomValues) {
            crypto.getRandomValues(bytes);
          } else {
            for (let i = 0; i < count; i++) bytes[i] = Math.floor(Math.random() * 256);
          }
          memoryBytes().set(bytes, outPtr);
          return count;
        },

        hmac_sha256(keyPtr, keyLen, dataPtr, dataLen, outPtr, outCap) {
          // Simplified HMAC-SHA256 using pure JS SHA-256
          const key = memoryBytes().subarray(keyPtr, keyPtr + keyLen);
          const data = memoryBytes().subarray(dataPtr, dataPtr + dataLen);
          const hash = jsHmacSha256(key, data);
          if (hash.length > outCap) return 0;
          memoryBytes().set(hash, outPtr);
          return hash.length;
        },

        /* ── Encoding host functions ──────────────────────────────── */

        base32_encode(dataPtr, dataLen, outPtr, outCap) {
          const data = memoryBytes().subarray(dataPtr, dataPtr + dataLen);
          const encoded = base32Encode(data);
          const encodedBytes = encoder.encode(encoded);
          if (encodedBytes.length > outCap) return 0;
          memoryBytes().set(encodedBytes, outPtr);
          return encodedBytes.length;
        },

        base32_decode(strPtr, strLen, outPtr, outCap) {
          const strBytes = memoryBytes().subarray(strPtr, strPtr + strLen);
          const str = decoder.decode(strBytes);
          const decoded = base32Decode(str);
          if (decoded.length > outCap) return 0;
          memoryBytes().set(decoded, outPtr);
          return decoded.length;
        },

        base58btc_encode(dataPtr, dataLen, outPtr, outCap) {
          const data = memoryBytes().subarray(dataPtr, dataPtr + dataLen);
          const encoded = base58btcEncode(data);
          const encodedBytes = encoder.encode(encoded);
          if (encodedBytes.length > outCap) return 0;
          memoryBytes().set(encodedBytes, outPtr);
          return encodedBytes.length;
        },

        base58btc_decode(strPtr, strLen, outPtr, outCap) {
          const strBytes = memoryBytes().subarray(strPtr, strPtr + strLen);
          const str = decoder.decode(strBytes);
          const decoded = base58btcDecode(str);
          if (decoded.length > outCap) return 0;
          memoryBytes().set(decoded, outPtr);
          return decoded.length;
        },

        /* ── CBOR host functions ──────────────────────────────────── */

        cbor_encode(jsonPtr, jsonLen, outPtr, outCap) {
          const jsonBytes = memoryBytes().subarray(jsonPtr, jsonPtr + jsonLen);
          const jsonStr = decoder.decode(jsonBytes);
          let obj;
          try {
            obj = JSON.parse(jsonStr);
          } catch (e) {
            return 0;
          }
          const cborData = dagCborEncode(obj);
          if (cborData.length > outCap) return 0;
          memoryBytes().set(cborData, outPtr);
          return cborData.length;
        },

        cbor_decode(dataPtr, dataLen, outPtr, outCap) {
          const data = memoryBytes().subarray(dataPtr, dataPtr + dataLen);
          let obj;
          try {
            obj = dagCborDecode(data);
          } catch (e) {
            return 0;
          }
          const jsonStr = JSON.stringify(obj);
          const jsonBytes = encoder.encode(jsonStr);
          if (jsonBytes.length > outCap) return 0;
          memoryBytes().set(jsonBytes, outPtr);
          return jsonBytes.length;
        },
      },
      bindMemory(nextMemory) {
        memory = nextMemory;
      },
      bindExports(nextExports) {
        exports = nextExports;
      },
      setStreamListener(nextListener) {
        streamListener = nextListener;
      },
      setInterruptBuffer(sharedBuffer) {
        interruptView = sharedBuffer ? new Int32Array(sharedBuffer) : null;
      },
      beginExecute() {
        pending.stdout = "";
        pending.stderr = "";
        bufferedStreams = [];
        localInterrupt = false;
        if (interruptView) {
          Atomics.store(interruptView, 0, 0);
        }
      },
      requestSoftInterrupt() {
        if (interruptView) {
          Atomics.store(interruptView, 0, 1);
          return true;
        }
        localInterrupt = true;
        return false;
      },
      clearInterrupt() {
        localInterrupt = false;
        if (interruptView) {
          Atomics.store(interruptView, 0, 0);
        }
      },
      drainStreams() {
        emit("stdout", "", true);
        emit("stderr", "", true);
        const streams = bufferedStreams;
        bufferedStreams = [];
        return streams;
      },
      emitText(name, text) {
        emit(name, text);
      },
      flushPending() {
        emit("stdout", "", true);
        emit("stderr", "", true);
      },
    };
  }

  static _createWasiImports(host = null) {
    const decoder = new TextDecoder();
    let memory = null;
    let stdout = "";
    let stderr = "";

    const bytes = () => {
      if (!memory) {
        throw new Error("WASI memory is not bound");
      }
      return new Uint8Array(memory.buffer);
    };

    const view = () => {
      if (!memory) {
        throw new Error("WASI memory is not bound");
      }
      return new DataView(memory.buffer);
    };

    const writeUint32 = (ptr, value) => {
      if (ptr !== 0) {
        view().setUint32(ptr, value >>> 0, true);
      }
    };

    const writeUint64 = (ptr, value) => {
      const data = view();
      data.setBigUint64(ptr, BigInt(value), true);
    };

    const appendStream = (fd, text) => {
      if (host && typeof host.emitText === "function") {
        host.emitText(fd === 2 ? "stderr" : "stdout", text);
        return;
      }
      if (fd === 1) {
        stdout += text;
      } else if (fd === 2) {
        stderr += text;
      }
    };

    return {
      imports: {
        fd_close(fd) {
          return fd >= 0 && fd <= 2 ? WASI_ERRNO.SUCCESS : WASI_ERRNO.BADF;
        },
        fd_seek(fd) {
          return fd >= 0 && fd <= 2 ? WASI_ERRNO.SPIPE : WASI_ERRNO.BADF;
        },
        fd_write(fd, iovs_ptr, iovs_count, nwritten_ptr) {
          if (fd !== 1 && fd !== 2) {
            return WASI_ERRNO.BADF;
          }

          const memoryBytes = bytes();
          const data = view();
          let written = 0;

          for (let i = 0; i < iovs_count; i++) {
            const iovPtr = iovs_ptr + i * 8;
            const ptr = data.getUint32(iovPtr, true);
            const length = data.getUint32(iovPtr + 4, true);
            appendStream(fd, decoder.decode(memoryBytes.subarray(ptr, ptr + length)));
            written += length;
          }

          writeUint32(nwritten_ptr, written);
          return WASI_ERRNO.SUCCESS;
        },
        fd_read(fd, iovs_ptr, iovs_count, nread_ptr) {
          if (fd !== 0) {
            return WASI_ERRNO.BADF;
          }
          writeUint32(nread_ptr, 0);
          return WASI_ERRNO.SUCCESS;
        },
        proc_exit(code) {
          throw new WasiProcExitError(code);
        },
        environ_sizes_get(count_ptr, buf_ptr) {
          writeUint32(count_ptr, 0);
          writeUint32(buf_ptr, 0);
          return WASI_ERRNO.SUCCESS;
        },
        environ_get() {
          return WASI_ERRNO.SUCCESS;
        },
        args_sizes_get(argc_ptr, argv_buf_size_ptr) {
          writeUint32(argc_ptr, 0);
          writeUint32(argv_buf_size_ptr, 0);
          return WASI_ERRNO.SUCCESS;
        },
        args_get() {
          return WASI_ERRNO.SUCCESS;
        },
        fd_fdstat_get(fd, stat_ptr) {
          if (fd < 0 || fd > 2) {
            return WASI_ERRNO.BADF;
          }
          bytes().fill(0, stat_ptr, stat_ptr + 24);
          bytes()[stat_ptr] = WASI_FILETYPE_CHARACTER_DEVICE;
          return WASI_ERRNO.SUCCESS;
        },
        random_get(buf_ptr, buf_len) {
          const cryptoObject = globalThis.crypto;
          if (!cryptoObject || typeof cryptoObject.getRandomValues !== "function") {
            return WASI_ERRNO.NOSYS;
          }
          let offset = 0;
          const target = bytes();
          while (offset < buf_len) {
            const chunkLength = Math.min(65536, buf_len - offset);
            cryptoObject.getRandomValues(
              target.subarray(buf_ptr + offset, buf_ptr + offset + chunkLength),
            );
            offset += chunkLength;
          }
          return WASI_ERRNO.SUCCESS;
        },
        clock_time_get(clock_id, precision, time_ptr) {
          writeUint64(time_ptr, BigInt(Date.now()) * 1000000n);
          return WASI_ERRNO.SUCCESS;
        },
        sched_yield() {
          return WASI_ERRNO.SUCCESS;
        },
        poll_oneoff(in_ptr, out_ptr, nsubscriptions, nevents_ptr) {
          writeUint32(nevents_ptr, 0);
          return WASI_ERRNO.SUCCESS;
        },
        fd_prestat_get() {
          return WASI_ERRNO.BADF;
        },
        fd_prestat_dir_name() {
          return WASI_ERRNO.BADF;
        },
      },
      bindMemory(nextMemory) {
        memory = nextMemory;
      },
      drainStreams() {
        const streams = [];
        if (stdout) {
          streams.push({ name: "stdout", text: stdout });
        }
        if (stderr) {
          streams.push({ name: "stderr", text: stderr });
        }
        stdout = "";
        stderr = "";
        return streams;
      },
    };
  }

  constructor(instance, runtimeManifest, host, wasi) {
    this.instance = instance;
    this.runtimeManifest = runtimeManifest;
    this.exports = instance.exports;
    this.host = host;
    this.wasi = wasi;
    this.encoder = new TextEncoder();
    this.decoder = new TextDecoder();

    for (const name of ABI_EXPORTS) {
      if (!this.exports[name]) {
        throw new Error(`kernel.wasm missing export: ${name}`);
      }
    }

    const status = this.exports.objc_kernel_init();
    if (status !== 0) {
      throw new Error(`objc_kernel_init failed with status ${status}`);
    }
  }

  setInterruptBuffer(sharedBuffer) {
    this.host.setInterruptBuffer(sharedBuffer);
  }

  setStreamListener(listener) {
    this.host.setStreamListener(listener);
  }

  requestSoftInterrupt() {
    return this.host.requestSoftInterrupt();
  }

  clearInterrupt() {
    this.host.clearInterrupt();
  }

  kernelInfo() {
    return this.callJsonWithoutRequest("objc_kernel_info_json");
  }

  async execute(code, cellId) {
    this.host.beginExecute();
    try {
      const reply = this.callJsonWithRequest("objc_kernel_execute_json", {
        code,
        cell_id: cellId || null,
      });

      // Wait for any asynchronous background tasks (like network fetches) to complete
      if (this.exports.objc_kernel_has_pending_tasks) {
        while (this.exports.objc_kernel_has_pending_tasks() > 0) {
          // Yield to event loop so fetch promises can resolve and trigger callbacks
          await new Promise((resolve) => setTimeout(resolve, 10));
        }
      }

      const streams = [...this.host.drainStreams(), ...this.wasi.drainStreams()];
      if (streams.length > 0) {
        reply.streams = streams;
      }
      return reply;
    } finally {
      this.host.clearInterrupt();
    }
  }

  complete(code, cursorPos) {
    return this.callJsonWithRequest("objc_kernel_complete_json", {
      code,
      cursor_pos: cursorPos,
    });
  }

  inspect(code, cursorPos, detailLevel) {
    return this.callJsonWithRequest("objc_kernel_inspect_json", {
      code,
      cursor_pos: cursorPos,
      detail_level: detailLevel,
    });
  }

  callJsonWithoutRequest(exportName) {
    const outPtrPtr = this.allocU32Slot();
    const outLenPtr = this.allocU32Slot();
    try {
      const status = this.exports[exportName](outPtrPtr, outLenPtr);
      if (status !== TRANSPORT_CODE.OK) {
        throw new ObjcKernelTransportError(status, exportName);
      }
      const responsePtr = this.readU32(outPtrPtr);
      const responseLen = this.readU32(outLenPtr);
      try {
        return JSON.parse(this.readUtf8(responsePtr, responseLen));
      } finally {
        this.exports.objc_kernel_free(responsePtr);
      }
    } finally {
      this.exports.objc_kernel_free(outPtrPtr);
      this.exports.objc_kernel_free(outLenPtr);
    }
  }

  callJsonWithRequest(exportName, payload) {
    const requestBytes = this.encoder.encode(JSON.stringify(payload));
    if (requestBytes.length > this.runtimeManifest.maxRequestBytes) {
      throw new ObjcKernelTransportError(TRANSPORT_CODE.REQUEST_TOO_LARGE, exportName);
    }

    const requestPtr = this.allocBytes(requestBytes.length);
    const outPtrPtr = this.allocU32Slot();
    const outLenPtr = this.allocU32Slot();
    try {
      this.writeBytes(requestPtr, requestBytes);
      const status = this.exports[exportName](
        requestPtr,
        requestBytes.length,
        outPtrPtr,
        outLenPtr,
      );
      if (status !== TRANSPORT_CODE.OK) {
        throw new ObjcKernelTransportError(status, exportName);
      }

      const responsePtr = this.readU32(outPtrPtr);
      const responseLen = this.readU32(outLenPtr);
      if (responseLen > this.runtimeManifest.maxResponseBytes) {
        throw new ObjcKernelTransportError(TRANSPORT_CODE.RESPONSE_TOO_LARGE, exportName);
      }

      try {
        return JSON.parse(this.readUtf8(responsePtr, responseLen));
      } finally {
        this.exports.objc_kernel_free(responsePtr);
      }
    } finally {
      this.exports.objc_kernel_free(requestPtr);
      this.exports.objc_kernel_free(outPtrPtr);
      this.exports.objc_kernel_free(outLenPtr);
    }
  }

  allocBytes(length) {
    const ptr = this.exports.objc_kernel_alloc(length === 0 ? 1 : length);
    if (!ptr) {
      throw new ObjcKernelTransportError(TRANSPORT_CODE.OOM, "objc_kernel_alloc");
    }
    return ptr;
  }

  allocU32Slot() {
    const ptr = this.allocBytes(4);
    this.writeU32(ptr, 0);
    return ptr;
  }

  writeBytes(ptr, bytes) {
    new Uint8Array(this.exports.memory.buffer).set(bytes, ptr);
  }

  writeU32(ptr, value) {
    new DataView(this.exports.memory.buffer).setUint32(ptr, value >>> 0, true);
  }

  readU32(ptr) {
    return new DataView(this.exports.memory.buffer).getUint32(ptr, true);
  }

  readUtf8(ptr, length) {
    return this.decoder.decode(new Uint8Array(this.exports.memory.buffer, ptr, length));
  }
}

function normalizeRuntimeManifest(runtimeManifestOrUrl) {
  if (typeof runtimeManifestOrUrl === "string") {
    return {
      ...DEFAULT_RUNTIME_MANIFEST,
      kernelWasmUrl: runtimeManifestOrUrl,
    };
  }

  return {
    ...DEFAULT_RUNTIME_MANIFEST,
    ...runtimeManifestOrUrl,
  };
}

async function verifySha256(runtimeManifest, bytes) {
  if (!runtimeManifest.sha256) {
    const isDev = typeof process !== "undefined" && process.env &&
      process.env.NODE_ENV === "development";
    if (!isDev) {
      throw new Error(
        `SHA-256 verification failed: runtime manifest has no sha256. ` +
          `Set NODE_ENV=development to skip (dev builds only).`,
      );
    }
    if (globalThis.console && typeof globalThis.console.warn === "function") {
      globalThis.console.warn(
        `[dev] Skipping SHA-256 verification for ${runtimeManifest.kernelWasmUrl}`,
      );
    }
    return;
  }

  const digest = await crypto.subtle.digest("SHA-256", bytes);
  const actual = Array.from(new Uint8Array(digest), (value) => value.toString(16).padStart(2, "0"))
    .join("");

  if (actual !== runtimeManifest.sha256) {
    throw new Error(
      `kernel.wasm SHA-256 mismatch: expected ${runtimeManifest.sha256}, got ${actual}`,
    );
  }
}

function transportErrorMessage(code, context) {
  switch (code) {
    case TRANSPORT_CODE.INVALID_ARGUMENT:
      return `${context} failed: invalid transport arguments`;
    case TRANSPORT_CODE.REQUEST_TOO_LARGE:
      return `${context} failed: request exceeded the Objective-C WASM transport limit`;
    case TRANSPORT_CODE.RESPONSE_TOO_LARGE:
      return `${context} failed: response exceeded the Objective-C WASM transport limit`;
    case TRANSPORT_CODE.OOM:
      return `${context} failed: kernel transport ran out of memory`;
    case TRANSPORT_CODE.INTERNAL_ERROR:
      return `${context} failed: kernel transport reported an internal error`;
    default:
      return `${context} failed with unknown transport code ${code}`;
  }
}
