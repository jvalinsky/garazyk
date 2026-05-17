import { readFile } from "node:fs/promises";
import { WASI } from "node:wasi";

const wasmPath = process.argv[2];
if (!wasmPath) throw new Error("Usage: node tests/test_category.mjs /path/to/kernel.wasm");

const TRANSPORT_CODE = {
  OK: 0,
  INVALID_ARGUMENT: 1,
  REQUEST_TOO_LARGE: 2,
  RESPONSE_TOO_LARGE: 3,
  OOM: 4,
  INTERNAL_ERROR: 5,
};

const bytes = await readFile(wasmPath);
const wasi = new WASI({ version: "preview1" });
const encoder = new TextEncoder();
const decoder = new TextDecoder();
const hostStreams = [];
let instance;

({ instance } = await WebAssembly.instantiate(bytes, {
  wasi_snapshot_preview1: wasi.wasiImport,
  objc_kernel_host: {
    stream(kind, ptr, len) {
      const name = kind === 2 ? "stderr" : "stdout";
      const text = decoder.decode(new Uint8Array(instance.exports.memory.buffer, ptr, len));
      hostStreams.push({ name, text });
    },
    should_interrupt() {
      return 0;
    },
    json_parse() {
      return 0;
    },
    json_stringify() {
      return 0;
    },
    fetch() {
      return 0;
    },
    /* Crypto host stubs */
    sha256(dataPtr, dataLen, outPtr, outCap) {
      return 0;
    },
    random_bytes(outPtr, count) {
      const bytes = new Uint8Array(instance.exports.memory.buffer, outPtr, count);
      for (let i = 0; i < count; i++) bytes[i] = 0;
      return count;
    },
    hmac_sha256(keyPtr, keyLen, dataPtr, dataLen, outPtr, outCap) {
      return 0;
    },
    /* Encoding host stubs */
    base32_encode(dataPtr, dataLen, outPtr, outCap) {
      return 0;
    },
    base32_decode(strPtr, strLen, outPtr, outCap) {
      return 0;
    },
    base58btc_encode(dataPtr, dataLen, outPtr, outCap) {
      return 0;
    },
    base58btc_decode(strPtr, strLen, outPtr, outCap) {
      return 0;
    },
    /* CBOR host stubs */
    cbor_encode(jsonPtr, jsonLen, outPtr, outCap) {
      return 0;
    },
    cbor_decode(dataPtr, dataLen, outPtr, outCap) {
      return 0;
    },
  },
}));
wasi.initialize(instance);

const exports = instance.exports;
const memory = exports.memory;

for (
  const name of [
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
  ]
) {
  if (!exports[name]) console.log("Missing export:", name);
}

exports.objc_kernel_init();

function allocateBytes(value) {
  const encoded = encoder.encode(typeof value === "string" ? value : JSON.stringify(value));
  const ptr = exports.objc_kernel_alloc(Math.max(encoded.length, 1));
  if (ptr === 0) throw new Error("Allocation failed");
  new Uint8Array(memory.buffer).set(encoded, ptr);
  return { ptr, len: encoded.length };
}

function allocateUint32() {
  const ptr = exports.objc_kernel_alloc(4);
  if (ptr === 0) throw new Error("Allocation failed");
  return ptr;
}

function readUint32(ptr) {
  return new DataView(memory.buffer).getUint32(ptr, true);
}

function readJsonResponse(ptr, len) {
  return JSON.parse(decoder.decode(new Uint8Array(memory.buffer, ptr, len)));
}

function callJson(exportName, payload) {
  const { ptr: requestPtr, len: requestLen } = allocateBytes(payload);
  const outPtrPtr = allocateUint32();
  const outLenPtr = allocateUint32();

  try {
    const transportStatus = exports[exportName](requestPtr, requestLen, outPtrPtr, outLenPtr);
    if (transportStatus !== TRANSPORT_CODE.OK) {
      console.log("Transport error:", transportStatus);
      return null;
    }
    const responsePtr = readUint32(outPtrPtr);
    const responseLen = readUint32(outLenPtr);
    const response = readJsonResponse(responsePtr, responseLen);
    exports.objc_kernel_free(responsePtr);
    return response;
  } finally {
    exports.objc_kernel_free(requestPtr);
    exports.objc_kernel_free(outPtrPtr);
    exports.objc_kernel_free(outLenPtr);
  }
}

function execute(code, cellId = "test-cell") {
  hostStreams.length = 0;
  return callJson("objc_kernel_execute_json", { code, cell_id: cellId });
}

// Test 1: Category on custom class
console.log("Test 1: Category on custom class...");
let r = execute(`
@interface MyClass : NSObject
@end

@implementation MyClass
@end

@interface MyClass (Additions)
- (id)extra;
@end

@implementation MyClass (Additions)
- (id)extra { return @42; }
@end

id result = [[MyClass new] extra];
NSLog(@"Category result: %@", result);
`);
console.log("Test 1:", JSON.stringify({ status: r?.status }));

// Test 2: Category on NSString (Foundation class)
console.log("Test 2: Category on NSString...");
r = execute(`
@interface NSString (TestCat)
- (id)myMethod;
@end

@implementation NSString (TestCat)
- (id)myMethod { return @"works"; }
@end

id result2 = [@"test" myMethod];
NSLog(@"NSString category: %@", result2);
`);
console.log("Test 2:", JSON.stringify({ status: r?.status, error: r?.evalue }));

console.log("Streams:", hostStreams);
