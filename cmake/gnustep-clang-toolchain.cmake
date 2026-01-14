# CMake Toolchain File for GNUstep/Clang builds
# Used in Docker builds to avoid compiler cache invalidation issues.
#
# Usage: cmake -DCMAKE_TOOLCHAIN_FILE=/path/to/gnustep-clang-toolchain.cmake ...

# Set compilers BEFORE project() - this is crucial to avoid cache invalidation
set(CMAKE_C_COMPILER /usr/bin/clang)
set(CMAKE_CXX_COMPILER /usr/bin/clang++)
set(CMAKE_OBJC_COMPILER /usr/bin/clang)

# GNUstep-specific compile definitions
set(CMAKE_C_FLAGS_INIT "-fblocks")
set(CMAKE_CXX_FLAGS_INIT "-fblocks")
set(CMAKE_OBJC_FLAGS_INIT "-fblocks -fobjc-arc -fobjc-runtime=gnustep-2.0")

# Link against libobjc2 from GNUstep
set(CMAKE_EXE_LINKER_FLAGS_INIT "-L/usr/GNUstep/Local/Library/Libraries -lobjc")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "-L/usr/GNUstep/Local/Library/Libraries -lobjc")
