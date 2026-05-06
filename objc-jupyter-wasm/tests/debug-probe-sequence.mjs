/**
 * Debug: exact gap probe code with error output
 */
import { readFile } from 'node:fs/promises';
import { WASI } from 'node:wasi';

const wasmPath = process.argv[2] || 'result/wasm/kernel.wasm';
const bytes = await readFile(wasmPath);
const wasi = new WASI({ version: 'preview1' });
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
    should_interrupt() { return 0; },
    json_parse() { return 0; },
    json_stringify() { return 0; },
    fetch() { return 0; },
    sha256() { return 0; },
    random_bytes() { return 0; },
    hmac_sha256() { return 0; },
    base32_encode() { return 0; },
    base32_decode() { return 0; },
    base58btc_encode() { return 0; },
    base58btc_decode() { return 0; },
    cbor_encode() { return 0; },
    cbor_decode() { return 0; }
  }
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
    return { status: 'transport_error', code: status, output: '', ename: '', evalue: '' };
  }
  const outPtr = new Uint32Array(exports.memory.buffer, outPtrPtr, 1)[0];
  const outLen = new Uint32Array(exports.memory.buffer, outLenPtr, 1)[0];
  const responseText = decoder.decode(new Uint8Array(exports.memory.buffer, outPtr, outLen));
  let response;
  try { response = JSON.parse(responseText); } catch { response = { status: 'parse_error' }; }
  exports.objc_kernel_free(reqPtr);
  exports.objc_kernel_free(outPtrPtr);
  exports.objc_kernel_free(outLenPtr);
  exports.objc_kernel_free(outPtr);
  const nslog = hostStreams.join('').trim();
  return {
    status: response.status || 'unknown',
    output: nslog,
    ename: response.ename || '',
    evalue: response.evalue || '',
    result: response.result || '',
    raw: responseText,
  };
}

// Run the first probe first (to pollute state)
console.log('=== Running first probe (Animal) ===');
let r = execute(`@interface Animal : NSObject\n@property NSString *name;\n@end\n@implementation Animal\n- (NSString *)speak { return @"..."; }\n@end\nAnimal *a = [Animal new];\na.name = @"Cat";\nNSLog(@"%@", a.name);`);
console.log('status:', r.status, 'output:', r.output);

// Now run the inheritance chain probe
console.log('\n=== Running inheritance chain probe ===');
r = execute(`@interface Base : NSObject\n@end\n@implementation Base\n- (int)ident { return 1; }\n@end\n@interface Mid : Base\n@end\n@implementation Mid\n- (int)ident { return 2; }\n@end\n@interface Leaf : Mid\n@end\n@implementation Leaf\n- (int)ident { return 3; }\n@end\nLeaf *l = [Leaf new];\nNSLog(@"%d", [l ident]);`);
console.log('status:', r.status);
console.log('output:', r.output);
console.log('error:', r.ename, r.evalue);
console.log('raw:', r.raw);
