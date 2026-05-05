// Notebook test harness for the ObjC WASM kernel.
// Loads a fresh kernel instance per notebook, runs all code cells in sequence,
// and reports pass/fail per cell. Exercise placeholder cells are skipped.
//
// Usage:
//   node tests/run-notebooks.mjs [options] [notebook.ipynb ...]
//   node tests/run-notebooks.mjs --dir demo/
//
// Options:
//   --kernel <path>   Path to kernel.wasm (default: result/wasm/kernel.wasm)
//   --dir <path>      Run all .ipynb files in a directory
//   --bail            Stop after the first failed cell in any notebook
//   --verbose         Show passing cells and their NSLog output
//   --json            Machine-readable JSON output to stdout

import { readFile, readdir } from 'node:fs/promises';
import { resolve, join, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { WASI } from 'node:wasi';

// ── ANSI palette ───────────────────────────────────────────────────────────────

const isTTY = process.stdout.isTTY;
const C = isTTY
  ? { reset: '\x1b[0m', bold: '\x1b[1m', dim: '\x1b[2m', green: '\x1b[32m', red: '\x1b[31m', yellow: '\x1b[33m', gray: '\x1b[90m' }
  : { reset: '', bold: '', dim: '', green: '', red: '', yellow: '', gray: '' };

// ── Argument parsing ───────────────────────────────────────────────────────────

const __dirname = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);

let kernelPath = resolve(__dirname, '../result/wasm/kernel.wasm');
let dirPath = null;
let bail = false;
let verbose = false;
let jsonOutput = false;
const notebookPaths = [];

for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === '--kernel')  { kernelPath = resolve(args[++i]); }
  else if (a === '--dir')     { dirPath = resolve(args[++i]); }
  else if (a === '--bail')    { bail = true; }
  else if (a === '--verbose') { verbose = true; }
  else if (a === '--json')    { jsonOutput = true; }
  else if (a.endsWith('.ipynb')) { notebookPaths.push(resolve(a)); }
  else { console.error(`Unknown argument: ${a}`); process.exit(2); }
}

if (dirPath) {
  const entries = await readdir(dirPath);
  for (const f of entries.filter(e => e.endsWith('.ipynb')).sort()) {
    notebookPaths.push(join(dirPath, f));
  }
}

if (notebookPaths.length === 0) {
  console.error([
    'Usage: node tests/run-notebooks.mjs [--kernel path] [--dir dir] [--bail] [--verbose] [--json] [notebook.ipynb ...]',
    '',
    'Examples:',
    '  node tests/run-notebooks.mjs demo/hello.ipynb demo/algorithms.ipynb',
    '  node tests/run-notebooks.mjs --dir demo/',
    '  node tests/run-notebooks.mjs --dir demo/',
  ].join('\n'));
  process.exit(2);
}

// ── WASM kernel factory ────────────────────────────────────────────────────────

const TRANSPORT = { OK: 0, INVALID_ARGUMENT: 1, REQUEST_TOO_LARGE: 2, RESPONSE_TOO_LARGE: 3, OOM: 4, INTERNAL_ERROR: 5 };
const encoder = new TextEncoder();
const decoder = new TextDecoder();

let wasmBytes;
try {
  wasmBytes = await readFile(kernelPath);
} catch (err) {
  console.error(`Cannot read kernel: ${kernelPath}\n${err.message}`);
  process.exit(2);
}

async function createKernel() {
  let instance;
  const streamBuf = [];

  const wasi = new WASI({ version: 'preview1' });

  ({ instance } = await WebAssembly.instantiate(wasmBytes, {
    wasi_snapshot_preview1: wasi.wasiImport,
    objc_kernel_host: {
      stream(kind, ptr, len) {
        const name = kind === 2 ? 'stderr' : 'stdout';
        const text = decoder.decode(new Uint8Array(instance.exports.memory.buffer, ptr, len));
        streamBuf.push({ name, text });
      },
      should_interrupt() { return 0; },
      json_parse() { return 0; },
      json_stringify() { return 0; },
      fetch() { return 0; },
      /* Crypto host stubs */
      sha256(dataPtr, dataLen, outPtr, outCap) { return 0; },
      random_bytes(outPtr, count) {
        const bytes = new Uint8Array(instance.exports.memory.buffer, outPtr, count);
        for (let i = 0; i < count; i++) bytes[i] = 0;
        return count;
      },
      hmac_sha256(keyPtr, keyLen, dataPtr, dataLen, outPtr, outCap) { return 0; },
      /* Encoding host stubs */
      base32_encode(dataPtr, dataLen, outPtr, outCap) { return 0; },
      base32_decode(strPtr, strLen, outPtr, outCap) { return 0; },
      base58btc_encode(dataPtr, dataLen, outPtr, outCap) { return 0; },
      base58btc_decode(strPtr, strLen, outPtr, outCap) { return 0; },
      /* CBOR host stubs */
      cbor_encode(jsonPtr, jsonLen, outPtr, outCap) { return 0; },
      cbor_decode(dataPtr, dataLen, outPtr, outCap) { return 0; }
    },
  }));

  wasi.initialize(instance);
  const { exports } = instance;
  const mem = exports.memory;

  if (exports.objc_kernel_init() !== TRANSPORT.OK) {
    throw new Error('objc_kernel_init() failed');
  }

  function allocBytes(value) {
    const encoded = encoder.encode(typeof value === 'string' ? value : JSON.stringify(value));
    const ptr = exports.objc_kernel_alloc(Math.max(encoded.length, 1));
    if (ptr === 0) throw new Error('WASM allocator returned null');
    new Uint8Array(mem.buffer).set(encoded, ptr);
    return { ptr, len: encoded.length };
  }

  function allocU32() {
    const ptr = exports.objc_kernel_alloc(4);
    if (ptr === 0) throw new Error('WASM allocator returned null');
    return ptr;
  }

  function readU32(ptr) {
    return new DataView(mem.buffer).getUint32(ptr, true);
  }

  function callJson(exportName, payload) {
    const { ptr: reqPtr, len: reqLen } = allocBytes(payload);
    const outPtrPtr = allocU32();
    const outLenPtr = allocU32();
    try {
      const rc = exports[exportName](reqPtr, reqLen, outPtrPtr, outLenPtr);
      if (rc !== TRANSPORT.OK) {
        const names = Object.keys(TRANSPORT);
        throw new Error(`Transport error ${rc} (${names.find(k => TRANSPORT[k] === rc) ?? 'UNKNOWN'}) from ${exportName}`);
      }
      const rPtr = readU32(outPtrPtr);
      const rLen = readU32(outLenPtr);
      const response = JSON.parse(decoder.decode(new Uint8Array(mem.buffer, rPtr, rLen)));
      exports.objc_kernel_free(rPtr);
      return response;
    } finally {
      exports.objc_kernel_free(reqPtr);
      exports.objc_kernel_free(outPtrPtr);
      exports.objc_kernel_free(outLenPtr);
    }
  }

  return {
    execute(code, cellId = 'cell') {
      streamBuf.length = 0;
      const reply = callJson('objc_kernel_execute_json', { code, cell_id: cellId });
      return { ...reply, streams: streamBuf.splice(0) };
    },
  };
}

// ── Cell classification ────────────────────────────────────────────────────────

function isPlaceholder(source) {
  const lines = source.trim().split('\n').map(l => l.trim()).filter(Boolean);
  if (lines.length === 0) return true;
  // Skip cells where every non-blank line is a comment, including "// Your code here..."
  if (lines.every(l => l.startsWith('//'))) {
    return true;
  }
  return false;
}

// ── Per-notebook runner ────────────────────────────────────────────────────────

async function runNotebook(notebookPath) {
  let nb;
  try {
    nb = JSON.parse(await readFile(notebookPath, 'utf8'));
  } catch (err) {
    return { notebookPath, error: `Failed to parse: ${err.message}`, cellResults: [], passed: 0, failed: 0, skipped: 0 };
  }

  const codeCells = nb.cells.filter(c => c.cell_type === 'code');
  const kernel = await createKernel();
  const cellResults = [];

  for (let i = 0; i < codeCells.length; i++) {
    const cell = codeCells[i];
    const source = Array.isArray(cell.source) ? cell.source.join('') : (cell.source ?? '');

    if (isPlaceholder(source)) {
      cellResults.push({ index: i, status: 'skip', source, streams: [] });
      continue;
    }

    let reply;
    try {
      reply = kernel.execute(source, `cell-${i}`);
    } catch (err) {
      reply = { status: 'error', ename: 'HarnessError', evalue: err.message, traceback: [], streams: [] };
    }

    cellResults.push({ index: i, status: reply.status, source, streams: reply.streams, data: reply.data, reply });

    if (bail && reply.status === 'error') break;
  }

  const passed  = cellResults.filter(r => r.status === 'ok').length;
  const failed  = cellResults.filter(r => r.status === 'error').length;
  const skipped = cellResults.filter(r => r.status === 'skip').length;

  return { notebookPath, cellResults, passed, failed, skipped };
}

// ── Console reporter ───────────────────────────────────────────────────────────

function printResult(result) {
  const name = basename(result.notebookPath);

  if (result.error) {
    console.log(`${C.bold}${name}${C.reset}  ${C.red}ERROR${C.reset}  ${result.error}`);
    return;
  }

  const tag = result.failed > 0 ? `${C.red}FAIL${C.reset}` : `${C.green}PASS${C.reset}`;
  console.log(`${C.bold}${name}${C.reset}  ${tag}  (${result.passed} ok, ${result.failed} failed, ${result.skipped} skipped)`);

  for (const cell of result.cellResults) {
    if (cell.status === 'skip') continue;

    const showCell = verbose || cell.status === 'error';
    if (!showCell) continue;

    const icon = cell.status === 'ok' ? `${C.green}✓${C.reset}` : `${C.red}✗${C.reset}`;
    console.log(`  ${icon} Cell [${cell.index}]`);

    // Source preview (first 4 lines)
    const preview = cell.source.trim().split('\n').slice(0, 4).join('\n');
    console.log(`${C.gray}${preview.split('\n').map(l => `    ${l}`).join('\n')}${C.reset}`);
    if (cell.source.trim().split('\n').length > 4) {
      console.log(`${C.gray}    ...${C.reset}`);
    }

    // NSLog / stderr output
    const output = cell.streams.map(s => s.text).join('');
    if (output.trim()) {
      console.log(`${C.dim}${output.trimEnd().split('\n').map(l => `    ${l}`).join('\n')}${C.reset}`);
    }

    // Error details
    if (cell.status === 'error') {
      console.log(`    ${C.red}${cell.reply.ename}: ${cell.reply.evalue}${C.reset}`);
      for (const line of cell.reply.traceback ?? []) {
        console.log(`    ${C.dim}${line}${C.reset}`);
      }
    }
  }
}

// ── Main ───────────────────────────────────────────────────────────────────────

const allResults = [];

for (const notebookPath of notebookPaths) {
  const result = await runNotebook(notebookPath);
  allResults.push(result);

  if (!jsonOutput) printResult(result);
  if (bail && result.failed > 0) break;
}

if (jsonOutput) {
  console.log(JSON.stringify(allResults, null, 2));
} else {
  const nb          = allResults.length;
  const failedNb    = allResults.filter(r => r.failed > 0 || r.error).length;
  const totalPassed = allResults.reduce((s, r) => s + r.passed,  0);
  const totalFailed = allResults.reduce((s, r) => s + r.failed,  0);
  const totalSkip   = allResults.reduce((s, r) => s + r.skipped, 0);
  const totalCells  = totalPassed + totalFailed + totalSkip;

  console.log('');
  if (failedNb === 0) {
    console.log(`${C.green}${C.bold}All ${nb} notebooks passed${C.reset}  (${totalPassed}/${totalCells} cells, ${totalSkip} skipped)`);
  } else {
    console.log(`${C.red}${C.bold}${failedNb}/${nb} notebooks failed${C.reset}  (${totalFailed} cells failed, ${totalPassed} passed, ${totalSkip} skipped)`);
  }
}

process.exit(allResults.reduce((s, r) => s + r.failed, 0) > 0 ? 1 : 0);
