import { JupyterFrontEnd, JupyterFrontEndPlugin } from '@jupyterlab/application';
import { IKernel, IKernelSpecs } from '@jupyterlite/kernel';

import { ObjcKernel } from '../js/objc-kernel';
import { clearRuntimeCache, fetchRuntimeManifest } from '../js/runtime-support';
import type { RuntimeManifest } from '../js/runtime-support';

type RuntimeState = {
  runtimeManifest: RuntimeManifest;
  runtimeManifestUrl: string;
};

const CLEAR_RUNTIME_CACHE_COMMAND = 'objc-jupyter-wasm:clear-runtime-cache';

let runtimeStatePromise: Promise<RuntimeState> | null = null;

/**
 * Derive the runtime manifest URL from the extension's static directory.
 *
 * Webpack 5 replaces `import.meta.url` with the build-time file path
 * (e.g. file:///Users/.../lib/src/index.js), which is not a valid
 * fetch target in a browser. Instead, we find the remoteEntry script
 * element at runtime and resolve relative to its directory.
 */
function getExtensionStaticUrl(): string {
  // Look for the remoteEntry script tag that Module Federation loaded
  const scripts = document.querySelectorAll('script[src*="remoteEntry"]');
  for (const script of scripts) {
    const src = script.getAttribute('src');
    if (src && src.includes('objc-jupyter-wasm')) {
      // src is like "extensions/objc-jupyter-wasm/static/remoteEntry.*.js"
      // or an absolute URL — resolve to get the full URL
      const url = new URL(src, document.baseURI);
      // Return the directory (strip the filename)
      return url.toString().replace(/[^/]+$/, '');
    }
  }
  throw new Error('objc-jupyter-wasm: cannot determine extension static URL — remoteEntry script not found');
}

function runtimeManifestUrlFromStaticUrl(staticUrl: string): string {
  return staticUrl + 'runtime-manifest.json';
}

async function getRuntimeState(): Promise<RuntimeState> {
  if (!runtimeStatePromise) {
    const staticUrl = getExtensionStaticUrl();
    const runtimeManifestUrl = runtimeManifestUrlFromStaticUrl(staticUrl);
    runtimeStatePromise = fetchRuntimeManifest(runtimeManifestUrl)
      .then(runtimeManifest => ({
        runtimeManifest,
        runtimeManifestUrl
      }))
      .catch(error => {
        runtimeStatePromise = null;
        throw error;
      });
  }

  return runtimeStatePromise;
}

const plugin: JupyterFrontEndPlugin<void> = {
  id: 'objc-jupyter-wasm:kernel',
  autoStart: true,
  requires: [IKernelSpecs],
  activate: (app: JupyterFrontEnd, kernelspecs: IKernelSpecs) => {
    if (!app.commands.hasCommand(CLEAR_RUNTIME_CACHE_COMMAND)) {
      app.commands.addCommand(CLEAR_RUNTIME_CACHE_COMMAND, {
        label: 'Clear Objective-C WASM Runtime Cache',
        execute: async () => {
          const staticUrl = getExtensionStaticUrl();
          const runtimeManifestUrl = runtimeManifestUrlFromStaticUrl(staticUrl);
          const removed = await clearRuntimeCache(runtimeManifestUrl);
          runtimeStatePromise = null;
          console.info(
            `objc-jupyter-wasm cleared ${removed} cached runtime asset${removed === 1 ? '' : 's'}`
          );
          return removed;
        }
      });
    }

    kernelspecs.register({
      spec: {
        name: 'objective-c',
        display_name: 'Objective-C',
        language: 'objective-c',
        argv: [],
        resources: {}
      },
      create: async (options: IKernel.IOptions): Promise<IKernel> => {
        const { runtimeManifest, runtimeManifestUrl } = await getRuntimeState();
        return new ObjcKernel(options, {
          runtimeManifest,
          runtimeManifestUrl
        }) as unknown as IKernel;
      }
    });
  }
};

export default plugin;
