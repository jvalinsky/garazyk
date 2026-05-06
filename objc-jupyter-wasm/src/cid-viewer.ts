/**
 * CID decoder viewer for JupyterLab.
 *
 * Renders CID strings (bafyrei..., Qm...) as structured tables showing
 * version, codec, multihash algorithm, and digest. Also works as a
 * document viewer for .cid files.
 *
 * MIME type: application/vnd.atproto.cid
 */
import { Widget } from '@lumino/widgets';
import { IRenderMime } from '@jupyterlab/rendermime';
import { CID } from 'multiformats/cid';

const MIME_TYPE = 'application/vnd.atproto.cid';

/** Codec code to human-readable name. */
const CODEC_NAMES: Record<number, string> = {
  0x55: 'raw',
  0x71: 'dag-cbor',
  0x70: 'dag-pb',
  0x0129: 'dag-json'
};

/** Multihash code to human-readable name. */
const HASH_NAMES: Record<number, string> = {
  0x12: 'sha2-256',
  0x13: 'sha2-512',
  0x56: 'sha2-256-256',
  0x17: 'sha3-224',
  0x16: 'sha3-256',
  0x15: 'sha3-384',
  0x14: 'sha3-512',
  0x00: 'identity'
};

function hexDigest(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

function codecName(code: number): string {
  return CODEC_NAMES[code] ?? `0x${code.toString(16)}`;
}

function hashName(code: number): string {
  return HASH_NAMES[code] ?? `0x${code.toString(16)}`;
}

export class CidViewer extends Widget implements IRenderMime.IRenderer {
  private _mimeType: string;

  constructor(options: IRenderMime.IRendererOptions) {
    super();
    this._mimeType = options.mimeType;
    this.addClass('atproto-cid-viewer');
  }

  renderModel(model: IRenderMime.IMimeModel): Promise<void> {
    const cidStr = model.data[this._mimeType] as string;
    if (!cidStr) {
      this.node.innerHTML = '<div class="atproto-error">No CID data</div>';
      return Promise.resolve();
    }

    try {
      const cid = CID.parse(cidStr.trim());
      const digest = cid.multihash.digest;
      const digestHex = hexDigest(digest);
      const shortHex = digestHex.length > 32
        ? digestHex.slice(0, 16) + '...' + digestHex.slice(-16)
        : digestHex;

      this.node.innerHTML = `
        <div class="atproto-cid-panel">
          <div class="atproto-cid-header">
            <span class="atproto-cid-badge">CID</span>
            <code class="atproto-cid-string">${escapeHtml(cid.toString())}</code>
          </div>
          <table class="atproto-cid-table">
            <tr><th>Version</th><td>${cid.version}</td></tr>
            <tr><th>Codec</th><td>${codecName(cid.code)} <span class="atproto-code">(${cid.code})</span></td></tr>
            <tr><th>Hash</th><td>${hashName(cid.multihash.code)} <span class="atproto-code">(${cid.multihash.code})</span></td></tr>
            <tr><th>Digest size</th><td>${digest.length} bytes</td></tr>
            <tr><th>Digest (hex)</th><td><code class="atproto-digest">${shortHex}</code></td></tr>
          </table>
        </div>`;
    } catch (e: any) {
      this.node.innerHTML = `
        <div class="atproto-error">
          <strong>Invalid CID</strong>: ${escapeHtml(e.message || String(e))}
          <br><code>${escapeHtml(cidStr)}</code>
        </div>`;
    }

    return Promise.resolve();
  }
}

function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

export const cidViewerExtension: IRenderMime.IExtension = {
  id: 'objc-jupyter-wasm:cid-viewer',
  rendererFactory: {
    safe: true,
    mimeTypes: [MIME_TYPE],
    createRenderer: (options: IRenderMime.IRendererOptions): IRenderMime.IRenderer => {
      return new CidViewer(options);
    }
  },
  fileTypes: [
    {
      name: 'CID',
      displayName: 'CID',
      mimeTypes: [MIME_TYPE],
      extensions: ['.cid'],
      fileFormat: 'text'
    }
  ],
  documentWidgetFactoryOptions: {
    name: 'CID Viewer',
    primaryFileType: 'CID',
    fileTypes: ['CID'],
    defaultFor: ['CID']
  }
};

export default cidViewerExtension;
