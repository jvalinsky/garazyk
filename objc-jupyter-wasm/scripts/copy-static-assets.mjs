import { access, copyFile, mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

function argValue(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : null;
}

async function exists(filePath) {
  try {
    await access(filePath);
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

async function copyIfPresent(source, destination) {
  if (!(await exists(source))) {
    return false;
  }
  await mkdir(path.dirname(destination), { recursive: true });
  await copyFile(source, destination);
  return true;
}

const outputDir = path.resolve(
  projectRoot,
  argValue('--out') ||
    process.env.OBJC_JUPYTER_LABEXTENSION_STATIC ||
    'objc_jupyter_wasm/labextension/static'
);

const kernelWasm = await resolveArtifact(
  'kernel-wasm',
  argValue('--kernel-wasm') || process.env.KERNEL_WASM,
  [
    'kernel/kernel.wasm',
    'jupyterlite/kernel/kernel.wasm',
    'result/wasm/kernel.wasm'
  ]
);

await mkdir(path.join(outputDir, 'kernel'), { recursive: true });
await mkdir(path.join(outputDir, 'js'), { recursive: true });

await copyFile(kernelWasm, path.join(outputDir, 'kernel/kernel.wasm'));

const workerSource =
  (await exists(path.join(projectRoot, 'lib/js/objc-worker.js')))
    ? path.join(projectRoot, 'lib/js/objc-worker.js')
    : path.join(projectRoot, 'js/objc-worker.js');
const loaderSource =
  (await exists(path.join(projectRoot, 'lib/js/wasm-loader.js')))
    ? path.join(projectRoot, 'lib/js/wasm-loader.js')
    : path.join(projectRoot, 'js/wasm-loader.js');

await copyFile(workerSource, path.join(outputDir, 'js/objc-worker.js'));
await copyFile(loaderSource, path.join(outputDir, 'js/wasm-loader.js'));

const copiedKernelJs = await copyIfPresent(
  path.join(projectRoot, 'jupyterlite/kernel.js'),
  path.join(outputDir, 'kernel.js')
);

await writeFile(
  path.join(outputDir, 'asset-manifest.json'),
  JSON.stringify(
    {
      kernelWasm: 'kernel/kernel.wasm',
      worker: 'js/objc-worker.js',
      loader: 'js/wasm-loader.js',
      staticDemoKernel: copiedKernelJs ? 'kernel.js' : null
    },
    null,
    2
  )
);

console.log(`objc-jupyter-wasm static assets copied to ${outputDir}`);
