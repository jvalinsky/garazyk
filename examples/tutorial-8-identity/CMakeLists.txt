cmake_minimum_required(VERSION 3.21)

#=============================
# Pre-project Compiler Setup
#=============================
if(APPLE)
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
    find_program(CLANG_COMPILER NAMES /bin/clang clang-14 clang)
    if(CLANG_COMPILER)
        set(CMAKE_C_COMPILER ${CLANG_COMPILER})
        set(CMAKE_CXX_COMPILER ${CLANG_COMPILER})
        set(CMAKE_OBJC_COMPILER ${CLANG_COMPILER})
    endif()
endif()

project(tutorial-8-identity
  VERSION 0.1.0
  DESCRIPTION "Tutorial 8: Identity & DID Resolution"
  LANGUAGES OBJC C
)

set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -fobjc-arc -fmodules -fmodules-cache-path=${CMAKE_BINARY_DIR}/ModuleCache")

# Common tutorial utilities
set(COMMON_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../common")

# Find required frameworks
if(APPLE)
    find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)
    find_library(SECURITY_FRAMEWORK Security REQUIRED)
    find_library(SQLITE3_LIBRARY sqlite3 REQUIRED)
    set(FRAMEWORKS ${FOUNDATION_FRAMEWORK} ${SECURITY_FRAMEWORK} ${SQLITE3_LIBRARY})
else()
    find_package(GNUstep REQUIRED)
    include(GNUstepCommon)
    find_library(SQLITE3_LIBRARY sqlite3 REQUIRED)
    find_package(OpenSSL REQUIRED)
    set(FRAMEWORKS gnustep-base ${SQLITE3_LIBRARY} OpenSSL::Crypto)
endif()

# Include directories
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${COMMON_DIR}
)

# Collect tutorial source files
file(GLOB TUTORIAL_SOURCES "src/*.m")

# Common utility sources
set(COMMON_SOURCES
    ${COMMON_DIR}/TutorialBase64URL.m
    ${COMMON_DIR}/TutorialECDSAUtils.m
    ${COMMON_DIR}/TutorialJWTMinter.m
    ${COMMON_DIR}/TutorialJWTVerifier.m
    ${COMMON_DIR}/TutorialSQLiteHelper.m
)

# Create the executable
add_executable(tutorial-8-identity
    ${TUTORIAL_SOURCES}
    ${COMMON_SOURCES}
)

# Link frameworks
target_link_libraries(tutorial-8-identity ${FRAMEWORKS} objc)
