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

function runtimeManifestUrlFromModule(moduleUrl: string): string {
  const url = new URL(moduleUrl);
  url.search = '';
  url.hash = '';
  url.pathname = url.pathname.replace(/[^/]+$/, 'runtime-manifest.json');
  return url.toString();
}

async function getRuntimeState(): Promise<RuntimeState> {
  if (!runtimeStatePromise) {
    const runtimeManifestUrl = runtimeManifestUrlFromModule(import.meta.url);
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
          const runtimeManifestUrl = runtimeManifestUrlFromModule(import.meta.url);
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
