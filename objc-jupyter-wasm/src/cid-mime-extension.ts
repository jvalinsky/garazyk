/**
 * MIME extension entry point for the CID viewer.
 *
 * JupyterLab loads this separately from the kernel plugin.
 * The default export is an IRenderMime.IExtension (or array thereof)
 * that registers the CID decoder renderer.
 */
import { cidViewerExtension } from "./cid-viewer";

export default cidViewerExtension;
