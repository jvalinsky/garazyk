// Static-demo module wrapper for objc-jupyter-wasm.
//
// Production JupyterLite registration lives in src/index.ts. This module keeps
// the old demo entry point usable when serving objc-jupyter-wasm/ directly.

import { ObjcWasmKernel } from '../js/wasm-loader.js';

let kernelPromise = null;

async function kernel() {
  if (!kernelPromise) {
    kernelPromise = ObjcWasmKernel.create('./kernel/kernel.wasm');
  }
  return kernelPromise;
}

globalThis.objcJupyterWasm = {
  async kernelInfo() {
    return (await kernel()).kernelInfo();
  },

  async execute(code, cellId = 'demo-cell') {
    return (await kernel()).execute(code, cellId);
  },

  async complete(code, cursorPos = code.length) {
    return (await kernel()).complete(code, cursorPos);
  },

  async inspect(code, cursorPos = code.length, detailLevel = 0) {
    return (await kernel()).inspect(code, cursorPos, detailLevel);
  }
};
