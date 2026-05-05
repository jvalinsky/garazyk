import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { WASI } from 'node:wasi';

const wasmPath = './result/wasm/kernel.wasm';

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
let instance;

// Helper to mimic ObjcWasmKernel._createHostImports logic
let exports = null;
const memoryBytes = () => new Uint8Array(instance.exports.memory.buffer);

function withCString(str, fn) {
  if (str == null) return fn(0);
  const encoded = encoder.encode(str + '\0');
  const ptr = exports.objc_kernel_alloc(Math.max(encoded.length, 1));
  memoryBytes().set(encoded, ptr);
  try {
    return fn(ptr);
  } finally {
    exports.objc_kernel_free(ptr);
  }
}

function buildObjcValue(val) {
  if (!exports) return 0;
  if (val === null) {
    let ptr = 0;
    withCString("NSNull:", p => { ptr = exports.coll_make_marker(p, 0); });
    return ptr;
  }
  if (typeof val === 'string') {
    const encoded = encoder.encode(val + '\0');
    const strPtr = exports.string_pool_alloc(encoded.length);
    if (strPtr) {
      memoryBytes().set(encoded, strPtr);
      return strPtr;
    }
    return 0;
  }
  if (typeof val === 'number') {
    return 0;
  }
  
  const coll_id = exports.coll_create_new();
  if (Array.isArray(val)) {
    for (let i = 0; i < val.length; i++) {
      addValueToColl(coll_id, null, val[i]);
    }
    let ptr = 0;
    withCString("NSArr:", p => { ptr = exports.coll_make_marker(p, coll_id); });
    return ptr;
  } else if (typeof val === 'object') {
    for (const key in val) {
      addValueToColl(coll_id, key, val[key]);
    }
    let ptr = 0;
    withCString("NSDict:", p => { ptr = exports.coll_make_marker(p, coll_id); });
    return ptr;
  }
  return 0;
}

function addValueToColl(coll_id, key, val) {
  withCString(key, (keyPtr) => {
    if (val === null) {
      withCString("null", valPtr => exports.coll_add_string_val(coll_id, keyPtr, valPtr));
    } else if (typeof val === 'string') {
      withCString(val, valPtr => exports.coll_add_string_val(coll_id, keyPtr, valPtr));
    } else if (typeof val === 'number') {
      if (Number.isInteger(val)) {
        exports.coll_add_int_val(coll_id, keyPtr, val);
      } else {
        exports.coll_add_double_val(coll_id, keyPtr, val);
      }
    } else if (typeof val === 'boolean') {
      exports.coll_add_bool_val(coll_id, keyPtr, val ? 1 : 0);
    } else if (typeof val === 'object') {
      const childMarker = buildObjcValue(val);
      if (childMarker) {
        exports.coll_add_marker_val(coll_id, keyPtr, childMarker);
      }
    }
  });
}

({ instance } = await WebAssembly.instantiate(bytes, {
  wasi_snapshot_preview1: wasi.wasiImport,
  objc_kernel_host: {
    stream(kind, ptr, len) {
      const name = kind === 2 ? 'stderr' : 'stdout';
      const text = decoder.decode(new Uint8Array(instance.exports.memory.buffer, ptr, len));
      console.log(`[${name}] ${text.trim()}`);
    },
    should_interrupt() {
      return 0;
    },
    json_parse(ptr, len) {
      const bytes = memoryBytes().subarray(ptr, ptr + len);
      const str = decoder.decode(bytes);
      let obj;
      try {
        obj = JSON.parse(str);
      } catch (e) {
        return 0;
      }
      return buildObjcValue(obj);
    },
    json_stringify(objMarker, outPtr, outLen) {
      return 0;
    },
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
  }
}));

wasi.initialize(instance);
exports = instance.exports;
exports.objc_kernel_init();

function allocateBytes(value) {
  const encoded = encoder.encode(typeof value === 'string' ? value : JSON.stringify(value));
  const ptr = exports.objc_kernel_alloc(Math.max(encoded.length, 1));
  new Uint8Array(exports.memory.buffer).set(encoded, ptr);
  return { ptr, len: encoded.length };
}

function allocateUint32() {
  return exports.objc_kernel_alloc(4);
}

function readUint32(ptr) {
  return new DataView(exports.memory.buffer).getUint32(ptr, true);
}

function readJsonResponse(ptr, len) {
  return JSON.parse(decoder.decode(new Uint8Array(exports.memory.buffer, ptr, len)));
}

async function execute(code) {
  console.log(`\nExecuting:\n${code}\n`);
  const req = allocateBytes({
    code,
    cell_id: 'test-cell'
  });
  const outPtrPtr = allocateUint32();
  const outLenPtr = allocateUint32();

  const status = exports.objc_kernel_execute_json(req.ptr, req.len, outPtrPtr, outLenPtr);
  console.log(`Status: ${status}`);

  if (status === TRANSPORT_CODE.OK) {
    const respPtr = readUint32(outPtrPtr);
    const respLen = readUint32(outLenPtr);
    const response = readJsonResponse(respPtr, respLen);
    console.log('Response:', JSON.stringify(response, null, 2));
    if (response.status === 'error') {
        console.error('Error:', response.ename, response.evalue);
    }
    exports.objc_kernel_free(respPtr);
  }
  
  exports.objc_kernel_free(req.ptr);
  exports.objc_kernel_free(outPtrPtr);
  exports.objc_kernel_free(outLenPtr);
}

console.log('--- Test 1: NSJSONSerialization JSONObjectWithData ---');
await execute(`
NSData *data = [NSData dataWithBytes:"{\\"name\\":\\"alice\\",\\"age\\":25}" length:25];
NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
NSLog(@"Name: %@", [dict objectForKey:@"name"]);
NSLog(@"Age: %d", (int)[[dict objectForKey:@"age"] intValue]);
`);

console.log('--- Test 2: NSJSONSerialization dataWithJSONObject ---');
await execute(`
NSMutableDictionary *mutDict = [NSMutableDictionary dictionary];
[mutDict setObject:@"bob" forKey:@"name"];
[mutDict setObject:@42 forKey:@"age"];
NSArray *arr = @[@1, @2];
[mutDict setObject:arr forKey:@"scores"];
NSData *outData = [NSJSONSerialization dataWithJSONObject:mutDict options:0 error:nil];
NSString *outStr = [outData bytes]; // decodes hex to string
NSLog(@"Output JSON: %@", outStr);
`);
