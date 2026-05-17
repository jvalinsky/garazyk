const fs = require("fs");

const wasmCode = fs.readFileSync("../../../objc-jupyter-wasm/result/wasm/kernel.wasm");

const memory = new WebAssembly.Memory({ initial: 256 });

function fd_write(fd, iovs, iovsLen, nwrittenPtr) {
  if (fd === 1 || fd === 2) {
    const mem = new Uint8Array(memory.buffer);
    let total = 0;
    for (let i = 0; i < iovsLen; i++) {
      const iovPtr = iovs + i * 8;
      const offset = new Uint32Array(memory.buffer, iovPtr, 1)[0];
      const len = new Uint32Array(memory.buffer, iovPtr + 4, 1)[0];
      const chunk = Buffer.from(mem.slice(offset, offset + len));
      if (fd === 1) process.stdout.write(chunk);
      else process.stderr.write(chunk);
      total += len;
    }
    new Uint32Array(memory.buffer, nwrittenPtr, 1)[0] = total;
    return 0;
  }
  return 8;
}

const wasi = {
  args: [],
  env: {},
  memory,
  "table": new WebAssembly.Table({ initial: 0, element: "anyfunc" }),
  "table_base": 0,
  "memory_base": 0,
  "fd_write": fd_write,
  "fd_read": () => 8,
  "fd_seek": () => 8,
  "fd_close": () => 0,
  "poll_oneoff": () => 0,
  "clock_time_get": () => 0,
  "proc_exit": (code) => process.exit(code),
};

const imports = {
  wasi_snapshot_preview1: wasi,
  env: wasi,
  objc_kernel_host: {
    stream: (kind, ptr, len) => {
      const mem = new Uint8Array(memory.buffer);
      const msg = Buffer.from(mem.slice(ptr, ptr + len)).toString("utf8");
      if (kind === 0) console.log("[stdout]:", msg);
      else if (kind === 1) console.log("[stderr]:", msg);
    },
    should_interrupt: () => 0,
    json_parse: () => 0,
    json_stringify: () => 0,
    fetch: () => 0,
    /* Crypto host stubs */
    sha256(dataPtr, dataLen, outPtr, outCap) {
      return 0;
    },
    random_bytes(outPtr, count) {
      const bytes = new Uint8Array(memory.buffer, outPtr, count);
      for (let i = 0; i < count; i++) bytes[i] = 0;
      return count;
    },
    hmac_sha256(keyPtr, keyLen, dataPtr, dataLen, outPtr, outCap) {
      return 0;
    },
    /* Encoding host stubs */
    base32_encode(dataPtr, dataLen, outPtr, outCap) {
      return 0;
    },
    base32_decode(strPtr, strLen, outPtr, outCap) {
      return 0;
    },
    base58btc_encode(dataPtr, dataLen, outPtr, outCap) {
      return 0;
    },
    base58btc_decode(strPtr, strLen, outPtr, outCap) {
      return 0;
    },
    /* CBOR host stubs */
    cbor_encode(jsonPtr, jsonLen, outPtr, outCap) {
      return 0;
    },
    cbor_decode(dataPtr, dataLen, outPtr, outCap) {
      return 0;
    },
  },
};

WebAssembly.instantiate(wasmCode, imports).then((obj) => {
  const { objc_kernel_init, objc_kernel_execute_json, objc_kernel_alloc, objc_kernel_free } =
    obj.instance.exports;
  objc_kernel_init();

  function exec(code) {
    const codeBuf = objc_kernel_alloc(code.length + 1);
    const mem = new Uint8Array(memory.buffer);
    for (let i = 0; i < code.length; i++) mem[codeBuf + i] = code.charCodeAt(i);
    mem[codeBuf + code.length] = 0;

    /* Allocate response pointer + length in memory.
     * The kernel expects out_ptr_ptr and out_len_ptr to be pointers
     * (addresses where it can write the response pointer and length).
     * We use offset 1024 for out_ptr, 1028 for out_len. */
    const outPtrAddr = 1024;
    const outLenAddr = 1028;
    /* Initialize them to 0 */
    new Uint32Array(memory.buffer, outPtrAddr, 1)[0] = 0;
    new Uint32Array(memory.buffer, outLenAddr, 1)[0] = 0;

    const status = objc_kernel_execute_json(codeBuf, code.length, outPtrAddr, outLenAddr);
    console.log("status:", status);

    const respPtr = new Uint32Array(memory.buffer, outPtrAddr, 1)[0];
    const respLen = new Uint32Array(memory.buffer, outLenAddr, 1)[0];
    console.log("respPtr:", respPtr, "respLen:", respLen);

    if (status === 0 && respPtr !== 0) {
      const respBuf = mem.slice(respPtr, respPtr + respLen);
      let hex = "";
      for (let i = 0; i < Math.min(respLen, 100); i++) {
        hex += respBuf[i].toString(16).padStart(2, "0") + " ";
      }
      console.log("Response hex:", hex);
      const resp = Buffer.from(respBuf).toString("utf8");
      console.log("Response string:", resp);
      objc_kernel_free(respPtr);
    } else {
      console.log("No response (error or empty)");
    }
  }

  console.log("=== Test 1: @protocol ===");
  exec('@protocol Foo\n- (void)bar;\n@end\nNSLog(@"protocol ok");');

  console.log("\n=== Test 2: @try/@catch/@finally ===");
  exec(
    'BOOL caught = NO;\n@try {\n    NSLog(@"Inside try");\n    @throw @"oops";\n}\n@catch (id e) {\n    caught = YES;\n    NSLog(@"Caught: %@", e);\n}\n@finally {\n    NSLog(@"finally");\n}\nNSLog(@"caught=%d", (int)caught);',
  );

  console.log("\n=== Test 3: @throw without @try (uncaught) ===");
  exec('@throw @"boom";\nNSLog(@"should not reach");');
}).catch((e) => console.error("Error:", e));
