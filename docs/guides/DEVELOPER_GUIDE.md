# Developer Guide: ATProto PDS API Extension

This guide provides procedures for adding new endpoints, modifying existing functionality, and contributing to the ATProto PDS server codebase.

## Project Structure

```
ATProtoPDS/
├── Sources/
│   ├── App/Explore/           # Web interface and API
│   │   ├── Assets/           # HTML/CSS/JS frontend
│   │   │   ├── index.html    # Main explorer UI
│   │   │   ├── docs.html     # API documentation UI
│   │   │   ├── css/          # Stylesheets
│   │   │   └── js/           # JavaScript modules
│   │   └── ExploreHandler.*  # Backend API handlers
│   ├── CLI/                  # Command-line interface
│   ├── Core/                 # AT Protocol business logic
│   ├── Database/             # SQLite persistence layer
│   └── Network/              # HTTP server implementation
├── Tests/                    # Unit and integration tests
├── docs/                     # Documentation
└── scripts/                  # Build and utility scripts
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

### Step 6: Update Frontend (Optional)

Update JavaScript for web UI accessibility:

```javascript
// Add to api.js
async searchRecords(query, options = {}) {
    const params = new URLSearchParams({ query });
    if (options.collection) params.set('collection', options.collection);
    if (options.limit) params.set('limit', options.limit);

    return getCachedOrFetch(`search:${query}:${options.collection || ''}:${options.limit || 20}`, CACHE_TTL.records,
        () => fetch(`${API_BASE}/search-records?${params}`).then(r => r.json())
    );
}

// Add UI in ui.js if needed
async function handleSearch() {
    const query = document.getElementById('search-input').value.trim();
    if (!query) return;

    const results = await API.searchRecords(query, { limit: 50 });
    renderSearchResults(results.records);
}
```

## Modifying Existing Endpoints

### Changing Response Format

1. Update handler method to return new format
2. Update OpenAPI schema to reflect changes
3. Update frontend code to handle new format
4. Add migration logic for breaking changes

### Adding Parameters

1. Add parameter validation in handler
2. Update OpenAPI descriptor with new parameter
3. Update frontend to pass new parameter
4. Add default values for backward compatibility

### Performance Optimization

1. Add caching in `getCachedOrFetch` wrapper
2. Implement pagination for large result sets
3. Add database indexes for frequently queried fields
4. Use prepared statements for repeated queries

## Database Schema Changes

### Adding New Tables

1. Create migration SQL:
```sql
CREATE TABLE new_table (
    id INTEGER PRIMARY KEY,
    data TEXT NOT NULL,
    created_at INTEGER DEFAULT (strftime('%s', 'now'))
);
```

2. Add migration logic in handler initialization:
```objc
- (void)runMigrations {
    char *errMsg = NULL;
    int rc = sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS new_table (...);", NULL, NULL, &errMsg);
    if (errMsg) {
        NSLog(@"Migration error: %s", errMsg);
        sqlite3_free(errMsg);
    }
}
```

3. Update PDSDatabase class with new methods:
```objc
- (BOOL)insertIntoNewTable:(NSDictionary *)data error:(NSError **)error;
- (NSArray *)queryNewTableWithLimit:(NSInteger)limit error:(NSError **)error;
```

### Schema Migrations

Implement migration tracking for production systems:

```objc
- (void)applyMigrations {
    NSInteger currentVersion = [self getCurrentSchemaVersion];

    if (currentVersion < 1) {
        [self applyMigration1];
        [self setSchemaVersion:1];
    }

    if (currentVersion < 2) {
        [self applyMigration2];
        [self setSchemaVersion:2];
    }
}
```

## Testing New Features

### Unit Tests

Add tests in `Tests/` directory:

```objc
- (void)testSearchRecords {
    // Setup test data
    NSDictionary *testRecord = @{
        @"uri": @"at://did:plc:test/app.test.record/test",
        @"value": @{@"text": @"test search content"}
    };

    // Insert test data
    [self insertTestRecord:testRecord];

    // Test search functionality
    NSArray *results = [handler searchRecordsWithQuery:@"search"
                                             collection:nil
                                                  limit:10];

    XCTAssertEqual(results.count, 1);
    XCTAssertEqualObjects(results[0][@"uri"], testRecord[@"uri"]);
}
```

### Integration Tests

Add API endpoint tests:

```bash
# Test new endpoint
curl -X GET "http://localhost:2583/explore/api/search-records?query=test" \
     -H "Content-Type: application/json" \
     -w "\nStatus: %{http_code}\n"

# Verify response format
curl -s "http://localhost:2583/explore/api/search-records?query=test" | jq '.records | length'
```

### Performance Testing

```bash
# Load testing
ab -n 1000 -c 10 "http://localhost:2583/explore/api/search-records?query=test"

# Memory profiling
instruments -t "Allocations" -D trace.trace ./atprotopds-cli serve --port 2583
```

## Frontend Development

### Adding New UI Components

1. Create HTML structure in appropriate section
2. Add CSS styling in `style.css`
3. Implement JavaScript logic in `ui.js`
4. Add API calls in `api.js`
5. Update navigation if needed

### Search Interface Implementation

```html
<section id="search" class="section">
    <h1>Search Records</h1>
    <div class="search-input-group">
        <input type="text" id="search-input" placeholder="Search records...">
        <select id="search-collection">
            <option value="">All collections</option>
            <option value="app.bsky.feed.post">Posts</option>
            <option value="app.bsky.feed.like">Likes</option>
        </select>
        <button id="search-btn" class="btn-primary">Search</button>
    </div>
    <div id="search-results" class="content-box"></div>
</section>
```

```javascript
document.getElementById('search-btn').addEventListener('click', async () => {
    const query = document.getElementById('search-input').value.trim();
    const collection = document.getElementById('search-collection').value;

    if (!query) return;

    const results = await API.searchRecords(query, {
        collection: collection || undefined,
        limit: 50
    });

    renderSearchResults(results.records);
});
```

## Security Considerations

### Input Validation

Validate all inputs:

```objc
- (BOOL)validateSearchQuery:(NSString *)query {
    if (!query || query.length == 0) return NO;
    if (query.length > 1000) return NO; // DoS prevention
    // Check for SQL injection attempts
    if ([query containsString:@"'"] || [query containsString:@";"]) return NO;
    return YES;
}
```

### Rate Limiting

Implement rate limiting for resource-intensive operations:

```objc
- (BOOL)shouldRateLimitRequest:(NSString *)clientIP endpoint:(NSString *)endpoint {
    // Rate limiting implementation
    // Return YES to block request
    return NO;
}
```

### Authentication Implementation

When implementing authentication:

```objc
- (BOOL)authenticateRequest:(HttpRequest *)request {
    NSString *authHeader = [request.headers objectForKey:@"Authorization"];
    // Validate JWT token
    return [self validateJWT:authHeader];
}
```

## Deployment and CI/CD

### Build Configuration

Update `Makefile` for new dependencies:

```makefile
deps: libsecp256k1
    # New dependency installation

libsecp256k1:
    cd secp256k1 && ./autogen.sh && ./configure && make
```

### CI Pipeline Updates

Add tests to GitHub Actions:

```yaml
- name: Test New Endpoint
  run: |
    ./scripts/test_endpoints.sh
    curl -f "http://localhost:2583/explore/api/search-records?query=test"
```

### Docker Support

```dockerfile
FROM macos:latest
COPY . /app
RUN make build-release
RUN make install-deps
EXPOSE 2583
HEALTHCHECK --interval=30s --timeout=3s \
  CMD curl -f http://localhost:2583/explore/api/accounts || exit 1
CMD ["/app/atprotopds-cli", "serve", "--port", "2583"]
```

## Debugging and Monitoring

### Logging

Implement structured logging:

```objc
NSLog(@"[Search] Query: %@, Collection: %@, Results: %ld",
      query, collection, results.count);
```

### Metrics

Add performance metrics:

```objc
NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
// Operation execution
NSTimeInterval duration = [NSDate timeIntervalSinceReferenceDate] - start;
[self recordMetric:@"search.duration" value:duration];
```

### Error Handling

Implement comprehensive error handling:

```objc
@try {
    // Operation execution
} @catch (NSException *e) {
    NSLog(@"Error in search operation: %@", e);
    [response setJsonBody:@{@"error": @"Internal server error"}];
    response.statusCode = 500;
} @finally {
    // Cleanup procedures
}
```

## Documentation Updates

### API Documentation

OpenAPI specification regenerates automatically. Document breaking changes:

```markdown
## v2.0.0 (Breaking Changes)
- Added `/explore/api/search-records` endpoint
- Changed response format for `/explore/api/accounts`
- Deprecated `oldParameter` in favor of `newParameter`
```

### User Documentation

Update user guide for new features:

```markdown
### Advanced Search
Use search endpoint to find records across collections:

```bash
curl "http://localhost:2583/explore/api/search-records?query=hello&limit=10"
```
```

### Code Documentation

Add inline documentation:

```objc
/**
 * Searches records across collections using full-text search
 *
 * @param query The search term to match
 * @param collection Optional collection namespace to limit search
 * @param limit Maximum number of results to return
 * @return Array of matching record dictionaries
 */
- (NSArray *)searchRecordsWithQuery:(NSString *)query
                         collection:(NSString *)collection
                              limit:(NSInteger)limit {
    // Search implementation
}
```

## Best Practices

### Code Quality

1. Use clear, descriptive naming conventions
2. Handle errors gracefully
3. Validate all inputs
4. Document complex logic
5. Write tests for new functionality

### Performance

1. Use appropriate TTL values for caching
2. Limit result sets with pagination
3. Add database indexes for queries
4. Use non-blocking I/O operations

### Security

1. Sanitize all user inputs
2. Implement rate limiting to prevent abuse
3. Require authentication for sensitive operations
4. Log security events

### Maintainability

1. Maintain modular, focused functions
2. Externalize configuration values
3. Keep documentation synchronized with code
4. Plan for API versioning

## Getting Help

### Resources

- API Documentation: `http://localhost:2583/explore/api/docs`
- OpenAPI Specification: `http://localhost:2583/explore/api/openapi.yaml`
- Architecture Documentation: `docs/ARCHITECTURE_DIAGRAMS.md`
- Session Summary: `docs/SESSION_SUMMARY.md`

### Common Issues

1. Build failures: Check dependencies and Xcode version
2. Test failures: Ensure test data is properly configured
3. API errors: Check request format and server logs
4. Performance issues: Profile with Instruments

### Contributing

1. Follow development workflow
2. Write tests for new features
3. Update documentation
4. Submit pull requests with clear descriptions

Consider backward compatibility, performance, and security when implementing changes.