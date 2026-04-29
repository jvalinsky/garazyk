"""JupyterLite build configuration for objc-jupyter-wasm.

Usage:
    jupyter lite build --config jupyterlite_config.py
"""

from pathlib import Path

# Project root (where this file lives)
HERE = Path(__file__).parent

# Output directory for the built site
OUTPUT_DIR = HERE / "dist" / "jupyterlite"

# Content directory — demo notebooks
CONTENT_DIR = HERE / "demo"

# Labextension directory — the built federated extension with WASM assets
LABEXTENSION_DIR = HERE / "objc_jupyter_wasm" / "labextension"

c = get_config()  # noqa: F821

c.LiteBuildApp.output_dir = str(OUTPUT_DIR)

if CONTENT_DIR.is_dir():
    c.LiteBuildApp.contents = [str(CONTENT_DIR)]

# Explicitly include the Objective-C kernel as a federated extension.
# JupyterLite discovers kernels from federated extensions. Our extension
# (src/index.ts) registers the kernel via IKernelSpecs.
if LABEXTENSION_DIR.is_dir():
    c.LiteBuildApp.federated_extensions = [str(LABEXTENSION_DIR)]
