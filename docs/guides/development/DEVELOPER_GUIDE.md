---
title: "Developer Guide: ATProto PDS API Extension"
---

# Developer Guide: ATProto PDS API Extension

This guide provides procedures for adding new endpoints, modifying existing functionality, and contributing to the ATProto PDS server codebase with a focus on Objective-C best practices.

## Project Structure

```

Garazyk/
├── Sources/
│   ├── App/Explore/           # Web interface and API
│   │   ├── Assets/           # HTML/CSS/JS frontend
│   │   └── ExploreHandler.*  # Backend API handlers
│   ├── CLI/                  # Command-line interface
│   ├── Core/                 # AT Protocol business logic
│   ├── Database/             # SQLite persistence layer
│   └── Network/              # HTTP server implementation
├── Tests/                    # Unit and integration tests
├── docs/                     # Documentation
├── scripts/                  # Build, test, scenario, docs, and operator tooling
│   ├── run_scenarios.ts      # Deno full-stack scenario runner
│   ├── scenarios/            # Scenario fixtures, config, and scenario modules
│   ├── lib/deno/             # Shared Deno clients and runner helpers
│   ├── build/quality_gate.sh # Code quality and static analysis wrapper
│   ├── ops/start_server.sh   # Production server startup script
│   └── test/run-tests.sh     # Test suite runner
├── deno.json                 # Root Deno configuration for repo scripts
├── .agents/skills/           # Development skills and best practices
├── CMakeLists.txt            # Main build configuration
└── project.yml               # Xcode project configuration
```

## Build System

The project uses a unified **CMake** build system wrapped by **XcodeGen** for Xcode integration.

### Generating the Project

To generate the Xcode project (required before building):

```bash
xcodegen generate
```

This creates `Garazyk.xcodeproj` configured to use XcodeGen + CMake for all build targets.

### Building Targets

You can build targets using `xcodebuild` or from within Xcode.

**Main CLI Tool:**
```bash
xcodebuild -scheme kaszlak build
```

## Objective-C Development Guidelines

### Memory Management
- Use ARC for automatic memory management
- Follow proper Core Foundation ownership rules
- Avoid retain cycles with weak references
- Use `dispatch_once` for thread-safe singletons

### Thread Safety
- Use dispatch queues for concurrent operations
- Follow proper synchronization patterns
- Avoid blocking main thread in UI operations
- Use `@synchronized` for critical sections when needed

### Error Handling
- Use NSError patterns for error propagation
- Validate all input parameters
- Handle edge cases and failure scenarios
- Log errors appropriately without exposing sensitive data

### Security Best Practices
- Validate all user input
- Use secure coding practices
- Avoid hardcoded credentials
- Follow principle of least privilege

## Adding New Endpoints

### XRPC Method Registration

To add a new XRPC endpoint, follow these steps:

1. **Define the method signature** in the appropriate handler
2. **Register the method** with the XRPC server
3. **Implement the handler logic** following Objective-C patterns
4. **Add validation** for input parameters
5. **Handle errors** appropriately with NSError
6. **Add unit tests** for the new functionality

### Code Organization

- Place new handlers in `Sources/App/Explore/`
- Follow existing naming conventions
- Use appropriate dispatch queues for concurrency
- Maintain consistent error handling patterns

## Common Development Patterns

### Repository Pattern

```objc
// Example repository pattern implementation
@interface PDSRepository : NSObject

@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) PDSDatabase *database;

- (instancetype)initWithDatabase:(PDSDatabase *)database;
- (void)performOperationWithCompletion:(void (^)(NSError *error))completion;

@end

@implementation PDSRepository

- (instancetype)initWithDatabase:(PDSDatabase *)database {
    self = [super init];
    if (self) {
        _database = database;
        _queue = dispatch_queue_create("com.atproto.pds.repository", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)performOperationWithCompletion:(void (^)(NSError *error))completion {
    dispatch_async(self.queue, ^{
        NSError *error = nil;
        
        // Perform database operation
        if (![self.database executeOperationWithError:&error]) {
            // Handle error appropriately
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(error);
                });
            }
            return;
        }
        
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil);
            });
        }
    });
}

@end
```

Garazyk/
├── Sources/
│   ├── App/Explore/           # Web interface and API
│   │   ├── Assets/           # HTML/CSS/JS frontend
│   │   └── ExploreHandler.*  # Backend API handlers
│   ├── CLI/                  # Command-line interface
│   ├── Core/                 # AT Protocol business logic
│   ├── Database/             # SQLite persistence layer
│   └── Network/              # HTTP server implementation
├── Tests/                    # Unit and integration tests
├── docs/                     # Documentation
├── scripts/                  # Build, test, scenario, docs, and operator tooling
│   ├── run_scenarios.ts      # Deno full-stack scenario runner
│   ├── scenarios/            # Scenario fixtures, config, and scenario modules
│   ├── lib/deno/             # Shared Deno clients and runner helpers
│   ├── build/quality_gate.sh # Code quality and static analysis wrapper
│   ├── ops/start_server.sh   # Production server startup script
│   └── test/run-tests.sh     # Test suite runner
├── deno.json                 # Root Deno configuration for repo scripts
├── .agents/skills/           # Development skills and best practices
├── CMakeLists.txt            # Main build configuration
└── project.yml               # Xcode project configuration
```

## Build System

The project uses a unified **CMake** build system wrapped by **XcodeGen** for Xcode integration.

### Generating the Project

To generate the Xcode project (required before building):

```bash
xcodegen generate
```

This creates `Garazyk.xcodeproj` configured to use XcodeGen + CMake for all build targets.

### Building Targets

You can build targets using `xcodebuild` or from within Xcode.

**Main CLI Tool:**
```bash
xcodebuild -scheme kaszlak build
```

The binary will be available at `./build/bin/kaszlak`.

**Unit Tests:**
```bash
xcodebuild -scheme AllTests build
```

The test runner will be at `./build/tests/AllTests`.

**Fuzzers:**
```bash
xcodebuild -scheme Fuzzers build
```

Fuzzer binaries will be at `./build/fuzzing/`.

### Running Tests

**Run all unit tests:**
```bash
./scripts/test/run-tests.sh
# or manually:
./build/tests/AllTests
```

**Run integration tests:**
```bash
./scripts/test/test-pds-integration.sh
```

**Run fuzzers:**
```bash
./build/fuzzing/fuzz_xrpc fuzzing/corpus_xrpc/xrpc_valid_create.txt
```

## Script Development Standards

Script standards live in `docs/guides/SCRIPT_DEVELOPMENT.md`. The short version:

- Use Bash for process boundaries, service lifecycle, CI wrappers, and operator glue.
- Use Deno/TypeScript for XRPC calls, scenario logic, structured JSON, docs analysis, and report generation.
- Keep shared Deno helpers in `scripts/lib/deno/`.
- Keep full-stack scenarios in `scripts/scenarios/scenarios/*.ts`.
- Run `bash -n` or ShellCheck for changed shell scripts.
- Run `deno fmt --config deno.json --check` and `deno check --config deno.json` for changed TypeScript scripts.

Common entrypoints:

- `scripts/run_scenarios.ts`: narrative full-stack scenario runner
- `scripts/build/quality_gate.sh`: code quality and static analysis wrapper
- `scripts/test/run-tests.sh`: Objective-C test suite wrapper
- `scripts/docs/repo_docs.ts`: repository documentation registry and validation

## Adding New API Endpoints

### Step 1: Define the Endpoint Specification

Document the endpoint specification before implementation:

```markdown
# New Endpoint: /explore/api/search-records

**Method**: GET
**Summary**: Search records across collections
**Parameters**:
- `query` (string, required): Search term
- `collection` (string, optional): Limit to specific collection
- `limit` (integer, optional): Max results (default 20)
**Response**: Array of matching records
**Tags**: Records, Search
```

## Step 2: Implement the Handler Method

Add the handler method to `ExploreHandler.m`:

```objc
- (void)handleApiSearchRecords:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *query = params[@"query"];
    if (!query || query.length == 0) {
        [response setJsonBody:@{@"error": @"Missing required parameter: query"}];
        response.statusCode = 400;
        return;
    }

    NSString *collection = params[@"collection"];
    NSNumber *limitNum = params[@"limit"];
    NSInteger limit = limitNum ? [limitNum integerValue] : 20;

    // Implement search logic
    NSArray *results = [self searchRecordsWithQuery:query
                                         collection:collection
                                              limit:limit];

    [response setJsonBody:@{
        @"records": results,
        @"query": query,
        @"count": @(results.count)
    }];
}
```

### Step 3: Add the Route

Update routing logic in `handleApiRequest:`:

```objc
else if ([endpoint isEqualToString:@"search-records"]) {
    [self handleApiSearchRecords:params response:response];
}
```

### Step 4: Implement the Backend Logic

Implement search functionality:

```objc
- (NSArray *)searchRecordsWithQuery:(NSString *)query
                         collection:(NSString *)collection
                              limit:(NSInteger)limit {
    // Database search implementation
    NSString *sql = @"SELECT * FROM records WHERE value LIKE ? ";
    NSMutableArray *args = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"%%%@%%", query]];

    if (collection.length > 0) {
        sql = [sql stringByAppendingString:@"AND collection = ? "];
        [args addObject:collection];
    }

    sql = [sql stringByAppendingFormat:@"LIMIT %ld", limit];

    // Execute query and return results
    return [self executeRecordsQuery:sql withArgs:args];
}
```

### Step 5: Add OpenAPI Documentation

Update `allEndpointDescriptors` to include new endpoint:

```objc
APIParameterDescriptor *queryParam = [[APIParameterDescriptor alloc] init];
queryParam.name = @"query";
queryParam.in = @"query";
queryParam.type = @"string";
queryParam.paramDescription = @"Search term to match in record content";
queryParam.required = YES;

APIParameterDescriptor *collectionParam = [[APIParameterDescriptor alloc] init];
collectionParam.name = @"collection";
collectionParam.in = @"query";
collectionParam.type = @"string";
collectionParam.paramDescription = @"Optional collection namespace to search within";
collectionParam.required = NO;

APIParameterDescriptor *limitParam = [[APIParameterDescriptor alloc] init];
limitParam.name = @"limit";
limitParam.in = @"query";
limitParam.type = @"integer";
limitParam.paramDescription = @"Maximum number of results to return";
limitParam.required = NO;

APIResponseDescriptor *searchResponse = [[APIResponseDescriptor alloc] init];
searchResponse.statusCode = @"200";
searchResponse.responseDescription = @"Array of records matching the search query";
searchResponse.arrayItemRef = @"#/components/schemas/Record";

[descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/explore/api/search-records"
                                                          method:@"get"
                                                         summary:@"Search records across collections"
                                                    endpointName:@"search-records"
                                                    operationId:@"searchRecords"
                                                           tags:@[@"Records", @"Search"]
                                                      parameters:@[queryParam, collectionParam, limitParam]
                                                      responses:@[searchResponse, error400, errorResponse]]];
```

## Testing New Features

### Unit Tests

Add tests in `Garazyk/Tests/` directory. All files matching `Garazyk/Tests/**/*.m` are automatically included in the `AllTests` target.

```bash
# Build and run unit tests
xcodebuild -scheme AllTests build
./build/tests/AllTests
```

## Integration Tests

Test the PDS server using the CLI and curl:

```bash
# Start server
./build/bin/kaszlak serve --verbose

# Create test account
./build/bin/kaszlak account create --email test@example.com --handle test.test

# Test API endpoint
curl -s http://localhost:2583/explore/api/accounts
```

## Security Development Guidelines

### Input Validation Requirements

All new endpoints must implement proper input validation:

```objc
// Example: Parameter validation
- (void)handleApiEndpoint:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *requiredParam = params[@"required"];
    if (!requiredParam || requiredParam.length == 0) {
        [response setJsonBody:@{@"error": @"Missing required parameter"}];
        response.statusCode = 400;
        return;
    }
    
    // Validate length limits
    if (requiredParam.length > 1000) {
        [response setJsonBody:@{@"error": @"Parameter too long"}];
        response.statusCode = 400;
        return;
    }
    
    // Sanitize input if needed
    NSString *sanitized = [self sanitizeInput:requiredParam];
}
```

### Memory Management for Security

Follow these patterns for secure memory management:

**Core Foundation Objects:**
```objc
// Always pair CFRetain with CFRelease
@property (nonatomic, assign) SecKeyRef securityKey;

- (void)setSecurityKey:(SecKeyRef)key {
    if (_securityKey) CFRelease(_securityKey);
    _securityKey = key ? CFRetain(key) : NULL;
}

- (void)dealloc {
    if (_securityKey) CFRelease(_securityKey);
}
```

**Queue Properties:**
```objc
// Use strong for dispatch queues
@property (nonatomic, strong) dispatch_queue_t workQueue;

// Create with proper naming
self.workQueue = dispatch_queue_create("com.atproto.pds.endpoint", DISPATCH_QUEUE_SERIAL);
```

### Network Security Limits

Implement size limits for all network-facing code:

```objc
// WebSocket frame size limit
static const NSUInteger MAX_FRAME_SIZE = 16 * 1024 * 1024;

// HTTP request size limit  
static const NSUInteger MAX_REQUEST_SIZE = 10 * 1024 * 1024;

// Validate before processing
if (requestSize > MAX_REQUEST_SIZE) {
    response.statusCode = 413; // Payload Too Large
    return;
}
```

### Cryptographic Best Practices

When implementing cryptographic features:

1. **Key Storage**: Use Keychain (`SecKeyRef`) for persistent keys
2. **Random Generation**: Use `SecRandomCopyBytes`, not `rand()`
3. **No Custom Crypto**: Use Apple's Security framework
4. **Constant-Time**: Use timing-safe comparisons for sensitive data

### Error Handling Security

Don't expose internal details in error messages:

```objc
// Bad - exposes internal state
*error = [NSError errorWithDomain:@"MyDomain" 
                             code:1001 
                         userInfo:@{NSLocalizedDescriptionKey: @"Database connection failed on table users"}];

// Good - generic error message
*error = [NSError errorWithDomain:@"MyDomain" 
                             code:1001 
                         userInfo:@{NSLocalizedDescriptionKey: @"Internal server error"}];
```

## Troubleshooting Build Issues

If you encounter build errors:

1.  **Check CMake Generation**: Run `cmake .` in `build/` directory to see detailed configuration errors.
2.  **Clean Build**: `rm -rf build` and regenerate project.
3.  **Dependency Issues**: Ensure `secp256k1` and `sqlite3` are properly linked. The CMake build handles `secp256k1` as a subproject.

## Getting Help

### Resources

- API Documentation: `http://localhost:2583/explore/api/docs`
- OpenAPI Specification: `http://localhost:2583/explore/api/openapi.yaml`
- Architecture Documentation: `docs/architecture/ARCHITECTURE_DIAGRAMS.md`
- Script Development Standards: `docs/guides/SCRIPT_DEVELOPMENT.md`

### Contributing

1.  Follow development workflow
2.  Write tests for new features
3.  Update documentation
4.  Submit pull requests with clear descriptions

## Related Documentation

- **[Setup Guide](# Setup guide)** - Build and installation instructions
- **<!-- Link placeholder: Objective-C Tips -->** - Memory management and coding patterns
- **<!-- Link placeholder: XRPC Protocol Reference -->** - Protocol quick reference
- **<!-- Link placeholder: Script Development -->** - Shell script standards
- **<!-- Link placeholder: Development Workflows -->** - Visual process diagrams
- **<!-- Link placeholder: Architecture Analysis -->** - System design overview
- **<!-- Link placeholder: PDS Architecture -->** - AT Protocol specifications
- **<!-- Link placeholder: OAuth 2.0 Implementation -->** - Authentication flow details
- **<!-- Link placeholder: Security Plan -->** - Security validation strategy
- **<!-- Link placeholder: Testing Guide -->** - Test suite documentation
