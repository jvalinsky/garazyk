/**
 * ATProto file upload plugin for JupyterLab.
 *
 * Adds commands and file type registrations for uploading ATProto-relevant
 * files (.car, .cbor, .cid) into the JupyterLite virtual filesystem.
 * Users can then read these files from ObjC kernel code.
 *
 * Commands:
 *   - atproto:upload-file — opens a file picker for .car/.cbor/.cid files
 *
 * File types registered:
 *   - CAR Archive (.car) — application/vnd.ipld.car
 *   - CBOR data (.cbor) — application/cbor
 *   - CID (.cid) — application/vnd.atproto.cid
 */
import { JupyterFrontEnd, JupyterFrontEndPlugin } from "@jupyterlab/application";
import { IContentsManager } from "@jupyterlab/services";

const UPLOAD_COMMAND = "atproto:upload-file";

const plugin: JupyterFrontEndPlugin<void> = {
  id: "objc-jupyter-wasm:atproto-upload",
  autoStart: true,
  requires: [IContentsManager],
  activate: (app: JupyterFrontEnd, contents: any) => {
    /* Register ATProto file types so JupyterLab recognizes them. */
    app.docRegistry.addFileType({
      name: "car",
      displayName: "CAR Archive",
      extensions: [".car"],
      mimeTypes: ["application/vnd.ipld.car"],
      fileFormat: "base64",
    });

    app.docRegistry.addFileType({
      name: "cbor",
      displayName: "CBOR Data",
      extensions: [".cbor"],
      mimeTypes: ["application/cbor"],
      fileFormat: "base64",
    });

    app.docRegistry.addFileType({
      name: "cid",
      displayName: "CID",
      extensions: [".cid"],
      mimeTypes: ["application/vnd.atproto.cid"],
      fileFormat: "text",
    });

    /* Upload command — opens a native file picker and writes
     * the selected file into the JupyterLite virtual filesystem. */
    app.commands.addCommand(UPLOAD_COMMAND, {
      label: "Upload ATProto File (.car, .cbor, .cid)",
      caption: "Upload a CAR archive, CBOR data, or CID file to the browser filesystem",
      execute: async () => {
        const input = document.createElement("input");
        input.type = "file";
        input.accept = ".car,.cbor,.cid";
        input.multiple = true;

        input.onchange = async () => {
          const files = input.files;
          if (!files || files.length === 0) return;

          for (let i = 0; i < files.length; i++) {
            const file = files[i];
            const name = file.name;
            const ext = name.split(".").pop()?.toLowerCase();

            try {
              if (ext === "cid") {
                /* Text file — read as UTF-8 string. */
                const text = await file.text();
                await contents.save(name, {
                  type: "file",
                  content: text,
                  format: "text",
                });
              } else {
                /* Binary file — read as base64. */
                const buffer = await file.arrayBuffer();
                const bytes = new Uint8Array(buffer);
                let binary = "";
                for (let j = 0; j < bytes.length; j++) {
                  binary += String.fromCharCode(bytes[j]);
                }
                const base64 = btoa(binary);
                await contents.save(name, {
                  type: "file",
                  content: base64,
                  format: "base64",
                });
              }
              console.info(`atproto-upload: saved ${name} to virtual filesystem`);
            } catch (err: any) {
              console.error(`atproto-upload: failed to save ${name}:`, err.message);
            }
          }
        };

        input.click();
      },
    });

    console.info("objc-jupyter-wasm: ATProto file upload plugin activated");
  },
};

export default plugin;
