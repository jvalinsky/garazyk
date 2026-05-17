/**
 * Debug probe: isKindOfClass: / isMemberOfClass:
 */
import { readFile } from "node:fs/promises";
import { WASI } from "node:wasi";

const wasmPath = process.argv[2] || "result/wasm/kernel.wasm";
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
      const text = decoder.decode(new Uint8Array(instance.exports.memory.buffer, ptr, len));
      hostStreams.push(text);
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
    sha256() {
      return 0;
    },
    random_bytes() {
      return 0;
    },
    hmac_sha256() {
      return 0;
    },
    base32_encode() {
      return 0;
    },
    base32_decode() {
      return 0;
    },
    base58btc_encode() {
      return 0;
    },
    base58btc_decode() {
      return 0;
    },
    cbor_encode() {
      return 0;
    },
    cbor_decode() {
      return 0;
    },
  },
}));
wasi.initialize(instance);
const exports = instance.exports;
exports.objc_kernel_init();

function execute(code) {
  hostStreams.length = 0;
  const req = { code };
  const encoded = encoder.encode(JSON.stringify(req));
  const reqPtr = exports.objc_kernel_alloc(encoded.length);
  new Uint8Array(exports.memory.buffer).set(encoded, reqPtr);
  const outPtrPtr = exports.objc_kernel_alloc(4);
  const outLenPtr = exports.objc_kernel_alloc(4);
  const status = exports.objc_kernel_execute_json(reqPtr, encoded.length, outPtrPtr, outLenPtr);
  if (status !== 0) {
    exports.objc_kernel_free(reqPtr);
    exports.objc_kernel_free(outPtrPtr);
    exports.objc_kernel_free(outLenPtr);
    return { status: "transport_error", code: status, output: "", ename: "", evalue: "" };
  }
  const outPtr = new Uint32Array(exports.memory.buffer, outPtrPtr, 1)[0];
  const outLen = new Uint32Array(exports.memory.buffer, outLenPtr, 1)[0];
  const responseText = decoder.decode(new Uint8Array(exports.memory.buffer, outPtr, outLen));
  let response;
  try {
    response = JSON.parse(responseText);
  } catch {
    response = { status: "parse_error" };
  }
  exports.objc_kernel_free(reqPtr);
  exports.objc_kernel_free(outPtrPtr);
  exports.objc_kernel_free(outLenPtr);
  exports.objc_kernel_free(outPtr);
  const nslog = hostStreams.join("").trim();
  return {
    status: response.status || "unknown",
    output: nslog,
    ename: response.ename || "",
    evalue: response.evalue || "",
    traceback: response.traceback || [],
    raw: responseText,
  };
}

// Test 1: isKindOfClass: with class argument
console.log("=== Test 1: isKindOfClass: with class argument ===");
let r = execute(`@interface Animal : NSObject @end
@implementation Animal @end
@interface Dog : Animal @end
@implementation Dog @end
Dog *d = [Dog new];
NSLog(@"%d", [d isKindOfClass:[Animal class]]);`);
console.log("status:", r.status);
console.log("output:", r.output);
console.log("error:", r.ename, r.evalue);

// Test 2: isMemberOfClass: with class argument
console.log("\n=== Test 2: isMemberOfClass: with class argument ===");
r = execute(`@interface Animal2 : NSObject @end
@implementation Animal2 @end
@interface Dog2 : Animal2 @end
@implementation Dog2 @end
Dog2 *d = [Dog2 new];
NSLog(@"%d", [d isMemberOfClass:[Dog2 class]]);`);
console.log("status:", r.status);
console.log("output:", r.output);
console.log("error:", r.ename, r.evalue);

// Test 3: isKindOfClass: with NSObject
console.log("\n=== Test 3: isKindOfClass: [NSObject class] ===");
r = execute(`@interface Animal3 : NSObject @end
@implementation Animal3 @end
Animal3 *a = [Animal3 new];
NSLog(@"%d", [a isKindOfClass:[NSObject class]]);`);
console.log("status:", r.status);
console.log("output:", r.output);
console.log("error:", r.ename, r.evalue);

// Test 4: isKindOfClass: with NSString
console.log("\n=== Test 4: isKindOfClass: [NSString class] ===");
r = execute(`NSString *s = @"hello";
NSLog(@"%d", [s isKindOfClass:[NSString class]]);`);
console.log("status:", r.status);
console.log("output:", r.output);
console.log("error:", r.ename, r.evalue);
