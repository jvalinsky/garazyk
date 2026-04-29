{
  lib,
  runCommand,
  wasilibc,
  libobjc2-wasm,
  llvmPackages,
}:

# Extended WASI sysroot that includes ObjC headers from libobjc2
# alongside the standard wasi-libc sysroot.
#
# This provides a single --sysroot path that contains both
# the WASI C library and the ObjC runtime headers, simplifying
# cross-compilation commands.

runCommand "wasi-sysroot-objc" {
  passthru = {
    inherit wasilibc libobjc2-wasm;
  };

  meta = with lib; {
    description = "Extended WASI sysroot with Objective-C runtime headers";
    platforms = platforms.all;
  };
} ''
  mkdir -p $out

  # Copy wasi-libc sysroot as base
  cp -r ${wasilibc.dev}/* $out/

  # Overlay ObjC runtime headers
  if [ -d ${libobjc2-wasm}/include ]; then
    cp -r ${libobjc2-wasm}/include/* $out/include/
  fi

  # Overlay ObjC runtime libraries
  if [ -d ${libobjc2-wasm}/lib ]; then
    cp -r ${libobjc2-wasm}/lib/* $out/lib/
  fi
''
