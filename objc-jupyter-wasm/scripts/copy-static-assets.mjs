import { createHash } from 'node:crypto';
import { access, mkdir, readFile, writeFile } from 'node:fs/promises';
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
        assetOwnership: 'webpack owns worker and loader chunks; this script copies runtime WASM only'
      },
      null,
      2
    )
  );
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

await mkdir(outputDir, { recursive: true });
await writeRuntimeAssets(kernelWasm, outputDir);

console.log(`objc-jupyter-wasm static assets copied to ${outputDir}`);
