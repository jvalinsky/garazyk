import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';

const wasmPath = process.argv[2];

if (!wasmPath) {
  throw new Error('Usage: node tests/kernel-smoke.mjs /path/to/kernel.wasm');
}

const bytes = await readFile(wasmPath);
const { instance } = await WebAssembly.instantiate(bytes, {});
const exports = instance.exports;

for (const name of [
  'memory',
  'objc_kernel_init',
  'objc_kernel_info_json',
  'objc_kernel_execute_json',
  'objc_kernel_complete_json',
  'objc_kernel_inspect_json',
  'objc_kernel_free',
  'objc_kernel_request_buffer',
  'objc_kernel_request_buffer_size'
]) {
  assert.ok(exports[name], `missing export: ${name}`);
}

const memory = exports.memory;
const encoder = new TextEncoder();
const decoder = new TextDecoder();

function readCString(ptr) {
  const bytes = new Uint8Array(memory.buffer);
  let end = ptr;
  while (end < bytes.length && bytes[end] !== 0) {
    end += 1;
  }
  return decoder.decode(bytes.subarray(ptr, end));
}

function writeCString(ptr, capacity, value) {
  const encoded = encoder.encode(value);
  assert.ok(encoded.length + 1 < capacity, 'request exceeds WASM request buffer');
  const bytes = new Uint8Array(memory.buffer);
  bytes.set(encoded, ptr);
  bytes[ptr + encoded.length] = 0;
}

assert.equal(exports.objc_kernel_init(), 0);

const info = JSON.parse(readCString(exports.objc_kernel_info_json()));
assert.equal(info.language_info.name, 'objective-c');

const requestPtr = exports.objc_kernel_request_buffer();
const requestSize = exports.objc_kernel_request_buffer_size();

function callJson(exportName, payload) {
  writeCString(
    requestPtr,
    requestSize,
    typeof payload === 'string' ? payload : JSON.stringify(payload)
  );
  return JSON.parse(readCString(exports[exportName](requestPtr)));
}

function execute(code, cellId = 'smoke-cell') {
  return callJson('objc_kernel_execute_json', {
    code,
    cell_id: cellId
  });
}

const firstExecute = execute('NSLog(@"hello smoke");');
assert.equal(firstExecute.status, 'ok');
assert.equal(firstExecute.execution_count, 1);
assert.match(firstExecute.data['text/plain'], /NSLog/);
assert.equal(firstExecute.streams[0].name, 'stdout');

const quotedCode = 'NSLog(@"quote \\" and slash \\\\");\nint value = 42;';
const quotedExecute = execute(quotedCode, 'quoted-cell');
assert.equal(quotedExecute.status, 'ok');
assert.equal(quotedExecute.execution_count, 2);
assert.match(quotedExecute.data['text/plain'], /quote \\"/);
assert.match(quotedExecute.data['text/plain'], /slash \\\\/);
assert.match(quotedExecute.data['text/plain'], /int value = 42/);

const thirdExecute = execute('@interface Smoke\n@end', 'third-cell');
assert.equal(thirdExecute.status, 'ok');
assert.equal(thirdExecute.execution_count, 3);

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

const largeCodeExecute = execute('x'.repeat(3000), 'large-cell');
assert.equal(largeCodeExecute.status, 'error');
assert.equal(largeCodeExecute.ename, 'RequestTooLarge');

assert.throws(
  () => writeCString(requestPtr, requestSize, JSON.stringify({ code: 'x'.repeat(requestSize) })),
  /request exceeds WASM request buffer/
);

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

exports.objc_kernel_free(0);
console.log('objc-jupyter-wasm kernel smoke passed');
