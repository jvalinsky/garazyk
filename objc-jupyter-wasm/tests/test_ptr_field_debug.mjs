import fs from "fs";

let wasmBuffer;
try {
  wasmBuffer = fs.readFileSync("result/wasm/kernel.wasm");
} catch (e) {
  console.error("Failed to read WASM", e);
  process.exit(1);
}

const env = {
  host_log: (ptr, len) => {},
  host_dispatch: () => 0,
  json_stringify: () => 0,
  fetch: () => 0,
  sha256: () => 0,
  random_bytes: () => 0,
  hmac_sha256: () => 0,
  base32_encode: () => 0,
  base32_decode: () => 0,
  base58btc_encode: () => 0,
  base58btc_decode: () => 0,
};

WebAssembly.instantiate(wasmBuffer, { env: {}, objc_kernel_host: env }).then(({ instance }) => {
  const exports = instance.exports;
  
  // init
  exports.objc_kernel_init();

  function execute(code) {
    console.log("Executing:", code);
    const reqLen = Buffer.byteLength(code);
    const reqPtr = exports.objc_kernel_malloc(reqLen + 1);
    const mem = new Uint8Array(exports.memory.buffer);
    mem.set(Buffer.from(code), reqPtr);
    mem[reqPtr + reqLen] = 0;

    const outPtrPtr = exports.objc_kernel_malloc(4);
    const outLenPtr = exports.objc_kernel_malloc(4);

    const success = exports.objc_kernel_eval(reqPtr, outPtrPtr, outLenPtr);
    
    // not reading output for simplicity
    console.log("Done. Success:", success);
  }
  
  execute("@interface IvarTest : NSObject { @public int field; } @end");
  execute("@implementation IvarTest - (instancetype)init { self = [super init]; return self; } @end");
  execute("IvarTest *t = [IvarTest new];");
  execute("t->field;");

}).catch(e => {
  console.error(e);
});
