export type TransportCode = 0 | 1 | 2 | 3 | 4 | 5;

export const TRANSPORT_CODE = {
  OK: 0,
  INVALID_ARGUMENT: 1,
  REQUEST_TOO_LARGE: 2,
  RESPONSE_TOO_LARGE: 3,
  OOM: 4,
  INTERNAL_ERROR: 5,
} as const;

export type RuntimeManifest = {
  kernelWasmUrl: string;
  runtimeVersion: string;
  sha256: string;
  maxRequestBytes: number;
  maxResponseBytes: number;
  softTimeoutMs: number;
  hardTimeoutMs: number;
};

export type CompileMode = "default" | "force-rebuild";

export type CompileDiagnostic = {
  severity: "error" | "warning" | "note";
  message: string;
  line: number;
  column: number;
  endLine: number;
  endColumn: number;
  code?: string;
  file?: string;
};

export type CompileRequest = {
  source: string;
  sessionId: string;
  cellId: string;
  workingDirectory: string;
  contextHash: string;
  sdkVersion: string;
  abiTarget: "wasm32-unknown-emscripten";
  compileMode: CompileMode;
};

export type CompileSuccessResponse = {
  status: "ok";
  cacheKey: string;
  artifactUrl: string;
  artifactSha256: string;
  runSymbol: string;
  sourceMapUrl: string | null;
  debugMapUrl: string | null;
  diagnostics: CompileDiagnostic[];
};

export type CompileErrorResponse = {
  status: "error";
  diagnostics: CompileDiagnostic[];
};

export type CompileResponse = CompileSuccessResponse | CompileErrorResponse;

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

export function assertRuntimeManifest(value: unknown): asserts value is RuntimeManifest {
  if (!isObject(value)) {
    throw new Error("Runtime manifest must be an object");
  }

  for (const key of ["kernelWasmUrl", "runtimeVersion", "sha256"]) {
    if (typeof value[key] !== "string" || value[key] === "") {
      throw new Error(`Runtime manifest field ${key} must be a non-empty string`);
    }
  }

  for (const key of ["maxRequestBytes", "maxResponseBytes", "softTimeoutMs", "hardTimeoutMs"]) {
    if (typeof value[key] !== "number" || !Number.isFinite(value[key]) || value[key] <= 0) {
      throw new Error(`Runtime manifest field ${key} must be a positive number`);
    }
  }
}

export async function fetchRuntimeManifest(manifestUrl: string): Promise<RuntimeManifest> {
  const response = await fetch(manifestUrl, { cache: "no-store" });
  if (!response.ok) {
    throw new Error(`Failed to fetch runtime manifest ${manifestUrl}: ${response.status}`);
  }

  const manifest = await response.json();
  assertRuntimeManifest(manifest);

  return {
    ...manifest,
    kernelWasmUrl: new URL(manifest.kernelWasmUrl, manifestUrl).toString(),
  };
}

export async function clearRuntimeCache(manifestUrl: string): Promise<number> {
  let removed = 0;
  const urls = new Set<string>([manifestUrl]);

  try {
    const manifest = await fetchRuntimeManifest(manifestUrl);
    urls.add(manifest.kernelWasmUrl);
    urls.add(new URL("./kernel/kernel.wasm", manifestUrl).toString());
  } catch {
    urls.add(new URL("./kernel/kernel.wasm", manifestUrl).toString());
  }

  if (typeof caches === "undefined") {
    return 0;
  }

  for (const cacheName of await caches.keys()) {
    const cache = await caches.open(cacheName);
    for (const url of urls) {
      if (await cache.delete(url, { ignoreSearch: true })) {
        removed++;
      }
    }
  }

  return removed;
}

export function transportErrorMessage(code: TransportCode, context: string): string {
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
