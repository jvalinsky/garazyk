import { copyFile, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

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
const libobjc2Wasm = await resolveArtifact(
  'libobjc2-wasm',
  argValue('--libobjc2-wasm') || process.env.LIBOBJC2_WASM,
  [
    'compiler/libobjc2.wasm',
    'jupyterlite/kernel/libobjc2.wasm',
    'result/wasm/libobjc2.wasm'
  ]
);

await rm(outputDir, { recursive: true, force: true });
await mkdir(path.join(outputDir, 'js'), { recursive: true });
await mkdir(path.join(outputDir, 'kernel'), { recursive: true });
await mkdir(path.join(outputDir, 'files/demo'), { recursive: true });
await mkdir(path.join(outputDir, 'kernelspecs/objective-c'), { recursive: true });

await copyFile(path.join(projectRoot, 'tests/browser-smoke.html'), path.join(outputDir, 'index.html'));
await copyFile(
  path.join(projectRoot, 'tests/browser-smoke-page.mjs'),
  path.join(outputDir, 'browser-smoke-page.mjs')
);
await copyFile(path.join(projectRoot, 'js/objc-worker.js'), path.join(outputDir, 'js/objc-worker.js'));
await copyFile(path.join(projectRoot, 'js/wasm-loader.js'), path.join(outputDir, 'js/wasm-loader.js'));
await copyFile(kernelWasm, path.join(outputDir, 'kernel/kernel.wasm'));
await copyFile(libobjc2Wasm, path.join(outputDir, 'kernel/libobjc2.wasm'));
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
