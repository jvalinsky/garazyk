// ES module worker entry point for the Objective-C WASM kernel.

import { ObjcWasmKernel } from "./wasm-loader.js";

function defaultRuntimeManifest() {
  try {
    const workerUrl = new URL(self.location.href);
    const workerDir = workerUrl.href.substring(0, workerUrl.href.lastIndexOf("/") + 1);
    return {
      kernelWasmUrl: new URL("kernel/kernel.wasm", workerDir).toString(),
      runtimeVersion: "auto",
      sha256: "",
      maxRequestBytes: 64 * 1024,
      maxResponseBytes: 1024 * 1024,
      softTimeoutMs: 30_000,
      hardTimeoutMs: 35_000,
    };
  } catch {
    return {
      kernelWasmUrl: "./kernel/kernel.wasm",
      runtimeVersion: "auto",
      sha256: "",
      maxRequestBytes: 64 * 1024,
      maxResponseBytes: 1024 * 1024,
      softTimeoutMs: 30_000,
      hardTimeoutMs: 35_000,
    };
  }
}

let runtimeManifest = defaultRuntimeManifest();
let kernelPromise = null;
let interruptBuffer = null;

function normalizeRuntimeManifest(nextManifest) {
  if (!nextManifest || typeof nextManifest !== "object") {
    return runtimeManifest;
  }

  return {
    ...runtimeManifest,
    ...nextManifest,
  };
}

function resetKernel(nextManifest = null, nextInterruptBuffer = null) {
  if (nextManifest) {
    runtimeManifest = normalizeRuntimeManifest(nextManifest);
  }
  if (nextInterruptBuffer !== undefined) {
    interruptBuffer = nextInterruptBuffer;
  }
  kernelPromise = null;
}

function postReply(id, generation, type, content) {
  self.postMessage({
    id,
    generation,
    type,
    content,
  });
}

function getKernel(activeId, activeGeneration) {
  if (!kernelPromise) {
    kernelPromise = ObjcWasmKernel.create(runtimeManifest, {
      onStream(stream) {
        postReply(activeId, activeGeneration, "stream", stream);
      },
    }).then((kernel) => {
      kernel.setInterruptBuffer(interruptBuffer);
      return kernel;
    }).catch((error) => {
      kernelPromise = null;
      throw error;
    });
  }
  return kernelPromise;
}

self.onmessage = async (event) => {
  const {
    id,
    generation = 0,
    type,
    code = "",
    cellId = null,
    cursorPos = 0,
    detailLevel = 0,
    runtimeManifest: explicitRuntimeManifest,
    interruptBuffer: explicitInterruptBuffer,
  } = event.data || {};

  if (explicitRuntimeManifest) {
    runtimeManifest = normalizeRuntimeManifest(explicitRuntimeManifest);
  }
  if (explicitInterruptBuffer !== undefined) {
    interruptBuffer = explicitInterruptBuffer;
  }

  try {
    if (type === "reset_request") {
      resetKernel(explicitRuntimeManifest || null, explicitInterruptBuffer);
      postReply(id, generation, "reset_reply", { status: "ok" });
      return;
    }

    console.log(`[Worker] Received ${type}, getting kernel...`);
    const kernel = await getKernel(id, generation);
    console.log(`[Worker] Kernel instantiated successfully!`);
    kernel.setInterruptBuffer(interruptBuffer);
    kernel.setStreamListener((stream) => {
      postReply(id, generation, "stream", stream);
    });

    if (type === "kernel_info_request") {
      postReply(id, generation, "kernel_info_reply", kernel.kernelInfo());
      return;
    }

    if (type === "execute_request") {
      const reply = await kernel.execute(code, cellId);
      for (const stream of reply.streams || []) {
        postReply(id, generation, "stream", stream);
      }
      postReply(id, generation, "execute_reply", {
        status: reply.status,
        execution_count: reply.execution_count,
        data: reply.data || {},
        metadata: reply.metadata || {},
        ename: reply.ename,
        evalue: reply.evalue,
        traceback: reply.traceback || [],
      });
      return;
    }

    if (type === "complete_request") {
      postReply(id, generation, "complete_reply", kernel.complete(code, cursorPos));
      return;
    }

    if (type === "inspect_request") {
      postReply(id, generation, "inspect_reply", kernel.inspect(code, cursorPos, detailLevel));
      return;
    }

    postReply(id, generation, "error", {
      ename: "UnknownMessage",
      evalue: `Unknown worker message type: ${type}`,
      traceback: [],
    });
  } catch (error) {
    console.error("[Worker] CAUGHT ERROR:", error);
    if (
      error &&
      (error.name === "WasiProcExitError" ||
        error.name === "RuntimeError" ||
        error.name === "CompileError")
    ) {
      resetKernel();
    }

    postReply(id, generation, "error", {
      ename: error && error.name ? error.name : "ObjcKernelError",
      evalue: error && error.message ? error.message : String(error),
      traceback: [],
    });
  }
};
