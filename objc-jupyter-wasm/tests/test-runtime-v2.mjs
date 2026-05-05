import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { WASI } from 'node:wasi';

const wasmPath = process.argv[2];

if (!wasmPath) {
  throw new Error('Usage: node tests/test-runtime-expansion.mjs /path/to/kernel.wasm');
}

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
      const name = kind === 2 ? 'stderr' : 'stdout';
      const text = decoder.decode(new Uint8Array(instance.exports.memory.buffer, ptr, len));
      hostStreams.push({ name, text });
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

function execute(code, expectedStatus = 'ok') {
  const req = { code };
  const encoded = encoder.encode(JSON.stringify(req));
  const reqPtr = exports.objc_kernel_alloc(encoded.length);
  new Uint8Array(exports.memory.buffer).set(encoded, reqPtr);

  const outPtrPtr = exports.objc_kernel_alloc(4);
  const outLenPtr = exports.objc_kernel_alloc(4);

  const status = exports.objc_kernel_execute_json(reqPtr, encoded.length, outPtrPtr, outLenPtr);
  if (status !== 0) {
      console.error('Transport failure:', status);
      console.error('Host streams:', hostStreams);
  }
  assert.equal(status, 0, 'Transport failure');

  const outPtr = new Uint32Array(exports.memory.buffer, outPtrPtr, 1)[0];
  const outLen = new Uint32Array(exports.memory.buffer, outLenPtr, 1)[0];
  const responseText = decoder.decode(new Uint8Array(exports.memory.buffer, outPtr, outLen));
  let response;
  try {
      response = JSON.parse(responseText);
  } catch (e) {
      console.error('Failed to parse response:', responseText);
      console.error('Host streams:', hostStreams);
      throw e;
  }

  exports.objc_kernel_free(reqPtr);
  exports.objc_kernel_free(outPtrPtr);
  exports.objc_kernel_free(outLenPtr);
  exports.objc_kernel_free(outPtr);

  if (response.status !== expectedStatus && expectedStatus !== 'any') {
      console.error('Execution status mismatch:', response);
      console.error('Host streams:', hostStreams);
  }

  return response;
}

function assertLog(pattern, message) {
    if (!hostStreams.some(s => s.text.includes(pattern))) {
        console.error('Assertion failed:', message);
        console.error('Pattern not found:', pattern);
        console.error('Host streams:', hostStreams);
        assert.fail(message);
    }
}

console.log('--- Testing @try/@catch ---');
const tryCatchResult = execute(`
@try {
    @throw @"Boom";
} @catch (id e) {
    NSLog(@"Caught: %@", e);
}
`);
assert.equal(tryCatchResult.status, 'ok');
assertLog('Caught: Boom', 'Exception was not caught');
hostStreams.length = 0;

console.log('--- Testing @protocol and conformsToProtocol: ---');
const protocolResult = execute(`
@protocol MyProtocol
- (void)doSomething;
@end

@interface MyClass : NSObject <MyProtocol>
@end
@implementation MyClass
- (void)doSomething {
}
@end

MyClass *obj = [[MyClass alloc] init];
[obj doSomething];

BOOL conforms = [obj conformsToProtocol:@protocol(MyProtocol)];
NSLog(@"Conforms: %d", conforms);

BOOL conformsStr = [obj conformsToProtocol:@"MyProtocol"];
NSLog(@"ConformsStr: %d", conformsStr);

BOOL classConforms = [MyClass conformsToProtocol:@protocol(MyProtocol)];
NSLog(@"Class Conforms: %d", classConforms);
`);
assert.equal(protocolResult.status, 'ok');
assertLog('Conforms: 1', 'Instance should conform to protocol');
assertLog('ConformsStr: 1', 'Instance should conform to protocol via string');
assertLog('Class Conforms: 1', 'Class should conform to protocol');
hostStreams.length = 0;

console.log('--- Testing @autoreleasepool ---');
const autoreleaseResult = execute(`
@autoreleasepool {
    id s = [@"test" autorelease];
}
NSLog(@"Autoreleasepool finished");
`);
assert.equal(autoreleaseResult.status, 'ok');
assert.ok(hostStreams.some(s => s.text.includes('Autoreleasepool finished')), 'Autoreleasepool should not crash');
hostStreams.length = 0;

console.log('--- Testing @property(readonly) ---');
const readonlyResult = execute(`
@interface MyBox : NSObject
@property (readonly) int val;
@end
@implementation MyBox
@synthesize val = _val;
- (void)setManual:(int)v { _val = v; }
@end

MyBox *box = [[MyBox alloc] init];
[box setManual:42];
NSLog(@"Val: %d", box.val);

// The following should NOT find a setter
[box setVal:100]; 
`);
// Since setVal: is not found, it should log a warning but the status might still be ok if it's just a method not found
assert.equal(readonlyResult.status, 'ok');
assert.ok(hostStreams.some(s => s.text.includes('Val: 42')), 'Readonly property getter failed');
assert.ok(hostStreams.some(s => s.text.includes('does not respond to selector')), 'Readonly setter should not exist');
hostStreams.length = 0;

console.log('--- Testing __block variables ---');
const blockResult = execute(`
__block int counter = 0;
__block NSString *str = @"Start";
void (^blk)(void) = ^{
    counter = counter + 1;
    str = @"End";
};
blk();
NSLog(@"Counter: %d", counter);
NSLog(@"String: %@", str);
`);
assert.equal(blockResult.status, 'ok');
assertLog('Counter: 1', '__block int modification failed');
assertLog('String: End', '__block object modification failed');
hostStreams.length = 0;

console.log('--- Testing custom collection iteration ---');
const enumResult = execute(`
@interface MyList : NSObject
@property (strong) NSArray *items;
@end
@implementation MyList
- (id)objectEnumerator { return [self.items objectEnumerator]; }
@end

MyList *list = [[MyList alloc] init];
list.items = @[@"A", @"B", @"C"];

NSString *result = @"";
for (NSString *s in list) {
    result = [result stringByAppendingString:s];
}
NSLog(@"Enum Result: %@", result);
`);
assert.equal(enumResult.status, 'ok');
assertLog('Enum Result: ABC', 'Custom collection iteration failed');
hostStreams.length = 0;

console.log('--- Testing message forwarding ---');
const forwardResult = execute(`
@interface Proxy : NSObject
@property (strong) id target;
@end
@implementation Proxy
- (void)forwardInvocation:(id)inv {
    NSLog(@"Forwarding: %@", [inv selector]);
    [inv invokeWithTarget:self.target];
}
- (id)methodSignatureForSelector:(SEL)sel {
    return [self.target methodSignatureForSelector:sel];
}
@end

@interface Real : NSObject
@end
@implementation Real
- (void)sayHello { NSLog(@"Hello from Real"); }
@end

Real *real = [[Real alloc] init];
Proxy *proxy = [[Proxy alloc] init];
proxy.target = real;

[proxy sayHello];
`);
assert.equal(forwardResult.status, 'ok');
assertLog('Forwarding: sayHello', 'Message forwarding failed (forwardInvocation: not called)');
assertLog('Hello from Real', 'Message forwarding failed (invokeWithTarget: failed)');
hostStreams.length = 0;

console.log('--- Testing KVC ---');
const kvcResult = execute(`
@interface PropObj : NSObject
@property (nonatomic) int count;
@property (strong) NSString *name;
@end
@implementation PropObj
@synthesize count, name;
@end

PropObj *o = [[PropObj alloc] init];
[o setValue:123 forKey:@"count"];
[o setValue:@"Gemini" forKey:@"name"];

NSLog(@"KVC count: %@", [o valueForKey:@"count"]);
NSLog(@"KVC name: %@", [o valueForKey:@"name"]);
`);
assert.equal(kvcResult.status, 'ok');
assertLog('KVC count: 123', 'KVC valueForKey:count failed');
assertLog('KVC name: Gemini', 'KVC valueForKey:name failed');
hostStreams.length = 0;

console.log('--- Testing uncaught exception ---');
const uncaughtResult = execute(`
@throw @"Fatal Error";
`, 'error');
assert.equal(uncaughtResult.status, 'error');
assert.equal(uncaughtResult.ename, 'ObjCException');
assert.ok(uncaughtResult.evalue.includes('Fatal Error'), 'Error message should contain exception value');
hostStreams.length = 0;

console.log('ALL TESTS PASSED');
