const fs = require('fs');
const wasmCode = fs.readFileSync('/Users/jack/Software/garazyk/objc-jupyter-wasm/result/wasm/kernel.wasm');

/* Mock WASI snapshot preview 1 — needed by the WASM module */
const wasiSnapshot = {
  instance: {
    exports: {
      memory: new WebAssembly.Memory({ initial: 256 })
    }
  }
};

const imports = {
  env: {},
  wasi_snapshot_preview1: wasiSnapshot,
  objc_kernel_host: {
    stream: (kind, ptr, len) => {
      const mem = new Uint8Array(wasiSnapshot.instance.exports.memory.buffer);
      const msg = Buffer.from(mem.slice(ptr, ptr + len)).toString('utf8');
      if (kind === 0) console.log('[stdout]:', msg);
      else if (kind === 1) console.log('[stderr]:', msg);
    },
    should_interrupt: () => 0,
    json_parse: () => 0,
    json_stringify: () => 0,
    fetch: () => 0,
    /* Crypto host stubs */
    sha256(dataPtr, dataLen, outPtr, outCap) { return 0; },
    random_bytes(outPtr, count) {
      const bytes = new Uint8Array(memory.buffer, outPtr, count);
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
};

WebAssembly.instantiate(wasmCode, imports).then(obj => {
  const { objc_kernel_init, objc_kernel_execute_json, objc_kernel_alloc, objc_kernel_free } = obj.instance.exports;
  objc_kernel_init();

  function exec(code) {
    const codeBuf = objc_kernel_alloc(code.length + 1);
    const mem = new Uint8Array(wasiSnapshot.instance.exports.memory.buffer);
    for (let i = 0; i < code.length; i++) mem[codeBuf + i] = code.charCodeAt(i);
    mem[codeBuf + code.length] = 0;

    const outPtr = new Uint32Array(wasiSnapshot.instance.exports.memory.buffer);
    const outLen = new Uint32Array(wasiSnapshot.instance.exports.memory.buffer);
    const status = objc_kernel_execute_json(codeBuf, code.length, outPtr.byteOffset, outLen.byteOffset);

    if (status === 0) {
      const ptr = outPtr[0];
      const len = outLen[0];
      const resp = Buffer.from(wasiSnapshot.instance.exports.memory.buffer.slice(ptr, ptr + len)).toString('utf8');
      console.log('Response:', resp);
      objc_kernel_free(ptr);
    } else {
      console.log('Transport error:', status);
    }
  }

  console.log('=== Test 1: @protocol ===');
  exec('@protocol Foo\n- (void)bar;\n@end\nNSLog(@"protocol ok");');

  console.log('\n=== Test 2: @try/@catch/@finally ===');
  exec('BOOL caught = NO;\n@try {\n    NSLog(@"Inside try");\n    @throw @"oops";\n}\n@catch (id e) {\n    caught = YES;\n    NSLog(@"Caught: %@", e);\n}\n@finally {\n    NSLog(@"finally");\n}\nNSLog(@"caught=%d", (int)caught);');

  console.log('\n=== Test 3: @throw without @try (uncaught) ===');
  exec('@throw @"boom";\nNSLog(@"should not reach");');

}).catch(e => console.error('Error:', e));
