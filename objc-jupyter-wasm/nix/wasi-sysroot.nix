{
  lib,
  runCommand,
  libobjc2-wasm,
}:

# Minimal WASI sysroot that includes ObjC headers from libobjc2
# This is a lightweight sysroot for cross-compiling ObjC to WASM.
#
# Note: This does NOT include wasi-libc since that's a target package.
# For full WASI libc support, use emscripten or wasi-sdk directly.
# This sysroot is primarily for the ObjC runtime headers.

runCommand "wasi-sysroot-objc" {
  passthru = {
    inherit libobjc2-wasm;
  };

  meta = with lib; {
    description = "Minimal WASI sysroot with Objective-C runtime headers";
    platforms = platforms.all;
  };
} ''
  mkdir -p $out/include $out/lib

  # Copy ObjC runtime headers
  if [ -d ${libobjc2-wasm}/include ]; then
    cp -r ${libobjc2-wasm}/include/* $out/include/
  fi

  # Copy ObjC runtime libraries
  if [ -d ${libobjc2-wasm}/lib ]; then
    cp -r ${libobjc2-wasm}/lib/* $out/lib/
  fi
''
