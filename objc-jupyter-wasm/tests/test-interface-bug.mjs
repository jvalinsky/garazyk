#!/usr/bin/env node
// Minimal test for @interface/@implementation double-execution bug
import { readFile } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { WASI } from 'node:wasi';

const __dirname = dirname(fileURLToPath(import.meta.url));
const kernelPath = resolve(__dirname, '../kernel/kernel.wasm');

const encoder = new TextEncoder();
const decoder = new TextDecoder();

const wasmBytes = await readFile(kernelPath);
let instance;
const streamBuf = [];

const TRANSPORT = { OK: 0 };

const wasi = new WASI({ version: 'preview1' });

({ instance } = await WebAssembly.instantiate(wasmBytes, {
  wasi_snapshot_preview1: wasi.wasiImport,
  objc_kernel_host: {
    stream(kind, ptr, len) {
      const text = decoder.decode(new Uint8Array(instance.exports.memory.buffer, ptr, len));
      streamBuf.push(text);
    },
    should_interrupt() { return 0; },
  },
}));

wasi.initialize(instance);

if (instance.exports.objc_kernel_init() !== TRANSPORT.OK) {
  throw new Error('objc_kernel_init() failed');
}

function execute(code) {
  streamBuf.length = 0;
  const payload = JSON.stringify({ code, cell_id: 'test' });
  const encoded = encoder.encode(payload);
  const ptr = instance.exports.objc_kernel_alloc(encoded.length);
  new Uint8Array(instance.exports.memory.buffer).set(encoded, ptr);
  const outPtrPtr = instance.exports.objc_kernel_alloc(4);
  const outLenPtr = instance.exports.objc_kernel_alloc(4);

  const rc = instance.exports.objc_kernel_execute_json(ptr, encoded.length, outPtrPtr, outLenPtr);
  const mem = new DataView(instance.exports.memory.buffer);
  const rPtr = mem.getUint32(outPtrPtr, true);
  const rLen = mem.getUint32(outLenPtr, true);
  const response = JSON.parse(decoder.decode(new Uint8Array(instance.exports.memory.buffer, rPtr, rLen)));
  instance.exports.objc_kernel_free(rPtr);
  instance.exports.objc_kernel_free(ptr);
  instance.exports.objc_kernel_free(outPtrPtr);
  instance.exports.objc_kernel_free(outLenPtr);

  return { ...response, streams: streamBuf.splice(0) };
}

// Test 1: Simple @interface + @implementation + usage
console.log('=== Test 1: Simple class with method ===');
const r1 = execute(`
@interface T : NSObject
- (int)add:(int)a to:(int)b;
@end

@implementation T
- (int)add:(int)a to:(int)b {
    return a + b;
}
@end

T *t = [[T alloc] init];
int result = [t add:3 to:4];
NSLog(@"3 + 4 = %d", result);
`);
console.log('  Status:', r1.status);
const nslog1 = r1.streams ? r1.streams.join('') : (r1.data?.['text/plain'] || '');
console.log('  NSLog:', nslog1.trim());
if (r1.status === 'error') console.log('  Error:', r1.ename, r1.evalue);

// Test 2: @interface with @property + multi-keyword method
console.log('\n=== Test 2: @interface with @property + multi-keyword method ===');
const r2 = execute(`
@interface InviteCodeStore : NSObject
@property (nonatomic, strong) NSMutableArray *codes;
- (NSString *)generateCode;
- (BOOL)useCode:(NSString *)code;
- (int)remainingCount;
@end

@implementation InviteCodeStore
- (NSString *)generateCode {
    return @"ABC123";
}
- (BOOL)useCode:(NSString *)code {
    return YES;
}
- (int)remainingCount {
    return 5;
}
@end

InviteCodeStore *store = [[InviteCodeStore alloc] init];
NSLog(@"Code: %@", [store generateCode]);
NSLog(@"Remaining: %d", [store remainingCount]);
`);
console.log('  Status:', r2.status);
const nslog2 = r2.streams ? r2.streams.join('') : '';
console.log('  NSLog:', nslog2.trim());
if (r2.status === 'error') console.log('  Error:', r2.ename, r2.evalue);

// Test 3: instancetype return type
console.log('\n=== Test 3: instancetype return type ===');
const r3 = execute(`
@interface Widget : NSObject
- (instancetype)initWithString:(NSString *)s;
@end

@implementation Widget
- (instancetype)initWithString:(NSString *)s {
    return self;
}
@end

Widget *w = [[Widget alloc] initWithString:@"hello"];
NSLog(@"Widget: %@", w);
`);
console.log('  Status:', r3.status);
const nslog3 = r3.streams ? r3.streams.join('') : '';
console.log('  NSLog:', nslog3.trim());
if (r3.status === 'error') console.log('  Error:', r3.ename, r3.evalue);

// Test 4: Multi-parameter method with typed args
console.log('\n=== Test 4: Multi-parameter method with typed args ===');
const r4 = execute(`
@interface Calc : NSObject
- (int)compute:(int)x plus:(int)y;
@end

@implementation Calc
- (int)compute:(int)x plus:(int)y {
    return x * y;
}
@end

Calc *c = [[Calc alloc] init];
int r = [c compute:5 plus:7];
NSLog(@"5 * 7 = %d", r);
`);
console.log('  Status:', r4.status);
const nslog4 = r4.streams ? r4.streams.join('') : '';
console.log('  NSLog:', nslog4.trim());
if (r4.status === 'error') console.log('  Error:', r4.ename, r4.evalue);

// Test 5: NSMutableDictionary property
console.log('\n=== Test 5: NSMutableDictionary property ===');
const r5 = execute(`
@interface DictStore : NSObject
@property (nonatomic, strong) NSMutableDictionary *data;
- (void)setKey:(NSString *)k value:(NSString *)v;
@end

@implementation DictStore
- (void)setKey:(NSString *)k value:(NSString *)v {
}
@end

DictStore *d = [[DictStore alloc] init];
NSLog(@"DictStore: %@", d);
`);
console.log('  Status:', r5.status);
const nslog5 = r5.streams ? r5.streams.join('') : '';
console.log('  NSLog:', nslog5.trim());
if (r5.status === 'error') console.log('  Error:', r5.ename, r5.evalue);

// Test 6: Multi-cell execution (simulates notebook)
console.log('\n=== Test 6: Multi-cell execution ===');
const r6a = execute(`
@interface HandleValidator : NSObject
- (BOOL)isValidHandle:(NSString *)handle;
@end

@implementation HandleValidator
- (BOOL)isValidHandle:(NSString *)handle {
    if (handle == nil) return NO;
    return YES;
}
@end
`);
console.log('  Cell 1 status:', r6a.status);
if (r6a.status === 'error') console.log('  Cell 1 error:', r6a.ename, r6a.evalue);

const r6b = execute(`
@interface InviteCodeStore : NSObject
@property (nonatomic, strong) NSMutableArray *codes;
- (NSString *)generateCode;
- (BOOL)useCode:(NSString *)code;
- (int)remainingCount;
@end

@implementation InviteCodeStore
- (NSString *)generateCode {
    return @"ABC123";
}
- (BOOL)useCode:(NSString *)code {
    return YES;
}
- (int)remainingCount {
    return 5;
}
@end
`);
console.log('  Cell 2 status:', r6b.status);
if (r6b.status === 'error') console.log('  Cell 2 error:', r6b.ename, r6b.evalue);

const r6c = execute(`
InviteCodeStore *store = [[InviteCodeStore alloc] init];
NSLog(@"Code: %@", [store generateCode]);
NSLog(@"Remaining: %d", [store remainingCount]);
`);
console.log('  Cell 3 status:', r6c.status);
const nslog6c = r6c.streams ? r6c.streams.join('') : '';
console.log('  Cell 3 NSLog:', nslog6c.trim());
if (r6c.status === 'error') console.log('  Cell 3 error:', r6c.ename, r6c.evalue);
