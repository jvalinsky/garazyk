/**
 * Debug probe: for-loop with break/continue
 * Minimal test to isolate the for-loop crash.
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

// Test 1: Simple for loop (no break/continue) — should PASS
console.log("=== Test 1: Simple for loop (no break/continue) ===");
let r = execute('int sum = 0;\nfor (int i = 1; i <= 5; i++) {\n  sum += i;\n}\nNSLog(@"%d", sum);');
console.log("status:", r.status);
console.log("output:", r.output);
console.log("error:", r.ename, r.evalue);

// Test 2: for loop with break — should PASS
console.log("\n=== Test 2: for loop with break ===");
r = execute(
  "int found = 0;\nfor (int i = 0; i < 10; i++) {\n  if (i == 5) { found = i; break; }\n}",
);
console.log("status:", r.status);
console.log("output:", r.output);
console.log("error:", r.ename, r.evalue);

// Test 3: for loop with continue — should PASS
console.log("\n=== Test 3: for loop with continue ===");
r = execute(
  'int sum = 0;\nfor (int i = 0; i < 10; i++) {\n  if (i % 2 == 0) continue;\n  sum += i;\n}\nNSLog(@"%d", sum);',
);
console.log("status:", r.status);
console.log("output:", r.output);
console.log("error:", r.ename, r.evalue);

// Test 4: do/while loop — should PASS
console.log("\n=== Test 4: do/while loop ===");
r = execute('int i = 0;\ndo {\n  i++;\n} while (i < 3);\nNSLog(@"%d", i);');
console.log("status:", r.status);
console.log("output:", r.output);
console.log("error:", r.ename, r.evalue);

// Test 5: for loop with i = i + 1 (no i++) — smoke test style
console.log("\n=== Test 5: for loop with i = i + 1 ===");
r = execute(
  'int sum = 0;\nfor (int i = 1; i <= 5; i = i + 1) {\n  sum += i;\n}\nNSLog(@"%d", sum);',
);
console.log("status:", r.status);
console.log("output:", r.output);
console.log("error:", r.ename, r.evalue);

// Test 6: for loop with break — smoke test style (i = i + 1)
console.log("\n=== Test 6: for loop with break (i = i + 1) ===");
r = execute(
  "int found = 0;\nfor (int i = 0; i < 10; i = i + 1) {\n  if (i == 5) { found = i; break; }\n}",
);
console.log("status:", r.status);
console.log("output:", r.output);
console.log("error:", r.ename, r.evalue);

// Test 7: for loop with continue — smoke test style (i = i + 1)
console.log("\n=== Test 7: for loop with continue (i = i + 1) ===");
r = execute(
  'int sum = 0;\nfor (int i = 1; i <= 10; i = i + 1) {\n  if (i % 2 == 0) continue;\n  sum += i;\n}\nNSLog(@"%d", sum);',
);
console.log("status:", r.status);
console.log("output:", r.output);
console.log("error:", r.ename, r.evalue);

// Test 8: while loop with break — known to work
console.log("\n=== Test 8: while loop with break ===");
r = execute('int i = 0;\nwhile (1) {\n  if (i >= 3) break;\n  i++;\n}\nNSLog(@"%d", i);');
console.log("status:", r.status);
console.log("output:", r.output);
console.log("error:", r.ename, r.evalue);
