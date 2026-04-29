# objc-jupyter-wasm: Objective-C Jupyter Kernel via WebAssembly
# Subproject CMake configuration

cmake_minimum_required(VERSION 3.25)

project(objc-jupyter-wasm VERSION 0.1.0 LANGUAGES C)

# Options
option(BUILD_OBJC_WASM_COMPILER "Build ObjC→WASM compiler" OFF)
option(BUILD_OBJC_WASM_RUNTIME "Build ObjC runtime for WASM" OFF)
option(BUILD_OBJC_WASM_KERNEL "Build Jupyter kernel for WASM" OFF)

# Nix is the authoritative build path for the current WASM smoke slice.
# The CMake options remain as placeholders for a later native integration, but
# they should fail clearly instead of trying to add missing subdirectories.
if(BUILD_OBJC_WASM_COMPILER OR BUILD_OBJC_WASM_RUNTIME OR BUILD_OBJC_WASM_KERNEL)
  message(FATAL_ERROR
    "objc-jupyter-wasm CMake WASM targets are not implemented yet. "
    "Use: nix build ./objc-jupyter-wasm#kernel-wasm"
  )
endif()

add_custom_target(objc-jupyter-wasm-all
  COMMAND ${CMAKE_COMMAND} -E echo "Use Nix for WASM builds: nix build ./objc-jupyter-wasm#kernel-wasm"
  COMMENT "objc-jupyter-wasm CMake target placeholder"
)

# Install target for JupyterLite integration
install(DIRECTORY jupyterlite/
  DESTINATION share/jupyterlite/kernels/objc
  FILES_MATCHING PATTERN "*.json" PATTERN "*.html" PATTERN "*.js"
)

install(DIRECTORY demo/
  DESTINATION share/jupyterlite/demo/objc
  FILES_MATCHING PATTERN "*.ipynb"
)
