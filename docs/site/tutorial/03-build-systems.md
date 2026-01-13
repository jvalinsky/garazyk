# Chapter 3: Build Systems & Project Structure

Building an Objective-C project involves more than just compiling code—you need a robust build system that handles dependencies, manages configurations, and integrates with your development environment. This chapter covers CMake for cross-platform builds and XcodeGen for Xcode project generation.

## Project Layout

Here's the recommended structure for a production Objective-C project:

```
NSPds/
├── ATProtoPDS/
│   ├── Sources/                   # Production source code
│   │   ├── App/                   # Application layer (HTTP handlers, explore UI)
│   │   ├── Auth/                  # Authentication (OAuth2, JWT, keys)
│   │   ├── CLI/                   # Command-line interface
│   │   ├── Core/                  # Core data types (CID, DID, TID)
│   │   ├── Database/              # SQLite persistence layer
│   │   ├── Identity/              # DID/PLC identity management
│   │   ├── Network/               # HTTP server, transport layer
│   │   ├── Repository/            # MST, CBOR, CAR files
│   │   ├── Security/              # Rate limiting, validation
│   │   └── Sync/                  # Firehose, WebSocket sync
│   ├── Tests/                     # Test suites
│   └── Resources/                 # Static assets
├── docs/                          # Documentation
├── fuzzing/                       # Fuzz testing
├── secp256k1/                     # Git submodule for cryptography
├── CMakeLists.txt                 # CMake build configuration
├── project.yml                    # XcodeGen specification
└── Makefile                       # Convenience make targets
```

## Module Organization Pattern

Each module follows a consistent structure with header (.h) and implementation (.m) pairs:

```
Core/
├── CID.h          # Content Identifier interface
├── CID.m          # Content Identifier implementation
├── DID.h          # Decentralized Identifier interface
├── DID.m          # Decentralized Identifier implementation
├── TID.h          # Timestamp Identifier interface
└── TID.m          # Timestamp Identifier implementation
```

**Best Practice:** Keep related functionality together. The `Core/` module contains foundational types used throughout the codebase.

## CMake Fundamentals

CMake is a build system generator—it creates native build files (Makefiles, Xcode projects, etc.) from a platform-independent specification.

### Project Declaration

```cmake
cmake_minimum_required(VERSION 3.21)

project(ATProtoPDS
  VERSION 0.1.0
  DESCRIPTION "ATProto Personal Data Server"
  LANGUAGES C CXX OBJC
)
```

- **VERSION 3.21**: Requires CMake 3.21+ (needed for Objective-C support)
- **LANGUAGES**: Enable C, C++, and Objective-C compilers

### Compiler Configuration

```cmake
# Enable ARC (Automatic Reference Counting)
set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -fobjc-arc")

# Language standards
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Build type configuration
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Debug CACHE STRING "Build type" FORCE)
endif()

# Debug vs Release flags
set(CMAKE_OBJC_FLAGS_DEBUG "${CMAKE_OBJC_FLAGS_DEBUG} -g -O0")
set(CMAKE_OBJC_FLAGS_RELEASE "${CMAKE_OBJC_FLAGS_RELEASE} -O2")
```

### Finding Dependencies

CMake provides `find_library` for macOS frameworks and `find_package` for third-party libraries:

```cmake
# macOS Frameworks
find_library(FOUNDATION Foundation REQUIRED)
find_library(SECURITY Security REQUIRED)
find_library(NETWORK Network REQUIRED)

# System libraries
find_library(SQLite3_LIBRARY sqlite3 REQUIRED)

# Third-party packages (Linux)
find_package(OpenSSL REQUIRED)
find_package(SQLite3 REQUIRED)

# Collect all platform libraries
set(PLATFORM_LIBRARIES 
    ${FOUNDATION} 
    ${SECURITY}
    ${NETWORK}
    ${SQLite3_LIBRARY}
)
```

### Source Collection

CMake's `GLOB_RECURSE` collects source files automatically:

```cmake
# Collect all Objective-C source files
file(GLOB_RECURSE ATProtoPDS_OBJC_SOURCES "ATProtoPDS/Sources/**/*.m")
file(GLOB_RECURSE ATProtoPDS_C_SOURCES "ATProtoPDS/Sources/**/*.c")

# Exclude main entry points (they conflict with test mains)
list(FILTER ATProtoPDS_OBJC_SOURCES EXCLUDE REGEX ".*main\\.m$")

# Platform-specific exclusions
if(APPLE)
    list(FILTER ATProtoPDS_OBJC_SOURCES EXCLUDE REGEX ".*/Compat/.*")
endif()

set(ATProtoPDS_SOURCES ${ATProtoPDS_OBJC_SOURCES} ${ATProtoPDS_C_SOURCES})
```

### Creating Executables

```cmake
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

set_target_properties(atprotopds-cli PROPERTIES
  OUTPUT_NAME "atprotopds-cli"
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)
```

### Subprojects

For dependencies like secp256k1, use `add_subdirectory`:

```cmake
option(BUILD_SECP256K1 "Build secp256k1 library" ON)

if(BUILD_SECP256K1)
  # Configure subproject options
  set(SECP256K1_BUILD_SHARED OFF CACHE BOOL "Build as static library" FORCE)
  set(SECP256K1_ENABLE_MODULE_RECOVERY ON CACHE BOOL "Enable recovery" FORCE)
  
  add_subdirectory(secp256k1)
  
  set(SECP256K1_LIBRARIES secp256k1)
  set(SECP256K1_INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/secp256k1/include)
endif()
```

### Test Configuration

```cmake
option(BUILD_TESTS "Build test targets" ON)

if(BUILD_TESTS)
  enable_testing()
  
  # Collect test sources
  file(GLOB_RECURSE MY_TEST_SOURCES "ATProtoPDS/Tests/**/*.m")
  list(APPEND MY_TEST_SOURCES "ATProtoPDS/Tests/test_main.m")
  
  add_executable(AllTests
    ${ATProtoPDS_SOURCES}
    ${MY_TEST_SOURCES}
  )
  
  # Link XCTest framework (macOS)
  if(APPLE)
    execute_process(
      COMMAND xcode-select -p 
      OUTPUT_VARIABLE XCODE_DEVELOPER_DIR 
      OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    find_library(XCTest XCTest 
      PATHS "${XCODE_DEVELOPER_DIR}/Platforms/MacOSX.platform/Developer/Library/Frameworks"
      REQUIRED
    )
    target_link_libraries(AllTests PRIVATE ${XCTest})
  endif()
  
  # Register test with CTest
  add_test(NAME AllTests COMMAND AllTests)
endif()
```

## XcodeGen Configuration

XcodeGen generates `.xcodeproj` files from a simple `project.yml` specification, wrapping the CMake build:

```yaml
# project.yml
name: ATProtoPDS
options:
  bundleIdPrefix: com.atproto
  deploymentTarget:
    macOS: "14.0"

settings:
  base:
    CLANG_ENABLE_OBJC_ARC: YES
    SDKROOT: macosx
    CLANG_C_LANGUAGE_STANDARD: c11

targets:
  ATProtoPDS-CLI:
    type: tool
    platform: macOS
    sources: []  # We use CMake for actual compilation
    settings:
      base:
        PRODUCT_NAME: atprotopds-cli
        EXECUTABLE_PATH: "$(PROJECT_DIR)/build/bin/atprotopds-cli"
    prebuildScripts:
      - name: "Build with CMake"
        script: |
          #!/bin/bash
          set -e
          mkdir -p "${PROJECT_DIR}/build"
          cd "${PROJECT_DIR}/build"
          cmake .. \
            -DCMAKE_BUILD_TYPE=${CONFIGURATION} \
            -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
            -DBUILD_SECP256K1=ON
          make -j$(sysctl -n hw.ncpu) atprotopds-cli

  AllTests:
    type: tool
    platform: macOS
    sources: []
    prebuildScripts:
      - name: "Build Tests with CMake"
        script: |
          #!/bin/bash
          set -e
          cd "${PROJECT_DIR}/build"
          cmake .. -DBUILD_TESTS=ON
          make -j$(sysctl -n hw.ncpu) AllTests
```

## Building the Project

### From Command Line

```bash
# Generate Xcode project
xcodegen generate

# Build CLI tool
xcodebuild -scheme ATProtoPDS-CLI build
# Output: ./build/bin/atprotopds-cli

# Build and run tests
xcodebuild -scheme AllTests build
./build/tests/AllTests

# Direct CMake build (without Xcode)
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
make -j$(sysctl -n hw.ncpu)
```

### Using Makefile Convenience Targets

A `Makefile` wraps common operations:

```makefile
.PHONY: build test clean

build:
	mkdir -p build && cd build && cmake .. && make -j$$(sysctl -n hw.ncpu)

test: build
	./build/tests/AllTests

clean:
	rm -rf build
```

## Practical Exercise: Create a New Module

Add a new `Config` module to the project:

### 1. Create Files

```bash
mkdir -p ATProtoPDS/Sources/Config
touch ATProtoPDS/Sources/Config/PDSConfig.h
touch ATProtoPDS/Sources/Config/PDSConfig.m
```

### 2. Implement Header

```objc
// PDSConfig.h
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PDSConfig : NSObject

@property (readonly, nonatomic, copy) NSString *hostname;
@property (readonly, nonatomic) NSUInteger port;
@property (readonly, nonatomic, copy) NSString *databasePath;

+ (nullable instancetype)loadFromPath:(NSString *)path error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
```

### 3. Verify Build

```bash
# CMake automatically picks up new .m files via GLOB_RECURSE
cd build
cmake ..
make atprotopds-cli

# Verify the new files are compiled
ls ATProtoPDS/Sources/Config/
```

### 4. Regenerate Xcode Project

```bash
xcodegen generate
open ATProtoPDS.xcodeproj
```

<script setup>
const pdsConfigCode = `#import <Foundation/Foundation.h>

// PDSConfig Interface
@interface PDSConfig : NSObject
@property (readonly, nonatomic, copy) NSString *hostname;
@property (readonly, nonatomic) NSUInteger port;
@property (readonly, nonatomic, copy) NSString *databasePath;
+ (instancetype)loadFromPath:(NSString *)path error:(NSError **)error;
@end

// PDSConfig Implementation
@implementation PDSConfig
+ (instancetype)loadFromPath:(NSString *)path error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (!data) return nil;
    
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (!json) return nil;
    
    PDSConfig *config = [[PDSConfig alloc] init];
    config->_hostname = [json[@"hostname"] copy];
    config->_port = [json[@"port"] unsignedIntegerValue];
    config->_databasePath = [json[@"databasePath"] copy];
    return config;
}
- (NSString *)description {
    return [NSString stringWithFormat:@"Server running at %@:%lu (DB: %@)", 
            self.hostname, (unsigned long)self.port, self.databasePath];
}
@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // 1. Create a dummy config file
        NSString *json = @"{\\"hostname\\": \\"bsky.social\\", \\"port\\": 3000, \\"databasePath\\": \\"pds.sqlite\\"}";
        NSString *path = @"/tmp/config.json";
        [json writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        
        // 2. Load it using our class
        NSError *error = nil;
        PDSConfig *config = [PDSConfig loadFromPath:path error:&error];
        
        if (config) {
            NSLog(@"✅ Loaded Config: %@", config);
        } else {
            NSLog(@"❌ Error: %@", error);
        }
    }
    return 0;
}`;
</script>

<ObjcRunner :initialCode="pdsConfigCode" />

---

## Common Mistakes

### Mistake 1: GLOB_RECURSE Without Filter

❌ **What people do:**
```cmake
# WRONG: Include everything, including test files and main.m
file(GLOB_RECURSE ALL_SOURCES "ATProtoPDS/**/*.m")
add_executable(myapp ${ALL_SOURCES})
```

**Why this fails:**
- Multiple `main()` functions cause linker errors
- Test files included in production binary
- Compatibility files for other platforms included

✅ **Correct approach:**
```cmake
file(GLOB_RECURSE ATProtoPDS_SOURCES "ATProtoPDS/Sources/**/*.m")
list(FILTER ATProtoPDS_SOURCES EXCLUDE REGEX ".*main\\.m$")
list(FILTER ATProtoPDS_SOURCES EXCLUDE REGEX ".*/Tests/.*")
```

### Mistake 2: Forgetting ARC Flags

❌ **What people do:**
```cmake
# WRONG: Missing ARC flag
add_executable(myapp ${SOURCES})
# Code compiles, but crashes at runtime with memory issues
```

**Why this fails:**
- Objective-C memory management is manual by default
- Without ARC, you must call `retain`/`release` manually
- Modern Objective-C code assumes ARC enabled

✅ **Correct approach:**
```cmake
# RIGHT: Enable ARC for all Objective-C files
set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -fobjc-arc")
```

### Mistake 3: Hardcoded XCTest Paths

❌ **What people do:**
```cmake
# WRONG: Hardcoded Xcode path
find_library(XCTest XCTest 
  PATHS "/Applications/Xcode.app/Contents/Developer/...")
```

**Why this fails:**
- Different machines may have Xcode in different locations
- xcode-select may point to beta or command-line tools
- Breaks on CI systems with custom Xcode installations

✅ **Correct approach:**
```cmake
# RIGHT: Use xcode-select to find current Xcode
execute_process(
  COMMAND xcode-select -p 
  OUTPUT_VARIABLE XCODE_DEVELOPER_DIR 
  OUTPUT_STRIP_TRAILING_WHITESPACE
)
find_library(XCTest XCTest 
  PATHS "${XCODE_DEVELOPER_DIR}/Platforms/MacOSX.platform/Developer/Library/Frameworks"
)
```

---

## Summary

In this chapter, you learned:

- ✅ Standard Objective-C project layout
- ✅ CMake configuration for Objective-C projects
- ✅ Finding and linking dependencies (frameworks, libraries)
- ✅ Source file collection and exclusion patterns
- ✅ XcodeGen for Xcode project generation
- ✅ Build commands for CLI and test targets

## Key Takeaways

1. **Use GLOB_RECURSE wisely** - Always filter out test files and entry points.

2. **Enable ARC** - Modern Objective-C requires `-fobjc-arc`.

3. **Keep CMake portable** - Avoid hardcoded paths; use `xcode-select` and `find_library`.

## Next Steps

With our build system in place, we're ready to dive into **Part II: Core Data Structures**. In **Chapter 4**, we'll implement Content Identifiers (CIDs)—the fundamental building block for content-addressed data.

---

**Files Referenced in This Chapter:**
- [CMakeLists.txt](file:///Users/jack/Software/objpds/CMakeLists.txt)
- [project.yml](file:///Users/jack/Software/objpds/project.yml)
- [Makefile](file:///Users/jack/Software/objpds/Makefile)
