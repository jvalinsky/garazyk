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

const request = JSON.stringify({
  code: 'NSLog(@"hello smoke");',
  cell_id: 'smoke-cell'
});
const requestPtr = exports.objc_kernel_request_buffer();
const requestSize = exports.objc_kernel_request_buffer_size();
writeCString(requestPtr, requestSize, request);

const execute = JSON.parse(readCString(exports.objc_kernel_execute_json(requestPtr)));
assert.equal(execute.status, 'ok');
assert.equal(execute.execution_count, 1);
assert.match(execute.data['text/plain'], /NSLog/);
assert.equal(execute.streams[0].name, 'stdout');

const complete = JSON.parse(readCString(exports.objc_kernel_complete_json(requestPtr)));
assert.equal(complete.status, 'ok');
assert.ok(complete.matches.includes('NSString'));

const inspect = JSON.parse(readCString(exports.objc_kernel_inspect_json(requestPtr)));
assert.equal(inspect.status, 'ok');
assert.equal(inspect.found, false);

exports.objc_kernel_free(0);
console.log('objc-jupyter-wasm kernel smoke passed');
