import {
  CompileRequest,
  CompileResponse,
  CompileSuccessResponse
} from './runtime-support';

function assertDiagnosticList(value: unknown): void {
  if (!Array.isArray(value)) {
    throw new Error('Compile diagnostics must be an array');
  }
}

export function assertCompileResponse(value: unknown): asserts value is CompileResponse {
  if (typeof value !== 'object' || value === null) {
    throw new Error('Compile response must be an object');
  }

  const response = value as Record<string, unknown>;
  if (response.status === 'ok') {
    for (const key of ['cacheKey', 'artifactUrl', 'artifactSha256', 'runSymbol']) {
      if (typeof response[key] !== 'string' || response[key] === '') {
        throw new Error(`Compile success field ${key} must be a non-empty string`);
      }
    }
    assertDiagnosticList(response.diagnostics);
    return;
  }

  if (response.status === 'error') {
    assertDiagnosticList(response.diagnostics);
    return;
  }

  throw new Error('Compile response status must be "ok" or "error"');
}

export async function compileObjectiveC(
  request: CompileRequest,
  endpoint: string = '/api/objc-wasm/compile'
): Promise<CompileResponse> {
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'content-type': 'application/json'
    },
    body: JSON.stringify(request)
  });

  if (!response.ok) {
    throw new Error(`Compile service request failed: ${response.status}`);
  }

  const payload = await response.json();
  assertCompileResponse(payload);
  return payload;
}

export function isCompileCacheHit(response: CompileResponse): response is CompileSuccessResponse {
  return response.status === 'ok' && response.cacheKey !== '';
}
