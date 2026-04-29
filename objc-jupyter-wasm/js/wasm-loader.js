// WebAssembly loading and C-string marshalling for objc-jupyter-wasm.

const ABI_EXPORTS = [
  'memory',
  'objc_kernel_init',
  'objc_kernel_info_json',
  'objc_kernel_execute_json',
  'objc_kernel_complete_json',
  'objc_kernel_inspect_json',
  'objc_kernel_free',
  'objc_kernel_request_buffer',
  'objc_kernel_request_buffer_size'
];

export class ObjcWasmKernel {
  static async create(wasmUrl = './kernel/kernel.wasm') {
    const response = await fetch(wasmUrl);
    if (!response.ok) {
      throw new Error(`Failed to fetch ${wasmUrl}: ${response.status}`);
    }

    const bytes = await response.arrayBuffer();
    const { instance } = await WebAssembly.instantiate(bytes, {});
    return new ObjcWasmKernel(instance);
  }

  constructor(instance) {
    this.instance = instance;
    this.exports = instance.exports;
    this.encoder = new TextEncoder();
    this.decoder = new TextDecoder();

    for (const name of ABI_EXPORTS) {
      if (!this.exports[name]) {
        throw new Error(`kernel.wasm missing export: ${name}`);
      }
    }

    const status = this.exports.objc_kernel_init();
    if (status !== 0) {
      throw new Error(`objc_kernel_init failed with status ${status}`);
    }
  }

  kernelInfo() {
    return JSON.parse(this.readCString(this.exports.objc_kernel_info_json()));
  }

  execute(code, cellId) {
    return this.callJson('objc_kernel_execute_json', {
      code,
      cell_id: cellId || null
    });
  }

  complete(code, cursorPos) {
    return this.callJson('objc_kernel_complete_json', {
      code,
      cursor_pos: cursorPos
    });
  }

  inspect(code, cursorPos, detailLevel) {
    return this.callJson('objc_kernel_inspect_json', {
      code,
      cursor_pos: cursorPos,
      detail_level: detailLevel
    });
  }

  callJson(exportName, payload) {
    const requestPtr = this.exports.objc_kernel_request_buffer();
    const requestCapacity = this.exports.objc_kernel_request_buffer_size();
    this.writeCString(requestPtr, requestCapacity, JSON.stringify(payload));

    const resultPtr = this.exports[exportName](requestPtr);
    try {
      return JSON.parse(this.readCString(resultPtr));
    } finally {
      this.exports.objc_kernel_free(resultPtr);
    }
  }

  readCString(ptr) {
    if (!ptr) {
      return '';
    }

    const bytes = new Uint8Array(this.exports.memory.buffer);
    let end = ptr;
    while (end < bytes.length && bytes[end] !== 0) {
      end += 1;
    }
    return this.decoder.decode(bytes.subarray(ptr, end));
  }

  writeCString(ptr, capacity, value) {
    const encoded = this.encoder.encode(value);
    if (encoded.length + 1 >= capacity) {
      throw new Error(`Kernel request is too large (${encoded.length} bytes, capacity ${capacity})`);
    }

    const bytes = new Uint8Array(this.exports.memory.buffer);
    bytes.set(encoded, ptr);
    bytes[ptr + encoded.length] = 0;
  }
}
