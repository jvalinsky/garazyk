// ES module worker entry point for the Objective-C WASM kernel.

import { ObjcWasmKernel } from './wasm-loader.js';

let kernelPromise = null;

function getKernel(wasmUrl) {
  if (!kernelPromise) {
    kernelPromise = ObjcWasmKernel.create(wasmUrl || './kernel/kernel.wasm');
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
    wasmUrl,
    code = '',
    cellId = null,
    cursorPos = 0,
    detailLevel = 0
  } = event.data || {};

  try {
    const kernel = await getKernel(wasmUrl);

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
        metadata: reply.metadata || {}
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
