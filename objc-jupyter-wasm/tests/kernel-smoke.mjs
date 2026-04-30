import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { WASI } from 'node:wasi';

const wasmPath = process.argv[2];

if (!wasmPath) {
  throw new Error('Usage: node tests/kernel-smoke.mjs /path/to/kernel.wasm');
}

const TRANSPORT_CODE = {
  OK: 0,
  INVALID_ARGUMENT: 1,
  REQUEST_TOO_LARGE: 2,
  RESPONSE_TOO_LARGE: 3,
  OOM: 4,
  INTERNAL_ERROR: 5
};

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
    should_interrupt() {
      return 0;
    }
  }
}));
wasi.initialize(instance);

const exports = instance.exports;
const memory = exports.memory;

for (const name of [
  'memory',
  'objc_kernel_init',
  'objc_kernel_max_request_bytes',
  'objc_kernel_max_response_bytes',
  'objc_kernel_alloc',
  'objc_kernel_free',
  'objc_kernel_info_json',
  'objc_kernel_execute_json',
  'objc_kernel_complete_json',
  'objc_kernel_inspect_json',
  'objc_getClass',
  'sel_registerName',
  'objc_msgSend',
  'objc_allocateClassPair',
  'class_addMethod'
]) {
  assert.ok(exports[name], `missing export: ${name}`);
}

assert.equal(exports.objc_kernel_request_buffer, undefined);
assert.equal(exports.objc_kernel_request_buffer_size, undefined);

function allocateBytes(value) {
  const encoded = encoder.encode(typeof value === 'string' ? value : JSON.stringify(value));
  const ptr = exports.objc_kernel_alloc(Math.max(encoded.length, 1));
  assert.notEqual(ptr, 0, 'WASM transport allocator returned null');
  new Uint8Array(memory.buffer).set(encoded, ptr);
  return { ptr, len: encoded.length };
}

function allocateUint32() {
  const ptr = exports.objc_kernel_alloc(4);
  assert.notEqual(ptr, 0, 'WASM transport allocator returned null');
  return ptr;
}

function readUint32(ptr) {
  return new DataView(memory.buffer).getUint32(ptr, true);
}

function readJsonResponse(ptr, len) {
  return JSON.parse(decoder.decode(new Uint8Array(memory.buffer, ptr, len)));
}

function callJsonWithoutRequest(exportName) {
  const outPtrPtr = allocateUint32();
  const outLenPtr = allocateUint32();

  try {
    const transportStatus = exports[exportName](outPtrPtr, outLenPtr);
    assert.equal(transportStatus, TRANSPORT_CODE.OK);

    const responsePtr = readUint32(outPtrPtr);
    const responseLen = readUint32(outLenPtr);
    const response = readJsonResponse(responsePtr, responseLen);

    exports.objc_kernel_free(responsePtr);
    return response;
  } finally {
    exports.objc_kernel_free(outPtrPtr);
    exports.objc_kernel_free(outLenPtr);
  }
}

function callJson(exportName, payload) {
  const { ptr: requestPtr, len: requestLen } = allocateBytes(payload);
  const outPtrPtr = allocateUint32();
  const outLenPtr = allocateUint32();

  try {
    const transportStatus = exports[exportName](requestPtr, requestLen, outPtrPtr, outLenPtr);
    assert.equal(transportStatus, TRANSPORT_CODE.OK);

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

assert.equal(exports.objc_kernel_init(), 0);
assert.equal(exports.objc_kernel_max_request_bytes(), 64 * 1024);
assert.equal(exports.objc_kernel_max_response_bytes(), 1024 * 1024);
assert.equal(exports.objc_kernel_info_json(0, 0), TRANSPORT_CODE.INVALID_ARGUMENT);

const info = callJsonWithoutRequest('objc_kernel_info_json');
assert.equal(info.language_info.name, 'objective-c');

function execute(code, cellId = 'smoke-cell') {
  hostStreams.length = 0;
  return callJson('objc_kernel_execute_json', {
    code,
    cell_id: cellId
  });
}

function hostStreamText(name = 'stdout') {
  return hostStreams
    .filter(stream => stream.name === name)
    .map(stream => stream.text)
    .join('');
}

const firstExecute = execute('NSLog(@"hello smoke");');
assert.equal(firstExecute.status, 'ok');
assert.equal(firstExecute.execution_count, 1);
assert.equal(firstExecute.streams, undefined);
assert.match(hostStreamText(), /hello smoke/);

const expressionExecute = execute('40 + 2;', 'expression-cell');
assert.equal(expressionExecute.status, 'ok');
assert.equal(expressionExecute.execution_count, 2);
assert.equal(expressionExecute.data['text/plain'], '42');
assert.deepEqual(hostStreams, []);

const quotedCode = 'NSLog(@"quote \\" and slash \\\\");\nint value = 42;';
const quotedExecute = execute(quotedCode, 'quoted-cell');
assert.equal(quotedExecute.status, 'ok');
assert.equal(quotedExecute.execution_count, 3);
assert.match(hostStreamText(), /quote " and slash \\/);

const fmtExecute = execute('NSLog(@"value = %d", 42);', 'fmt-cell');
assert.equal(fmtExecute.status, 'ok');
assert.match(hostStreamText(), /value = 42/);

const thirdExecute = execute('@interface Smoke\n@end', 'third-cell');
assert.equal(thirdExecute.status, 'ok');
assert.equal(thirdExecute.execution_count, 5);

const malformedExecute = callJson('objc_kernel_execute_json', '{"code":');
assert.equal(malformedExecute.status, 'error');
assert.equal(malformedExecute.ename, 'InvalidJSON');

const missingCodeExecute = callJson('objc_kernel_execute_json', {
  cell_id: 'missing-code'
});
assert.equal(missingCodeExecute.status, 'error');
assert.equal(missingCodeExecute.ename, 'MissingCode');

const nonStringCodeExecute = callJson('objc_kernel_execute_json', {
  code: 17
});
assert.equal(nonStringCodeExecute.status, 'error');
assert.equal(nonStringCodeExecute.ename, 'InvalidCode');

{
  const outPtrPtr = allocateUint32();
  const outLenPtr = allocateUint32();

  try {
    const transportStatus = exports.objc_kernel_execute_json(
      0,
      exports.objc_kernel_max_request_bytes() + 1,
      outPtrPtr,
      outLenPtr
    );
    assert.equal(transportStatus, TRANSPORT_CODE.REQUEST_TOO_LARGE);
    assert.equal(readUint32(outPtrPtr), 0);
    assert.equal(readUint32(outLenPtr), 0);
  } finally {
    exports.objc_kernel_free(outPtrPtr);
    exports.objc_kernel_free(outLenPtr);
  }
}

const complete = callJson('objc_kernel_complete_json', {
  code: 'NS',
  cursor_pos: 2
});
assert.equal(complete.status, 'ok');
assert.ok(complete.matches.includes('NSString'));

const malformedComplete = callJson('objc_kernel_complete_json', '{"code"');
assert.equal(malformedComplete.status, 'error');
assert.equal(malformedComplete.ename, 'InvalidJSON');

const inspect = callJson('objc_kernel_inspect_json', {
  code: 'NSString',
  cursor_pos: 8,
  detail_level: 0
});
assert.equal(inspect.status, 'ok');
assert.equal(inspect.found, false);

const malformedInspect = callJson('objc_kernel_inspect_json', '{"code":null}');
assert.equal(malformedInspect.status, 'error');
assert.equal(malformedInspect.ename, 'InvalidCode');

// ── Method body execution tests ──────────────────────────────────

// Define a class with a method that returns a value
const methodClassCode = [
  '@interface Calculator',
  '- (int)add:(int)a to:(int)b;',
  '@end',
  '',
  '@implementation Calculator',
  '- (int)add:(int)a to:(int)b {',
  '    return a + b;',
  '}',
  '@end'
].join('\n');

const methodClassExecute = execute(methodClassCode, 'method-class-cell');
console.log('method class result:', JSON.stringify(methodClassExecute));
assert.equal(methodClassExecute.status, 'ok');

// Use the class: alloc + method call
const methodUseCode = [
  'Calculator *calc = [Calculator alloc];',
  'int result = [calc add:3 to:4];',
  'NSLog(@"3 + 4 = %d", result);'
].join('\n');

const methodUseExecute = execute(methodUseCode, 'method-use-cell');
assert.equal(methodUseExecute.status, 'ok');
assert.match(hostStreamText(), /3 \+ 4 = 7/);

// Cross-cell method dispatch: define class in one cell, use in another
const crossCellMethodCode = [
  '@interface Adder',
  '- (int)compute:(int)x plus:(int)y;',
  '@end',
  '',
  '@implementation Adder',
  '- (int)compute:(int)x plus:(int)y {',
  '    int sum = x + y;',
  '    NSLog(@"x=%d y=%d sum=%d", x, y, sum);',
  '    return sum;',
  '}',
  '@end'
].join('\n');

const crossCellMethodExec = execute(crossCellMethodCode, 'cross-cell-method');
assert.equal(crossCellMethodExec.status, 'ok');

const crossCellMethodUseCode = [
  'Adder *a = [Adder alloc];',
  'int r = [a compute:5 plus:3];',
  'NSLog(@"5 + 3 = %d", r);'
].join('\n');

const crossCellMethodUseExec = execute(crossCellMethodUseCode, 'cross-cell-method-use');
assert.equal(crossCellMethodUseExec.status, 'ok');
assert.match(hostStreamText(), /x=5 y=3 sum=8/);
assert.match(hostStreamText(), /5 \+ 3 = 8/);

// Method with NSLog inside the body (void return)
const nslogMethodCode = [
  '@interface Greeter',
  '- (void)greet;',
  '@end',
  '',
  '@implementation Greeter',
  '- (void)greet {',
  '    NSLog(@"hello from method");',
  '}',
  '@end'
].join('\n');

const nslogMethodExecute = execute(nslogMethodCode, 'nslog-method-cell');
assert.equal(nslogMethodExecute.status, 'ok');

const nslogMethodUseCode = [
  'Greeter *g = [Greeter alloc];',
  '[g greet];'
].join('\n');

const nslogMethodUseExecute = execute(nslogMethodUseCode, 'nslog-method-use-cell');
assert.equal(nslogMethodUseExecute.status, 'ok');
assert.match(hostStreamText(), /hello from method/);

exports.objc_kernel_free(0);
console.log('objc-jupyter-wasm kernel smoke passed');
