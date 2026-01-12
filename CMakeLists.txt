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
set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -fobjc-arc -Wno-implicit-function-declaration")

# Platform Specific Configuration
if(NOT APPLE)
    set(CMAKE_OBJC_STANDARD 20)
    add_compile_definitions(GNUSTEP LINUX)
    
    # GNUstep Configuration
    find_program(GNUSTEP_CONFIG gnustep-config REQUIRED)
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
        set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} ${GNUSTEP_CFLAGS} -fblocks -fobjc-runtime=gnustep-2.0")
        string(REPLACE " " ";" GNUSTEP_LIBS_LIST "${GNUSTEP_LIBS}")
    endif()
    
    include_directories(/usr/include/GNUstep)
    include_directories(${CMAKE_CURRENT_SOURCE_DIR}/Sources/Compat)
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
    
    set(PLATFORM_LIBRARIES
        ${GNUSTEP_LIBS_LIST}
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
if(BUILD_TESTS)
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
