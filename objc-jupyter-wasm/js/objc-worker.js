// ES module worker entry point for the Objective-C WASM kernel.

import { ObjcWasmKernel } from './wasm-loader.js';

/**
 * Resolve the WASM kernel URL relative to the worker's own location.
 *
 * In JupyterLite, the worker is loaded from the extension's static directory:
 *   <base>/extensions/objc-jupyter-wasm/static/js/objc-worker.js
 * The WASM files are at:
 *   <base>/extensions/objc-jupyter-wasm/static/kernel/kernel.wasm
 *
 * We use self.location.href (the Worker's runtime URL) instead of
 * import.meta.url, because webpack 5 replaces import.meta.url with the
 * build-time file path at compile time, which is wrong at runtime.
 * self.location.href is always the actual runtime URL of the worker script.
 */
function resolveWasmUrl() {
  try {
    const workerUrl = self.location.href;
    // In JupyterLite, the worker chunk is at:
    //   <base>/extensions/objc-jupyter-wasm/static/822.<hash>.js
    // The WASM file is at:
    //   <base>/extensions/objc-jupyter-wasm/static/kernel/kernel.wasm
    // Strip the filename to get the directory, then append the WASM path.
    const staticDir = workerUrl.substring(0, workerUrl.lastIndexOf('/'));
    return staticDir + '/kernel/kernel.wasm';
  } catch {
    return './kernel/kernel.wasm';
  }
}

const WASM_URL = resolveWasmUrl();

let kernelPromise = null;

function getKernel() {
  if (!kernelPromise) {
    kernelPromise = ObjcWasmKernel.create(WASM_URL);
  }
  return kernelPromise;
}

function postReply(id, type, content) {
  self.postMessage({
    id,
    type,
    content
  });
}

self.onmessage = async event => {
  const {
    id,
    type,
    code = '',
    cellId = null,
    cursorPos = 0,
    detailLevel = 0
  } = event.data || {};

  try {
    const kernel = await getKernel();

    if (type === 'kernel_info_request') {
      postReply(id, 'kernel_info_reply', kernel.kernelInfo());
      return;
    }

    if (type === 'execute_request') {
      const reply = kernel.execute(code, cellId);
      for (const stream of reply.streams || []) {
        postReply(id, 'stream', stream);
      }
      postReply(id, 'execute_reply', {
        status: reply.status,
        execution_count: reply.execution_count,
        data: reply.data || {},
        metadata: reply.metadata || {},
        ename: reply.ename,
        evalue: reply.evalue,
        traceback: reply.traceback || []
      });
      return;
    }

    if (type === 'complete_request') {
      postReply(id, 'complete_reply', kernel.complete(code, cursorPos));
      return;
    }

    if (type === 'inspect_request') {
      postReply(id, 'inspect_reply', kernel.inspect(code, cursorPos, detailLevel));
      return;
    }

    postReply(id, 'error', {
      ename: 'UnknownMessage',
      evalue: `Unknown worker message type: ${type}`,
      traceback: []
    });
  } catch (error) {
    postReply(id, 'error', {
      ename: error && error.name ? error.name : 'ObjcKernelError',
      evalue: error && error.message ? error.message : String(error),
      traceback: []
    });
  }
};
