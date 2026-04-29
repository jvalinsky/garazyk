import { BaseKernel } from '@jupyterlite/kernel';

type PendingRequest = {
  resolve: (value: any) => void;
  reject: (reason: Error) => void;
  expectedType: string;
};

export class ObjcKernel extends BaseKernel {
  private _worker: Worker;
  private _pending = new Map<number, PendingRequest>();
  private _nextMessageId = 1;

  constructor(options: any) {
    super(options);
    this._worker = new Worker(new URL('./objc-worker.js', import.meta.url), {
      type: 'module'
    });
    this._worker.onmessage = event => this._onWorkerMessage(event.data);
  }

  async kernelInfoRequest(): Promise<any> {
    return this._request('kernel_info_request', {}, 'kernel_info_reply');
  }

  async executeRequest(content: { code: string; cell_id?: string }): Promise<any> {
    const reply = await this._request(
      'execute_request',
      {
        code: content.code,
        cellId: content.cell_id || null
      },
      'execute_reply'
    );

    if (reply.status === 'ok') {
      this.publishExecuteResult(
        {
          execution_count: reply.execution_count,
          data: reply.data || {},
          metadata: reply.metadata || {}
        },
        this.parentHeader
      );

      return {
        status: 'ok',
        execution_count: reply.execution_count,
        payload: [],
        user_expressions: {}
      };
    }

    const error = {
      ename: reply.ename || 'ObjcKernelError',
      evalue: reply.evalue || 'Objective-C kernel execution failed',
      traceback: reply.traceback || []
    };
    this.publishExecuteError(error, this.parentHeader);
    return {
      status: 'error',
      ...error
    };
  }

  async completeRequest(content: { code: string; cursor_pos: number }): Promise<any> {
    return this._request(
      'complete_request',
      {
        code: content.code,
        cursorPos: content.cursor_pos
      },
      'complete_reply'
    );
  }

  async inspectRequest(content: {
    code: string;
    cursor_pos: number;
    detail_level: number;
  }): Promise<any> {
    return this._request(
      'inspect_request',
      {
        code: content.code,
        cursorPos: content.cursor_pos,
        detailLevel: content.detail_level
      },
      'inspect_reply'
    );
  }

  async isCompleteRequest(content: { code: string }): Promise<any> {
    const trimmed = content.code.trimEnd();
    return {
      status: trimmed.endsWith(';') || trimmed.endsWith('@end') ? 'complete' : 'incomplete',
      indent: ''
    };
  }

  async commInfoRequest(_content: any): Promise<any> {
    return {
      status: 'ok',
      comms: {}
    };
  }

  inputReply(_content: any): void {
    // Frontend input is not used by the browser smoke kernel.
  }

  async commOpen(_msg: any): Promise<void> {
    // Comms are intentionally unsupported in the smoke kernel.
  }

  async commMsg(_msg: any): Promise<void> {
    // Comms are intentionally unsupported in the smoke kernel.
  }

  async commClose(_msg: any): Promise<void> {
    // Comms are intentionally unsupported in the smoke kernel.
  }

  dispose(): void {
    if (this.isDisposed) {
      return;
    }
    this._worker.terminate();
    super.dispose();
  }

  private _request(type: string, payload: Record<string, unknown>, expectedType: string): Promise<any> {
    const id = this._nextMessageId++;
    const wasmUrl = './kernel/kernel.wasm';

    return new Promise((resolve, reject) => {
      this._pending.set(id, {
        resolve,
        reject,
        expectedType
      });
      this._worker.postMessage({
        id,
        type,
        wasmUrl,
        ...payload
      });
    });
  }

  private _onWorkerMessage(message: any): void {
    const { id, type, content } = message || {};

    if (type === 'stream') {
      this.stream(content, this.parentHeader);
      return;
    }

    const pending = this._pending.get(id);
    if (!pending) {
      return;
    }

    if (type === 'error') {
      this._pending.delete(id);
      pending.reject(new Error(content?.evalue || 'Objective-C worker error'));
      return;
    }

    if (type !== pending.expectedType) {
      this._pending.delete(id);
      pending.reject(new Error(`Expected ${pending.expectedType}, got ${type}`));
      return;
    }

    this._pending.delete(id);
    pending.resolve(content);
  }
}
