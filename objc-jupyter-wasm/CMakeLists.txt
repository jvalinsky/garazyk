# objc-jupyter-wasm: Objective-C Jupyter Kernel via WebAssembly
# Subproject CMake configuration

cmake_minimum_required(VERSION 3.25)

project(objc-jupyter-wasm VERSION 0.1.0 LANGUAGES C)

# Options
option(BUILD_OBJC_WASM_COMPILER "Build ObjC→WASM compiler" OFF)
option(BUILD_OBJC_WASM_RUNTIME "Build ObjC runtime for WASM" OFF)
option(BUILD_OBJC_WASM_KERNEL "Build Jupyter kernel for WASM" OFF)

# Emscripten toolchain (required for WASM targets)
if(BUILD_OBJC_WASM_COMPILER OR BUILD_OBJC_WASM_RUNTIME OR BUILD_OBJC_WASM_KERNEL)
  if(NOT DEFINED ENV{EMSDK})
    message(WARNING "EMSDK not set. Source emsdk/env.sh first.")
  endif()
  set(CMAKE_TOOLCHAIN_FILE "$ENV{EMSDK}/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake"
      CACHE FILEPATH "Emscripten toolchain")
endif()

# Subdirectories
if(BUILD_OBJC_WASM_COMPILER)
  add_subdirectory(compiler)
endif()

if(BUILD_OBJC_WASM_RUNTIME)
  add_subdirectory(kernel/runtime)
endif()

if(BUILD_OBJC_WASM_KERNEL)
  add_subdirectory(kernel)
endif()

# Build orchestration target
add_custom_target(objc-jupyter-wasm-all
  DEPENDS objc-wasm-compiler objc-wasm-runtime objc-wasm-kernel
  COMMENT "Building all WASM targets for objc-jupyter-wasm"
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
