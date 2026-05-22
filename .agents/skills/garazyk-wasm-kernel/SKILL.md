---
name: garazyk-wasm-kernel
description: Work on Garazyk's Objective-C Jupyter WASM kernel in objc-jupyter-wasm. Covers build flow, JupyterLite integration, interpreter/runtime limits, notebook demos, browser smoke tests, packaging, and ATProto tutorial snippets.
---

# Garazyk WASM Kernel

Use this skill for `objc-jupyter-wasm/` changes: kernel runtime, Objective-C interpreter, JupyterLite packaging, demo notebooks, browser smoke tests, and WASM-specific limitations.

## Key files

- Project root: `objc-jupyter-wasm/README.md`, `pyproject.toml`, `package.json`, `CMakeLists.txt`
- Kernel C runtime: `objc-jupyter-wasm/kernel/*.{c,h}`
- WASM/runtime bridge: `kernel/objc_runtime_bridge.c`, `kernel/objc_kernel.h`, `kernel/kernel.wasm`
- JS integration: `js/objc-kernel.ts`, `js/objc-worker.js`, `js/wasm-loader.js`, `js/runtime-support.ts`
- JupyterLite: `jupyterlite_config.py`, `jupyterlite/kernel.js`, `jupyterlite/kernelspec.json`
- Build scripts: `scripts/build-jupyterlite-site.sh`, `scripts/build-smoke-site.mjs`, `scripts/copy-static-assets.mjs`
- Tests: `test-jl.mjs`, `tests/browser-smoke-page.mjs`, `tests/browser-smoke.html`
- Notebooks: `demo/*.ipynb`
- Docs: `docs/PRD.md`, `docs/runtime-gap-report.md`, `docs/garazyk-tutorial-snippet-policy.md`
- Nix/WASI: `nix/*.nix`, `flake.nix`

## Working model

The WASM kernel is not full clang/Objective-C. Treat it as a constrained teaching/runtime environment:

- C/Objective-C syntax support is interpreter-defined.
- Foundation/runtime behavior is shimmed or bridged.
- Browser execution has memory, filesystem, networking, and threading limits.
- Demo notebooks must avoid unsupported language/runtime features unless the lesson is explicitly about the limitation.

When changing behavior, update runtime-gap docs or parser status if the support boundary moves.

## Build workflow

Start by reading `objc-jupyter-wasm/README.md` and relevant package manifests.

Common commands:

```bash
cd objc-jupyter-wasm
npm install
npm test
node test-jl.mjs
./scripts/build-jupyterlite-site.sh
./scripts/serve-demo.sh
```

If Nix/WASI is involved:

```bash
cd objc-jupyter-wasm
nix develop
```

Prefer the repo's scripts over ad-hoc Emscripten/WASI commands.

## Kernel/runtime changes

For parser/interpreter work:

1. Identify the grammar/runtime feature and current support in `kernel/PARSER_STATUS.md` or docs.
2. Add the smallest parser/runtime change.
3. Add direct tests or browser smoke coverage.
4. Update a demo notebook only after the runtime behavior is stable.

Check for:

- memory ownership and fixed buffers
- recursive parser limits
- clear error messages for unsupported syntax
- deterministic output ordering
- worker/kernel message protocol compatibility
- no browser-only global assumptions in shared code

## JupyterLite integration

When changing packaging or kernel startup:

- Verify `jupyterlite/kernelspec.json` points to the right assets.
- Ensure WASM paths work from the built site, not only dev paths.
- Keep worker loading compatible with static hosting.
- Avoid network fetches that break offline/static demos unless documented.
- Rebuild the smoke site after asset changes.

Useful checks:

```bash
cd objc-jupyter-wasm
node tests/browser-smoke-page.mjs
./scripts/build-smoke-site.mjs
```

## Demo notebook guidance

Demo notebooks are teaching artifacts. Keep them:

- short and focused
- aligned with supported runtime features
- ordered from simple language features to ATProto concepts
- deterministic in output
- explicit about limitations

ATProto notebooks should follow `docs/garazyk-tutorial-snippet-policy.md` and avoid snippets that imply production security or networking behavior the WASM kernel cannot provide.

## Runtime limits checklist

Before claiming support for a feature, check:

- Does it work in the browser worker, not just local Node?
- Is memory bounded and recoverable after errors?
- Does the error path return a clean Jupyter message?
- Does the feature interact with Objective-C message dispatch, classes, protocols, exceptions, or autorelease pools?
- Is Foundation behavior shimmed consistently?
- Does it fail gracefully when unsupported?

## Packaging checklist

- Python package metadata updated if needed (`pyproject.toml`, `MANIFEST.in`).
- npm package assets included if needed (`package.json`, build scripts).
- JupyterLite static assets copied.
- Kernel spec references packaged paths.
- Smoke test verifies import/start/evaluate.
- Screenshots/docs updated only when behavior changed.

## Review output format

```md
## WASM kernel review

- Area: parser/runtime/JupyterLite/demo/package
- Files touched:
- Build/test command:
- Runtime support boundary:
- Browser smoke result:
- Docs/notebooks updated:
```

## Definition of done

- Local build/test path succeeds.
- Browser/JupyterLite smoke path succeeds for integration changes.
- Unsupported runtime behavior fails clearly.
- Demo notebooks remain deterministic.
- Packaging includes required WASM/JS/kernel assets.
- Runtime-gap or parser-status docs updated when support changes.
