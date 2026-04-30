import { createHash } from 'node:crypto';
import { copyFile, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DEFAULT_RUNTIME_MANIFEST = {
  maxRequestBytes: 64 * 1024,
  maxResponseBytes: 1024 * 1024,
  softTimeoutMs: 30_000,
  hardTimeoutMs: 35_000
};

function argValue(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : null;
}

async function exists(filePath) {
  try {
    await readFile(filePath);
    return true;
  } catch {
    return false;
  }
}

async function resolveArtifact(label, explicitPath, candidates) {
  const paths = explicitPath ? [explicitPath, ...candidates] : candidates;
  for (const candidate of paths) {
    if (!candidate) {
      continue;
    }
    const resolved = path.resolve(projectRoot, candidate);
    if (await exists(resolved)) {
      return resolved;
    }
  }
  throw new Error(`Could not find ${label}. Build the WASM packages first or pass --${label}.`);
}

async function writeRuntimeAssets(kernelWasmPath, outputPath) {
  const bytes = await readFile(kernelWasmPath);
  const sha256 = createHash('sha256').update(bytes).digest('hex');
  const hashedKernelRelativePath = `./kernel/kernel.${sha256}.wasm`;
  const stableKernelRelativePath = './kernel/kernel.wasm';
  const runtimeManifest = {
    kernelWasmUrl: hashedKernelRelativePath,
    runtimeVersion: `sha256-${sha256.slice(0, 12)}`,
    sha256,
    ...DEFAULT_RUNTIME_MANIFEST
  };

  await mkdir(path.join(outputPath, 'kernel'), { recursive: true });
  await writeFile(path.join(outputPath, hashedKernelRelativePath), bytes);
  await writeFile(path.join(outputPath, stableKernelRelativePath), bytes);
  await writeFile(
    path.join(outputPath, 'runtime-manifest.json'),
    JSON.stringify(runtimeManifest, null, 2)
  );
  await writeFile(
    path.join(outputPath, 'asset-manifest.json'),
    JSON.stringify(
      {
        runtimeManifest: './runtime-manifest.json',
        kernelWasm: hashedKernelRelativePath,
        stableKernelWasm: stableKernelRelativePath,
        assetOwnership:
          'smoke site owns runtime-manifest.json plus kernel WASM assets; worker and loader remain raw source modules'
      },
      null,
      2
    )
  );
}

const outputDir = path.resolve(projectRoot, argValue('--out') || 'dist/jupyterlite-smoke');
const kernelWasm = await resolveArtifact(
  'kernel-wasm',
  argValue('--kernel-wasm') || process.env.KERNEL_WASM,
  [
    'kernel/kernel.wasm',
    'jupyterlite/kernel/kernel.wasm',
    'result/wasm/kernel.wasm'
  ]
);

await rm(outputDir, { recursive: true, force: true });
await mkdir(path.join(outputDir, 'js'), { recursive: true });
await mkdir(path.join(outputDir, 'files/demo'), { recursive: true });
await mkdir(path.join(outputDir, 'kernelspecs/objective-c'), { recursive: true });

await copyFile(path.join(projectRoot, 'tests/browser-smoke.html'), path.join(outputDir, 'index.html'));
await copyFile(
  path.join(projectRoot, 'tests/browser-smoke-page.mjs'),
  path.join(outputDir, 'browser-smoke-page.mjs')
);
await copyFile(path.join(projectRoot, 'js/objc-worker.js'), path.join(outputDir, 'js/objc-worker.js'));
await copyFile(path.join(projectRoot, 'js/wasm-loader.js'), path.join(outputDir, 'js/wasm-loader.js'));
await writeRuntimeAssets(kernelWasm, outputDir);
await copyFile(path.join(projectRoot, 'demo/hello.ipynb'), path.join(outputDir, 'files/demo/hello.ipynb'));

const kernelSpec = {
  display_name: 'Objective-C',
  language: 'objective-c',
  argv: [],
  env: {},
  interrupt_mode: 'message'
};

await writeFile(
  path.join(outputDir, 'kernelspecs/objective-c/kernel.json'),
  JSON.stringify(kernelSpec, null, 2)
);
await writeFile(
  path.join(outputDir, 'jupyter-lite.json'),
  JSON.stringify(
    {
      'jupyter-config-data': {
        kernelspecs: {
          'objective-c': {
            name: 'objective-c',
            spec: kernelSpec,
            resources: {}
          }
        }
      }
    },
    null,
    2
  )
);

console.log(`objc-jupyter-wasm browser smoke site built at ${outputDir}`);
