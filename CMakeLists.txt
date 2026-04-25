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
    set(GNUSTEP_PREFIX "DEPLOY_DIR/GNUstep/install" CACHE PATH "GNUstep installation prefix")
    
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
    include_directories(${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Sources/Compat/PlatformShims)

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

    # Find XCTest framework (only on macOS, not GNUstep/Linux)
    set(XCTEST_SEARCH_PATHS "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks")
    find_library(XCTEST XCTest PATHS ${XCTEST_SEARCH_PATHS} NO_DEFAULT_PATH)

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
  "Garazyk/Sources/Core/*.m"
  "Garazyk/Sources/Core/*.c"
  "Garazyk/Sources/Compat/*.m"
  "Garazyk/Sources/Compat/*.c"
  "Garazyk/Sources/Debug/*.m"
  "Garazyk/Sources/Debug/*.c"
  "Garazyk/Sources/Metrics/*.m"
  "Garazyk/Sources/Metrics/*.c"
  "Garazyk/Sources/Auth/Crypto/*.m"
  "Garazyk/Sources/Auth/Crypto/*.c"
  "Garazyk/Sources/Auth/Verifier/*.m"
  "Garazyk/Sources/Auth/Verifier/*.c"
  "Garazyk/Sources/Security/*.m"
  "Garazyk/Sources/Security/*.c"
  "Garazyk/Sources/Lexicon/*.m"
  "Garazyk/Sources/Lexicon/*.c"
  "Garazyk/Sources/App/PDSConfiguration.m"
)
list(FILTER ATPROTO_CORE_SOURCES EXCLUDE REGEX ".*/Core/Repositories/.*\\.m$")
list(FILTER ATPROTO_CORE_SOURCES EXCLUDE REGEX ".*/Core/Repositories/.*\\.c$")

file(GLOB_RECURSE ATPROTO_STORAGE_SOURCES
  "Garazyk/Sources/Database/*.m"
  "Garazyk/Sources/Database/*.c"
  "Garazyk/Sources/Repository/*.m"
  "Garazyk/Sources/Repository/*.c"
  "Garazyk/Sources/Core/Repositories/*.m"
  "Garazyk/Sources/Core/Repositories/*.c"
)

file(GLOB_RECURSE ATPROTO_SERVICES_SOURCES
  "Garazyk/Sources/Auth/*.m"
  "Garazyk/Sources/Auth/*.c"
  "Garazyk/Sources/Blob/*.m"
  "Garazyk/Sources/Blob/*.c"
  "Garazyk/Sources/Email/*.m"
  "Garazyk/Sources/Email/*.c"
  "Garazyk/Sources/Identity/*.m"
  "Garazyk/Sources/Identity/*.c"
  "Garazyk/Sources/Services/*.m"
  "Garazyk/Sources/Services/*.c"
  "Garazyk/Sources/Admin/*.m"
  "Garazyk/Sources/Admin/*.c"
  "Garazyk/Sources/AppView/*.m"
  "Garazyk/Sources/AppView/*.c"
  "Garazyk/Sources/Media/*.m"
  "Garazyk/Sources/Media/*.c"
  "Garazyk/Sources/Federation/*.m"
  "Garazyk/Sources/Federation/*.c"
)
list(FILTER ATPROTO_SERVICES_SOURCES EXCLUDE REGEX ".*/PDSAuth/.*")
list(FILTER ATPROTO_SERVICES_SOURCES EXCLUDE REGEX ".*/Auth/Crypto/.*")
list(FILTER ATPROTO_SERVICES_SOURCES EXCLUDE REGEX ".*/Auth/Verifier/.*")
list(FILTER ATPROTO_SERVICES_SOURCES EXCLUDE REGEX ".*/Auth/PDS/.*")
list(FILTER ATPROTO_SERVICES_SOURCES EXCLUDE REGEX ".*/AppView/Server/.*")
list(FILTER ATPROTO_SERVICES_SOURCES EXCLUDE REGEX ".*/Services/PDS(AdminService|PhoneVerificationProvider)\\.m$")

file(GLOB_RECURSE ATPROTO_TRANSPORT_SOURCES
  "Garazyk/Sources/Network/*.m"
  "Garazyk/Sources/Network/*.c"
)
list(FILTER ATPROTO_TRANSPORT_SOURCES EXCLUDE REGEX ".*/Network/Xrpc.*\\.m$")
list(FILTER ATPROTO_TRANSPORT_SOURCES EXCLUDE REGEX ".*/Network/Xrpc.*\\.c$")
list(FILTER ATPROTO_TRANSPORT_SOURCES EXCLUDE REGEX ".*/Network/PDSHttpXrpcRoutePack\\.m$")
list(FILTER ATPROTO_TRANSPORT_SOURCES EXCLUDE REGEX ".*/Network/RelayXrpcRoutePack\\.m$")
list(FILTER ATPROTO_TRANSPORT_SOURCES EXCLUDE REGEX ".*/Network/AppViewXRpcRoutePack\\.m$")
list(FILTER ATPROTO_TRANSPORT_SOURCES EXCLUDE REGEX ".*/Network/PDSHttpServerBuilder\\.m$")

file(GLOB_RECURSE ATPROTO_XRPC_SOURCES
  "Garazyk/Sources/Network/Xrpc*.m"
  "Garazyk/Sources/Network/Xrpc*.c"
  "Garazyk/Sources/Network/PDSHttpXrpcRoutePack.m"
  "Garazyk/Sources/Network/RelayXrpcRoutePack.m"
  "Garazyk/Sources/Network/AppViewXRpcRoutePack.m"
)
# XRPCError.m is included in ATPROTO_TRANSPORT_SOURCES, exclude from here to avoid duplicate
list(FILTER ATPROTO_XRPC_SOURCES EXCLUDE REGEX ".*/Network/XRPCError\\.m$")

file(GLOB_RECURSE ATPROTO_SYNC_SOURCES
  "Garazyk/Sources/Sync/Firehose/*.m"
  "Garazyk/Sources/Sync/Firehose/*.c"
  "Garazyk/Sources/Sync/Relay/*.m"
  "Garazyk/Sources/Sync/Relay/*.c"
  "Garazyk/Sources/Sync/WebSocket/*.m"
  "Garazyk/Sources/Sync/WebSocket/*.c"
)

file(GLOB_RECURSE ATPROTO_PLC_SOURCES
  "Garazyk/Sources/PLC/*.m"
  "Garazyk/Sources/PLC/*.c"
)

file(GLOB_RECURSE ATPROTO_RUNTIME_SOURCES
  "Garazyk/Sources/App/*.m"
  "Garazyk/Sources/App/*.c"
  "Garazyk/Sources/CLI/*.m"
  "Garazyk/Sources/CLI/*.c"
  "Garazyk/Sources/Auth/PDS/*.m"
  "Garazyk/Sources/Auth/PDS/*.c"
  "Garazyk/Sources/Network/PDSHttpServerBuilder.m"
)
list(FILTER ATPROTO_RUNTIME_SOURCES EXCLUDE REGEX ".*/App/Services/.*")
list(FILTER ATPROTO_RUNTIME_SOURCES EXCLUDE REGEX ".*/App/PDSConfiguration\\.m$")

# Handle platform-specific network transport implementations.
list(FILTER ATPROTO_TRANSPORT_SOURCES EXCLUDE REGEX ".*/PDSNetworkTransport(Mac|Linux)\\.m$")
list(APPEND ATPROTO_TRANSPORT_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Sources/Network/PDSNetworkTransportLinux.m")
if(APPLE)
  list(APPEND ATPROTO_TRANSPORT_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Sources/Network/PDSNetworkTransportMac.m")
  if(NOT PDS_OPENSSL_SESSION_KEY_MANAGER_AVAILABLE)
    # OpenSSL-based manager is unavailable on this macOS host.
    list(FILTER ATPROTO_SERVICES_SOURCES EXCLUDE REGEX ".*/Auth/PDSOpenSSLSessionKeyManager\\.m$")
  endif()
  # PDSOpenSSLES256KeyManager is only for GNUstep/Linux
  list(FILTER ATPROTO_SERVICES_SOURCES EXCLUDE REGEX ".*/Auth/PDSOpenSSLES256KeyManager\\.m$")
endif()

if(NOT APPLE)
  # PDSAppleKeyManager.m uses Security.framework (macOS/iOS only)
  list(FILTER ATPROTO_SERVICES_SOURCES EXCLUDE REGEX ".*/Auth/PDSAppleKeyManager\\.m$")

  # PDSOpenSSLES256KeyManager is required by AuthCryptoJWK (Core) on GNUstep.
  # Keep it in Core to satisfy static-link ordering for Linux binaries.
  list(FILTER ATPROTO_SERVICES_SOURCES EXCLUDE REGEX ".*/Auth/PDSOpenSSLES256KeyManager\\.m$")
  list(APPEND ATPROTO_CORE_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Sources/Auth/PDSOpenSSLES256KeyManager.m")

  # PDSCLIHealthCommand now has cross-platform guards and is included on Linux.

  # SSLPinningManager.m uses SecTrust (not yet ported).
  list(FILTER ATPROTO_TRANSPORT_SOURCES EXCLUDE REGEX ".*/Network/SSLPinningManager\\.m$")

  # WebSocketServer.m uses Network.framework.
  list(FILTER ATPROTO_SYNC_SOURCES EXCLUDE REGEX ".*/Sync/WebSocketServer\\.m$")

  # Compat shim implementations are already captured by the GLOB_RECURSE on
  # Garazyk/Sources/Compat/*.m above — no explicit additions needed here.
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
    ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Sources
    ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Frameworks
    ${SECP256K1_INCLUDE_DIRS}
  )
  target_compile_definitions(${target} PUBLIC
    SQLITE_THREADSAFE=2
  )
endforeach()

target_link_libraries(ATProtoStorage PUBLIC ATProtoCore)
target_link_libraries(ATProtoServices PUBLIC ATProtoStorage ATProtoCore ${SECP256K1_LIBRARIES})
target_link_libraries(ATProtoTransport PUBLIC ATProtoCore)
target_link_libraries(ATProtoSync PUBLIC ATProtoStorage ATProtoTransport ATProtoCore)
target_link_libraries(ATProtoXRPC PUBLIC ATProtoServices ATProtoStorage ATProtoTransport ATProtoSync ATProtoCore)
target_link_libraries(ATProtoPLC PUBLIC ATProtoTransport ATProtoCore)
target_link_libraries(ATProtoRuntime PUBLIC ATProtoPLC ATProtoServices ATProtoTransport ATProtoXRPC ATProtoSync ATProtoCore)

#=============================
# Main Executables
#=============================


# CLI Tool (kaszlak - PDS binary)
add_executable(kaszlak
  Garazyk/Sources/CLI/main.m
)

target_include_directories(kaszlak PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Sources
  ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Frameworks
  ${SECP256K1_INCLUDE_DIRS}
)

if(APPLE)
  target_link_libraries(kaszlak PRIVATE
    ATProtoAppViewServer
    ATProtoRuntime
    ATProtoServices
    ATProtoTransport
    ATProtoXRPC
    ATProtoSync
    ATProtoStorage
    ATProtoPLC
    ATProtoCore
    # GNU ld resolves static archives in a single pass; keep a second pass for
    # cyclic refs between runtime/transport/plc objects.
    ATProtoRuntime
    ATProtoPLC
    ${PLATFORM_LIBRARIES}
    ${SECP256K1_LIBRARIES}
    ${READLINE_LIBRARY}
  )
else()
  target_link_libraries(kaszlak PRIVATE
    -Wl,--whole-archive
    ATProtoAppViewServer
    ATProtoRuntime
    ATProtoServices
    ATProtoTransport
    ATProtoXRPC
    ATProtoSync
    ATProtoStorage
    ATProtoPLC
    ATProtoCore
    -Wl,--no-whole-archive
    ${PLATFORM_LIBRARIES}
    ${SECP256K1_LIBRARIES}
    ${READLINE_LIBRARY}
  )
endif()

target_compile_definitions(kaszlak PRIVATE
  SQLITE_THREADSAFE=2
)

# Without -ObjC, category methods are not linked from static libraries
set_target_properties(kaszlak PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
  LINK_FLAGS "-ObjC"
)

# PLC Server (campagnola - PLC directory binary)
add_executable(campagnola
  Garazyk/Binaries/campagnola/main.m
)

target_include_directories(campagnola PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Sources
  ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Frameworks
  ${SECP256K1_INCLUDE_DIRS}
)

if(APPLE)
  target_link_libraries(campagnola PRIVATE
    ATProtoAppViewServer
    ATProtoPLC
    ATProtoTransport
    ATProtoCore
    ATProtoRuntime
    ATProtoServices
    ${PLATFORM_LIBRARIES}
    ${SECP256K1_LIBRARIES}
    ${READLINE_LIBRARY}
  )
else()
  target_link_libraries(campagnola PRIVATE
    -Wl,--whole-archive
    ATProtoAppViewServer
    ATProtoPLC
    ATProtoTransport
    ATProtoCore
    ATProtoRuntime
    ATProtoServices
    -Wl,--no-whole-archive
    ${PLATFORM_LIBRARIES}
    ${SECP256K1_LIBRARIES}
    ${READLINE_LIBRARY}
  )
endif()

target_compile_definitions(campagnola PRIVATE
  SQLITE_THREADSAFE=2
)

# Without -ObjC, category methods are not linked from static libraries
set_target_properties(campagnola PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
  LINK_FLAGS "-ObjC"
)

# Relay Server (zuk - AT Protocol relay)
add_executable(zuk
  Garazyk/Binaries/zuk/main.m
)

target_include_directories(zuk PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Sources
  ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Frameworks
  ${SECP256K1_INCLUDE_DIRS}
)

if(APPLE)
  target_link_libraries(zuk PRIVATE
    ATProtoAppViewServer
    ATProtoSync
    ATProtoTransport
    ATProtoCore
    ATProtoRuntime
    ATProtoServices
    ATProtoStorage
    ${PLATFORM_LIBRARIES}
    ${SECP256K1_LIBRARIES}
    ${READLINE_LIBRARY}
  )
else()
  target_link_libraries(zuk PRIVATE
    -Wl,--whole-archive
    ATProtoAppViewServer
    ATProtoSync
    ATProtoTransport
    ATProtoCore
    ATProtoRuntime
    ATProtoServices
    ATProtoStorage
    -Wl,--no-whole-archive
    ${PLATFORM_LIBRARIES}
    ${SECP256K1_LIBRARIES}
    ${READLINE_LIBRARY}
  )
endif()

target_compile_definitions(zuk PRIVATE
  SQLITE_THREADSAFE=2
)

# Without -ObjC, category methods are not linked from static libraries
set_target_properties(zuk PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
  LINK_FLAGS "-ObjC"
)

# AppView server source library
file(GLOB_RECURSE ATPROTO_APPVIEW_SERVER_SOURCES
  "Garazyk/Sources/AppView/Server/*.m"
  "Garazyk/Sources/AppView/Server/*.c"
)
# Exclude binary entrypoint from the library
list(FILTER ATPROTO_APPVIEW_SERVER_SOURCES EXCLUDE REGEX ".*/AppView/Server/Binary/.*\\.m$")

add_library(ATProtoAppViewServer STATIC ${ATPROTO_APPVIEW_SERVER_SOURCES})

target_include_directories(ATProtoAppViewServer PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Sources
  ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Frameworks
  ${SECP256K1_INCLUDE_DIRS}
)

target_link_libraries(ATProtoAppViewServer PRIVATE
  ATProtoStorage
  ATProtoServices
  ATProtoSync
  ATProtoTransport
  ATProtoCore
  ATProtoRuntime
  ${PLATFORM_LIBRARIES}
  ${SECP256K1_LIBRARIES}
)

# AppView Server binary (syrena)
add_executable(syrena
  Garazyk/Binaries/syrena/main.m
)

target_include_directories(syrena PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Sources
  ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Frameworks
  ${SECP256K1_INCLUDE_DIRS}
)

if(APPLE)
  target_link_libraries(syrena PRIVATE
    ATProtoAppViewServer
    ATProtoRuntime
    ATProtoStorage
    ATProtoServices
    ATProtoSync
    ATProtoTransport
    ATProtoCore
    ${PLATFORM_LIBRARIES}
    ${SECP256K1_LIBRARIES}
    ${READLINE_LIBRARY}
  )
else()
  target_link_libraries(syrena PRIVATE
    -Wl,--whole-archive
    ATProtoAppViewServer
    ATProtoRuntime
    ATProtoStorage
    ATProtoServices
    ATProtoSync
    ATProtoTransport
    ATProtoCore
    -Wl,--no-whole-archive
    ${PLATFORM_LIBRARIES}
    ${SECP256K1_LIBRARIES}
    ${READLINE_LIBRARY}
  )
endif()

target_compile_definitions(syrena PRIVATE
  SQLITE_THREADSAFE=2
)

# Without -ObjC, category methods are not linked from static libraries
set_target_properties(syrena PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
  LINK_FLAGS "-ObjC"
)

# Tutorial 1: Hello PDS Example
add_executable(hello-pds
  examples/tutorial-1-hello-pds/src/main.m
)

target_include_directories(hello-pds PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Sources
  ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Frameworks
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
  ATProtoPLC
  ${PLATFORM_LIBRARIES}
  ${SECP256K1_LIBRARIES}
)

target_compile_definitions(hello-pds PRIVATE
  SQLITE_THREADSAFE=2
)

set_target_properties(hello-pds PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

# Migration Tests (standalone, no XCTest)
add_executable(migration_tests
  Garazyk/Tests/Database/MigrationTests.m
)

target_include_directories(migration_tests PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Sources
  ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Frameworks
  ${SECP256K1_INCLUDE_DIRS}
)

if(APPLE)
  target_link_libraries(migration_tests PRIVATE
    ATProtoRuntime
    ATProtoStorage
    ATProtoServices
    ATProtoCore
    ATProtoRuntime    # Duplicate for cyclic refs as in kaszlak
    ${PLATFORM_LIBRARIES}
    ${SECP256K1_LIBRARIES}
  )
else()
  target_link_libraries(migration_tests PRIVATE
    ATProtoRuntime
    ATProtoStorage
    ATProtoServices
    ATProtoCore
    ${OBJC_LIBRARY}
    ${GNUSTEP_LIBRARIES}
    ${PLATFORM_LIBRARIES}
    ${SECP256K1_LIBRARIES}
  )
endif()

target_compile_definitions(migration_tests PRIVATE
  SQLITE_THREADSAFE=2
)

# Without -ObjC, category methods are not linked from static libraries
set_target_properties(migration_tests PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
  LINK_FLAGS "-ObjC"
)

# Connection Pool Tests (standalone, no XCTest)
add_executable(connection_pool_tests
  Garazyk/Tests/Database/ConnectionPoolTests.m
)

target_include_directories(connection_pool_tests PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Sources
  ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Frameworks
  ${SECP256K1_INCLUDE_DIRS}
)

if(APPLE)
  target_link_libraries(connection_pool_tests PRIVATE
    ATProtoRuntime
    ATProtoStorage
    ATProtoServices
    ATProtoCore
    ATProtoRuntime    # Duplicate for cyclic refs
    ${PLATFORM_LIBRARIES}
    ${SECP256K1_LIBRARIES}
  )
else()
  target_link_libraries(connection_pool_tests PRIVATE
    ATProtoRuntime
    ATProtoStorage
    ATProtoServices
    ATProtoCore
    ${OBJC_LIBRARY}
    ${GNUSTEP_LIBRARIES}
    ${PLATFORM_LIBRARIES}
    ${SECP256K1_LIBRARIES}
  )
endif()

target_compile_definitions(connection_pool_tests PRIVATE
  SQLITE_THREADSAFE=2
)

set_target_properties(connection_pool_tests PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
  LINK_FLAGS "-ObjC"
)

# Record Cache Tests (standalone, no XCTest)
add_executable(record_cache_tests
  Garazyk/Tests/Database/RecordCacheTests.m
)

target_include_directories(record_cache_tests PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Sources
  ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Frameworks
  ${SECP256K1_INCLUDE_DIRS}
)

if(APPLE)
  target_link_libraries(record_cache_tests PRIVATE
    ATProtoRuntime
    ATProtoStorage
    ATProtoServices
    ATProtoCore
    ATProtoRuntime
    ${PLATFORM_LIBRARIES}
    ${SECP256K1_LIBRARIES}
  )
else()
  target_link_libraries(record_cache_tests PRIVATE
    ATProtoRuntime
    ATProtoStorage
    ATProtoServices
    ATProtoCore
    ${OBJC_LIBRARY}
    ${GNUSTEP_LIBRARIES}
    ${PLATFORM_LIBRARIES}
    ${SECP256K1_LIBRARIES}
  )
endif()

target_compile_definitions(record_cache_tests PRIVATE
  SQLITE_THREADSAFE=2
)

set_target_properties(record_cache_tests PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
  LINK_FLAGS "-ObjC"
)

#=============================
# Fuzzer Targets
#=============================

option(BUILD_FUZZERS "Build fuzzing targets" OFF)
option(FUZZER_COVERAGE "Build fuzzers with coverage instrumentation" OFF)

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

  # Coverage instrumentation
  if(FUZZER_COVERAGE)
    message(STATUS "Building fuzzers with coverage instrumentation")
    set(FUZZER_CFLAGS "${FUZZER_CFLAGS} -fprofile-instr-generate -fcoverage-mapping")
    set(FUZZER_LDFLAGS "${FUZZER_LDFLAGS} -fprofile-instr-generate -fcoverage-mapping")
  endif()

  set(FUZZER_SOURCES ${ATPROTO_ALL_RUNTIME_SOURCES})
  
  # Macro to add fuzzer targets
  macro(add_pds_fuzzer name source)
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${source}")
      # Fuzzers link only against runtime libraries, no need to recompile sources
      add_executable(${name} ${source} ${FUZZER_DRIVER})
      target_include_directories(${name} PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Sources
        ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Frameworks
        ${SECP256K1_INCLUDE_DIRS})
      target_link_libraries(${name} PRIVATE
        ATProtoRuntime
        ATProtoServices
        ATProtoTransport
        ATProtoXRPC
        ATProtoSync
        ATProtoStorage
        ATProtoCore
        ATProtoPLC
        ATProtoAppViewServer
        ${PLATFORM_LIBRARIES}
        ${SECP256K1_LIBRARIES})
      target_compile_options(${name} PRIVATE ${FUZZER_CFLAGS})
      target_link_options(${name} PRIVATE ${FUZZER_LDFLAGS})
      set_target_properties(${name} PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/fuzzing"
        LINK_FLAGS "-ObjC"
      )
    endif()
  endmacro()

  # Macro to add fuzzer targets with custom mutator
  macro(add_pds_fuzzer_with_mutator name source mutator)
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${source}")
      # Fuzzers link only against runtime libraries, no need to recompile sources
      add_executable(${name} ${source} ${mutator} ${FUZZER_DRIVER})
      target_include_directories(${name} PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Sources
        ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Frameworks
        ${SECP256K1_INCLUDE_DIRS})
      target_link_libraries(${name} PRIVATE
        ATProtoRuntime
        ATProtoServices
        ATProtoTransport
        ATProtoXRPC
        ATProtoSync
        ATProtoStorage
        ATProtoCore
        ATProtoPLC
        ATProtoAppViewServer
        ${PLATFORM_LIBRARIES}
        ${SECP256K1_LIBRARIES})
      target_compile_options(${name} PRIVATE ${FUZZER_CFLAGS})
      target_link_options(${name} PRIVATE ${FUZZER_LDFLAGS})
      set_target_properties(${name} PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/fuzzing"
        LINK_FLAGS "-ObjC"
      )
    endif()
  endmacro()

  add_pds_fuzzer(fuzz_xrpc "fuzzing/harness/FuzzXrpcDispatcher.m")
  add_pds_fuzzer(fuzz_cbor "fuzzing/harness/FuzzCBORDecoder.m")
  add_pds_fuzzer(fuzz_http "fuzzing/harness/FuzzHttp1Parser.m")
  add_pds_fuzzer(fuzz_jwt "fuzzing/harness/FuzzJWT.m")
  add_pds_fuzzer(fuzz_dpop "fuzzing/harness/FuzzDPoP.m")
  add_pds_fuzzer(fuzz_mime "fuzzing/harness/FuzzMimeTypeValidator.m")
  add_pds_fuzzer(fuzz_sqlite "fuzzing/harness/FuzzPDSDatabase.m")
  add_pds_fuzzer(fuzz_lexicon "fuzzing/harness/FuzzATProtoLexiconValidator.m")
  add_pds_fuzzer(fuzz_mst "fuzzing/harness/FuzzMST.m")

  # Structural mutator fuzzers (Phase 4)
  add_pds_fuzzer_with_mutator(fuzz_jwt_struct "fuzzing/harness/FuzzJWT.m" "fuzzing/mutators/JWTMutator.mm")
  add_pds_fuzzer_with_mutator(fuzz_http_struct "fuzzing/harness/FuzzHttp1Parser.m" "fuzzing/mutators/HTTPMutator.mm")

  # Extended mutator fuzzers (Phase improvements)
  add_pds_fuzzer_with_mutator(fuzz_cbor_struct "fuzzing/harness/FuzzCBORDecoder.m" "fuzzing/mutators/CBORMutator.mm")
  add_pds_fuzzer_with_mutator(fuzz_xrpc_struct "fuzzing/harness/FuzzXrpcDispatcher.m" "fuzzing/mutators/XrpcMutator.mm")

  # Corpus minimizer target
  add_pds_fuzzer(fuzz_minimizer "fuzzing/harness/FuzzMinimizer.m")

  # Multi-path JSON fuzzer
  add_pds_fuzzer(fuzz_multi_json "fuzzing/harness/FuzzMultiJSON.m")

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
  file(GLOB_RECURSE TEST_OBJC_SOURCES "Garazyk/Tests/**/*.m")
  list(APPEND TEST_OBJC_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Tests/test_main.m")
  list(APPEND TEST_OBJC_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Tests/Database/PDSDatabaseLRUTests.m")
  
  # Exclude problematic tests (preserved from original)
  list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Database/PDSNewArchitectureTests.m")
  # Exclude top-level Integration tests only, except our new PLC integration test
  list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX "Garazyk/Tests/Integration/PDSIntegrationTests.m")
  list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX "Garazyk/Tests/Integration/comprehensive_tests.m")
  # Exclude standalone test files with their own main() - they have separate executable targets
  list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Database/ConnectionPoolTests.m")
  list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Database/RecordCacheTests.m")
  list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Database/MigrationTests.m")
  # Exclude duplicate SecurityHardeningTests - keep only the Security/ one
  list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Network/SecurityHardeningTests.m")
  # list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Database/Integration/.*")
  # list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Identity/DIDResolverTests.m")
  # Phase 1: Enabled Core Logic & Crypto Tests
  # list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Auth/KeyRotationTests.m")
  # list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Network/RateLimitingTests.m")
  # list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Auth/OAuth2Tests.m")
  # list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Auth/OAuth2EndpointTests.m")
  # list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Auth/TOTPTests.m")

  # Compat tests are now enabled on all platforms (Phase A/B/C implementation)
  # if(APPLE)
  #     list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Compat/.*")
  # endif()

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
    ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Sources
    ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Frameworks
    ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Tests
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
    ATProtoAppViewServer
    ${PLATFORM_LIBRARIES}
    ${SECP256K1_LIBRARIES}
  )
  
  if(APPLE)
    target_link_libraries(AllTests PRIVATE "-framework XCTest")
    target_compile_options(AllTests PRIVATE "-F${XCTEST_SEARCH_PATHS}")
    target_link_options(AllTests PRIVATE 
      "-F${XCTEST_SEARCH_PATHS}"
      "LINKER:-rpath,${XCTEST_SEARCH_PATHS}"
    )
    # Critical: Load all Objective-C categories from static libraries
    # Without -ObjC, category methods (like PDSActorStore+Account) are not linked
    set_target_properties(AllTests PROPERTIES
      LINK_FLAGS "-ObjC"
    )
  else()
     target_link_libraries(AllTests PRIVATE
       -Wl,--whole-archive
       ATProtoRuntime
       ATProtoServices
       ATProtoTransport
       ATProtoXRPC
       ATProtoSync
       ATProtoStorage
       ATProtoCore
       ATProtoPLC
       ATProtoAppViewServer
       -Wl,--no-whole-archive
       ${PLATFORM_LIBRARIES}
       ${SECP256K1_LIBRARIES}
     )
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
  set(FUZZER_TARGETS_TO_INSTALL)
  foreach(target fuzz_xrpc fuzz_cbor fuzz_http fuzz_jwt fuzz_jwt_struct fuzz_http_struct fuzz_dpop fuzz_mime fuzz_sqlite fuzz_lexicon fuzz_mst)
    if(TARGET ${target})
      list(APPEND FUZZER_TARGETS_TO_INSTALL ${target})
    endif()
  endforeach()
  if(FUZZER_TARGETS_TO_INSTALL)
    install(TARGETS ${FUZZER_TARGETS_TO_INSTALL}
      RUNTIME DESTINATION bin
    )
  endif()
endif()

#=============================
# Convenience Scripts
#=============================

# Generate helper scripts for development tasks
file(WRITE "${CMAKE_BINARY_DIR}/run-fuzzers-limited.sh" "#!/bin/bash
set -e
cd \"${CMAKE_SOURCE_DIR}\"
echo \"Running fuzzers with limited runs...\"
mkdir -p fuzzing/crashers fuzzing/corpus/{xrpc,cbor,http,auth,blob,sql,lexicon,mst}
${CMAKE_BINARY_DIR}/fuzzing/fuzz_xrpc fuzzing/corpus/xrpc/ -max_len=65536 -jobs=8 -runs=5000 || echo \"XRPC fuzzer completed\"
${CMAKE_BINARY_DIR}/fuzzing/fuzz_cbor fuzzing/corpus/cbor/ -max_len=65536 -jobs=8 -runs=5000 || echo \"CBOR fuzzer completed\"
${CMAKE_BINARY_DIR}/fuzzing/fuzz_http fuzzing/corpus/http/ -max_len=65536 -jobs=8 -runs=5000 || echo \"HTTP fuzzer completed\"
${CMAKE_BINARY_DIR}/fuzzing/fuzz_jwt fuzzing/corpus/auth/ -max_len=65536 -jobs=8 -runs=5000 || echo \"JWT fuzzer completed\"
${CMAKE_BINARY_DIR}/fuzzing/fuzz_dpop fuzzing/corpus/auth/ -max_len=65536 -jobs=8 -runs=5000 || echo \"DPoP fuzzer completed\"
${CMAKE_BINARY_DIR}/fuzzing/fuzz_mime fuzzing/corpus/blob/ -max_len=65536 -jobs=8 -runs=1000 || echo \"MIME fuzzer completed\"
${CMAKE_BINARY_DIR}/fuzzing/fuzz_sqlite fuzzing/corpus/sql/ -max_len=10000 -jobs=8 -runs=1000 || echo \"SQLite fuzzer completed\"
${CMAKE_BINARY_DIR}/fuzzing/fuzz_lexicon fuzzing/corpus/lexicon/ -max_len=65536 -jobs=8 -runs=1000 || echo \"Lexicon fuzzer completed\"
${CMAKE_BINARY_DIR}/fuzzing/fuzz_mst fuzzing/corpus/mst/ -max_len=65536 -jobs=8 -runs=1000 || echo \"MST fuzzer completed\"
echo \"Fuzzing session complete.\"
")

file(WRITE "${CMAKE_BINARY_DIR}/run-fuzzers-extended.sh" "#!/bin/bash
set -e
cd \"${CMAKE_SOURCE_DIR}\"
echo \"Running comprehensive fuzzing session...\"
mkdir -p fuzzing/crashers fuzzing/corpus/{xrpc,cbor,http,auth,blob,sql,lexicon,mst}
echo \"Running XRPC fuzzer (30 seconds)...\"
timeout 30 ${CMAKE_BINARY_DIR}/fuzzing/fuzz_xrpc fuzzing/corpus/xrpc/ -max_len=65536 -jobs=8 -timeout=10 || true
echo \"Running CBOR fuzzer (30 seconds)...\"
timeout 30 ${CMAKE_BINARY_DIR}/fuzzing/fuzz_cbor fuzzing/corpus/cbor/ -max_len=65536 -jobs=8 -timeout=10 || true
echo \"Running HTTP fuzzer (30 seconds)...\"
timeout 30 ${CMAKE_BINARY_DIR}/fuzzing/fuzz_http fuzzing/corpus/http/ -max_len=65536 -jobs=8 -timeout=10 || true
echo \"Running JWT fuzzer (30 seconds)...\"
timeout 30 ${CMAKE_BINARY_DIR}/fuzzing/fuzz_jwt fuzzing/corpus/auth/ -max_len=65536 -jobs=8 -timeout=10 || true
echo \"Running DPoP fuzzer (30 seconds)...\"
timeout 30 ${CMAKE_BINARY_DIR}/fuzzing/fuzz_dpop fuzzing/corpus/auth/ -max_len=65536 -jobs=8 -timeout=10 || true
echo \"Running MIME fuzzer (30 seconds)...\"
timeout 30 ${CMAKE_BINARY_DIR}/fuzzing/fuzz_mime fuzzing/corpus/blob/ -max_len=65536 -jobs=4 -timeout=10 || true
echo \"Running SQLite fuzzer (30 seconds)...\"
timeout 30 ${CMAKE_BINARY_DIR}/fuzzing/fuzz_sqlite fuzzing/corpus/sql/ -max_len=10000 -jobs=4 -timeout=10 || true
echo \"Running Lexicon fuzzer (30 seconds)...\"
timeout 30 ${CMAKE_BINARY_DIR}/fuzzing/fuzz_lexicon fuzzing/corpus/lexicon/ -max_len=65536 -jobs=8 -timeout=10 || true
echo \"Running MST fuzzer (30 seconds)...\"
timeout 30 ${CMAKE_BINARY_DIR}/fuzzing/fuzz_mst fuzzing/corpus/mst/ -max_len=65536 -jobs=8 -timeout=10 || true
echo \"Comprehensive fuzzing session complete.\"
ls -la fuzzing/crashers/ 2>/dev/null || echo \"No crashes detected\"
")

file(WRITE "${CMAKE_BINARY_DIR}/run-clang-tidy.sh" "#!/bin/bash
set -e
cd \"${CMAKE_SOURCE_DIR}\"
echo \"Running clang-tidy static analysis...\"
find Garazyk/Sources -name \"*.m\" -o -name \"*.c\" | head -50 | xargs -I{} clang-tidy -p . --config-file=.clang-tidy {} 2>&1 | grep -E \"(warning|error)\" | head -100 || true
echo \"Clang-tidy analysis complete.\"
")

file(WRITE "${CMAKE_BINARY_DIR}/run-format.sh" "#!/bin/bash
cd \"${CMAKE_SOURCE_DIR}\"
echo \"Formatting source files...\"
find Garazyk/Sources Garazyk/Tests -name \"*.m\" -o -name \"*.c\" -o -name \"*.h\" | xargs clang-format -i -style=file
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
  DEPENDS fuzz_xrpc fuzz_cbor fuzz_http fuzz_jwt fuzz_dpop fuzz_mime fuzz_sqlite fuzz_lexicon fuzz_mst
)

add_custom_target(run-fuzzers-extended COMMAND "${CMAKE_BINARY_DIR}/scripts/run-fuzzers-extended.sh"
  COMMENT "Running comprehensive fuzzing session"
  DEPENDS fuzz_xrpc fuzz_cbor fuzz_http fuzz_jwt fuzz_dpop fuzz_mime fuzz_sqlite fuzz_lexicon fuzz_mst
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
  # Alias targets for convenience
add_custom_target(fuzz-all ALL DEPENDS fuzz_xrpc fuzz_cbor fuzz_http fuzz_jwt fuzz_jwt_struct fuzz_http_struct fuzz_cbor_struct fuzz_xrpc_struct fuzz_dpop fuzz_mime fuzz_sqlite fuzz_lexicon fuzz_mst fuzz_minimizer fuzz_multi_json)
  add_custom_target(fuzz-xrpc DEPENDS fuzz_xrpc)
  add_custom_target(fuzz-cbor DEPENDS fuzz_cbor)
  add_custom_target(fuzz-http DEPENDS fuzz_http)
  add_custom_target(fuzz-jwt DEPENDS fuzz_jwt)
  add_custom_target(fuzz-jwt-struct DEPENDS fuzz_jwt_struct)
  add_custom_target(fuzz-http-struct DEPENDS fuzz_http_struct)
  add_custom_target(fuzz-cbor-struct DEPENDS fuzz_cbor_struct)
  add_custom_target(fuzz-xrpc-struct DEPENDS fuzz_xrpc_struct)
  add_custom_target(fuzz-dpop DEPENDS fuzz_dpop)
  add_custom_target(fuzz-mime DEPENDS fuzz_mime)
  add_custom_target(fuzz-sqlite DEPENDS fuzz_sqlite)
  add_custom_target(fuzz-lexicon DEPENDS fuzz_lexicon)
  add_custom_target(fuzz-mst DEPENDS fuzz_mst)
  add_custom_target(fuzz-minimizer DEPENDS fuzz_minimizer)
  add_custom_target(fuzz-multi-json DEPENDS fuzz_multi_json)
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
message(STATUS "  syrena          - Standalone AppView server")
message(STATUS "  AllTests          - Unit tests")
message(STATUS "  fuzz_xrpc         - XRPC fuzzer")
message(STATUS "  fuzz_cbor         - CBOR decoder fuzzer")
message(STATUS "  fuzz_http         - HTTP parser fuzzer")
message(STATUS "  fuzz_jwt          - JWT parsing fuzzer")
  message(STATUS "  fuzz_jwt_struct   - JWT with structural mutator")
  message(STATUS "  fuzz_http_struct - HTTP with structural mutator")
  message(STATUS "  fuzz_dpop         - DPoP verification fuzzer")
message(STATUS "  fuzz_mime         - MIME type validation fuzzer")
message(STATUS "  fuzz_sqlite       - SQL injection fuzzer")
message(STATUS "  fuzz_lexicon      - Lexicon validation fuzzer")
message(STATUS "  fuzz_mst          - MST/CAR deserialization fuzzer")
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
