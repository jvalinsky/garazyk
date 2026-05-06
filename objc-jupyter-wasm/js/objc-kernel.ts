import { BaseKernel } from '@jupyterlite/kernel';
import { KernelMessage } from '@jupyterlab/services';

import type { RuntimeManifest } from './runtime-support';

type PendingRequest = {
  resolve: (value: any) => void;
  reject: (reason: Error) => void;
  expectedType: string;
  timer: ReturnType<typeof setTimeout> | null;
  hardTimer: ReturnType<typeof setTimeout> | null;
  generation: number;
  parentHeader?: KernelMessage.IHeader<KernelMessage.MessageType>;
  silent: boolean;
  requestType: string;
  softInterrupted: boolean;
};

type ObjcKernelOptions = {
  runtimeManifest: RuntimeManifest;
  runtimeManifestUrl: string;
};

const READY_TIMEOUT_MS = 15_000;
const DEFAULT_TIMEOUT_MS = 5_000;

const FALLBACK_KERNEL_INFO: KernelMessage.IInfoReplyMsg['content'] = {
  status: 'ok',
  protocol_version: '5.3',
  implementation: 'objc-jupyter-wasm',
  implementation_version: '0.1.0',
  language_info: {
    name: 'objective-c',
    version: '2.2',
    mimetype: 'text/x-objective-c',
    file_extension: '.m',
    pygments_lexer: 'objective-c',
    codemirror_mode: 'clike'
  },
  help_links: [],
  banner: 'Objective-C WASM smoke kernel'
};

class KernelTimeoutError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'TimeoutError';
  }
}

export class ObjcKernel extends BaseKernel {
  private _worker: Worker;
  private _pending = new Map<number, PendingRequest>();
  private _nextMessageId = 1;
  private _workerGeneration = 0;
  private _ready: Promise<void>;
  private _infoReply: KernelMessage.IInfoReplyMsg['content'] | null = null;
  private _sendKernelMessage: (msg: KernelMessage.IMessage) => void;
  private _objcExecutionCount = 0;
  private _objcHistory: [number, number, string][] = [];
  private _runtimeManifest: RuntimeManifest;
  private _runtimeManifestUrl: string;
  private _interruptBuffer: SharedArrayBuffer | null = null;
  private _interruptView: Int32Array | null = null;

  constructor(options: any, kernelOptions: ObjcKernelOptions) {
    super(options);
    this._sendKernelMessage = options.sendMessage;
    this._runtimeManifest = kernelOptions.runtimeManifest;
    this._runtimeManifestUrl = kernelOptions.runtimeManifestUrl;

    if (
      typeof SharedArrayBuffer === 'function' &&
      globalThis.crossOriginIsolated === true
    ) {
      this._interruptBuffer = new SharedArrayBuffer(4);
      this._interruptView = new Int32Array(this._interruptBuffer);
    }

    this._worker = this._createWorker();
    this._ready = this._initializeWorker();
    this._ready.catch(() => undefined);
  }

  override get ready(): Promise<void> {
    return this._ready;
  }

  override get executionCount(): number {
    return this._objcExecutionCount;
  }

  override async handleMessage(msg: KernelMessage.IMessage): Promise<void> {
    const msgType = msg.header.msg_type;

    if (msgType === 'execute_request') {
      await this._handleExecute(msg as KernelMessage.IExecuteRequestMsg);
      return;
    }

    if (msgType === 'interrupt_request') {
      this._handleInterrupt(msg);
      return;
    }

    if (msgType === 'comm_info_request') {
      await this._handleCommInfo(msg as KernelMessage.ICommInfoRequestMsg);
      return;
    }

    if (msgType === 'history_request') {
      await this._handleHistory(msg as KernelMessage.IHistoryRequestMsg);
      return;
    }

    await super.handleMessage(msg);
  }

  async kernelInfoRequest(): Promise<any> {
    try {
      await this._ensureReady();
    } catch {
      return this._infoReply || FALLBACK_KERNEL_INFO;
    }
    return this._infoReply || FALLBACK_KERNEL_INFO;
  }

  async executeRequest(content: KernelMessage.IExecuteRequestMsg['content']): Promise<any> {
    const storeHistory = content.silent ? false : content.store_history !== false;
    const executionCount = storeHistory ? this._objcExecutionCount + 1 : this._objcExecutionCount;
    return this._executeContent(content, executionCount, this.parentHeader);
  }

  async completeRequest(content: { code: string; cursor_pos: number }): Promise<any> {
    try {
      await this._ensureReady();
      return await this._request(
        'complete_request',
        {
          code: content.code,
          cursorPos: content.cursor_pos
        },
        'complete_reply'
      );
    } catch {
      return { status: 'ok', matches: [], cursor_start: 0, cursor_end: 0, metadata: {} };
    }
  }

  async inspectRequest(content: {
    code: string;
    cursor_pos: number;
    detail_level: number;
  }): Promise<any> {
    try {
      await this._ensureReady();
      return await this._request(
        'inspect_request',
        {
          code: content.code,
          cursorPos: content.cursor_pos,
          detailLevel: content.detail_level
        },
        'inspect_reply'
      );
    } catch {
      return { status: 'ok', found: false, data: {}, metadata: {} };
    }
  }

  async isCompleteRequest(content: { code: string }): Promise<any> {
    return analyzeCompleteness(content.code);
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
    for (const pending of this._pending.values()) {
      clearPendingTimers(pending);
      pending.reject(new Error('Objective-C kernel disposed'));
    }
    this._pending.clear();
    this._worker.terminate();
    super.dispose();
  }

  private _createWorker(): Worker {
    const worker = new Worker(new URL('./objc-worker.js', import.meta.url), {
      type: 'module'
    });
    worker.onmessage = event => this._onWorkerMessage(event.data);
    worker.onerror = event => {
      event.preventDefault();
      this._restartWorker(new Error(event.message || 'Objective-C worker crashed'));
    };
    worker.onmessageerror = () => {
      this._restartWorker(new Error('Objective-C worker sent an invalid message'));
    };
    return worker;
  }

  private _initializeWorker(): Promise<void> {
    console.log(">>>>>>>>>>> _initializeWorker STARTING <<<<<<<<<<<");
    return this._request(
      'kernel_info_request',
      {},
      'kernel_info_reply',
      READY_TIMEOUT_MS
    ).then(info => {
      console.log(">>>>>>>>>>> _initializeWorker SUCCESS! <<<<<<<<<<<", info);
      this._infoReply = { ...FALLBACK_KERNEL_INFO, ...info };
    }).catch(err => {
      console.error(">>>>>>>>>>> _initializeWorker FAILED! <<<<<<<<<<<", err);
      throw err;
    });
  }

  private _restartWorker(reason: Error): void {
    this._workerGeneration++;
    this._resetInterruptFlag();

    for (const [id, pending] of this._pending) {
      clearPendingTimers(pending);
      pending.reject(reason);
      this._pending.delete(id);
    }

    try {
      this._worker.terminate();
    } catch {
      // Ignore termination races during fatal restarts.
    }

    this._worker = this._createWorker();
    this._ready = this._initializeWorker();
    this._ready.catch(() => undefined);
  }

  private async _ensureReady(): Promise<void> {
    try {
      await this._ready;
    } catch (error: any) {
      this._restartWorker(error instanceof Error ? error : new Error(String(error)));
      throw error;
    }
  }

  private async _handleExecute(msg: KernelMessage.IExecuteRequestMsg): Promise<void> {
    const content = msg.content;
    const silent = content.silent === true;
    const storeHistory = silent ? false : content.store_history !== false;
    let executionCount = this._objcExecutionCount;

    this._sendStatus(msg, 'busy');

    if (storeHistory) {
      this._objcExecutionCount++;
      executionCount = this._objcExecutionCount;
      this._objcHistory.push([0, 0, content.code]);
    }

    if (!silent) {
      this._sendExecuteInput(msg, executionCount);
    }

    try {
      const reply = await this._executeContent(content, executionCount, msg.header);
      this._sendExecuteReply(msg, reply);
    } finally {
      this._sendStatus(msg, 'idle');
    }
  }

  private async _executeContent(
    content: KernelMessage.IExecuteRequestMsg['content'],
    executionCount: number,
    parentHeader: KernelMessage.IHeader<KernelMessage.MessageType> | undefined
  ): Promise<KernelMessage.IExecuteReplyMsg['content']> {
    const silent = content.silent === true;
    const cellId = (content as { cell_id?: string }).cell_id || null;

    try {
      await this._ensureReady();
      const reply = await this._request(
        'execute_request',
        {
          code: content.code,
          cellId,
          silent,
          storeHistory: silent ? false : content.store_history !== false,
          allowStdin: content.allow_stdin === true
        },
        'execute_reply',
        this._runtimeManifest.hardTimeoutMs,
        {
          parentHeader,
          silent
        }
      );

      return this._normalizeExecuteReply(reply, executionCount, silent, parentHeader);
    } catch (err: any) {
      const error = {
        ename: err?.name || 'ObjcKernelError',
        evalue: err?.message || String(err),
        traceback: [] as string[]
      };

      if (!silent) {
        this.publishExecuteError(error, parentHeader);
      }

      return {
        status: 'error',
        execution_count: executionCount,
        ...error
      };
    }
  }

  private _normalizeExecuteReply(
    reply: any,
    executionCount: number,
    silent: boolean,
    parentHeader: KernelMessage.IHeader<KernelMessage.MessageType> | undefined
  ): KernelMessage.IExecuteReplyMsg['content'] {
    if (reply.status === 'ok') {
      const data = normalizeDisplayData(reply.data || {});

      if (!silent && hasDisplayData(data)) {
        this.publishExecuteResult(
          {
            execution_count: executionCount,
            data,
            metadata: reply.metadata || {}
          },
          parentHeader
        );
      }

      return {
        status: 'ok',
        execution_count: executionCount,
        payload: [],
        user_expressions: {}
      };
    }

    const error = {
      ename: reply.ename || 'ObjcKernelError',
      evalue: reply.evalue || 'Objective-C kernel execution failed',
      traceback: reply.traceback || []
    };

    /* Map ObjCException to a proper error name for display */
    if (reply.ename === 'ObjCException') {
      error.ename = 'ObjCException';
    }

    if (!silent) {
      this.publishExecuteError(error, parentHeader);
    }

    return {
      status: 'error',
      execution_count: executionCount,
      ...error
    };
  }

  private async _handleCommInfo(msg: KernelMessage.ICommInfoRequestMsg): Promise<void> {
    this._sendStatus(msg, 'busy');
    try {
      const message = KernelMessage.createMessage<KernelMessage.ICommInfoReplyMsg>({
        msgType: 'comm_info_reply',
        channel: 'shell',
        parentHeader: msg.header,
        session: msg.header.session,
        content: await this.commInfoRequest(msg.content)
      });
      this._sendKernelMessage(message);
    } finally {
      this._sendStatus(msg, 'idle');
    }
  }

  private async _handleHistory(msg: KernelMessage.IHistoryRequestMsg): Promise<void> {
    this._sendStatus(msg, 'busy');
    try {
      const message = KernelMessage.createMessage<KernelMessage.IHistoryReplyMsg>({
        msgType: 'history_reply',
        channel: 'shell',
        parentHeader: msg.header,
        session: msg.header.session,
        content: {
          status: 'ok',
          history: this._objcHistory as KernelMessage.IHistoryReply['history']
        }
      });
      this._sendKernelMessage(message);
    } finally {
      this._sendStatus(msg, 'idle');
    }
  }

  private _handleInterrupt(msg: KernelMessage.IMessage): void {
    /* Set the interrupt flag so the WASM interpreter checks it on
     * the next loop iteration or eval_ast re-entry.  The WASM
     * `should_interrupt` host import reads this flag via Atomics. */
    if (this._interruptView) {
      Atomics.store(this._interruptView, 0, 1);
    }

    /* Reply per the Jupyter protocol: interrupt_reply.
     * KernelMessage.createMessage has no overload for interrupt_reply
     * (@jupyterlab/services doesn't define IInterruptReplyMsg), so we
     * construct the message manually. */
    const reply: KernelMessage.IMessage = {
      header: {
        date: new Date().toISOString(),
        msg_id: `${msg.header.session}-${Date.now()}`,
        msg_type: 'interrupt_reply' as KernelMessage.ShellMessageType,
        session: msg.header.session,
        username: '',
        version: '5.3'
      },
      parent_header: msg.header,
      metadata: {},
      channel: 'shell',
      content: { status: 'ok' },
      buffers: []
    };
    this._sendKernelMessage(reply);
  }

  private _sendStatus(
    parent: KernelMessage.IMessage,
    executionState: KernelMessage.IStatusMsg['content']['execution_state']
  ): void {
    const message = KernelMessage.createMessage<KernelMessage.IStatusMsg>({
      msgType: 'status',
      session: parent.header.session,
      parentHeader: parent.header,
      channel: 'iopub',
      content: {
        execution_state: executionState
      }
    });
    this._sendKernelMessage(message);
  }

  private _sendExecuteInput(
    msg: KernelMessage.IExecuteRequestMsg,
    executionCount: number
  ): void {
    const message = KernelMessage.createMessage<KernelMessage.IExecuteInputMsg>({
      msgType: 'execute_input',
      parentHeader: msg.header,
      channel: 'iopub',
      session: msg.header.session,
      content: {
        code: msg.content.code,
        execution_count: executionCount
      }
    });
    this._sendKernelMessage(message);
  }

  private _sendExecuteReply(
    msg: KernelMessage.IExecuteRequestMsg,
    content: KernelMessage.IExecuteReplyMsg['content']
  ): void {
    const message = KernelMessage.createMessage<KernelMessage.IExecuteReplyMsg>({
      msgType: 'execute_reply',
      channel: 'shell',
      parentHeader: msg.header,
      session: msg.header.session,
      content
    });
    this._sendKernelMessage(message);
  }

  private _request(
    type: string,
    payload: Record<string, unknown>,
    expectedType: string,
    timeoutMs: number = DEFAULT_TIMEOUT_MS,
    options: {
      parentHeader?: KernelMessage.IHeader<KernelMessage.MessageType>;
      silent?: boolean;
    } = {}
  ): Promise<any> {
    const id = this._nextMessageId++;
    const generation = this._workerGeneration;
    const isExecute = type === 'execute_request';

    return new Promise((resolve, reject) => {
      if (this.isDisposed) {
        reject(new Error('Objective-C kernel disposed'));
        return;
      }

      this._resetInterruptFlag();

      const pending: PendingRequest = {
        resolve,
        reject,
        expectedType,
        timer: null,
        hardTimer: null,
        generation,
        parentHeader: options.parentHeader,
        silent: options.silent === true,
        requestType: type,
        softInterrupted: false
      };

      if (isExecute && this._interruptView) {
        pending.timer = setTimeout(() => {
          pending.softInterrupted = true;
          Atomics.store(this._interruptView as Int32Array, 0, 1);
        }, this._runtimeManifest.softTimeoutMs);

        pending.hardTimer = setTimeout(() => {
          this._pending.delete(id);
          const error = new KernelTimeoutError(
            `Execution exceeded ${this._runtimeManifest.hardTimeoutMs}ms; terminating the Objective-C worker`
          );
          reject(error);
          this._restartWorker(error);
        }, timeoutMs);
      } else if (isExecute) {
        pending.hardTimer = setTimeout(() => {
          this._pending.delete(id);
          const error = new KernelTimeoutError(
            `Execution exceeded ${this._runtimeManifest.softTimeoutMs}ms and SharedArrayBuffer is unavailable; restarting the Objective-C worker`
          );
          reject(error);
          this._restartWorker(error);
        }, this._runtimeManifest.softTimeoutMs);
      } else {
        pending.hardTimer = setTimeout(() => {
          this._pending.delete(id);
          reject(new Error(`Kernel request timed out after ${timeoutMs}ms: ${type}`));
        }, timeoutMs);
      }

      this._pending.set(id, pending);

      try {
        this._worker.postMessage({
          id,
          generation,
          type,
          runtimeManifest: this._runtimeManifest,
          interruptBuffer: this._interruptBuffer,
          ...payload
        });
      } catch (error: any) {
        clearPendingTimers(pending);
        this._pending.delete(id);
        reject(error);
      }
    });
  }

  private _onWorkerMessage(message: any): void {
    const { id, type, content, generation } = message || {};

    if (generation !== undefined && generation !== this._workerGeneration) {
      return;
    }

    if (type === 'stream') {
      const pending = this._pending.get(id);
      if (!pending || pending.silent) {
        return;
      }
      this.stream(content, pending.parentHeader);
      return;
    }

    const pending = this._pending.get(id);
    if (!pending) {
      return;
    }

    if (pending.generation !== this._workerGeneration) {
      return;
    }

    clearPendingTimers(pending);
    this._pending.delete(id);
    this._resetInterruptFlag();

    if (type === 'error') {
      const error = new Error(content?.evalue || 'Objective-C worker error');
      error.name = content?.ename || 'ObjcKernelError';
      if (content?.ename === 'ObjCException') {
        error.name = 'ObjCException';
      }
      pending.reject(error);
      return;
    }

    if (type !== pending.expectedType) {
      pending.reject(new Error(`Expected ${pending.expectedType}, got ${type}`));
      return;
    }

    pending.resolve(content);
  }

  private _resetInterruptFlag(): void {
    if (this._interruptView) {
      Atomics.store(this._interruptView, 0, 0);
    }
  }
}

function clearPendingTimers(pending: PendingRequest): void {
  if (pending.timer) {
    clearTimeout(pending.timer);
    pending.timer = null;
  }
  if (pending.hardTimer) {
    clearTimeout(pending.hardTimer);
    pending.hardTimer = null;
  }
}

type MimeBundle = KernelMessage.IExecuteResultMsg['content']['data'];

function hasDisplayData(data: MimeBundle): boolean {
  return Object.keys(data).length > 0;
}

function normalizeDisplayData(data: Record<string, any>): MimeBundle {
  const normalized = { ...(data as MimeBundle) };

  if (!hasDisplayData(normalized) || normalized['text/plain'] !== undefined) {
    /* Enrich CID-like text output with the CID MIME type so the
     * CID viewer extension can render it as a structured table. */
    enrichAtprotoMimeTypes(normalized);
    return normalized;
  }

  const firstValue = Object.values(normalized)[0];
  return {
    'text/plain':
      typeof firstValue === 'string' ? firstValue : JSON.stringify(firstValue ?? normalized),
    ...normalized
  };
}

/**
 * Detect ATProto data types in text/plain output and add corresponding
 * MIME types so the viewer extensions can render them.
 */
function enrichAtprotoMimeTypes(data: MimeBundle): void {
  const text = data['text/plain'];
  if (typeof text !== 'string') return;

  const trimmed = text.trim();

  /* CIDv1 base32: starts with 'b' and uses base32 chars (bafyrei..., bafkrei...) */
  if (/^b[a-z2-7]{8,}$/i.test(trimmed)) {
    data['application/vnd.atproto.cid'] = trimmed;
    return;
  }

  /* CIDv0 base58btc: starts with 'Qm' and uses base58 chars */
  if (/^Qm[1-9A-HJ-NP-Za-km-z]{20,}$/.test(trimmed)) {
    data['application/vnd.atproto.cid'] = trimmed;
    return;
  }
}

function analyzeCompleteness(code: string): KernelMessage.IIsCompleteReplyMsg['content'] {
  const trimmed = code.trimEnd();

  if (trimmed === '') {
    return { status: 'complete' };
  }

  const scan = scanObjectiveC(code);

  if (scan.inBlockComment || scan.inString || scan.inChar) {
    return { status: 'incomplete', indent: '    ' };
  }

  if (
    scan.bracketDepth > 0 ||
    scan.braceDepth > 0 ||
    scan.parenDepth > 0 ||
    scan.directiveDepth > 0
  ) {
    return { status: 'incomplete', indent: '    ' };
  }

  const outside = scan.outsideCode.trimEnd();

  if (outside.endsWith(';') || outside.endsWith('@end') || outside.endsWith('}')) {
    return { status: 'complete' };
  }

  if (/[,:+\-*/%=&|!<>?]$/.test(outside)) {
    return { status: 'incomplete', indent: '    ' };
  }

  if (!outside.includes('\n')) {
    return { status: 'complete' };
  }

  return { status: 'unknown' };
}

function scanObjectiveC(code: string): {
  outsideCode: string;
  bracketDepth: number;
  braceDepth: number;
  parenDepth: number;
  directiveDepth: number;
  inBlockComment: boolean;
  inString: boolean;
  inChar: boolean;
} {
  let outsideCode = '';
  let bracketDepth = 0;
  let braceDepth = 0;
  let parenDepth = 0;
  let directiveDepth = 0;
  let state: 'code' | 'lineComment' | 'blockComment' | 'string' | 'char' = 'code';
  let escaped = false;

  for (let i = 0; i < code.length; i++) {
    const ch = code[i];
    const next = code[i + 1];

    if (state === 'lineComment') {
      if (ch === '\n') {
        state = 'code';
        outsideCode += ch;
      }
      continue;
    }

    if (state === 'blockComment') {
      if (ch === '*' && next === '/') {
        state = 'code';
        i++;
      }
      continue;
    }

    if (state === 'string') {
      if (escaped) {
        escaped = false;
      } else if (ch === '\\') {
        escaped = true;
      } else if (ch === '"') {
        state = 'code';
        outsideCode += ' ';
      }
      continue;
    }

    if (state === 'char') {
      if (escaped) {
        escaped = false;
      } else if (ch === '\\') {
        escaped = true;
      } else if (ch === "'") {
        state = 'code';
        outsideCode += ' ';
      }
      continue;
    }

    if (ch === '/' && next === '/') {
      state = 'lineComment';
      i++;
      continue;
    }

    if (ch === '/' && next === '*') {
      state = 'blockComment';
      i++;
      continue;
    }

    if (ch === '"') {
      state = 'string';
      outsideCode += ' ';
      continue;
    }

    if (ch === "'") {
      state = 'char';
      outsideCode += ' ';
      continue;
    }

    if (ch === '[') {
      bracketDepth++;
    } else if (ch === ']') {
      bracketDepth = Math.max(0, bracketDepth - 1);
    } else if (ch === '{') {
      braceDepth++;
    } else if (ch === '}') {
      braceDepth = Math.max(0, braceDepth - 1);
    } else if (ch === '(') {
      parenDepth++;
    } else if (ch === ')') {
      parenDepth = Math.max(0, parenDepth - 1);
    }

    outsideCode += ch;
  }

  const directiveMatches = outsideCode.match(/@(interface|implementation|protocol)\b|@end\b/g) || [];
  for (const directive of directiveMatches) {
    if (directive === '@end') {
      directiveDepth = Math.max(0, directiveDepth - 1);
    } else {
      directiveDepth++;
    }
  }

  return {
    outsideCode,
    bracketDepth,
    braceDepth,
    parenDepth,
    directiveDepth,
    inBlockComment: state === 'blockComment',
    inString: state === 'string',
    inChar: state === 'char'
  };
}
