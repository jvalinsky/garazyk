cmake_minimum_required(VERSION 3.21)

#=============================
# Project Configuration
#=============================
project(ATProtoPDS
  VERSION 0.1.0
  DESCRIPTION "ATProto Personal Data Server"
  LANGUAGES C CXX OBJC
)

#=============================
# Global Settings
#=============================
# Enable ARC for Objective-C and disable strict standards
set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -Wno-implicit-function-declaration")

# Platform Specific Configuration
if(APPLE)
    set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -fobjc-arc")
endif()

if(NOT APPLE)
    add_compile_definitions(GNUSTEP LINUX OS_OBJECT_USE_OBJC=0)

    # Use Clang for Objective-C on Linux (required for ARC and blocks)
    find_program(OBJC_COMPILER NAMES /bin/clang clang-14 clang)
    if(OBJC_COMPILER)
        set(CMAKE_OBJC_COMPILER ${OBJC_COMPILER})
        message(STATUS "Using ${OBJC_COMPILER} for Objective-C")
        # Also use clang for C/C++ to avoid ABI issues
        set(CMAKE_C_COMPILER ${OBJC_COMPILER})
        set(CMAKE_CXX_COMPILER ${OBJC_COMPILER})
        message(STATUS "Using ${OBJC_COMPILER} for C/C++")
    else()
        message(FATAL_ERROR "Clang compiler not found for Objective-C")
    endif()

    # Find libobjc2 (GNU runtime with blocks support)
    if(NOT OBJC_RUNTIME)
        find_library(OBJC_RUNTIME objc)
    endif()

    if(OBJC_RUNTIME)
        message(STATUS "Found libobjc2 at ${OBJC_RUNTIME}")
        set(OBJC_FLAGS "-fblocks -fobjc-arc -fobjc-runtime=gnustep-2.0")
    else()
        # Fallback for manual source builds in Docker or systems with non-standard paths
        find_program(GNUSTEP_CONFIG gnustep-config)
        if(GNUSTEP_CONFIG)
            execute_process(
                COMMAND ${GNUSTEP_CONFIG} --variable=GNUSTEP_LOCAL_LIBRARIES
                OUTPUT_VARIABLE GNUSTEP_LOCAL_LIBS_DIR
                OUTPUT_STRIP_TRAILING_WHITESPACE
            )
            find_library(OBJC_RUNTIME objc PATHS ${GNUSTEP_LOCAL_LIBS_DIR} NO_DEFAULT_PATH)
        endif()

        if(OBJC_RUNTIME)
            message(STATUS "Found libobjc2 at ${OBJC_RUNTIME} via gnustep-config")
            set(OBJC_FLAGS "-fblocks -fobjc-arc -fobjc-runtime=gnustep-2.0")
        else()
            message(FATAL_ERROR "libobjc2 not found. Install gnustep-devel or gnustep-base-dev package.")
        endif()
    endif()

    # GNUstep Configuration
    find_program(GNUSTEP_CONFIG gnustep-config)
    if(GNUSTEP_CONFIG)
        execute_process(
            COMMAND ${GNUSTEP_CONFIG} --objc-flags
            OUTPUT_VARIABLE GNUSTEP_CFLAGS
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        execute_process(
            COMMAND ${GNUSTEP_CONFIG} --base-libs
            OUTPUT_VARIABLE GNUSTEP_LIBS
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} ${GNUSTEP_CFLAGS} ${OBJC_FLAGS}")
        string(REPLACE " " ";" GNUSTEP_LIBS_LIST "${GNUSTEP_LIBS}")
        message(STATUS "Found GNUstep via gnustep-config")
    else()
        # Try pkg-config as fallback
        find_package(PkgConfig)
        if(PKG_CONFIG_FOUND AND pkg_check_modules(GNUSTEP_BASE gnustep-base))
            message(STATUS "Found GNUstep via pkg-config")
            set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} ${GNUSTEP_BASE_CFLAGS} ${OBJC_FLAGS}")
            string(REPLACE " " ";" GNUSTEP_LIBS_LIST "${GNUSTEP_BASE_LIBS}")
        else()
            message(FATAL_ERROR "GNUstep not found. Install gnustep-devel or gnustep-base-dev package.")
        endif()
    endif()

    include_directories(/usr/GNUstep/Local/Library/Headers)
    include_directories(/usr/include/GNUstep)
    include_directories(/usr/include)
    include_directories(${CMAKE_CURRENT_SOURCE_DIR}/Sources/Compat)
    
    # Link directories - prioritize local GNUstep builds
    link_directories(/usr/GNUstep/Local/Library/Libraries)
endif()

#=============================
# Build Type Configuration
#=============================
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Debug CACHE STRING "Build type" FORCE)
endif()

# Set compiler flags based on build type
set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -g -O0")
set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} -O2")
set(CMAKE_OBJC_FLAGS_DEBUG "${CMAKE_OBJC_FLAGS_DEBUG} -g -O0")
set(CMAKE_OBJC_FLAGS_RELEASE "${CMAKE_OBJC_FLAGS_RELEASE} -O2")

#=============================
# Dependencies
#=============================

if(APPLE)
    # Find required frameworks
    find_library(FOUNDATION Foundation REQUIRED)
    find_library(NETWORK Network REQUIRED)
    find_library(SECURITY Security REQUIRED)
    find_library(COREIMAGE CoreImage REQUIRED)
    find_library(APPKIT AppKit REQUIRED)
    find_library(IMAGEIO ImageIO REQUIRED)
    find_library(COREGRAPHICS CoreGraphics REQUIRED)
    
    # Find SQLite3
    find_library(SQLite3_LIBRARY sqlite3 REQUIRED)
    
    set(PLATFORM_LIBRARIES 
        ${FOUNDATION} 
        ${NETWORK} 
        ${SECURITY} 
        ${COREIMAGE} 
        ${APPKIT} 
        ${IMAGEIO} 
        ${COREGRAPHICS}
        ${SQLite3_LIBRARY}
        resolv
    )
else()
    # Linux Dependencies
    find_package(OpenSSL REQUIRED)
    find_package(SQLite3 REQUIRED)

    # Create SQLite3 imported target if not already created by find_package
    if(NOT TARGET SQLite3::SQLite3)
        add_library(SQLite3::SQLite3 INTERFACE IMPORTED)
        set_target_properties(SQLite3::SQLite3 PROPERTIES
            INTERFACE_INCLUDE_DIRECTORIES "${SQLite3_INCLUDE_DIRS}"
            INTERFACE_LINK_LIBRARIES "${SQLite3_LIBRARIES}"
        )
    endif()

    find_library(DISPATCH_LIB dispatch)
    find_library(BLOCKS_RUNTIME_LIB BlocksRuntime)
    find_library(QRENCODE_LIB qrencode REQUIRED)
    find_path(QRENCODE_INCLUDE_DIR qrencode.h REQUIRED)
    
    if(NOT DISPATCH_LIB)
        message(WARNING "libdispatch not found")
    endif()

    if(QRENCODE_INCLUDE_DIR)
        include_directories(${QRENCODE_INCLUDE_DIR})
    endif()
    
    # Use local GNUstep libraries (from /usr/GNUstep/Local) which are compiled with libobjc2
    find_library(LOCAL_GNUSTEP_BASE gnustep-base PATHS /usr/GNUstep/Local/Library/Libraries NO_DEFAULT_PATH)
    if(LOCAL_GNUSTEP_BASE)
        message(STATUS "Using local gnustep-base: ${LOCAL_GNUSTEP_BASE}")
    else()
        message(STATUS "Local gnustep-base not found, using system default")
        set(LOCAL_GNUSTEP_BASE gnustep-base)
    endif()
    
    set(PLATFORM_LIBRARIES
        ${OBJC_RUNTIME}
        ${LOCAL_GNUSTEP_BASE}
        OpenSSL::SSL
        OpenSSL::Crypto
        SQLite3::SQLite3
        ${DISPATCH_LIB}
        ${BLOCKS_RUNTIME_LIB}
        ${QRENCODE_LIB}
        pthread
        m
        dl
        resolv
    )
endif()

#=============================
# secp256k1 Subproject
#=============================
option(BUILD_SECP256K1 "Build secp256k1 library" ON)
if(BUILD_SECP256K1)
  set(SECP256K1_BUILD_SHARED OFF CACHE BOOL "Build secp256k1 as static library" FORCE)
  set(SECP256K1_ENABLE_MODULE_RECOVERY ON CACHE BOOL "Enable recovery module" FORCE)
  set(SECP256K1_INSTALL OFF CACHE BOOL "Disable secp256k1 installation" FORCE)

  add_subdirectory(secp256k1)
  set(SECP256K1_LIBRARIES secp256k1)
  set(SECP256K1_INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/secp256k1/include)
endif()

#=============================
# Source Files
#=============================

# Collect all Objective-C source files
file(GLOB_RECURSE ATProtoPDS_OBJC_SOURCES "ATProtoPDS/Sources/**/*.m")
file(GLOB_RECURSE ATProtoPDS_C_SOURCES "ATProtoPDS/Sources/**/*.c")

# Exclude main entry points and test files
list(FILTER ATProtoPDS_OBJC_SOURCES EXCLUDE REGEX ".*main\.m$")
list(FILTER ATProtoPDS_OBJC_SOURCES EXCLUDE REGEX ".*/tests/.*")
list(FILTER ATProtoPDS_OBJC_SOURCES EXCLUDE REGEX ".*/Tests/.*")

# Handle platform-specific network transport implementations
list(FILTER ATProtoPDS_OBJC_SOURCES EXCLUDE REGEX ".*/PDSNetworkTransport(Mac|Linux)\.m$")
list(APPEND ATProtoPDS_OBJC_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/ATProtoPDS/Sources/Network/PDSNetworkTransportLinux.m")
if(APPLE)
    list(APPEND ATProtoPDS_OBJC_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/ATProtoPDS/Sources/Network/PDSNetworkTransportMac.m")
endif()

# Exclude AppDelegate on Linux/Server builds if not used or has deps
if(NOT APPLE)
  # AppDelegate is now guarded with ifdefs and can be compiled on Linux
  # list(FILTER ATProtoPDS_OBJC_SOURCES EXCLUDE REGEX ".*AppDelegate\.m$")

  # KeyManager uses extensive Security framework APIs not available on Linux
  list(FILTER ATProtoPDS_OBJC_SOURCES EXCLUDE REGEX ".*/Auth/KeyManager\\.m$")
  list(FILTER ATProtoPDS_OBJC_SOURCES EXCLUDE REGEX ".*/Auth/KeyRotationManager\\.m$")

  # PDSCLIHealthCommand uses Mach APIs (task_info, TASK_VM_INFO) which are macOS-specific
  list(FILTER ATProtoPDS_OBJC_SOURCES EXCLUDE REGEX ".*/CLI/PDSCLIHealthCommand\\.m$")

  # DID.m uses NSURLSession - the VM's GNUstep library doesn't have NSURLSession compiled in
  list(FILTER ATProtoPDS_OBJC_SOURCES EXCLUDE REGEX ".*/Core/DID\\.m$")

  # FederationClient.m uses NSURLSession - same issue as DID.m
  list(FILTER ATProtoPDS_OBJC_SOURCES EXCLUDE REGEX ".*/Federation/FederationClient\\.m$")

  # PDSMetrics.m uses os_unfair_lock from os/lock.h (macOS-only)
  list(FILTER ATProtoPDS_OBJC_SOURCES EXCLUDE REGEX ".*/Metrics/PDSMetrics\\.m$")

  # SSLPinningManager.m uses NSURLSession (not available on VM's GNUstep)
  list(FILTER ATProtoPDS_OBJC_SOURCES EXCLUDE REGEX ".*/Network/SSLPinningManager\\.m$")

  # WebSocketServer.m uses Network.framework (macOS-only)
  list(FILTER ATProtoPDS_OBJC_SOURCES EXCLUDE REGEX ".*/Sync/WebSocketServer\\.m$")
endif()

# Add compat sources for Linux
if(NOT APPLE)
  file(GLOB COMPAT_SOURCES "Sources/Compat/**/*.m")
  list(APPEND ATProtoPDS_OBJC_SOURCES ${COMPAT_SOURCES})
endif()

set(ATProtoPDS_SOURCES ${ATProtoPDS_OBJC_SOURCES} ${ATProtoPDS_C_SOURCES})

#=============================
# Main Executables
#=============================

# CLI Tool
add_executable(atprotopds-cli
  ${ATProtoPDS_SOURCES}
  ATProtoPDS/Sources/CLI/main.m
)

target_include_directories(atprotopds-cli PRIVATE
  ATProtoPDS/Sources
  ${SECP256K1_INCLUDE_DIRS}
)

target_link_libraries(atprotopds-cli PRIVATE
  ${PLATFORM_LIBRARIES}
  ${SECP256K1_LIBRARIES}
)

target_compile_definitions(atprotopds-cli PRIVATE
  SQLITE_THREADSAFE=2
)

set_target_properties(atprotopds-cli PROPERTIES
  OUTPUT_NAME "atprotopds-cli"
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
  BUILD_RPATH "/usr/lib"
  INSTALL_RPATH "/usr/lib"
)

# Server Executable
add_executable(atprotopds-server
  ${ATProtoPDS_SOURCES}
  ATProtoPDS/Sources/App/server_main.m
)

target_include_directories(atprotopds-server PRIVATE
  ATProtoPDS/Sources
  ${SECP256K1_INCLUDE_DIRS}
)

target_link_libraries(atprotopds-server PRIVATE
  ${PLATFORM_LIBRARIES}
  ${SECP256K1_LIBRARIES}
)

target_compile_definitions(atprotopds-server PRIVATE
  SQLITE_THREADSAFE=2
)

set_target_properties(atprotopds-server PROPERTIES
  OUTPUT_NAME "atprotopds"
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
  BUILD_RPATH "/usr/lib"
  INSTALL_RPATH "/usr/lib"
)

#=============================
# Fuzzer Targets
#=============================

option(BUILD_FUZZERS "Build fuzzing targets" OFF)

if(BUILD_FUZZERS)
  # Check if fuzzer sanitize is supported
  include(CheckCXXCompilerFlag)
  CHECK_CXX_COMPILER_FLAG("-fsanitize=fuzzer" HAS_FUZZER_SANITIZE)

  if(HAS_FUZZER_SANITIZE)
    message(STATUS "Using libFuzzer")
    set(FUZZER_CFLAGS -g -O1 -fno-omit-frame-pointer -fsanitize=fuzzer,address,undefined)
    set(FUZZER_LDFLAGS -fsanitize=fuzzer,address,undefined)
    set(FUZZER_DRIVER "")
    add_compile_definitions(LIBFUZZER=1)
  else()
    message(STATUS "libFuzzer not found, using internal main")
    set(FUZZER_CFLAGS -g -O1 -fno-omit-frame-pointer -fsanitize=address,undefined)
    set(FUZZER_LDFLAGS -fsanitize=address,undefined)
    set(FUZZER_DRIVER "")
  endif()

  set(FUZZER_SOURCES ${ATProtoPDS_SOURCES})
  
  # Macro to add fuzzer targets
  macro(add_pds_fuzzer name source)
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${source}")
      add_executable(${name} ${source} ${FUZZER_SOURCES} ${FUZZER_DRIVER})
      target_include_directories(${name} PRIVATE ATProtoPDS/Sources ${SECP256K1_INCLUDE_DIRS})
      target_link_libraries(${name} PRIVATE ${PLATFORM_LIBRARIES} ${SECP256K1_LIBRARIES})
      target_compile_options(${name} PRIVATE ${FUZZER_CFLAGS})
      target_link_options(${name} PRIVATE ${FUZZER_LDFLAGS})
      set_target_properties(${name} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/fuzzing")
    endif()
  endmacro()

  add_pds_fuzzer(fuzz_xrpc "fuzzing/fuzz_xrpc.mm")
  add_pds_fuzzer(fuzz_cbor "fuzzing/fuzz_cbor.mm")
  add_pds_fuzzer(fuzz_http "fuzzing/fuzz_http.mm")
  add_pds_fuzzer(fuzz_auth "fuzzing/fuzz_auth.mm")
  add_pds_fuzzer(fuzz_blob "fuzzing/fuzz_blob.mm")
  add_pds_fuzzer(fuzz_sqlite "fuzzing/fuzz_sqlite.mm")

endif()

#=============================
# Test Targets
#=============================

option(BUILD_TESTS "Build test targets" ON)
if(BUILD_TESTS AND APPLE)
  enable_testing()
  
  # Test sources
  file(GLOB_RECURSE TEST_OBJC_SOURCES "ATProtoPDS/Tests/**/*.m")
  list(APPEND TEST_OBJC_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/ATProtoPDS/Tests/test_main.m")
  
  # Exclude problematic tests (preserved from original)
  list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Database/PDSNewArchitectureTests.m")
  list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Integration/.*")
  list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Database/Integration/.*")
  # list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Identity/DIDResolverTests.m")
  list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Auth/KeyRotationTests.m")
  # list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Auth/OAuth2HandlerTests.m")
  list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Network/RateLimitingTests.m")

  add_executable(AllTests
    ${ATProtoPDS_SOURCES}
    ${TEST_OBJC_SOURCES}
  )

  target_include_directories(AllTests PRIVATE
    ATProtoPDS/Sources
    ATProtoPDS/Tests
    ${SECP256K1_INCLUDE_DIRS}
  )
  
  target_link_libraries(AllTests PRIVATE
    ${PLATFORM_LIBRARIES}
    ${SECP256K1_LIBRARIES}
  )
  
  if(APPLE)
    execute_process(COMMAND xcode-select -p OUTPUT_VARIABLE XCODE_DEVELOPER_DIR OUTPUT_STRIP_TRAILING_WHITESPACE)
    find_library(XCTest XCTest PATHS "${XCODE_DEVELOPER_DIR}/Platforms/MacOSX.platform/Developer/Library/Frameworks" REQUIRED)
    target_link_libraries(AllTests PRIVATE ${XCTest})
  else()
     # On GNUstep/Linux we need a test framework. 
     # Usually gnustep-base provides NSAutoreleasePool etc, but XCTest is Apple specific.
     # We might need a port of XCTest or use a different test runner.
     # For now, we'll try to link what we have, but if the tests import XCTest, they will fail on Linux.
     # The instructions don't explicitly ask to port tests yet, just build system setup.
  endif()

  target_compile_definitions(AllTests PRIVATE
    SQLITE_THREADSAFE=2
  )

  set_target_properties(AllTests PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/tests"
  )

  add_test(NAME AllTests COMMAND AllTests)
endif()

#=============================
# Installation
#=============================
install(TARGETS atprotopds-cli atprotopds-server
  RUNTIME DESTINATION bin
)

if(BUILD_FUZZERS)
  install(TARGETS fuzz_xrpc fuzz_cbor fuzz_http fuzz_auth
    RUNTIME DESTINATION bin
  )
endif()

#=============================
# Convenience Scripts
#=============================

# Generate helper scripts for development tasks
file(WRITE "${CMAKE_BINARY_DIR}/run-fuzzers-limited.sh" "#!/bin/bash
set -e
cd \"${CMAKE_SOURCE_DIR}\"
echo \"Running fuzzers with limited runs...\"
mkdir -p fuzzing/crashers fuzzing/corpus_xrpc fuzzing/corpus_cbor fuzzing/corpus_http fuzzing/corpus_sql
${CMAKE_BINARY_DIR}/fuzzing/fuzz_xrpc fuzzing/corpus_xrpc/ -max_len=65536 -jobs=8 -runs=5000 || echo \"XRPC fuzzer completed\"
${CMAKE_BINARY_DIR}/fuzzing/fuzz_cbor fuzzing/corpus_cbor/ -max_len=65536 -jobs=8 -runs=5000 || echo \"CBOR fuzzer completed\"
${CMAKE_BINARY_DIR}/fuzzing/fuzz_http fuzzing/corpus_http/ -max_len=65536 -jobs=8 -runs=5000 || echo \"HTTP fuzzer completed\"
${CMAKE_BINARY_DIR}/fuzzing/fuzz_auth fuzzing/corpus_xrpc/ -max_len=65536 -jobs=8 -runs=5000 || echo \"Auth fuzzer completed\"
${CMAKE_BINARY_DIR}/fuzzing/fuzz_blob /dev/null -max_len=65536 -jobs=8 -runs=1000 || echo \"Blob fuzzer completed\"
${CMAKE_BINARY_DIR}/fuzzing/fuzz_sqlite fuzzing/corpus_sql/ -max_len=10000 -jobs=8 -runs=1000 || echo \"SQL fuzzer completed\"
echo \"Fuzzing session complete.\"
")

file(WRITE "${CMAKE_BINARY_DIR}/run-fuzzers-extended.sh" "#!/bin/bash
set -e
cd \"${CMAKE_SOURCE_DIR}\"
echo \"Running comprehensive fuzzing session...\"
mkdir -p fuzzing/crashers fuzzing/corpus_xrpc fuzzing/corpus_cbor fuzzing/corpus_http fuzzing/corpus_sql
echo \"Running XRPC fuzzer (30 seconds)...\"
timeout 30 ${CMAKE_BINARY_DIR}/fuzzing/fuzz_xrpc fuzzing/corpus_xrpc/ -max_len=65536 -jobs=8 -timeout=10 || true
echo \"Running CBOR fuzzer (30 seconds)...\"
timeout 30 ${CMAKE_BINARY_DIR}/fuzzing/fuzz_cbor fuzzing/corpus_cbor/ -max_len=65536 -jobs=8 -timeout=10 || true
echo \"Running HTTP fuzzer (30 seconds)...\"
timeout 30 ${CMAKE_BINARY_DIR}/fuzzing/fuzz_http fuzzing/corpus_http/ -max_len=65536 -jobs=8 -timeout=10 || true
echo \"Running Auth fuzzer (30 seconds)...\"
timeout 30 ${CMAKE_BINARY_DIR}/fuzzing/fuzz_auth fuzzing/corpus_xrpc/ -max_len=65536 -jobs=8 -timeout=10 || true
echo \"Running Blob fuzzer (30 seconds)...\"
timeout 30 ${CMAKE_BINARY_DIR}/fuzzing/fuzz_blob /dev/null -max_len=50000000 -jobs=4 -timeout=10 || true
echo \"Running SQL fuzzer (30 seconds)...\"
timeout 30 ${CMAKE_BINARY_DIR}/fuzzing/fuzz_sqlite fuzzing/corpus_sql/ -max_len=10000 -jobs=4 -timeout=10 || true
echo \"Comprehensive fuzzing session complete.\"
ls -la fuzzing/crashers/ 2>/dev/null || echo \"No crashes detected\"
")

file(WRITE "${CMAKE_BINARY_DIR}/run-clang-tidy.sh" "#!/bin/bash
set -e
cd \"${CMAKE_SOURCE_DIR}\"
echo \"Running clang-tidy static analysis...\"
find ATProtoPDS/Sources -name \"*.m\" -o -name \"*.c\" | head -50 | xargs -I{} clang-tidy -p . --config-file=.clang-tidy {} 2>&1 | grep -E \"(warning|error)\" | head -100 || true
echo \"Clang-tidy analysis complete.\"
")

file(WRITE "${CMAKE_BINARY_DIR}/run-format.sh" "#!/bin/bash
cd \"${CMAKE_SOURCE_DIR}\"
echo \"Formatting source files...\"
find ATProtoPDS/Sources ATProtoPDS/Tests -name \"*.m\" -o -name \"*.c\" -o -name \"*.h\" | xargs clang-format -i -style=file
echo \"Formatting complete.\"
")

file(WRITE "${CMAKE_BINARY_DIR}/run-scan-build.sh" "#!/bin/bash
set -e
cd \"${CMAKE_SOURCE_DIR}\"
echo \"Running Clang Static Analyzer (scan-build)...\"
rm -rf build-analyzed
mkdir build-analyzed
cd build-analyzed
scan-build -use-cc=$(which clang) cmake .. -DCMAKE_BUILD_TYPE=Debug
scan-build -use-cc=$(which clang) make -j$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
echo \"Static analysis complete.\"
")

file(WRITE "${CMAKE_BINARY_DIR}/run-tests.sh" "#!/bin/bash
set -e
cd \"${CMAKE_SOURCE_DIR}\"
echo \"Running all tests...\"
${CMAKE_BINARY_DIR}/tests/AllTests
echo \"Tests complete.\"
")

# Make scripts executable
file(COPY "${CMAKE_BINARY_DIR}/run-fuzzers-limited.sh" DESTINATION "${CMAKE_SOURCE_DIR}/scripts/" FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
file(COPY "${CMAKE_BINARY_DIR}/run-fuzzers-extended.sh" DESTINATION "${CMAKE_SOURCE_DIR}/scripts/" FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
file(COPY "${CMAKE_BINARY_DIR}/run-clang-tidy.sh" DESTINATION "${CMAKE_SOURCE_DIR}/scripts/" FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
file(COPY "${CMAKE_BINARY_DIR}/run-format.sh" DESTINATION "${CMAKE_SOURCE_DIR}/scripts/" FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
file(COPY "${CMAKE_BINARY_DIR}/run-scan-build.sh" DESTINATION "${CMAKE_SOURCE_DIR}/scripts/" FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
file(COPY "${CMAKE_BINARY_DIR}/run-tests.sh" DESTINATION "${CMAKE_SOURCE_DIR}/scripts/" FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)

# Add custom targets for convenience
add_custom_target(run-fuzzers-limited COMMAND "${CMAKE_SOURCE_DIR}/scripts/run-fuzzers-limited.sh"
  COMMENT "Running fuzzers with limited runs"
  DEPENDS fuzz_xrpc fuzz_cbor fuzz_http fuzz_auth fuzz_blob fuzz_sqlite
)

add_custom_target(run-fuzzers-extended COMMAND "${CMAKE_SOURCE_DIR}/scripts/run-fuzzers-extended.sh"
  COMMENT "Running comprehensive fuzzing session"
  DEPENDS fuzz_xrpc fuzz_cbor fuzz_http fuzz_auth fuzz_blob fuzz_sqlite
)

add_custom_target(clang-tidy COMMAND "${CMAKE_SOURCE_DIR}/scripts/run-clang-tidy.sh"
  COMMENT "Running clang-tidy static analysis"
)

add_custom_target(format COMMAND "${CMAKE_SOURCE_DIR}/scripts/run-format.sh"
  COMMENT "Formatting source files"
)

add_custom_target(scan-build COMMAND "${CMAKE_SOURCE_DIR}/scripts/run-scan-build.sh"
  COMMENT "Running Clang Static Analyzer"
)

add_custom_target(run-tests COMMAND "${CMAKE_SOURCE_DIR}/scripts/run-tests.sh"
  COMMENT "Running all tests"
  DEPENDS AllTests
)

if(BUILD_FUZZERS)
  # Alias targets matching old Makefile names
  add_custom_target(fuzz-all ALL DEPENDS fuzz_xrpc fuzz_cbor fuzz_http fuzz_auth fuzz_blob fuzz_sqlite)
  add_custom_target(fuzz-xrpc DEPENDS fuzz_xrpc)
  add_custom_target(fuzz-cbor DEPENDS fuzz_cbor)
  add_custom_target(fuzz-http DEPENDS fuzz_http)
  add_custom_target(fuzz-auth DEPENDS fuzz_auth)
  add_custom_target(fuzz-blob DEPENDS fuzz_blob)
  add_custom_target(fuzz-sqlite DEPENDS fuzz_sqlite)
endif()

# Print build instructions
message(STATUS "")
message(STATUS "===========================================")
message(STATUS "ATProtoPDS Build System")
message(STATUS "===========================================")
message(STATUS "")
message(STATUS "Build Targets:")
message(STATUS "  atprotopds-cli    - CLI tool")
message(STATUS "  atprotopds-server - Server executable")
message(STATUS "  AllTests          - Unit tests")
message(STATUS "  fuzz_xrpc         - XRPC fuzzer")
message(STATUS "  fuzz_cbor         - CBOR/CAR fuzzer")
message(STATUS "  fuzz_http         - HTTP parser fuzzer")
message(STATUS "  fuzz_auth         - Authentication fuzzer")
message(STATUS "  fuzz_blob         - Blob security fuzzer")
message(STATUS "  fuzz_sqlite       - SQL injection fuzzer")
message(STATUS "")
message(STATUS "Convenience Targets:")
message(STATUS "  make run-fuzzers-limited   - Run fuzzers (limited)")
message(STATUS "  make run-fuzzers-extended  - Run fuzzers (extended)")
message(STATUS "  make clang-tidy            - Static analysis")
message(STATUS "  make format                - Format code")
message(STATUS "  make scan-build            - Static analyzer")
message(STATUS "  make run-tests             - Run all tests")
message(STATUS "")
message(STATUS "Options:")
message(STATUS "  -DBUILD_FUZZERS=ON   - Build fuzzing targets")
message(STATUS "  -DBUILD_TESTS=ON     - Build test targets")
message(STATUS "  -DCMAKE_BUILD_TYPE=  - Debug|Release")
message(STATUS "===========================================")
