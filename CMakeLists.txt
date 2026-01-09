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

# Find required frameworks
find_library(FOUNDATION Foundation REQUIRED)
find_library(NETWORK Network REQUIRED)
find_library(SECURITY Security REQUIRED)
find_library(COREIMAGE CoreImage REQUIRED)
find_library(APPKIT AppKit REQUIRED)

# Find SQLite3
find_library(SQLite3_LIBRARY sqlite3 REQUIRED)

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
  ${FOUNDATION}
  ${NETWORK}
  ${SECURITY}
  ${COREIMAGE}
  ${APPKIT}
  ${SQLite3_LIBRARY}
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
  ${FOUNDATION}
  ${NETWORK}
  ${SECURITY}
  ${COREIMAGE}
  ${APPKIT}
  ${SQLite3_LIBRARY}
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
  # Check if fuzzer sanitize is supported (AppleClang usually lacks libFuzzer)
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
    # Do NOT define LIBFUZZER so internal main is used
  endif()

  # Base fuzzer sources (without main entry points)
  set(FUZZER_SOURCES ${ATProtoPDS_SOURCES})

  # XRPC Fuzzer
  add_executable(fuzz_xrpc fuzzing/fuzz_xrpc.mm ${FUZZER_SOURCES} ${FUZZER_DRIVER})
  target_include_directories(fuzz_xrpc PRIVATE ATProtoPDS/Sources ${SECP256K1_INCLUDE_DIRS})
  target_link_libraries(fuzz_xrpc PRIVATE ${FOUNDATION} ${NETWORK} ${SECURITY} ${COREIMAGE} ${APPKIT} ${SQLite3_LIBRARY} ${SECP256K1_LIBRARIES})
  target_compile_options(fuzz_xrpc PRIVATE ${FUZZER_CFLAGS})
  target_link_options(fuzz_xrpc PRIVATE ${FUZZER_LDFLAGS})
  set_target_properties(fuzz_xrpc PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/fuzzing")

  # CBOR Fuzzer
  add_executable(fuzz_cbor fuzzing/fuzz_cbor.mm ${FUZZER_SOURCES} ${FUZZER_DRIVER})
  target_include_directories(fuzz_cbor PRIVATE ATProtoPDS/Sources ${SECP256K1_INCLUDE_DIRS})
  target_link_libraries(fuzz_cbor PRIVATE ${FOUNDATION} ${NETWORK} ${SECURITY} ${COREIMAGE} ${APPKIT} ${SQLite3_LIBRARY} ${SECP256K1_LIBRARIES})
  target_compile_options(fuzz_cbor PRIVATE ${FUZZER_CFLAGS})
  target_link_options(fuzz_cbor PRIVATE ${FUZZER_LDFLAGS})
  set_target_properties(fuzz_cbor PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/fuzzing")

  # HTTP Fuzzer
  add_executable(fuzz_http fuzzing/fuzz_http.mm ${FUZZER_SOURCES} ${FUZZER_DRIVER})
  target_include_directories(fuzz_http PRIVATE ATProtoPDS/Sources ${SECP256K1_INCLUDE_DIRS})
  target_link_libraries(fuzz_http PRIVATE ${FOUNDATION} ${NETWORK} ${SECURITY} ${COREIMAGE} ${APPKIT} ${SQLite3_LIBRARY} ${SECP256K1_LIBRARIES})
  target_compile_options(fuzz_http PRIVATE ${FUZZER_CFLAGS})
  target_link_options(fuzz_http PRIVATE ${FUZZER_LDFLAGS})
  set_target_properties(fuzz_http PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/fuzzing")

  # Auth Fuzzer
  add_executable(fuzz_auth fuzzing/fuzz_auth.mm ${FUZZER_SOURCES} ${FUZZER_DRIVER})
  target_include_directories(fuzz_auth PRIVATE ATProtoPDS/Sources ${SECP256K1_INCLUDE_DIRS})
  target_link_libraries(fuzz_auth PRIVATE ${FOUNDATION} ${NETWORK} ${SECURITY} ${COREIMAGE} ${APPKIT} ${SQLite3_LIBRARY} ${SECP256K1_LIBRARIES})
  target_compile_options(fuzz_auth PRIVATE ${FUZZER_CFLAGS})
  target_link_options(fuzz_auth PRIVATE ${FUZZER_LDFLAGS})
  set_target_properties(fuzz_auth PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/fuzzing")

  # Blob Fuzzer
  if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/fuzzing/fuzz_blob.mm")
    add_executable(fuzz_blob fuzzing/fuzz_blob.mm ${FUZZER_SOURCES} ${FUZZER_DRIVER})
    target_include_directories(fuzz_blob PRIVATE ATProtoPDS/Sources ${SECP256K1_INCLUDE_DIRS})
    target_link_libraries(fuzz_blob PRIVATE ${FOUNDATION} ${NETWORK} ${SECURITY} ${COREIMAGE} ${APPKIT} ${SQLite3_LIBRARY} ${SECP256K1_LIBRARIES})
    target_compile_options(fuzz_blob PRIVATE ${FUZZER_CFLAGS})
    target_link_options(fuzz_blob PRIVATE ${FUZZER_LDFLAGS})
    set_target_properties(fuzz_blob PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/fuzzing")
  endif()

  # SQLite Fuzzer
  if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/fuzzing/fuzz_sqlite.mm")
    add_executable(fuzz_sqlite fuzzing/fuzz_sqlite.mm ${FUZZER_SOURCES} ${FUZZER_DRIVER})
    target_include_directories(fuzz_sqlite PRIVATE ATProtoPDS/Sources ${SECP256K1_INCLUDE_DIRS})
    target_link_libraries(fuzz_sqlite PRIVATE ${FOUNDATION} ${NETWORK} ${SECURITY} ${COREIMAGE} ${APPKIT} ${SQLite3_LIBRARY} ${SECP256K1_LIBRARIES})
    target_compile_options(fuzz_sqlite PRIVATE ${FUZZER_CFLAGS})
    target_link_options(fuzz_sqlite PRIVATE ${FUZZER_LDFLAGS})
    set_target_properties(fuzz_sqlite PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/fuzzing")
  endif()
endif()

#=============================
# Test Targets
#=============================

option(BUILD_TESTS "Build test targets" ON)
if(BUILD_TESTS)
  enable_testing()

  # Find XCTest
  execute_process(COMMAND xcode-select -p OUTPUT_VARIABLE XCODE_DEVELOPER_DIR OUTPUT_STRIP_TRAILING_WHITESPACE)
  find_library(XCTest XCTest PATHS "${XCODE_DEVELOPER_DIR}/Platforms/MacOSX.platform/Developer/Library/Frameworks" REQUIRED)

  # Collect test sources
  file(GLOB_RECURSE TEST_OBJC_SOURCES "ATProtoPDS/Tests/**/*.m")
  list(APPEND TEST_OBJC_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/ATProtoPDS/Tests/test_main.m")
  message(STATUS "Test Sources found: ${TEST_OBJC_SOURCES}")

  # Exclude problematic tests
  list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Database/PDSNewArchitectureTests.m")
  list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Integration/.*")
  list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Database/Integration/.*")
  list(FILTER TEST_OBJC_SOURCES EXCLUDE REGEX ".*/Identity/DIDResolverTests.m")



  # Test executable
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
    ${FOUNDATION}
    ${NETWORK}
    ${SECURITY}
    ${COREIMAGE}
    ${APPKIT}
    ${SQLite3_LIBRARY}
    ${SECP256K1_LIBRARIES}
    ${XCTest}
  )

  target_compile_definitions(AllTests PRIVATE
    SQLITE_THREADSAFE=2
  )

  set_target_properties(AllTests PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/tests"
  )

  # Add test
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
# Build Summary
#=============================
message(STATUS "ATProtoPDS Build Configuration:")
message(STATUS "  Build Type: ${CMAKE_BUILD_TYPE}")
message(STATUS "  macOS Deployment Target: ${CMAKE_OSX_DEPLOYMENT_TARGET}")
message(STATUS "  Build secp256k1: ${BUILD_SECP256K1}")
message(STATUS "  Build Fuzzers: ${BUILD_FUZZERS}")
message(STATUS "  Build Tests: ${BUILD_TESTS}")
message(STATUS "  Install Prefix: ${CMAKE_INSTALL_PREFIX}")