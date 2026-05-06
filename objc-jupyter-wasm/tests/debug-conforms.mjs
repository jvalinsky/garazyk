/**
 * Debug: conformsToProtocol
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
  };
}

// Test 1: conformsToProtocol
console.log('=== Test 1: conformsToProtocol ===');
let r = execute(`@protocol Drawable
- (void)draw;
@end
@interface Shape : NSObject <Drawable>
@end
@implementation Shape
- (void)draw { NSLog(@"drawing"); }
@end
Shape *s = [Shape new];
NSLog(@"%d", [s conformsToProtocol:@protocol(Drawable)]);`);
console.log('status:', r.status);
console.log('output:', r.output);
console.log('error:', r.ename, r.evalue);

// Test 2: Check @protocol() expression value
console.log('\n=== Test 2: @protocol() expression ===');
r = execute(`@protocol Drawable
- (void)draw;
@end
id p = @protocol(Drawable);
NSLog(@"protocol: %@", p);`);
console.log('status:', r.status);
console.log('output:', r.output);
console.log('error:', r.ename, r.evalue);

// Test 3: Check conformance table
console.log('\n=== Test 3: Conformance check ===');
r = execute(`@protocol MyProto
- (void)doStuff;
@end
@interface MyClass : NSObject <MyProto>
@end
@implementation MyClass
- (void)doStuff { NSLog(@"stuff"); }
@end
id obj = [MyClass new];
BOOL b = [obj conformsToProtocol:@protocol(MyProto)];
NSLog(@"conforms: %d", b);`);
console.log('status:', r.status);
console.log('output:', r.output);
console.log('error:', r.ename, r.evalue);
