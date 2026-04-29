import { JupyterFrontEnd, JupyterFrontEndPlugin } from '@jupyterlab/application';
import { IKernel, IKernelSpecs } from '@jupyterlite/kernel';
import { ObjcKernel } from '../js/objc-kernel';

const plugin: JupyterFrontEndPlugin<void> = {
  id: 'objc-jupyter-wasm:kernel',
  autoStart: true,
  requires: [IKernelSpecs],
  activate: (_app: JupyterFrontEnd, kernelspecs: IKernelSpecs) => {
    kernelspecs.register({
      spec: {
        name: 'objective-c',
        display_name: 'Objective-C',
        language: 'objective-c',
        argv: [],
        resources: {}
      },
      create: async (options: IKernel.IOptions): Promise<IKernel> => {
        return new ObjcKernel(options) as unknown as IKernel;
      }
    });
  }
};

export default plugin;
