// Static-demo module wrapper for objc-jupyter-wasm.
//
// Production JupyterLite registration lives in src/index.ts. This module keeps
// the old demo entry point usable when serving objc-jupyter-wasm/ directly.

import { ObjcWasmKernel } from '../js/wasm-loader.js';

let kernelPromise = null;

const DEFAULT_RUNTIME_MANIFEST = {
  kernelWasmUrl: new URL('./kernel/kernel.wasm', import.meta.url).toString(),
  runtimeVersion: 'demo-fallback',
  sha256: '',
  maxRequestBytes: 64 * 1024,
  maxResponseBytes: 1024 * 1024,
  softTimeoutMs: 30_000,
  hardTimeoutMs: 35_000
};

async function loadRuntimeManifest() {
  const manifestUrl = new URL('./runtime-manifest.json', import.meta.url).toString();

  try {
    const response = await fetch(manifestUrl, { cache: 'no-store' });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    const manifest = await response.json();
    return {
      ...DEFAULT_RUNTIME_MANIFEST,
      ...manifest,
      kernelWasmUrl: new URL(manifest.kernelWasmUrl, manifestUrl).toString()
    };
  } catch {
    return DEFAULT_RUNTIME_MANIFEST;
  }
}

async function kernel() {
  if (!kernelPromise) {
    kernelPromise = loadRuntimeManifest()
      .then(runtimeManifest => ObjcWasmKernel.create(runtimeManifest))
      .catch(error => {
        kernelPromise = null;
        throw error;
      });
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
