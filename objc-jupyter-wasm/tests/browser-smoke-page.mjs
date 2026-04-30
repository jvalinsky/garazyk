const submittedCode = 'NSLog(@"hello browser smoke");';
const runtimeManifestUrl = new URL('./runtime-manifest.json', import.meta.url).toString();
const worker = new Worker(new URL('./js/objc-worker.js', import.meta.url), {
  type: 'module'
});

const pending = new Map();
let nextMessageId = 1;
const streams = [];
let runtimeManifest = null;

async function loadRuntimeManifest() {
  const response = await fetch(runtimeManifestUrl, { cache: 'no-store' });
  if (!response.ok) {
    throw new Error(`Failed to fetch runtime manifest: ${response.status}`);
  }

  const manifest = await response.json();
  return {
    ...manifest,
    kernelWasmUrl: new URL(manifest.kernelWasmUrl, runtimeManifestUrl).toString()
  };
}

function setText(testId, value) {
  document.querySelector(`[data-testid="${testId}"]`).textContent = value;
}

function request(type, payload, expectedType) {
  const id = nextMessageId++;
  return new Promise((resolve, reject) => {
    pending.set(id, {
      expectedType,
      resolve,
      reject
    });
    worker.postMessage({
      id,
      type,
      runtimeManifest,
      ...payload
    });
  });
}

worker.onmessage = event => {
  const { id, type, content } = event.data || {};

  if (type === 'stream') {
    streams.push(content);
    setText('stream-output', streams.map(stream => stream.text).join(''));
    return;
  }

  const waiter = pending.get(id);
  if (!waiter) {
    return;
  }

  if (type === 'error') {
    pending.delete(id);
    waiter.reject(new Error(content?.evalue || 'Objective-C worker error'));
    return;
  }

  if (type !== waiter.expectedType) {
    pending.delete(id);
    waiter.reject(new Error(`Expected ${waiter.expectedType}, got ${type}`));
    return;
  }

  pending.delete(id);
  waiter.resolve(content);
};

try {
  runtimeManifest = await loadRuntimeManifest();
  const kernelSpec = {
    name: 'objective-c',
    display_name: 'Objective-C',
    language: 'objective-c'
  };
  setText('kernel-spec', kernelSpec.display_name);

  const info = await request('kernel_info_request', {}, 'kernel_info_reply');
  setText('kernel-info-status', info.language_info?.name === 'objective-c' ? 'ok' : 'error');

  const execute = await request(
    'execute_request',
    {
      code: submittedCode,
      cellId: 'browser-smoke-cell'
    },
    'execute_reply'
  );
  setText('execute-status', execute.status);
  setText('result-output', execute.data?.['text/plain'] || '');

  window.__objcSmokeResult = {
    kernelSpec,
    runtimeManifest,
    runtimeManifestUrl,
    info,
    execute,
    streams,
    submittedCode
  };
  document.body.dataset.smokeStatus = 'passed';
  window.dispatchEvent(new CustomEvent('objc-smoke-complete'));
} catch (error) {
  document.body.dataset.smokeStatus = 'failed';
  window.__objcSmokeError = String(error?.stack || error);
  setText('execute-status', 'error');
  setText('result-output', window.__objcSmokeError);
  window.dispatchEvent(new CustomEvent('objc-smoke-complete'));
}
