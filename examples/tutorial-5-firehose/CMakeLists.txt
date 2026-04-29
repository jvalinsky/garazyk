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

project(tutorial-5-firehose
  VERSION 0.1.0
  DESCRIPTION "Tutorial 5: Firehose"
  LANGUAGES OBJC C
)

set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -fobjc-arc")

# Find required frameworks
if(APPLE)
    find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)
    find_library(SECURITY_FRAMEWORK Security REQUIRED)
    set(FRAMEWORKS ${FOUNDATION_FRAMEWORK} ${SECURITY_FRAMEWORK})
else()
    find_package(GNUstep REQUIRED)
    include(GNUstepCommon)
    find_package(OpenSSL REQUIRED)
    set(FRAMEWORKS gnustep-base OpenSSL::Crypto)
endif()

# Include directories
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/src)

# Source files
set(SOURCES
    src/main.m
    src/WebSocketConnection.m
    src/EventFormatter.m
    src/SubscribeReposHandler.m
)

# Create executable
add_executable(tutorial-5-firehose ${SOURCES})

# Link libraries
target_link_libraries(tutorial-5-firehose ${FRAMEWORKS} objc)

# Set output directory
set_target_properties(tutorial-5-firehose PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
)
