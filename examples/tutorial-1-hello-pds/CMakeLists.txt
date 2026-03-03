cmake_minimum_required(VERSION 3.21)

#=============================
# Pre-project Compiler Setup
#=============================
if(APPLE)
    # On macOS, find absolute paths to Xcode compilers to avoid circular proxy invocation
    execute_process(COMMAND xcrun -find clang OUTPUT_VARIABLE XCODE_CLANG OUTPUT_STRIP_TRAILING_WHITESPACE)
    execute_process(COMMAND xcrun -find clang++ OUTPUT_VARIABLE XCODE_CLANGXX OUTPUT_STRIP_TRAILING_WHITESPACE)
    
    if(XCODE_CLANG)
        set(CMAKE_C_COMPILER "${XCODE_CLANG}")
        set(CMAKE_OBJC_COMPILER "${XCODE_CLANG}")
    endif()
    if(XCODE_CLANGXX)
        set(CMAKE_CXX_COMPILER "${XCODE_CLANGXX}")
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

project(HelloPDS
  VERSION 0.1.0
  DESCRIPTION "Tutorial 1: Hello PDS"
  LANGUAGES OBJC
)

# Enable ARC and modules for Objective-C on macOS
if(APPLE)
    set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -fobjc-arc -fmodules -include ${CMAKE_CURRENT_SOURCE_DIR}/src/prefix.pch")
endif()

# Find required frameworks
if(APPLE)
    find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)
    find_library(SECURITY_FRAMEWORK Security REQUIRED)
    find_library(SQLITE3_LIBRARY sqlite3 REQUIRED)
    set(FRAMEWORKS ${FOUNDATION_FRAMEWORK} ${SECURITY_FRAMEWORK} ${SQLITE3_LIBRARY})
else()
    # GNUstep
    find_package(GNUstep REQUIRED)
    include(GNUstepCommon)
    find_library(SQLITE3_LIBRARY sqlite3 REQUIRED)
    set(FRAMEWORKS gnustep-base ${SQLITE3_LIBRARY})
endif()

# Get the absolute path to the main PDS source directory
get_filename_component(PDS_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../ATProtoPDS/Sources" ABSOLUTE)

# Include directories
include_directories(
    ${PDS_SOURCE_DIR}
    ${PDS_SOURCE_DIR}/App
    ${PDS_SOURCE_DIR}/Network
    ${PDS_SOURCE_DIR}/Services
    ${PDS_SOURCE_DIR}/Database
    ${PDS_SOURCE_DIR}/Core
    ${PDS_SOURCE_DIR}/Auth
    ${PDS_SOURCE_DIR}/Compat
    ${PDS_SOURCE_DIR}/Repository
    ${PDS_SOURCE_DIR}/Sync
    ${PDS_SOURCE_DIR}/Identity
    ${PDS_SOURCE_DIR}/Blob
    ${PDS_SOURCE_DIR}/Admin
    ${PDS_SOURCE_DIR}/Debug
    ${PDS_SOURCE_DIR}/PLC
    ${PDS_SOURCE_DIR}/OAuthProvider
    ${PDS_SOURCE_DIR}/PDSAuth
    ${PDS_SOURCE_DIR}/Security
    ${PDS_SOURCE_DIR}/Lexicon
    ${PDS_SOURCE_DIR}/Email
    ${PDS_SOURCE_DIR}/Federation
    ${PDS_SOURCE_DIR}/AuthCrypto
    ${PDS_SOURCE_DIR}/AuthVerifier
    ${PDS_SOURCE_DIR}/Metrics
    ${PDS_SOURCE_DIR}/AppView
)

# Collect source files from the main PDS (only .m files)
file(GLOB_RECURSE PDS_SOURCES
    "../../ATProtoPDS/Sources/App/*.m"
    "../../ATProtoPDS/Sources/Network/*.m"
    "../../ATProtoPDS/Sources/Services/*.m"
    "../../ATProtoPDS/Sources/Database/*.m"
    "../../ATProtoPDS/Sources/Core/*.m"
    "../../ATProtoPDS/Sources/Auth/*.m"
    "../../ATProtoPDS/Sources/Compat/*.m"
    "../../ATProtoPDS/Sources/Repository/*.m"
    "../../ATProtoPDS/Sources/Sync/*.m"
    "../../ATProtoPDS/Sources/Identity/*.m"
    "../../ATProtoPDS/Sources/Blob/*.m"
    "../../ATProtoPDS/Sources/Admin/*.m"
    "../../ATProtoPDS/Sources/Debug/*.m"
    "../../ATProtoPDS/Sources/PLC/*.m"
    "../../ATProtoPDS/Sources/OAuthProvider/*.m"
    "../../ATProtoPDS/Sources/PDSAuth/*.m"
    "../../ATProtoPDS/Sources/Security/*.m"
    "../../ATProtoPDS/Sources/Lexicon/*.m"
    "../../ATProtoPDS/Sources/Email/*.m"
    "../../ATProtoPDS/Sources/Federation/*.m"
    "../../ATProtoPDS/Sources/AuthCrypto/*.m"
    "../../ATProtoPDS/Sources/AuthVerifier/*.m"
    "../../ATProtoPDS/Sources/Metrics/*.m"
    "../../ATProtoPDS/Sources/AppView/*.m"
)

# Create the executable
add_executable(hello-pds
    src/main.m
    ${PDS_SOURCES}
)

# Link frameworks
target_link_libraries(hello-pds ${FRAMEWORKS})

# Platform-specific settings
if(APPLE)
    target_compile_options(hello-pds PRIVATE 
        -fmodules
        -iframework /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks
    )
else()
    # GNUstep settings
    target_compile_options(hello-pds PRIVATE -fPIC)
endif()
