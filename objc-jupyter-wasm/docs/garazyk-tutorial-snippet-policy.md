# Garazyk Tutorial Snippet Policy

The Objective-C JupyterLite kernel targets tutorial-grade Garazyk snippets. A snippet may mirror
production structure, names, and control flow, but it must be safe to run in a browser-hosted
kernel.

## Support Classes

- `direct`: Runs in the interpreter without host services. This includes Objective-C classes,
  properties, protocols, categories, inheritance, blocks, exceptions, Foundation collections,
  `NSData`, selectors, KVC, and logging.
- `host-bridge`: Uses deterministic browser or JavaScript host services. Current tutorial examples
  cover JSON parsing, fetch fixtures, SHA-256, Base32, and related encoding helpers.
- `adapted-shim`: Mirrors a production boundary with an in-memory model, such as repository storage,
  blob metadata, account/session state, migrations, firehose cursors, or XRPC dispatch.
- `unsupported-production`: Production APIs that should not execute directly in tutorials. The
  compatibility runner reports these as diagnostics instead of sending them to the WASM interpreter.

## Unsupported Production APIs

Tutorial snippets must not directly use:

- SQLite C APIs (`sqlite3_*`)
- GCD/libdispatch (`dispatch_*`, `dispatch_queue_t`)
- Filesystem APIs (`NSFileManager`, `NSFileHandle`, file reads/writes)
- Keychain, Security, CommonCrypto, OpenSSL, or platform crypto key APIs
- Media frameworks such as AVFoundation, CoreGraphics, CoreMedia, and CoreVideo
- Threading primitives such as `NSThread`, `NSLock`, or `NSOperationQueue`

Use an `adapted-shim` example or a deterministic `host-bridge` fixture instead. Unsupported
production snippets should fail with a diagnostic from `tests/test-garazyk-compat.mjs`, never with a
WASM trap.

## Compatibility Gates

Run these before publishing tutorial notebooks:

```bash
node tests/test-runtime-v2.mjs result/wasm/kernel.wasm
node tests/test-runtime-gap-probes.mjs result/wasm/kernel.wasm
node tests/test-garazyk-compat.mjs result/wasm/kernel.wasm
node tests/run-notebooks.mjs --dir demo/
```
