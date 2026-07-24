import fs from "fs";
import { setupWasm } from "./objc-kernel-test-harness.mjs";

const wasmBuffer = fs.readFileSync("result/wasm/kernel.wasm");
let hostStreams = [];

const env = {
  host_log: (ptr, len) => {
    // We could capture logs if needed
  },
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

async function run() {
  const { kernel, instance } = await setupWasm(wasmBuffer, env);
  const code = `@interface IvarTest : NSObject {\n@public int field;\n}\n@end\n@implementation IvarTest\n- (instancetype)init { self = [super init]; field = 42; return self; }\n@end\nIvarTest *t = [IvarTest new];\nNSLog(@"%d", t->field);`;
  
  console.log("Evaluating...");
  kernel.eval(code);
  console.log("Done evaluating!");
}

run();
