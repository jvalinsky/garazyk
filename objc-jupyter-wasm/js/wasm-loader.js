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

    // The kernel is linked with wasi-libc and requires WASI imports.
    // We provide a minimal WASI implementation that supports the
    // fd_write syscall (for stdout/stderr capture) and proc_exit.
    const wasiImports = ObjcWasmKernel._createWasiImports();
    const { instance } = await WebAssembly.instantiate(bytes, {
      wasi_snapshot_preview1: wasiImports
    });

    // Call _start if exported (WASI reactor entry point)
    if (instance.exports._start) {
      instance.exports._start();
    }

    return new ObjcWasmKernel(instance);
  }

  /**
   * Create a minimal WASI preview1 import object.
   * Only the syscalls needed by the kernel are implemented:
   *   - fd_write: capture stdout/stderr to a ring buffer
   *   - proc_exit: no-op (kernel runs forever)
   *   - environ_sizes_get / environ_get: no environment
   *   - fd_fdstat_get: report character device for stdout/stderr
   *   - random_get: no-op (not used by kernel)
   */
  static _createWasiImports() {
    const encoder = new TextEncoder();
    const decoder = new TextDecoder();

    return {
      // fd_write(fd, iovs_ptr, iovs_count, nwritten_ptr) -> count
      fd_write(fd, iovs_ptr, iovs_count, nwritten_ptr) {
        // We don't capture stdout in the WASI layer — the kernel
        // captures NSLog output via its own ring buffer.
        return 0;
      },

      // proc_exit(code) -> !
      proc_exit(code) {
        // Kernel should not exit. Ignore.
      },

      // environ_sizes_get(count_ptr, buf_ptr) -> 0
      environ_sizes_get(count_ptr, buf_ptr) {
        return 0;
      },

      // environ_get(environ_ptr, buf_ptr) -> 0
      environ_get(environ_ptr, buf_ptr) {
        return 0;
      },

      // fd_fdstat_get(fd, stat_ptr) -> errno
      fd_fdstat_get(fd, stat_ptr) {
        // Report stdout (1) and stderr (2) as character devices
        if (fd === 1 || fd === 2) {
          return 0;
        }
        return 8; // EBADF
      },

      // random_get(buf_ptr, buf_len) -> 0
      random_get(buf_ptr, buf_len) {
        return 0;
      },

      // clock_time_get(clock_id, precision, time_ptr) -> 0
      clock_time_get(clock_id, precision, time_ptr) {
        // Return 0 epoch time
        return 0;
      },

      // sched_yield() -> 0
      sched_yield() {
        return 0;
      },

      // poll_oneoff(in_ptr, out_ptr, nsubscriptions, nevents_ptr) -> 0
      poll_oneoff(in_ptr, out_ptr, nsubscriptions, nevents_ptr) {
        return 0;
      }
    };
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
