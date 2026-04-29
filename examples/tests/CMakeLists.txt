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

project(TutorialTests
  VERSION 0.1.0
  DESCRIPTION "Unit tests for ATProto PDS tutorials"
  LANGUAGES OBJC C
)

set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -fobjc-arc -fmodules -fmodules-cache-path=${CMAKE_BINARY_DIR}/ModuleCache")

# Common tutorial utilities
set(COMMON_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../common")

# Tutorial source directories
set(T2_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../tutorial-2-accounts/src")
set(T3_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../tutorial-3-records/src")
set(T7_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../tutorial-7-blobs/src")
set(T8_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../tutorial-8-identity/src")
set(T9_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../tutorial-9-moderation/src")

# Find required frameworks
if(APPLE)
    find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)
    find_library(SECURITY_FRAMEWORK Security REQUIRED)
    find_library(SQLITE3_LIBRARY sqlite3 REQUIRED)

    # XCTest — same path as the main project
    set(XCTEST_SEARCH_PATHS "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks")
    find_library(XCTEST_FRAMEWORK XCTest PATHS ${XCTEST_SEARCH_PATHS} NO_DEFAULT_PATH)

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
    ${CMAKE_CURRENT_SOURCE_DIR}/tests
    ${COMMON_DIR}
    ${T2_DIR}
    ${T3_DIR}
    ${T7_DIR}
    ${T8_DIR}
    ${T9_DIR}
)

# Common utility sources
set(COMMON_SOURCES
    ${COMMON_DIR}/TutorialBase64URL.m
    ${COMMON_DIR}/TutorialCIDGenerator.m
    ${COMMON_DIR}/TutorialECDSAUtils.m
    ${COMMON_DIR}/TutorialJWTMinter.m
    ${COMMON_DIR}/TutorialJWTVerifier.m
    ${COMMON_DIR}/TutorialSQLiteHelper.m
)

# Tutorial-specific sources (no main.m — we have our own)
set(T2_SOURCES
    ${T2_DIR}/Account.m
    ${T2_DIR}/AccountRepository.m
    ${T2_DIR}/AccountService.m
)

set(T3_SOURCES
    ${T3_DIR}/Record.m
    ${T3_DIR}/RecordRepository.m
    ${T3_DIR}/RecordService.m
)

set(T7_SOURCES
    ${T7_DIR}/TutorialBlobStore.m
)

set(T8_SOURCES
    ${T8_DIR}/TutorialIdentityService.m
)

set(T9_SOURCES
    ${T9_DIR}/TutorialModerationService.m
)

# Test sources
file(GLOB TEST_SOURCES "tests/*.m")

# Create the test executable
add_executable(tutorial-tests
    ${TEST_SOURCES}
    ${COMMON_SOURCES}
    ${T2_SOURCES}
    ${T3_SOURCES}
    ${T7_SOURCES}
    ${T8_SOURCES}
    ${T9_SOURCES}
)

target_link_libraries(tutorial-tests ${FRAMEWORKS} objc)

# Platform-specific settings
if(APPLE)
    if(XCTEST_FRAMEWORK)
        target_link_libraries(tutorial-tests "-framework XCTest")
        target_compile_options(tutorial-tests PRIVATE "-F${XCTEST_SEARCH_PATHS}")
        target_link_options(tutorial-tests PRIVATE
            "-F${XCTEST_SEARCH_PATHS}"
            "LINKER:-rpath,${XCTEST_SEARCH_PATHS}"
        )
    endif()
    target_compile_options(tutorial-tests PRIVATE
        -fmodules
        -iframework /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks
    )
    # Load all ObjC categories from static libraries
    set_target_properties(tutorial-tests PROPERTIES
        LINK_FLAGS "-ObjC"
    )
else()
    target_compile_options(tutorial-tests PRIVATE -fPIC)
endif()

# Register with CTest
enable_testing()
add_test(NAME TutorialTests COMMAND tutorial-tests)
