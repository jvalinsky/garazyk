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

project(AccountsPDS
  VERSION 0.1.0
  DESCRIPTION "Tutorial 2: Account Management"
  LANGUAGES OBJC C
)

# Enable ARC for Objective-C
set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -fobjc-arc -fmodules -fmodules-cache-path=${CMAKE_BINARY_DIR}/ModuleCache")

# Find required frameworks
if(APPLE)
    find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)
    find_library(SQLITE3_LIBRARY sqlite3 REQUIRED)
    set(FRAMEWORKS ${FOUNDATION_FRAMEWORK})
else()
    # GNUstep
    find_package(GNUstep REQUIRED)
    include(GNUstepCommon)
    set(FRAMEWORKS gnustep-base)
    find_library(SQLITE3_LIBRARY sqlite3 REQUIRED)
endif()

# Include directories
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/src)

# Collect tutorial source files
file(GLOB TUTORIAL_SOURCES
    "src/*.m"
)

# Create the executable
add_executable(tutorial-2-accounts
    ${TUTORIAL_SOURCES}
)

# Link frameworks
target_link_libraries(tutorial-2-accounts ${FRAMEWORKS} ${SQLITE3_LIBRARY})
