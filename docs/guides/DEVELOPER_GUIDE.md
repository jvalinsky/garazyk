# Developer Guide: ATProto PDS API Extension

This guide provides procedures for adding new endpoints, modifying existing functionality, and contributing to the ATProto PDS server codebase.

## Project Structure

```
ATProtoPDS/
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
├── scripts/                  # Build and utility scripts
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

This creates `ATProtoPDS.xcodeproj` configured to use CMake for all build targets.

### Building Targets

You can build targets using `xcodebuild` or from within Xcode.

**Main CLI Tool:**
```bash
xcodebuild -scheme ATProtoPDS-CLI build
```
The binary will be available at `./build/bin/atprotopds-cli`.

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
./build/tests/AllTests
```

**Run fuzzers:**
```bash
./build/fuzzing/fuzz_xrpc fuzzing/corpus_xrpc/xrpc_valid_create.txt
```

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

### Step 2: Implement the Handler Method

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

Add tests in `ATProtoPDS/Tests/` directory. All files matching `ATProtoPDS/Tests/**/*.m` are automatically included in the `AllTests` target.

```bash
# Build and run unit tests
xcodebuild -scheme AllTests build
./build/tests/AllTests
```

### Integration Tests

Test the PDS server using the CLI and curl:

```bash
# Start server
./build/bin/atprotopds-cli serve --verbose

# Create test account
./build/bin/atprotopds-cli account create --email test@example.com --handle test.test

# Test API endpoint
curl -s http://localhost:2583/explore/api/accounts
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
- Architecture Documentation: `docs/ARCHITECTURE_DIAGRAMS.md`
- Session Summary: `docs/SESSION_SUMMARY.md`

### Contributing

1.  Follow development workflow
2.  Write tests for new features
3.  Update documentation
4.  Submit pull requests with clear descriptions
