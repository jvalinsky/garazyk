cmake_minimum_required(VERSION 3.21)

#=============================
# Pre-project Compiler Setup
#=============================
if(APPLE)
    # On macOS, find absolute paths to Xcode compilers to avoid circular proxy invocation
    # through wrappers like /usr/bin/cc or ~/.swiftly/bin/cc
    # NOTE: On macOS 26 Tahoe, xcrun requires explicit SDK name (macosx26.4 instead of macosx)
    # or SDKROOT to be set. Use direct path as fallback if xcrun fails.
    execute_process(
        COMMAND xcrun --sdk macosx26.4 -find clang
        OUTPUT_VARIABLE XCODE_CLANG
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
        RESULT_VARIABLE XCODE_CLANG_RESULT
    )
    execute_process(
        COMMAND xcrun --sdk macosx26.4 -find clang++
        OUTPUT_VARIABLE XCODE_CLANGXX
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
        RESULT_VARIABLE XCODE_CLANGXX_RESULT
    )

    # Only use xcrun output if it succeeded (result == 0) and path exists
    if(XCODE_CLANG_RESULT EQUAL 0 AND EXISTS "${XCODE_CLANG}")
        set(CMAKE_C_COMPILER "${XCODE_CLANG}")
        set(CMAKE_OBJC_COMPILER "${XCODE_CLANG}")
    else()
        # Fallback to direct Xcode toolchain path
        set(XCODE_TOOLCHAIN "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin")
        if(EXISTS "${XCODE_TOOLCHAIN}/clang")
            set(CMAKE_C_COMPILER "${XCODE_TOOLCHAIN}/clang")
            set(CMAKE_OBJC_COMPILER "${XCODE_TOOLCHAIN}/clang")
            message(STATUS "Using direct compiler path (xcrun failed): ${XCODE_TOOLCHAIN}/clang")
        endif()
    endif()

    if(XCODE_CLANGXX_RESULT EQUAL 0 AND EXISTS "${XCODE_CLANGXX}")
        set(CMAKE_CXX_COMPILER "${XCODE_CLANGXX}")
    else()
        if(EXISTS "${XCODE_TOOLCHAIN}/clang++")
            set(CMAKE_CXX_COMPILER "${XCODE_TOOLCHAIN}/clang++")
        endif()
    endif()

    # Set default SDK path for CMake 4.0+ (which no longer sets CMAKE_OSX_SYSROOT automatically)
    if(NOT DEFINED CMAKE_OSX_SYSROOT OR CMAKE_OSX_SYSROOT STREQUAL "")
        set(CMAKE_OSX_SYSROOT "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk")
        message(STATUS "Setting CMAKE_OSX_SYSROOT to macOS SDK (CMake 4.0+ compatibility)")
    endif()
elseif(UNIX)
    # On Linux, set compilers BEFORE project() to use clang
    find_program(CLANG_COMPILER NAMES /bin/clang clang-14 clang)
    if(CLANG_COMPILER)
        set(CMAKE_C_COMPILER ${CLANG_COMPILER})
        set(CMAKE_CXX_COMPILER ${CLANG_COMPILER})
        set(CMAKE_OBJC_COMPILER ${CLANG_COMPILER})
    endif()
endif()

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
# Compiler flags
set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -Wno-implicit-function-declaration")

# Enable ARC only on macOS (GNUstep runtime doesn't support it)
if(APPLE)
    set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -fobjc-arc")
endif()

# Platform Specific Configuration
if(NOT APPLE)
    add_compile_definitions(GNUSTEP LINUX)
    
    # GNUstep Configuration - defaults to common locations
    set(GNUSTEP_PREFIX "/home/exedev/GNUstep/install" CACHE PATH "GNUstep installation prefix")
    
    # Add common custom library search paths
    list(APPEND CMAKE_PREFIX_PATH "/usr/local" "${GNUSTEP_PREFIX}")
    
    # Find ObjC Runtime
    find_library(OBJC_LIBRARY NAMES objc-2 objc NAMES_PER_DIR
                 PATHS "/usr/local/lib" "${GNUSTEP_PREFIX}/lib" "${GNUSTEP_PREFIX}/Library/Libraries"
                 NO_DEFAULT_PATH)
    if(NOT OBJC_LIBRARY)
        find_library(OBJC_LIBRARY NAMES objc)
    endif()
    message(STATUS "Using ObjC library: ${OBJC_LIBRARY}")

    # Set Objective-C flags for modern runtime with ARC support
    set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -fblocks -fobjc-runtime=gnustep-2.2 -fobjc-arc")
    
    # Include Directories
    include_directories(SYSTEM "/usr/local/include")
    include_directories(SYSTEM "${GNUSTEP_PREFIX}/include")
    include_directories(SYSTEM "${GNUSTEP_PREFIX}/Library/Headers")
    include_directories(${CMAKE_CURRENT_SOURCE_DIR}/Sources/Compat)

    # Link Directories
    link_directories(BEFORE "/usr/local/lib")
    link_directories(BEFORE "${GNUSTEP_PREFIX}/lib")
    link_directories(BEFORE "${GNUSTEP_PREFIX}/Library/Libraries")
    link_directories(BEFORE /usr/GNUstep/Local/Library/Libraries)
    link_directories(BEFORE /usr/GNUstep/Local/lib)
endif()

#=============================
# Sanitizer Configuration
#=============================
option(ENABLE_ASAN "Enable AddressSanitizer" OFF)
option(ENABLE_TSAN "Enable ThreadSanitizer" OFF)
option(ENABLE_UBSAN "Enable UndefinedBehaviorSanitizer" OFF)

if(ENABLE_ASAN)
    message(STATUS "AddressSanitizer enabled")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fsanitize=address -fno-omit-frame-pointer")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fsanitize=address -fno-omit-frame-pointer")
    set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -fsanitize=address -fno-omit-frame-pointer")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -fsanitize=address")
endif()

if(ENABLE_TSAN)
    message(STATUS "ThreadSanitizer enabled")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fsanitize=thread")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fsanitize=thread")
    set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -fsanitize=thread")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -fsanitize=thread")
endif()

if(ENABLE_UBSAN)
    message(STATUS "UndefinedBehaviorSanitizer enabled")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fsanitize=undefined")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fsanitize=undefined")
    set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -fsanitize=undefined")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -fsanitize=undefined")
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

if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    add_compile_definitions(DEBUG=1)
endif()

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
    find_library(LOCALAUTH LocalAuthentication REQUIRED)

    # Find readline for REPL
    find_library(READLINE_LIBRARY NAMES readline libedit REQUIRED)

    # Find SQLite3
    find_library(SQLite3_LIBRARY sqlite3 REQUIRED)

    # Optional OpenSSL (enables non-keychain session key manager on macOS)
    set(PDS_OPENSSL_SESSION_KEY_MANAGER_AVAILABLE OFF)
    find_package(OpenSSL QUIET)
    if(OpenSSL_FOUND)
        set(PDS_OPENSSL_SESSION_KEY_MANAGER_AVAILABLE ON)
    endif()

    set(PLATFORM_LIBRARIES
        ${FOUNDATION}
        ${NETWORK}
        ${SECURITY}
        ${LOCALAUTH}
        ${COREIMAGE}
        ${APPKIT}
        ${IMAGEIO}
        ${COREGRAPHICS}
        ${SQLite3_LIBRARY}
        ${READLINE_LIBRARY}
        resolv
    )
    if(PDS_OPENSSL_SESSION_KEY_MANAGER_AVAILABLE)
        list(APPEND PLATFORM_LIBRARIES OpenSSL::Crypto)
        message(STATUS "macOS OpenSSL support enabled for non-keychain key manager")
    else()
        message(STATUS "macOS OpenSSL support not found; using Apple key manager only")
    endif()
else()
    # Linux Dependencies
    find_package(OpenSSL REQUIRED)
    find_package(SQLite3 REQUIRED)
    
    find_library(QRENCODE_LIB qrencode REQUIRED)
    find_path(QRENCODE_INCLUDE_DIR qrencode.h REQUIRED)
    
    if(QRENCODE_INCLUDE_DIR)
        include_directories(${QRENCODE_INCLUDE_DIR})
    endif()
    
    set(PLATFORM_LIBRARIES
        gnustep-base
        objc
        curl
        dispatch
        OpenSSL::SSL
        OpenSSL::Crypto
        ${SQLite3_LIBRARIES}
        ${QRENCODE_LIB}
        pthread
        m
        dl
        resolv
        icui18n
        icuuc
        icudata
        ffi
        xml2
        xslt
        z
        readline
    )
endif()

if(PDS_OPENSSL_SESSION_KEY_MANAGER_AVAILABLE)
    add_compile_definitions(PDS_OPENSSL_SESSION_KEY_MANAGER_AVAILABLE=1)
endif()

if(SQLite3_INCLUDE_DIRS)
    include_directories(${SQLite3_INCLUDE_DIRS})
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
# Source Files & Module Targets
#=============================

function(pds_filter_common_sources source_var)
  list(FILTER ${source_var} EXCLUDE REGEX ".*server_main\\.m$")
  list(FILTER ${source_var} EXCLUDE REGEX ".*/App/main\\.m$")
  list(FILTER ${source_var} EXCLUDE REGEX ".*/CLI/main\\.m$")
  list(FILTER ${source_var} EXCLUDE REGEX ".*/PLC/main\\.m$")
  list(FILTER ${source_var} EXCLUDE REGEX ".*/Relay/main\\.m$")
  list(FILTER ${source_var} EXCLUDE REGEX ".*/tests/.*")
  list(FILTER ${source_var} EXCLUDE REGEX ".*/Tests/.*")
  list(REMOVE_DUPLICATES ${source_var})
  set(${source_var} "${${source_var}}" PARENT_SCOPE)
endfunction()

file(GLOB_RECURSE ATPROTO_CORE_SOURCES
  "ATProtoPDS/Sources/Core/*.m"
  "ATProtoPDS/Sources/Core/*.c"
  "ATProtoPDS/Sources/Compat/*.m"
  "ATProtoPDS/Sources/Compat/*.c"
  "ATProtoPDS/Sources/Debug/*.m"
  "ATProtoPDS/Sources/Debug/*.c"
  "ATProtoPDS/Sources/Metrics/*.m"
  "ATProtoPDS/Sources/Metrics/*.c"
  "ATProtoPDS/Sources/AuthCrypto/*.m"
  "ATProtoPDS/Sources/AuthCrypto/*.c"
  "ATProtoPDS/Sources/AuthVerifier/*.m"
  "ATProtoPDS/Sources/AuthVerifier/*.c"
  "ATProtoPDS/Sources/Security/*.m"
  "ATProtoPDS/Sources/Security/*.c"
  "ATProtoPDS/Sources/Lexicon/*.m"
  "ATProtoPDS/Sources/Lexicon/*.c"
  "ATProtoPDS/Sources/App/PDSConfiguration.m"
)
list(FILTER ATPROTO_CORE_SOURCES EXCLUDE REGEX ".*/Core/Repositories/.*\\.m$")
list(FILTER ATPROTO_CORE_SOURCES EXCLUDE REGEX ".*/Core/Repositories/.*\\.c$")

file(GLOB_RECURSE ATPROTO_STORAGE_SOURCES
  "ATProtoPDS/Sources/Database/*.m"
  "ATProtoPDS/Sources/Database/*.c"
  "ATProtoPDS/Sources/Repository/*.m"
  "ATProtoPDS/Sources/Repository/*.c"
  "ATProtoPDS/Sources/Core/Repositories/*.m"
  "ATProtoPDS/Sources/Core/Repositories/*.c"
)

file(GLOB_RECURSE ATPROTO_SERVICES_SOURCES
  "ATProtoPDS/Sources/Auth/*.m"
  "ATProtoPDS/Sources/Auth/*.c"
  "ATProtoPDS/Sources/Blob/*.m"
  "ATProtoPDS/Sources/Blob/*.c"
  "ATProtoPDS/Sources/Email/*.m"
  "ATProtoPDS/Sources/Email/*.c"
  "ATProtoPDS/Sources/Identity/*.m"
  "ATProtoPDS/Sources/Identity/*.c"
  "ATProtoPDS/Sources/OAuthProvider/*.m"
  "ATProtoPDS/Sources/OAuthProvider/*.c"
  "ATProtoPDS/Sources/App/Services/*.m"
  "ATProtoPDS/Sources/App/Services/*.c"
  "ATProtoPDS/Sources/Services/*.m"
  "ATProtoPDS/Sources/Services/*.c"
  "ATProtoPDS/Sources/Admin/*.m"
  "ATProtoPDS/Sources/Admin/*.c"
  "ATProtoPDS/Sources/AppView/*.m"
  "ATProtoPDS/Sources/AppView/*.c"
  "ATProtoPDS/Sources/Media/*.m"
  "ATProtoPDS/Sources/Media/*.c"
  "ATProtoPDS/Sources/Federation/*.m"
  "ATProtoPDS/Sources/Federation/*.c"
)
list(FILTER ATPROTO_SERVICES_SOURCES EXCLUDE REGEX ".*/PDSAuth/.*")

file(GLOB_RECURSE ATPROTO_TRANSPORT_SOURCES
  "ATProtoPDS/Sources/Network/*.m"
  "ATProtoPDS/Sources/Network/*.c"
)
list(FILTER ATPROTO_TRANSPORT_SOURCES EXCLUDE REGEX ".*/Network/Xrpc.*\\.m$")
list(FILTER ATPROTO_TRANSPORT_SOURCES EXCLUDE REGEX ".*/Network/Xrpc.*\\.c$")
list(FILTER ATPROTO_TRANSPORT_SOURCES EXCLUDE REGEX ".*/Network/PDSHttpXrpcRoutePack\\.m$")
list(FILTER ATPROTO_TRANSPORT_SOURCES EXCLUDE REGEX ".*/Network/PDSHttpServerBuilder\\.m$")

file(GLOB_RECURSE ATPROTO_XRPC_SOURCES
  "ATProtoPDS/Sources/Network/Xrpc*.m"
  "ATProtoPDS/Sources/Network/Xrpc*.c"
  "ATProtoPDS/Sources/Network/PDSHttpXrpcRoutePack.m"
  "ATProtoPDS/Sources/Sync/RelayXRPCMethods.m"
  "ATProtoPDS/Sources/Sync/RelayXRPCMethods.c"
)
# XRPCError.m is included in ATPROTO_TRANSPORT_SOURCES, exclude from here to avoid duplicate
list(FILTER ATPROTO_XRPC_SOURCES EXCLUDE REGEX ".*/Network/XRPCError\\.m$")

file(GLOB_RECURSE ATPROTO_SYNC_SOURCES
  "ATProtoPDS/Sources/Sync/*.m"
  "ATProtoPDS/Sources/Sync/*.c"
)
list(FILTER ATPROTO_SYNC_SOURCES EXCLUDE REGEX ".*/Sync/RelayXRPCMethods\\.m$")
list(FILTER ATPROTO_SYNC_SOURCES EXCLUDE REGEX ".*/Sync/RelayXRPCMethods\\.c$")

file(GLOB_RECURSE ATPROTO_PLC_SOURCES
  "ATProtoPDS/Sources/PLC/*.m"
  "ATProtoPDS/Sources/PLC/*.c"
)

file(GLOB_RECURSE ATPROTO_RUNTIME_SOURCES
  "ATProtoPDS/Sources/App/*.m"
  "ATProtoPDS/Sources/App/*.c"
  "ATProtoPDS/Sources/CLI/*.m"
  "ATProtoPDS/Sources/CLI/*.c"
  "ATProtoPDS/Sources/PDSAuth/*.m"
  "ATProtoPDS/Sources/PDSAuth/*.c"
  "ATProtoPDS/Sources/Network/PDSHttpServerBuilder.m"
)
list(FILTER ATPROTO_RUNTIME_SOURCES EXCLUDE REGEX ".*/App/Services/.*")
list(FILTER ATPROTO_RUNTIME_SOURCES EXCLUDE REGEX ".*/App/PDSConfiguration\\.m$")

# Handle platform-specific network transport implementations.
list(FILTER ATPROTO_TRANSPORT_SOURCES EXCLUDE REGEX ".*/PDSNetworkTransport(Mac|Linux)\\.m$")
list(APPEND ATPROTO_TRANSPORT_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/ATProtoPDS/Sources/Network/PDSNetworkTransportLinux.m")
if(APPLE)
  list(APPEND ATPROTO_TRANSPORT_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/ATProtoPDS/Sources/Network/PDSNetworkTransportMac.m")
  if(NOT PDS_OPENSSL_SESSION_KEY_MANAGER_AVAILABLE)
    # OpenSSL-based manager is unavailable on this macOS host.
    list(FILTER ATPROTO_SERVICES_SOURCES EXCLUDE REGEX ".*/Auth/PDSOpenSSLSessionKeyManager\\.m$")
  endif()
endif()

if(NOT APPLE)
  # PDSAppleKeyManager.m uses Security.framework (macOS/iOS only)
  list(FILTER ATPROTO_SERVICES_SOURCES EXCLUDE REGEX ".*/Auth/PDSAppleKeyManager\\.m$")

  # PDSCLIHealthCommand uses Mach APIs.
  list(FILTER ATPROTO_RUNTIME_SOURCES EXCLUDE REGEX ".*/CLI/PDSCLIHealthCommand\\.m$")

  # SSLPinningManager.m uses SecTrust (not yet ported).
  list(FILTER ATPROTO_TRANSPORT_SOURCES EXCLUDE REGEX ".*/Network/SSLPinningManager\\.m$")

  # WebSocketServer.m uses Network.framework.
  list(FILTER ATPROTO_SYNC_SOURCES EXCLUDE REGEX ".*/Sync/WebSocketServer\\.m$")

  # Add Linux stub implementations and compat shims.
  list(APPEND ATPROTO_CORE_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/Sources/Compat/Stubs/LinuxStubs.m")
  file(GLOB COMPAT_SOURCES
    "Sources/Compat/*.m"
    "Sources/Compat/*.c")
  list(APPEND ATPROTO_CORE_SOURCES ${COMPAT_SOURCES})
endif()

pds_filter_common_sources(ATPROTO_CORE_SOURCES)
pds_filter_common_sources(ATPROTO_STORAGE_SOURCES)
pds_filter_common_sources(ATPROTO_SERVICES_SOURCES)
pds_filter_common_sources(ATPROTO_TRANSPORT_SOURCES)
pds_filter_common_sources(ATPROTO_XRPC_SOURCES)
pds_filter_common_sources(ATPROTO_SYNC_SOURCES)
pds_filter_common_sources(ATPROTO_PLC_SOURCES)
pds_filter_common_sources(ATPROTO_RUNTIME_SOURCES)

set(ATPROTO_ALL_RUNTIME_SOURCES
  ${ATPROTO_CORE_SOURCES}
  ${ATPROTO_STORAGE_SOURCES}
  ${ATPROTO_SERVICES_SOURCES}
  ${ATPROTO_TRANSPORT_SOURCES}
  ${ATPROTO_XRPC_SOURCES}
  ${ATPROTO_SYNC_SOURCES}
  ${ATPROTO_PLC_SOURCES}
  ${ATPROTO_RUNTIME_SOURCES}
)
list(REMOVE_DUPLICATES ATPROTO_ALL_RUNTIME_SOURCES)

add_library(ATProtoCore STATIC ${ATPROTO_CORE_SOURCES})
add_library(ATProtoStorage STATIC ${ATPROTO_STORAGE_SOURCES})
add_library(ATProtoServices STATIC ${ATPROTO_SERVICES_SOURCES})
add_library(ATProtoTransport STATIC ${ATPROTO_TRANSPORT_SOURCES})
add_library(ATProtoXRPC STATIC ${ATPROTO_XRPC_SOURCES})
add_library(ATProtoSync STATIC ${ATPROTO_SYNC_SOURCES})
add_library(ATProtoPLC STATIC ${ATPROTO_PLC_SOURCES})
add_library(ATProtoRuntime STATIC ${ATPROTO_RUNTIME_SOURCES})

set(PDS_MODULE_TARGETS
  ATProtoCore
  ATProtoStorage
  ATProtoServices
  ATProtoTransport
  ATProtoXRPC
  ATProtoSync
  ATProtoPLC
  ATProtoRuntime
)

foreach(target ${PDS_MODULE_TARGETS})
  target_include_directories(${target} PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/ATProtoPDS/Sources
    ${CMAKE_CURRENT_SOURCE_DIR}/ATProtoPDS/Frameworks
    ${SECP256K1_INCLUDE_DIRS}
  )
  target_compile_definitions(${target} PUBLIC
    SQLITE_THREADSAFE=2
  )
endforeach()

target_link_libraries(ATProtoStorage PUBLIC ATProtoCore)
target_link_libraries(ATProtoServices PUBLIC ATProtoStorage ATProtoCore)
target_link_libraries(ATProtoTransport PUBLIC ATProtoCore)
target_link_libraries(ATProtoSync PUBLIC ATProtoStorage ATProtoTransport ATProtoCore)
target_link_libraries(ATProtoXRPC PUBLIC ATProtoServices ATProtoStorage ATProtoTransport ATProtoSync ATProtoCore)
target_link_libraries(ATProtoPLC PUBLIC ATProtoTransport ATProtoCore)
target_link_libraries(ATProtoRuntime PUBLIC ATProtoServices ATProtoTransport ATProtoXRPC ATProtoSync ATProtoCore)

#=============================
# Main Executables
#=============================

# CLI Tool (kaszlak - PDS binary)
add_executable(kaszlak
  ATProtoPDS/Sources/CLI/main.m
)

target_include_directories(kaszlak PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/ATProtoPDS/Sources
  ${CMAKE_CURRENT_SOURCE_DIR}/ATProtoPDS/Frameworks
  ${SECP256K1_INCLUDE_DIRS}
)

target_link_libraries(kaszlak PRIVATE
  ATProtoRuntime
  ATProtoServices
  ATProtoTransport
  ATProtoXRPC
  ATProtoSync
  ATProtoStorage
  ATProtoCore
  ${PLATFORM_LIBRARIES}
  ${SECP256K1_LIBRARIES}
  ${READLINE_LIBRARY}
)

target_compile_definitions(kaszlak PRIVATE
  SQLITE_THREADSAFE=2
)

set_target_properties(kaszlak PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

# PLC Server (campagnola - PLC directory binary)
add_executable(campagnola
  ATProtoPDS/Sources/PLC/main.m
)

target_include_directories(campagnola PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/ATProtoPDS/Sources
  ${CMAKE_CURRENT_SOURCE_DIR}/ATProtoPDS/Frameworks
  ${SECP256K1_INCLUDE_DIRS}
)

target_link_libraries(campagnola PRIVATE
  ATProtoPLC
  ATProtoTransport
  ATProtoCore
  ${PLATFORM_LIBRARIES}
  ${SECP256K1_LIBRARIES}
  ${READLINE_LIBRARY}
)

target_compile_definitions(campagnola PRIVATE
  SQLITE_THREADSAFE=2
)

set_target_properties(campagnola PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

# Relay Server (zuk - AT Protocol relay)
add_executable(zuk
  ATProtoPDS/Sources/Relay/main.m
)

target_include_directories(zuk PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/ATProtoPDS/Sources
  ${CMAKE_CURRENT_SOURCE_DIR}/ATProtoPDS/Frameworks
  ${SECP256K1_INCLUDE_DIRS}
)

target_link_libraries(zuk PRIVATE
  ATProtoSync
  ATProtoTransport
  ATProtoCore
  ${PLATFORM_LIBRARIES}
  ${SECP256K1_LIBRARIES}
  ${READLINE_LIBRARY}
)

target_compile_definitions(zuk PRIVATE
  SQLITE_THREADSAFE=2
)

set_target_properties(zuk PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

# Tutorial 1: Hello PDS Example
add_executable(hello-pds
  examples/tutorial-1-hello-pds/src/main.m
)

target_include_directories(hello-pds PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/ATProtoPDS/Sources
  ${CMAKE_CURRENT_SOURCE_DIR}/ATProtoPDS/Frameworks
  ${SECP256K1_INCLUDE_DIRS}
)

target_link_libraries(hello-pds PRIVATE
  ATProtoRuntime
  ATProtoServices
  ATProtoTransport
  ATProtoXRPC
  ATProtoSync
  ATProtoStorage
  ATProtoCore
  ${PLATFORM_LIBRARIES}
  ${SECP256K1_LIBRARIES}
)

target_compile_definitions(hello-pds PRIVATE
  SQLITE_THREADSAFE=2
)

set_target_properties(hello-pds PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
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
    set(FUZZER_DRIVER "fuzzing/standalone_driver.cpp")
  endif()

  set(FUZZER_SOURCES ${ATPROTO_ALL_RUNTIME_SOURCES})
  
  # Macro to add fuzzer targets
  macro(add_pds_fuzzer name source)
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${source}")
      add_executable(${name} ${source} ${FUZZER_SOURCES} ${FUZZER_DRIVER})
      target_include_directories(${name} PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/ATProtoPDS/Sources
        ${CMAKE_CURRENT_SOURCE_DIR}/ATProtoPDS/Frameworks
        ${SECP256K1_INCLUDE_DIRS})
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
  add_pds_fuzzer(fuzz_lexicon "fuzzing/fuzz_lexicon.mm")
  add_pds_fuzzer(fuzz_mst "fuzzing/fuzz_mst.mm")

endif()

#=============================
# Test Targets
#=============================

option(BUILD_TESTS "Build test targets" ON)
if(BUILD_TESTS)
  enable_testing()
  
  # Enable LLVM Source-Based Code Coverage
  set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fprofile-instr-generate -fcoverage-mapping")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fprofile-instr-generate -fcoverage-mapping")
  set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -fprofile-instr-generate -fcoverage-mapping")
  set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -fprofile-instr-generate -fcoverage-mapping")

  # Test sources
  file(GLOB_RECURSE TEST_OBJC_SOURCES "ATProtoPDS/Tests/**/*.m")
  list(APPEND TEST_OBJC_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/ATProtoPDS/Tests/test_main.m")
  list(APPEND TEST_OBJC_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/ATProtoPDS/Tests/Database/PDSDatabaseLRUTests.m")
  
  # Exclude problematic tests (preserved from original)
  list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Database/PDSNewArchitectureTests.m")
  # Exclude top-level Integration tests only, except our new PLC integration test
  list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX "ATProtoPDS/Tests/Integration/PDSIntegrationTests.m")
  list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX "ATProtoPDS/Tests/Integration/comprehensive_tests.m")
  # list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Database/Integration/.*")
  # list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Identity/DIDResolverTests.m")
  # Phase 1: Enabled Core Logic & Crypto Tests
  # list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Auth/KeyRotationTests.m")
  # list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Network/RateLimitingTests.m")
  # list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Auth/OAuth2Tests.m")
  # list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Auth/OAuth2EndpointTests.m")
  # list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Auth/TOTPTests.m")
  
  if(APPLE)
      list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Compat/.*")
  endif()

  list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Network/PDSIntegrationTests.m")

  # Linux-specific test exclusions
  if(NOT APPLE)
    # Exclude OAuth2EndpointTests if they depend on specific auth flows not yet fully ported
    # But basic OAuth/DID tests should now work
    # list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Auth/OAuth2EndpointTests.m")
    
    # Enable Identity/Network tests
    # list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Identity/DIDResolverTests.m")
    # list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Identity/HandleResolverTests.m")
    # list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Identity/PLCDirectoryClientTests.m")
    # list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Network/XrpcIntegrationTests.m")
    
    # Exclude WebSocket/Sync tests (WebSocketServer not implemented)
    list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Sync/SubscribeReposHandlerTests.m")
    list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Sync/WebSocketConnectionTests.m")

    # Exclude KeyManager tests that might rely on specific Keychain behaviors not yet mocked
    # But we want to test SecKey implementation!
    # list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Auth/KeyManagerSecurityTests.m")
    # list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/CharacterizationTests/KeyManagerCharacterizationTests.m")
    
    # Enable ActorStore tests (uses SQLite)
    # list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Database/ActorStore/ActorStoreTests.m")
    
    # Enable DID validation
    # list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Core/DIDValidationTests.m")
  endif()

  add_executable(AllTests
    ${TEST_OBJC_SOURCES}
  )

  target_include_directories(AllTests PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/ATProtoPDS/Sources
    ${CMAKE_CURRENT_SOURCE_DIR}/ATProtoPDS/Frameworks
    ${CMAKE_CURRENT_SOURCE_DIR}/ATProtoPDS/Tests
    ${SECP256K1_INCLUDE_DIRS}
  )
  
  target_link_libraries(AllTests PRIVATE
    ATProtoRuntime
    ATProtoServices
    ATProtoTransport
    ATProtoXRPC
    ATProtoSync
    ATProtoStorage
    ATProtoCore
    ATProtoPLC
    ${PLATFORM_LIBRARIES}
    ${SECP256K1_LIBRARIES}
  )
  
  if(APPLE)
    execute_process(COMMAND xcode-select -p OUTPUT_VARIABLE XCODE_DEVELOPER_DIR OUTPUT_STRIP_TRAILING_WHITESPACE)
    find_library(XCTest XCTest PATHS "${XCODE_DEVELOPER_DIR}/Platforms/MacOSX.platform/Developer/Library/Frameworks" REQUIRED)
    target_link_libraries(AllTests PRIVATE ${XCTest})
    # Critical: Load all Objective-C categories from static libraries
    # Without -ObjC, category methods (like PDSActorStore+Account) are not linked
    set_target_properties(AllTests PROPERTIES
      LINK_FLAGS "-ObjC"
    )
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
# Dependency Boundary Audits
#=============================
add_custom_target(check-boundaries
  COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/scripts/check_module_boundaries.sh" "${CMAKE_CURRENT_SOURCE_DIR}"
  WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
  COMMENT "Validating source import and module linkage boundaries"
  VERBATIM
)

#=============================
# Installation
#=============================
install(TARGETS kaszlak
  RUNTIME DESTINATION bin
)

if(BUILD_FUZZERS)
  install(TARGETS fuzz_xrpc fuzz_cbor fuzz_http fuzz_auth
    RUNTIME DESTINATION bin
  )
endif()

#=============================
# Frontend (Objective-J)
#=============================
option(BUILD_CAPPUCCINO_UI "Build Cappuccino Objective-J UI assets" OFF)
if(BUILD_CAPPUCCINO_UI)
  find_program(NPM_EXECUTABLE npm)
  if(NOT NPM_EXECUTABLE)
    message(FATAL_ERROR "BUILD_CAPPUCCINO_UI=ON requires npm in PATH")
  endif()

  add_custom_target(cappuccino-ui-build
    COMMAND "${CMAKE_SOURCE_DIR}/scripts/build_cappuccino_ui.sh" Release
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    COMMENT "Building Cappuccino Objective-J UI"
    VERBATIM
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
echo \"Running Lexicon fuzzer...\"
${CMAKE_BINARY_DIR}/fuzzing/fuzz_lexicon fuzzing/corpus_lexicon/ -max_len=65536 -jobs=8 -runs=1000 || echo \"Lexicon fuzzer completed\"
echo \"Running MST fuzzer...\"
${CMAKE_BINARY_DIR}/fuzzing/fuzz_mst fuzzing/corpus_mst/ -max_len=65536 -jobs=8 -runs=1000 || echo \"MST fuzzer completed\"
echo \"Fuzzing session complete.\"
")

file(WRITE "${CMAKE_BINARY_DIR}/run-fuzzers-extended.sh" "#!/bin/bash
set -e
cd \"${CMAKE_SOURCE_DIR}\"
echo \"Running comprehensive fuzzing session...\"
mkdir -p fuzzing/crashers fuzzing/corpus_xrpc fuzzing/corpus_cbor fuzzing/corpus_http fuzzing/corpus_sql fuzzing/corpus_lexicon fuzzing/corpus_mst
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
echo \"Running Lexicon fuzzer (30 seconds)...\"
timeout 30 ${CMAKE_BINARY_DIR}/fuzzing/fuzz_lexicon fuzzing/corpus_lexicon/ -max_len=65536 -jobs=8 -timeout=10 || true
echo \"Running MST fuzzer (30 seconds)...\"
timeout 30 ${CMAKE_BINARY_DIR}/fuzzing/fuzz_mst fuzzing/corpus_mst/ -max_len=65536 -jobs=8 -timeout=10 || true
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
set -euo pipefail
script_dir=\"$(cd \"$(dirname \"\${BASH_SOURCE[0]}\")\" && pwd)\"
repo_root=\"$(cd \"\${script_dir}/..\" && pwd)\"
test_binary=\"\${repo_root}/build/tests/AllTests\"

if [[ ! -x \"\${test_binary}\" ]]; then
echo \"Test binary not found at: \${test_binary}\"
echo \"Build it first with: xcodebuild -scheme AllTests build\"
exit 1
fi

echo \"Running all tests...\"
\"\${test_binary}\"
echo \"Tests complete.\"
")

# Make scripts executable
file(COPY "${CMAKE_BINARY_DIR}/run-fuzzers-limited.sh" DESTINATION "${CMAKE_BINARY_DIR}/scripts/" FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
file(COPY "${CMAKE_BINARY_DIR}/run-fuzzers-extended.sh" DESTINATION "${CMAKE_BINARY_DIR}/scripts/" FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
file(COPY "${CMAKE_BINARY_DIR}/run-clang-tidy.sh" DESTINATION "${CMAKE_BINARY_DIR}/scripts/" FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
file(COPY "${CMAKE_BINARY_DIR}/run-format.sh" DESTINATION "${CMAKE_BINARY_DIR}/scripts/" FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
file(COPY "${CMAKE_BINARY_DIR}/run-scan-build.sh" DESTINATION "${CMAKE_BINARY_DIR}/scripts/" FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
file(COPY "${CMAKE_BINARY_DIR}/run-tests.sh" DESTINATION "${CMAKE_BINARY_DIR}/scripts/" FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)

# Add custom targets for convenience
add_custom_target(run-fuzzers-limited COMMAND "${CMAKE_BINARY_DIR}/scripts/run-fuzzers-limited.sh"
  COMMENT "Running fuzzers with limited runs"
  DEPENDS fuzz_xrpc fuzz_cbor fuzz_http fuzz_auth fuzz_blob fuzz_sqlite
)

add_custom_target(run-fuzzers-extended COMMAND "${CMAKE_BINARY_DIR}/scripts/run-fuzzers-extended.sh"
  COMMENT "Running comprehensive fuzzing session"
  DEPENDS fuzz_xrpc fuzz_cbor fuzz_http fuzz_auth fuzz_blob fuzz_sqlite
)

add_custom_target(clang-tidy COMMAND "${CMAKE_BINARY_DIR}/scripts/run-clang-tidy.sh"
  COMMENT "Running clang-tidy static analysis"
)

add_custom_target(format COMMAND "${CMAKE_BINARY_DIR}/scripts/run-format.sh"
  COMMENT "Formatting source files"
)

add_custom_target(scan-build COMMAND "${CMAKE_BINARY_DIR}/scripts/run-scan-build.sh"
  COMMENT "Running Clang Static Analyzer"
)

add_custom_target(run-tests COMMAND "${CMAKE_BINARY_DIR}/scripts/run-tests.sh"
  COMMENT "Running all tests"
  DEPENDS AllTests
)

if(BUILD_FUZZERS)
  # Alias targets matching old Makefile names
  add_custom_target(fuzz-all ALL DEPENDS fuzz_xrpc fuzz_cbor fuzz_http fuzz_auth fuzz_blob fuzz_sqlite fuzz_lexicon fuzz_mst)
  add_custom_target(fuzz-xrpc DEPENDS fuzz_xrpc)
  add_custom_target(fuzz-cbor DEPENDS fuzz_cbor)
  add_custom_target(fuzz-http DEPENDS fuzz_http)
  add_custom_target(fuzz-auth DEPENDS fuzz_auth)
  add_custom_target(fuzz-blob DEPENDS fuzz_blob)
  add_custom_target(fuzz-sqlite DEPENDS fuzz_sqlite)
  add_custom_target(fuzz-lexicon DEPENDS fuzz_lexicon)
  add_custom_target(fuzz-mst DEPENDS fuzz_mst)
endif()

# Print build instructions
message(STATUS "")
message(STATUS "===========================================")
message(STATUS "ATProtoPDS Build System")
message(STATUS "===========================================")
message(STATUS "")
message(STATUS "Build Targets:")
message(STATUS "  kaszlak           - PDS CLI tool")
message(STATUS "  campagnola        - PLC directory server")
message(STATUS "  zuk               - Relay server")
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
message(STATUS "  -DBUILD_CAPPUCCINO_UI=ON - Build Objective-J/Cappuccino UI assets")
message(STATUS "  -DCMAKE_BUILD_TYPE=  - Debug|Release")
message(STATUS "===========================================")
