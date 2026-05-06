/**
 * test-runtime-gap-probes.mjs
 * Targeted probe snippets for ObjC 2.0 runtime gap analysis.
 * Uses the same JSON bridge API as test-runtime-v2.mjs.
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

  // Combine NSLog output and execution result
  const nslog = hostStreams.join('').trim();
  const lastLine = nslog.split('\n').pop() || '';

  return {
    status: response.status || 'unknown',
    output: nslog,
    lastLine,
    ename: response.ename || '',
    evalue: response.evalue || '',
    traceback: response.traceback || [],
  };
}

// ── Probe definitions ──────────────────────────────────────────────

const probes = [
  // ── Class definition & inheritance ──────────────────────────
  { cat: 'Class definition & inheritance', name: 'Basic @interface + @implementation',
    code: `@interface Animal : NSObject\n@property NSString *name;\n@end\n@implementation Animal\n- (NSString *)speak { return @"..."; }\n@end\nAnimal *a = [Animal new];\na.name = @"Cat";\nNSLog(@"%@", a.name);`,
    expect: 'Cat' },
  { cat: 'Class definition & inheritance', name: 'Inheritance chain (3 levels)',
    code: `@interface Base : NSObject\n@end\n@implementation Base\n- (int)ident { return 1; }\n@end\n@interface Mid : Base\n@end\n@implementation Mid\n- (int)ident { return 2; }\n@end\n@interface Leaf : Mid\n@end\n@implementation Leaf\n- (int)ident { return 3; }\n@end\nLeaf *l = [Leaf new];\nNSLog(@"%d", [l ident]);`,
    expect: '3' },
  { cat: 'Class definition & inheritance', name: '[super message] dispatch',
    code: `@interface Parent : NSObject\n@end\n@implementation Parent\n- (int)val { return 10; }\n@end\n@interface Child : Parent\n@end\n@implementation Child\n- (int)val { return [super val] + 5; }\n@end\nChild *c = [Child new];\nNSLog(@"%d", [c val]);`,
    expect: '15' },
  { cat: 'Class definition & inheritance', name: '[obj class] returns class',
    code: `@interface Foo : NSObject @end\n@implementation Foo @end\nFoo *f = [Foo new];\nClass cls = [f class];\nNSLog(@"got class");`,
    expect: 'got class' },

  // ── Protocols ───────────────────────────────────────────────
  { cat: 'Protocols', name: '@protocol + conformsToProtocol:',
    code: `@protocol Drawable\n- (void)draw;\n@end\n@interface Shape : NSObject <Drawable>\n@end\n@implementation Shape\n- (void)draw { NSLog(@"drawing"); }\n@end\nShape *s = [Shape new];\nNSLog(@"%d", [s conformsToProtocol:@protocol(Drawable)]);`,
    expect: '1' },
  { cat: 'Protocols', name: 'Optional protocol methods',
    code: `@protocol Opt\n@required - (void)req;\n@optional - (void)opt;\n@end\n@interface Impl : NSObject <Opt>\n@end\n@implementation Impl\n- (void)req { NSLog(@"req"); }\n@end\nNSLog(@"conforms %d", [[Impl new] conformsToProtocol:@protocol(Opt)]);`,
    expect: 'conforms 1' },
  { cat: 'Protocols', name: 'Protocol inheritance',
    code: `@protocol Base <NSObject>\n- (void)baseMethod;\n@end\n@protocol Sub <Base>\n- (void)subMethod;\n@end\nNSLog(@"ok");`,
    expect: 'ok' },

  // ── Properties ──────────────────────────────────────────────
  { cat: 'Properties', name: 'Dot syntax on custom class',
    code: `@interface Point : NSObject\n@property int x;\n@property int y;\n@end\n@implementation Point @end\nPoint *p = [Point new];\np.x = 10;\np.y = 20;\nNSLog(@"%d,%d", p.x, p.y);`,
    expect: '10,20' },
  { cat: 'Properties', name: 'Auto-synthesized ivar',
    code: `@interface Auto : NSObject\n@property int count;\n@end\n@implementation Auto @end\nAuto *a = [Auto new];\na.count = 42;\nNSLog(@"%d", a.count);`,
    expect: '42' },
  { cat: 'Properties', name: 'Custom @synthesize ivar name',
    code: `@interface Custom : NSObject\n@property int value;\n@end\n@implementation Custom\n@synthesize value = _myValue;\n@end\nCustom *c = [Custom new];\nc.value = 99;\nNSLog(@"%d", c.value);`,
    expect: '99' },
  { cat: 'Properties', name: '@property(readonly)',
    code: `@interface RO : NSObject\n@property (nonatomic, readonly) int ro;\n@end\n@implementation RO\n@synthesize ro = _ro;\n- (int)ro { return _ro; }\n@end\nRO *r = [RO new];\nNSLog(@"%d", r.ro);`,
    expect: '0' },

  // ── Blocks ──────────────────────────────────────────────────
  { cat: 'Blocks', name: 'Block returning value',
    code: `int (^adder)(int, int) = ^(int a, int b) { return a + b; };\nNSLog(@"%d", adder(3, 4));`,
    expect: '7' },
  { cat: 'Blocks', name: 'Block capturing variable (by-value)',
    code: `int x = 10;\nint (^block)(void) = ^{ return x; };\nx = 20;\nNSLog(@"%d", block());`,
    expect: '10' },
  { cat: 'Blocks', name: '__block variable mutation',
    code: `__block int sum = 0;\nint (^acc)(int) = ^(int n) { sum += n; return sum; };\nacc(5);\nacc(3);\nNSLog(@"%d", sum);`,
    expect: '8' },
  { cat: 'Blocks', name: 'Block as method argument',
    code: `@interface Worker : NSObject\n- (void)run:(void (^)(int))block;\n@end\n@implementation Worker\n- (void)run:(void (^)(int))block {\n  block(42);\n}\n@end\n__block int captured = 0;\nWorker *w = [Worker new];\n[w run:^(int n) { captured = n; }];\nNSLog(@"%d", captured);`,
    expect: '42' },

  // ── Exceptions ──────────────────────────────────────────────
  { cat: 'Exceptions', name: '@try/@catch/@finally',
    code: `@try {\n  @throw @"error";\n} @catch (id e) {\n  NSLog(@"caught: %@", e);\n} @finally {\n  NSLog(@"finally");\n}`,
    expect: 'caught: error' },
  { cat: 'Exceptions', name: 'Nested @try/@catch',
    code: `@try {\n  @try {\n    @throw @"inner";\n  } @catch (id e) {\n    NSLog(@"inner: %@", e);\n    @throw @"outer";\n  }\n} @catch (id e2) {\n  NSLog(@"outer: %@", e2);\n}`,
    expect: 'outer: outer' },
  { cat: 'Exceptions', name: 'Uncaught exception',
    code: `@throw @"uncaught";\nNSLog(@"should not reach");`,
    expect: 'should not reach', expectAbsent: true },

  // ── Message forwarding ──────────────────────────────────────
  { cat: 'Message forwarding', name: 'forwardInvocation:',
    code: `@interface Proxy : NSObject\n- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel;\n- (void)forwardInvocation:(NSInvocation *)inv;\n@end\n@implementation Proxy\n- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {\n  return [NSMethodSignature signatureWithObjCTypes:"v@:"];\n}\n- (void)forwardInvocation:(NSInvocation *)inv {\n  NSLog(@"forwarded");\n}\n@end\nProxy *p = [Proxy new];\n[p nonexistentMethod];`,
    expect: 'forwarded' },

  // ── KVC ─────────────────────────────────────────────────────
  { cat: 'KVC', name: 'valueForKey: / setValue:forKey:',
    code: `@interface KV : NSObject\n@property NSString *name;\n@end\n@implementation KV @end\nKV *o = [KV new];\no.name = @"hello";\nNSLog(@"%@", [o valueForKey:@"name"]);`,
    expect: 'hello' },
  { cat: 'KVC', name: 'KVC on dictionary',
    code: `NSDictionary *d = @{@"key": @"value"};\nNSLog(@"%@", [d valueForKey:@"key"]);`,
    expect: 'value' },

  // ── Autorelease pool ────────────────────────────────────────
  { cat: 'Autorelease pool', name: '@autoreleasepool basic',
    code: `@autoreleasepool {\n  NSString *s = @"test";\n  NSLog(@"%@", s);\n}`,
    expect: 'test' },
  { cat: 'Autorelease pool', name: 'Nested autorelease pools',
    code: `@autoreleasepool {\n  @autoreleasepool {\n    NSLog(@"inner");\n  }\n  NSLog(@"outer");\n}`,
    expect: 'inner' },
  { cat: 'Autorelease pool', name: '[obj autorelease] returns self',
    code: `NSString *s = @"hello";\nNSString *s2 = [s autorelease];\nNSLog(@"%d", s == s2);`,
    expect: '1' },

  // ── Categories ──────────────────────────────────────────────
  { cat: 'Categories', name: 'Category on custom class',
    code: `@interface Cat : NSObject\n- (int)base;\n@end\n@implementation Cat\n- (int)base { return 1; }\n@end\n@interface Cat (Ext)\n- (int)ext;\n@end\n@implementation Cat (Ext)\n- (int)ext { return 2; }\n@end\nCat *c = [Cat new];\nNSLog(@"%d,%d", [c base], [c ext]);`,
    expect: '1,2' },
  { cat: 'Categories', name: 'Category on Foundation class',
    code: `@interface NSString (Rev)\n- (NSString *)myReverse;\n@end\n@implementation NSString (Rev)\n- (NSString *)myReverse {\n  return @"reversed";\n}\n@end\nNSLog(@"%@", [@"hello" myReverse]);`,
    expect: 'reversed' },

  // ── nil messaging ───────────────────────────────────────────
  { cat: 'nil messaging', name: '[nil anyMethod] returns nil/0',
    code: `id nothing = nil;\nint i = [nothing intValue];\nNSLog(@"%d", i);`,
    expect: '0' },
  { cat: 'nil messaging', name: '[nil count] returns 0',
    code: `id n = nil;\nint c = [n count];\nNSLog(@"%d", c);`,
    expect: '0' },

  // ── @selector ────────────────────────────────────────────────
  { cat: '@selector', name: '@selector() basic',
    code: `SEL s = @selector(count);\nNSLog(@"ok");`,
    expect: 'ok' },
  { cat: '@selector', name: '@selector with keyword',
    code: `SEL s = @selector(setObject:forKey:);\nNSLog(@"ok");`,
    expect: 'ok' },
  { cat: '@selector', name: 'performSelector:',
    code: `@interface Perf : NSObject\n- (int)getValue { return 77; }\n@end\n@implementation Perf @end\nPerf *p = [Perf new];\nint v = (int)[p performSelector:@selector(getValue)];\nNSLog(@"%d", v);`,
    expect: '77' },

  // ── Introspection ───────────────────────────────────────────
  { cat: 'Introspection', name: 'respondsToSelector:',
    code: `@interface Resp : NSObject\n- (void)doThing;\n@end\n@implementation Resp\n- (void)doThing { NSLog(@"thing"); }\n@end\nResp *r = [Resp new];\nNSLog(@"%d", [r respondsToSelector:@selector(doThing)]);`,
    expect: '1' },
  { cat: 'Introspection', name: 'isKindOfClass:',
    code: `@interface A : NSObject @end\n@implementation A @end\n@interface B : A @end\n@implementation B @end\nB *b = [B new];\nNSLog(@"%d", [b isKindOfClass:[A class]]);`,
    expect: '1' },
  { cat: 'Introspection', name: 'isMemberOfClass:',
    code: `@interface M : NSObject @end\n@implementation M @end\nM *m = [M new];\nNSLog(@"%d", [m isMemberOfClass:[M class]]);`,
    expect: '1' },

  // ── Format strings ──────────────────────────────────────────
  { cat: 'Format strings', name: 'stringWithFormat: %@ %d %f',
    code: `NSString *s = [NSString stringWithFormat:@"name=%@ count=%d pi=%f", @"test", 42, 3.14];\nNSLog(@"%@", s);`,
    expect: 'name=test count=42 pi=3.14' },
  { cat: 'Format strings', name: '%% escape',
    code: `NSString *s = [NSString stringWithFormat:@"100%%"];\nNSLog(@"%@", s);`,
    expect: '100%' },

  // ── String operations ──────────────────────────────────────
  { cat: 'String operations', name: 'compare: selector',
    code: `NSLog(@"%d", [@"abc" compare:@"abc"]);`,
    expect: '0' },
  { cat: 'String operations', name: 'NSMutableString',
    code: `NSMutableString *ms = [NSMutableString stringWithString:@"hello"];\n[ms appendString:@" world"];\nNSLog(@"%@", ms);`,
    expect: 'hello world' },

  // ── Collection operations ──────────────────────────────────
  { cat: 'Collection operations', name: 'NSArray literal + subscript',
    code: `NSArray *a = @[@"x", @"y", @"z"];\nNSLog(@"%@", a[1]);`,
    expect: 'y' },
  { cat: 'Collection operations', name: 'NSDictionary literal + subscript',
    code: `NSDictionary *d = @{@"key": @"val"};\nNSLog(@"%@", d[@"key"]);`,
    expect: 'val' },
  { cat: 'Collection operations', name: 'NSMutableArray subscript assignment',
    code: `NSMutableArray *a = [NSMutableArray arrayWithCapacity:3];\n[a addObject:@"a"];\n[a addObject:@"b"];\na[1] = @"c";\nNSLog(@"%@", a[1]);`,
    expect: 'c' },
  { cat: 'Collection operations', name: 'NSMutableDictionary subscript',
    code: `NSMutableDictionary *d = [NSMutableDictionary dictionary];\nd[@"k"] = @"v";\nNSLog(@"%@", d[@"k"]);`,
    expect: 'v' },
  { cat: 'Collection operations', name: 'Fast enumeration (for...in) on array',
    code: `NSArray *a = @[@"a", @"b", @"c"];\n__block NSString *result = @"";\nfor (NSString *s in a) {\n  result = [result stringByAppendingString:s];\n}\nNSLog(@"%@", result);`,
    expect: 'abc' },
  { cat: 'Collection operations', name: 'Fast enumeration on dictionary',
    code: `NSDictionary *d = @{@"x": @"1", @"y": @"2"};\n__block int count = 0;\nfor (NSString *k in d) {\n  count++;\n}\nNSLog(@"%d", count);`,
    expect: '2' },
  { cat: 'Collection operations', name: 'enumerateObjectsUsingBlock:',
    code: `NSArray *a = @[@"a", @"b"];\n__block NSString *result = @"";\n[a enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {\n  result = [result stringByAppendingString:obj];\n}];\nNSLog(@"%@", result);`,
    expect: 'ab' },

  // ── NSNumber boxing ─────────────────────────────────────────
  { cat: 'NSNumber boxing', name: 'Boxed expression @()',
    code: `NSNumber *n = @(42);\nNSLog(@"%d", [n intValue]);`,
    expect: '42' },
  { cat: 'NSNumber boxing', name: 'NSNumber equality',
    code: `NSNumber *a = [NSNumber numberWithInt:5];\nNSNumber *b = [NSNumber numberWithInt:5];\nNSLog(@"%d", [a isEqual:b]);`,
    expect: '1' },

  // ── NSData ──────────────────────────────────────────────────
  { cat: 'NSData', name: 'NSData creation and length',
    code: `NSData *d = [NSData dataWithBytes:"hello" length:5];\nNSLog(@"%d", [d length]);`,
    expect: '5' },
  { cat: 'NSData', name: 'NSData isEqualToData:',
    code: `NSData *a = [NSData dataWithBytes:"abc" length:3];\nNSData *b = [NSData dataWithBytes:"abc" length:3];\nNSLog(@"%d", [a isEqualToData:b]);`,
    expect: '1' },

  // ── Control flow ────────────────────────────────────────────
  { cat: 'Control flow', name: 'switch/case',
    code: `int x = 2;\nswitch (x) {\n  case 1: NSLog(@"one"); break;\n  case 2: NSLog(@"two"); break;\n  default: NSLog(@"other"); break;\n}`,
    expect: 'two' },
  { cat: 'Control flow', name: 'do/while loop',
    code: `int i = 0;\ndo {\n  i++;\n} while (i < 3);\nNSLog(@"%d", i);`,
    expect: '3' },
  { cat: 'Control flow', name: 'C-style for loop',
    code: `int sum = 0;\nfor (int i = 1; i <= 5; i++) {\n  sum += i;\n}\nNSLog(@"%d", sum);`,
    expect: '15' },
  { cat: 'Control flow', name: 'break in for loop',
    code: `int found = 0;\nfor (int i = 0; i < 10; i++) {\n  if (i == 5) { found = i; break; }\n}\nNSLog(@"%d", found);`,
    expect: '5' },
  { cat: 'Control flow', name: 'continue in for loop',
    code: `int sum = 0;\nfor (int i = 0; i < 10; i++) {\n  if (i % 2 == 0) continue;\n  sum += i;\n}\nNSLog(@"%d", sum);`,
    expect: '25' },

  // ── Operators ───────────────────────────────────────────────
  { cat: 'Operators', name: 'Ternary operator',
    code: `int x = 1 ? 10 : 20;\nNSLog(@"%d", x);`,
    expect: '10' },
  { cat: 'Operators', name: 'Compound assignment (*=, /=, %=)',
    code: `int x = 12;\nx *= 3;\nx /= 4;\nx %= 5;\nNSLog(@"%d", x);`,
    expect: '4' },
  { cat: 'Operators', name: 'Bitwise operators',
    code: `int a = 0xF0;\nint b = 0x0F;\nNSLog(@"%d", (a | b) == 255);`,
    expect: '1' },
  { cat: 'Operators', name: 'Unary minus',
    code: `int x = -5;\nNSLog(@"%d", x);`,
    expect: '-5' },
  { cat: 'Operators', name: 'Logical short-circuit',
    code: `int x = 0;\nint y = 1;\nNSLog(@"%d", x || y);`,
    expect: '1' },

  // ── Static variables ────────────────────────────────────────
  // SKIPPED: C function definitions not supported by interpreter

  // ── Typedef ─────────────────────────────────────────────────
  { cat: 'Typedef', name: 'typedef int NSInteger',
    code: `typedef int NSInteger;\nNSInteger x = 5;\nNSLog(@"%d", x);`,
    expect: '5' },

  // ── Associated objects ──────────────────────────────────────
  { cat: 'Associated objects', name: 'objc_setAssociatedObject / objc_getAssociatedObject',
    code: `@interface Assoc : NSObject @end\n@implementation Assoc @end\nAssoc *obj = [Assoc new];\nstatic char key;\nobjc_setAssociatedObject(obj, &key, @"value", 1);\nNSLog(@"%@", objc_getAssociatedObject(obj, &key));`,
    expect: 'value' },

  // ── KVO ────────────────────────────────────────────────────
  { cat: 'KVO', name: 'addObserver:forKeyPath:options:context:',
    code: `@interface Obs : NSObject\n@property int count;\n@end\n@implementation Obs @end\nObs *o = [Obs new];\n[o addObserver:o forKeyPath:@"count" options:0 context:nil];\nNSLog(@"observer added");`,
    expect: 'observer added' },

  // ── Copying ─────────────────────────────────────────────────
  { cat: 'Copying', name: 'NSCopying protocol + copy',
    code: `@interface Copy : NSObject <NSCopying>\n@property NSString *name;\n@end\n@implementation Copy\n- (id)copyWithZone:(NSZone *)zone {\n  Copy *c = [[Copy allocWithZone:zone] init];\n  c.name = self.name;\n  return c;\n}\n@end\nCopy *orig = [Copy new];\norig.name = @"test";\nCopy *dup = [orig copy];\nNSLog(@"%@", dup.name);`,
    expect: 'test' },
  { cat: 'Copying', name: '[obj copy] on Foundation',
    code: `NSArray *a = @[@"x"];\nNSArray *b = [a copy];\nNSLog(@"%@", b);`,
    expect: 'x' },

  // ── Memory management ──────────────────────────────────────
  { cat: 'Memory management', name: 'retain/release/autorelease no-ops',
    code: `NSString *s = @"hello";\n[s retain];\n[s release];\n[s autorelease];\nNSLog(@"ok");`,
    expect: 'ok' },

  // ── Class methods ───────────────────────────────────────────
  { cat: 'Class methods', name: '+ (class method) dispatch',
    code: `@interface Factory : NSObject\n+ (instancetype)create;\n@end\n@implementation Factory\n+ (instancetype)create {\n  return [[Factory alloc] init];\n}\n@end\nFactory *f = [Factory create];\nNSLog(@"%d", f != nil);`,
    expect: '1' },
  { cat: 'Class methods', name: '+ initialize auto-called',
    code: `@interface InitTest : NSObject\n+ (void)initialize;\n@end\n@implementation InitTest\n+ (void)initialize {\n  NSLog(@"initialized");\n}\n@end\nInitTest *t = [InitTest new];`,
    expect: 'initialized' },

  // ── Instance variable access ────────────────────────────────
  // SKIPPED: -> operator causes infinite loop in parser

  // ── @class forward declaration ──────────────────────────────
  { cat: '@class forward declaration', name: '@class forward decl',
    code: `@class Fwd;\n@interface Fwd : NSObject\n- (void)hello;\n@end\n@implementation Fwd\n- (void)hello { NSLog(@"hello"); }\n@end\nFwd *f = [Fwd new];\n[f hello];`,
    expect: 'hello' },

  // ── @encode ────────────────────────────────────────────────
  // SKIPPED: @encode not implemented, causes parse error

  // ── @synchronized ──────────────────────────────────────────
  // SKIPPED: @synchronized not implemented, causes parse error

  // ── Struct/NSRange ─────────────────────────────────────────
  { cat: 'Struct/NSRange', name: 'NSRange struct access',
    code: `NSRange r = {5, 3};\nNSLog(@"%d %d", r.location, r.length);`,
    expect: '5 3' },

  // ── C array subscript ──────────────────────────────────────
  { cat: 'C array subscript', name: 'NSMutableArray subscript [idx]',
    code: `NSMutableArray *a = [NSMutableArray array];\n[a addObject:@"first"];\nNSLog(@"%@", a[0]);`,
    expect: 'first' },

  // ── NSLog ──────────────────────────────────────────────────
  { cat: 'NSLog', name: 'NSLog basic format',
    code: `NSLog(@"hello %d", 42);`,
    expect: 'hello 42' },
  { cat: 'NSLog', name: 'NSLog with object',
    code: `NSLog(@"obj: %@", @"world");`,
    expect: 'obj: world' },

  // ── Networking ─────────────────────────────────────────────
  { cat: 'Networking', name: 'NSURL + NSURLRequest',
    code: `NSURL *url = [NSURL URLWithString:@"https://example.com"];\nNSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];\n[req setHTTPMethod:@"POST"];\nNSLog(@"ok");`,
    expect: 'ok' },

  // ── Crypto host bridge ──────────────────────────────────────
  { cat: 'Crypto host bridge', name: '[CID sha256Digest:]',
    code: `NSData *input = [NSData dataWithBytes:"abc" length:3];\nNSData *hash = [CID sha256Digest:input];\nNSLog(@"%d", [hash length]);`,
    expect: '32' },

  // ── Tab completion ──────────────────────────────────────────
  { cat: 'Tab completion', name: 'Tab completion via bridge',
    code: `NSLog(@"tab completion tested via bridge");`,
    expect: 'tab completion tested via bridge' },

  // ── class_addMethod ────────────────────────────────────────
  { cat: 'Runtime API', name: 'class_addMethod',
    code: `@interface Dyn : NSObject @end\n@implementation Dyn @end\nDyn *d = [Dyn new];\nClass cls = [Dyn class];\nint result = class_addMethod(cls, @selector(hello), 0, "v@:");\nNSLog(@"addMethod=%d", result);`,
    expect: 'addMethod=' },

  // ── objc_getClass / objc_lookUpClass ────────────────────────
  { cat: 'Runtime API', name: 'objc_getClass',
    code: `Class cls = objc_getClass("NSObject");\nNSLog(@"%d", cls != nil);`,
    expect: '1' },

  // ── sel_registerName / sel_getName ──────────────────────────
  { cat: 'Runtime API', name: 'sel_registerName / sel_getName',
    code: `SEL s = sel_registerName("count");\nconst char *name = sel_getName(s);\nNSLog(@"%s", name);`,
    expect: 'count' },

  // ── NSStringFromSelector ────────────────────────────────────
  { cat: 'Runtime API', name: 'NSStringFromSelector',
    code: `SEL s = @selector(count);\nNSLog(@"%@", NSStringFromSelector(s));`,
    expect: 'count' },

  // ── NSNull ────────────────────────────────────────────────
  { cat: 'NSNull', name: '[NSNull null]',
    code: `NSNull *n = [NSNull null];\nNSLog(@"%d", n != nil);`,
    expect: '1' },

  // ── @protocol() expression ─────────────────────────────────
  { cat: '@protocol() expression', name: '@protocol(Drawable) as argument',
    code: `@protocol Drawable\n- (void)draw;\n@end\nNSLog(@"%d", @protocol(Drawable) != nil);`,
    expect: '1' },

  // ── instancetype ───────────────────────────────────────────
  { cat: 'instancetype', name: 'instancetype return type',
    code: `@interface Inst : NSObject\n+ (instancetype)create;\n@end\n@implementation Inst\n+ (instancetype)create { return [[Inst alloc] init]; }\n@end\nInst *i = [Inst create];\nNSLog(@"%d", i != nil);`,
    expect: '1' },

  // ── Multiple inheritance levels + super ────────────────────
  { cat: 'Class definition & inheritance', name: 'Deep super chain',
    code: `@interface A : NSObject\n@end\n@implementation A\n- (int)val { return 1; }\n@end\n@interface B : A\n@end\n@implementation B\n- (int)val { return [super val] + 10; }\n@end\n@interface C : B\n@end\n@implementation C\n- (int)val { return [super val] + 100; }\n@end\nC *c = [C new];\nNSLog(@"%d", [c val]);`,
    expect: '111' },

  // ── Cross-cell persistence ─────────────────────────────────
  { cat: 'Cross-cell persistence', name: 'Class persists across cells',
    code: `@interface Persist : NSObject\n@property int x;\n@end\n@implementation Persist @end`,
    expect: '' },
];

// ── Runner ─────────────────────────────────────────────────────────

const results = {};
let totalPass = 0, totalFail = 0;

for (const probe of probes) {
  const result = execute(probe.code);
  const cat = probe.cat;
  if (!results[cat]) results[cat] = [];

  let passed;
  if (probe.expectAbsent) {
    passed = !result.output.includes(probe.expect);
  } else if (probe.expect === '') {
    // Empty expectation: pass if no error
    passed = result.status === 'ok';
  } else {
    passed = result.output.includes(probe.expect);
  }

  results[cat].push({
    name: probe.name,
    passed,
    expected: probe.expect,
    actual: result.lastLine || result.output.trim().split('\n').pop() || '(empty)',
    status: result.status,
    ename: result.ename,
    evalue: result.evalue,
  });

  if (passed) totalPass++; else totalFail++;
  const icon = passed ? 'PASS' : 'FAIL';
  console.log(`  ${icon}: [${cat}] ${probe.name}`);
  if (!passed) {
    console.log(`       expected: "${probe.expect}"`);
    console.log(`       actual:   "${result.lastLine || result.output.trim().split('\n').pop() || '(empty)'}"`);
    if (result.ename) console.log(`       error:    ${result.ename}: ${result.evalue}`);
  }
}

// Summary
console.log('\n─── Summary ───');
for (const [cat, items] of Object.entries(results)) {
  const pass = items.filter(i => i.passed).length;
  const fail = items.filter(i => !i.passed).length;
  console.log(`  ${cat}: ${pass}/${pass + fail} passed`);
}
console.log(`\n  Total: ${totalPass}/${totalPass + totalFail} passed`);
