// WebAssembly loading and transport v2 marshalling for objc-jupyter-wasm.

const ABI_EXPORTS = [
  'memory',
  'objc_kernel_init',
  'objc_kernel_max_request_bytes',
  'objc_kernel_max_response_bytes',
  'objc_kernel_alloc',
  'objc_kernel_free',
  'objc_kernel_info_json',
  'objc_kernel_execute_json',
  'objc_kernel_complete_json',
  'objc_kernel_inspect_json'
];

const TRANSPORT_CODE = {
  OK: 0,
  INVALID_ARGUMENT: 1,
  REQUEST_TOO_LARGE: 2,
  RESPONSE_TOO_LARGE: 3,
  OOM: 4,
  INTERNAL_ERROR: 5
};

const DEFAULT_RUNTIME_MANIFEST = {
  kernelWasmUrl: './kernel/kernel.wasm',
  runtimeVersion: 'dev',
  sha256: '',
  maxRequestBytes: 64 * 1024,
  maxResponseBytes: 1024 * 1024,
  softTimeoutMs: 30_000,
  hardTimeoutMs: 35_000
};

const WASI_ERRNO = {
  SUCCESS: 0,
  BADF: 8,
  NOSYS: 52,
  SPIPE: 70
};

const WASI_FILETYPE_CHARACTER_DEVICE = 2;
const STREAM_FLUSH_THRESHOLD = 4096;

export class WasiProcExitError extends Error {
  constructor(code) {
    super(`WASI proc_exit(${code})`);
    this.name = 'WasiProcExitError';
    this.code = code;
  }
}

class ObjcKernelTransportError extends Error {
  constructor(code, context) {
    super(transportErrorMessage(code, context));
    this.name = 'ObjcKernelTransportError';
    this.code = code;
  }
}

export class ObjcWasmKernel {
  static async create(runtimeManifestOrUrl = DEFAULT_RUNTIME_MANIFEST, options = {}) {
    const runtimeManifest = normalizeRuntimeManifest(runtimeManifestOrUrl);
    const response = await fetch(runtimeManifest.kernelWasmUrl);
    if (!response.ok) {
      throw new Error(`Failed to fetch ${runtimeManifest.kernelWasmUrl}: ${response.status}`);
    }

    const bytes = new Uint8Array(await response.arrayBuffer());
    await verifySha256(runtimeManifest, bytes);

    const host = ObjcWasmKernel._createHostImports(options.onStream || null);
    const wasi = ObjcWasmKernel._createWasiImports();
    const { instance } = await WebAssembly.instantiate(bytes, {
      wasi_snapshot_preview1: wasi.imports,
      objc_kernel_host: host.imports
    });

    host.bindMemory(instance.exports.memory);
    wasi.bindMemory(instance.exports.memory);

    if (instance.exports._start) {
      try {
        instance.exports._start();
      } catch (error) {
        if (!(error instanceof WasiProcExitError) || error.code !== 0) {
          throw error;
        }
      }
    }

    return new ObjcWasmKernel(instance, runtimeManifest, host, wasi);
  }

  static _createHostImports(onStream) {
    const decoder = new TextDecoder();
    let memory = null;
    let interruptView = null;
    let localInterrupt = false;
    let bufferedStreams = [];
    const pending = {
      stdout: '',
      stderr: ''
    };

    const memoryBytes = () => {
      if (!memory) {
        throw new Error('Objective-C host imports have no memory binding');
      }
      return new Uint8Array(memory.buffer);
    };

    let streamListener = onStream;

    const emit = (name, text, force = false) => {
      if (text === '') {
        return;
      }

      pending[name] += text;
      if (!force && !pending[name].includes('\n') && pending[name].length < STREAM_FLUSH_THRESHOLD) {
        return;
      }

      const chunk = pending[name];
      pending[name] = '';
      const stream = { name, text: chunk };
      if (streamListener) {
        streamListener(stream);
      } else {
        bufferedStreams.push(stream);
      }
    };

    return {
      imports: {
        stream(kind, ptr, len) {
          const name = kind === 2 ? 'stderr' : 'stdout';
          const bytes = memoryBytes().subarray(ptr, ptr + len);
          emit(name, decoder.decode(bytes));
        },
        should_interrupt() {
          if (interruptView) {
            return Atomics.load(interruptView, 0) === 1 ? 1 : 0;
          }
          return localInterrupt ? 1 : 0;
        }
      },
      bindMemory(nextMemory) {
        memory = nextMemory;
      },
      setStreamListener(nextListener) {
        streamListener = nextListener;
      },
      setInterruptBuffer(sharedBuffer) {
        interruptView = sharedBuffer ? new Int32Array(sharedBuffer) : null;
      },
      beginExecute() {
        pending.stdout = '';
        pending.stderr = '';
        bufferedStreams = [];
        localInterrupt = false;
        if (interruptView) {
          Atomics.store(interruptView, 0, 0);
        }
      },
      requestSoftInterrupt() {
        if (interruptView) {
          Atomics.store(interruptView, 0, 1);
          return true;
        }
        localInterrupt = true;
        return false;
      },
      clearInterrupt() {
        localInterrupt = false;
        if (interruptView) {
          Atomics.store(interruptView, 0, 0);
        }
      },
      drainStreams() {
        emit('stdout', '', true);
        emit('stderr', '', true);
        const streams = bufferedStreams;
        bufferedStreams = [];
        return streams;
      },
      flushPending() {
        emit('stdout', '', true);
        emit('stderr', '', true);
      }
    };
  }

  static _createWasiImports() {
    const decoder = new TextDecoder();
    let memory = null;
    let stdout = '';
    let stderr = '';

    const bytes = () => {
      if (!memory) {
        throw new Error('WASI memory is not bound');
      }
      return new Uint8Array(memory.buffer);
    };

    const view = () => {
      if (!memory) {
        throw new Error('WASI memory is not bound');
      }
      return new DataView(memory.buffer);
    };

    const writeUint32 = (ptr, value) => {
      if (ptr !== 0) {
        view().setUint32(ptr, value >>> 0, true);
      }
    };

    const writeUint64 = (ptr, value) => {
      const data = view();
      data.setBigUint64(ptr, BigInt(value), true);
    };

    const appendStream = (fd, text) => {
      if (fd === 1) {
        stdout += text;
      } else if (fd === 2) {
        stderr += text;
      }
    };

    return {
      imports: {
        fd_close(fd) {
          return fd >= 0 && fd <= 2 ? WASI_ERRNO.SUCCESS : WASI_ERRNO.BADF;
        },
        fd_seek(fd) {
          return fd >= 0 && fd <= 2 ? WASI_ERRNO.SPIPE : WASI_ERRNO.BADF;
        },
        fd_write(fd, iovs_ptr, iovs_count, nwritten_ptr) {
          if (fd !== 1 && fd !== 2) {
            return WASI_ERRNO.BADF;
          }

          const memoryBytes = bytes();
          const data = view();
          let written = 0;

          for (let i = 0; i < iovs_count; i++) {
            const iovPtr = iovs_ptr + i * 8;
            const ptr = data.getUint32(iovPtr, true);
            const length = data.getUint32(iovPtr + 4, true);
            appendStream(fd, decoder.decode(memoryBytes.subarray(ptr, ptr + length)));
            written += length;
          }

          writeUint32(nwritten_ptr, written);
          return WASI_ERRNO.SUCCESS;
        },
        fd_read(fd, iovs_ptr, iovs_count, nread_ptr) {
          if (fd !== 0) {
            return WASI_ERRNO.BADF;
          }
          writeUint32(nread_ptr, 0);
          return WASI_ERRNO.SUCCESS;
        },
        proc_exit(code) {
          throw new WasiProcExitError(code);
        },
        environ_sizes_get(count_ptr, buf_ptr) {
          writeUint32(count_ptr, 0);
          writeUint32(buf_ptr, 0);
          return WASI_ERRNO.SUCCESS;
        },
        environ_get() {
          return WASI_ERRNO.SUCCESS;
        },
        args_sizes_get(argc_ptr, argv_buf_size_ptr) {
          writeUint32(argc_ptr, 0);
          writeUint32(argv_buf_size_ptr, 0);
          return WASI_ERRNO.SUCCESS;
        },
        args_get() {
          return WASI_ERRNO.SUCCESS;
        },
        fd_fdstat_get(fd, stat_ptr) {
          if (fd < 0 || fd > 2) {
            return WASI_ERRNO.BADF;
          }
          bytes().fill(0, stat_ptr, stat_ptr + 24);
          bytes()[stat_ptr] = WASI_FILETYPE_CHARACTER_DEVICE;
          return WASI_ERRNO.SUCCESS;
        },
        random_get(buf_ptr, buf_len) {
          const cryptoObject = globalThis.crypto;
          if (!cryptoObject || typeof cryptoObject.getRandomValues !== 'function') {
            return WASI_ERRNO.NOSYS;
          }
          let offset = 0;
          const target = bytes();
          while (offset < buf_len) {
            const chunkLength = Math.min(65536, buf_len - offset);
            cryptoObject.getRandomValues(target.subarray(buf_ptr + offset, buf_ptr + offset + chunkLength));
            offset += chunkLength;
          }
          return WASI_ERRNO.SUCCESS;
        },
        clock_time_get(clock_id, precision, time_ptr) {
          writeUint64(time_ptr, BigInt(Date.now()) * 1000000n);
          return WASI_ERRNO.SUCCESS;
        },
        sched_yield() {
          return WASI_ERRNO.SUCCESS;
        },
        poll_oneoff(in_ptr, out_ptr, nsubscriptions, nevents_ptr) {
          writeUint32(nevents_ptr, 0);
          return WASI_ERRNO.SUCCESS;
        },
        fd_prestat_get() {
          return WASI_ERRNO.BADF;
        },
        fd_prestat_dir_name() {
          return WASI_ERRNO.BADF;
        }
      },
      bindMemory(nextMemory) {
        memory = nextMemory;
      },
      drainStreams() {
        const streams = [];
        if (stdout) {
          streams.push({ name: 'stdout', text: stdout });
        }
        if (stderr) {
          streams.push({ name: 'stderr', text: stderr });
        }
        stdout = '';
        stderr = '';
        return streams;
      }
    };
  }

  constructor(instance, runtimeManifest, host, wasi) {
    this.instance = instance;
    this.runtimeManifest = runtimeManifest;
    this.exports = instance.exports;
    this.host = host;
    this.wasi = wasi;
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

  setInterruptBuffer(sharedBuffer) {
    this.host.setInterruptBuffer(sharedBuffer);
  }

  setStreamListener(listener) {
    this.host.setStreamListener(listener);
  }

  requestSoftInterrupt() {
    return this.host.requestSoftInterrupt();
  }

  clearInterrupt() {
    this.host.clearInterrupt();
  }

  kernelInfo() {
    return this.callJsonWithoutRequest('objc_kernel_info_json');
  }

  execute(code, cellId) {
    this.host.beginExecute();
    try {
      const reply = this.callJsonWithRequest('objc_kernel_execute_json', {
        code,
        cell_id: cellId || null
      });
      const streams = [...this.host.drainStreams(), ...this.wasi.drainStreams()];
      if (streams.length > 0) {
        reply.streams = streams;
      }
      return reply;
    } finally {
      this.host.clearInterrupt();
    }
  }

  complete(code, cursorPos) {
    return this.callJsonWithRequest('objc_kernel_complete_json', {
      code,
      cursor_pos: cursorPos
    });
  }

  inspect(code, cursorPos, detailLevel) {
    return this.callJsonWithRequest('objc_kernel_inspect_json', {
      code,
      cursor_pos: cursorPos,
      detail_level: detailLevel
    });
  }

  callJsonWithoutRequest(exportName) {
    const outPtrPtr = this.allocU32Slot();
    const outLenPtr = this.allocU32Slot();
    try {
      const status = this.exports[exportName](outPtrPtr, outLenPtr);
      if (status !== TRANSPORT_CODE.OK) {
        throw new ObjcKernelTransportError(status, exportName);
      }
      const responsePtr = this.readU32(outPtrPtr);
      const responseLen = this.readU32(outLenPtr);
      try {
        return JSON.parse(this.readUtf8(responsePtr, responseLen));
      } finally {
        this.exports.objc_kernel_free(responsePtr);
      }
    } finally {
      this.exports.objc_kernel_free(outPtrPtr);
      this.exports.objc_kernel_free(outLenPtr);
    }
  }

  callJsonWithRequest(exportName, payload) {
    const requestBytes = this.encoder.encode(JSON.stringify(payload));
    if (requestBytes.length > this.runtimeManifest.maxRequestBytes) {
      throw new ObjcKernelTransportError(TRANSPORT_CODE.REQUEST_TOO_LARGE, exportName);
    }

    const requestPtr = this.allocBytes(requestBytes.length);
    const outPtrPtr = this.allocU32Slot();
    const outLenPtr = this.allocU32Slot();
    try {
      this.writeBytes(requestPtr, requestBytes);
      const status = this.exports[exportName](
        requestPtr,
        requestBytes.length,
        outPtrPtr,
        outLenPtr
      );
      if (status !== TRANSPORT_CODE.OK) {
        throw new ObjcKernelTransportError(status, exportName);
      }

      const responsePtr = this.readU32(outPtrPtr);
      const responseLen = this.readU32(outLenPtr);
      if (responseLen > this.runtimeManifest.maxResponseBytes) {
        throw new ObjcKernelTransportError(TRANSPORT_CODE.RESPONSE_TOO_LARGE, exportName);
      }

      try {
        return JSON.parse(this.readUtf8(responsePtr, responseLen));
      } finally {
        this.exports.objc_kernel_free(responsePtr);
      }
    } finally {
      this.exports.objc_kernel_free(requestPtr);
      this.exports.objc_kernel_free(outPtrPtr);
      this.exports.objc_kernel_free(outLenPtr);
    }
  }

  allocBytes(length) {
    const ptr = this.exports.objc_kernel_alloc(length === 0 ? 1 : length);
    if (!ptr) {
      throw new ObjcKernelTransportError(TRANSPORT_CODE.OOM, 'objc_kernel_alloc');
    }
    return ptr;
  }

  allocU32Slot() {
    const ptr = this.allocBytes(4);
    this.writeU32(ptr, 0);
    return ptr;
  }

  writeBytes(ptr, bytes) {
    new Uint8Array(this.exports.memory.buffer).set(bytes, ptr);
  }

  writeU32(ptr, value) {
    new DataView(this.exports.memory.buffer).setUint32(ptr, value >>> 0, true);
  }

  readU32(ptr) {
    return new DataView(this.exports.memory.buffer).getUint32(ptr, true);
  }

  readUtf8(ptr, length) {
    return this.decoder.decode(new Uint8Array(this.exports.memory.buffer, ptr, length));
  }
}

function normalizeRuntimeManifest(runtimeManifestOrUrl) {
  if (typeof runtimeManifestOrUrl === 'string') {
    return {
      ...DEFAULT_RUNTIME_MANIFEST,
      kernelWasmUrl: runtimeManifestOrUrl
    };
  }

  return {
    ...DEFAULT_RUNTIME_MANIFEST,
    ...runtimeManifestOrUrl
  };
}

async function verifySha256(runtimeManifest, bytes) {
  if (!runtimeManifest.sha256) {
    return;
  }

  const digest = await crypto.subtle.digest('SHA-256', bytes);
  const actual = Array.from(new Uint8Array(digest), value =>
    value.toString(16).padStart(2, '0')
  ).join('');

  if (actual !== runtimeManifest.sha256) {
    throw new Error(
      `kernel.wasm SHA-256 mismatch: expected ${runtimeManifest.sha256}, got ${actual}`
    );
  }
}

function transportErrorMessage(code, context) {
  switch (code) {
    case TRANSPORT_CODE.INVALID_ARGUMENT:
      return `${context} failed: invalid transport arguments`;
    case TRANSPORT_CODE.REQUEST_TOO_LARGE:
      return `${context} failed: request exceeded the Objective-C WASM transport limit`;
    case TRANSPORT_CODE.RESPONSE_TOO_LARGE:
      return `${context} failed: response exceeded the Objective-C WASM transport limit`;
    case TRANSPORT_CODE.OOM:
      return `${context} failed: kernel transport ran out of memory`;
    case TRANSPORT_CODE.INTERNAL_ERROR:
      return `${context} failed: kernel transport reported an internal error`;
    default:
      return `${context} failed with unknown transport code ${code}`;
  }
}
