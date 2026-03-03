# End-to-End Testing

September PDS uses end-to-end (E2E) testing to validate complete workflows across the entire system. E2E tests exercise the full stack from HTTP requests through to database persistence, ensuring all components work together correctly.

## E2E Testing Strategy

### Test Levels

September employs a multi-level testing strategy:

1. **Unit Tests** - Test individual components in isolation (~800 tests)
2. **Integration Tests** - Test multiple components together (~150 tests)
3. **E2E Tests** - Test complete workflows end-to-end (~50 tests)
4. **Interoperability Tests** - Test AT Protocol compliance (~20 tests)

### E2E Test Characteristics

E2E tests in September:
- Start a real HTTP server
- Use real databases (SQLite in temporary directories)
- Make actual HTTP requests
- Verify end-to-end behavior
- Test complete user workflows
- Validate protocol compliance

## Integration Test Examples

### OAuth Integration Test

Tests the complete OAuth 2.0 authorization flow:

```objective-c
@interface OAuthIntegrationTests : XCTestCase
@property (nonatomic, strong) HttpServer *server;
@property (nonatomic, strong) OAuth2Server *oauthServer;
@property (nonatomic, strong) OAuth2Handler *oauthHandler;
@property (nonatomic, strong) PDSDatabase *db;
@end

@implementation OAuthIntegrationTests

- (void)setUp {
    [super setUp];
    
    // Setup Database
    NSString *tempPath = [NSTemporaryDirectory() 
                          stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    self.db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:tempPath]];
    [self.db openWithError:nil];
    
    // Setup OAuth Server
    self.oauthServer = [[OAuth2Server alloc] initWithDatabase:self.db];
    self.oauthServer.issuer = @"http://127.0.0.1:8443";
    
    // Setup HTTP Server
    self.server = [HttpServer serverWithPort:0];
    self.oauthHandler = [[OAuth2Handler alloc] initWithDatabase:self.db];
    self.oauthHandler.oauthServer = self.oauthServer;
    [self.oauthHandler registerRoutesWithServer:self.server];
    
    // Seed test client
    NSDictionary *testClient = @{
        @"client_id": @"test-client",
        @"client_secret": @"test-secret",
        @"redirect_uris": @[@"http://127.0.0.1:3000/callback"],
        @"grant_types": @"authorization_code,refresh_token",
        @"scope": @"atproto"
    };
    [self.db createClient:testClient error:nil];
    
    // Start server
    NSError *startError = nil;
    if (![self.server startWithError:&startError]) {
        XCTFail(@"Failed to start HttpServer: %@", startError);
    }
}

- (void)tearDown {
    [self.server stop];
    [self.db close];
    [super tearDown];
}

- (void)testFullOAuthFlow {
    // 1. Authorization Request
    NSURL *authURL = [NSURL URLWithString:
        [NSString stringWithFormat:@"http://127.0.0.1:%lu/oauth/authorize?client_id=test-client&response_type=code&redirect_uri=http://127.0.0.1:3000/callback&scope=atproto",
         (unsigned long)self.server.port]];
    
    // Make request and capture redirect
    __block NSString *authCode = nil;
    // ... HTTP request logic ...
    
    XCTAssertNotNil(authCode, @"Should receive authorization code");
    
    // 2. Token Exchange
    NSURL *tokenURL = [NSURL URLWithString:
        [NSString stringWithFormat:@"http://127.0.0.1:%lu/oauth/token",
         (unsigned long)self.server.port]];
    
    // ... token exchange request ...
    
    XCTAssertNotNil(accessToken, @"Should receive access token");
    XCTAssertNotNil(refreshToken, @"Should receive refresh token");
    
    // 3. Use Access Token
    // ... make authenticated request ...
    
    XCTAssertEqual(statusCode, 200, @"Authenticated request should succeed");
}

@end
```

### Firehose Integration Test

Tests the complete firehose subscription workflow:

```objective-c
@interface FirehoseIntegrationTests : XCTestCase
@property (nonatomic, strong) PDSController *controller;
@property (nonatomic, copy) NSString *tempDir;
@property (nonatomic, copy) NSString *did;
@end

@implementation FirehoseIntegrationTests

- (void)setUp {
    [super setUp];
    
    // Create temporary directory
    NSString *guid = [[NSProcessInfo processInfo] globallyUniqueString];
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:guid];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir 
                              withIntermediateDirectories:YES 
                                               attributes:nil 
                                                    error:nil];
    
    // Initialize controller
    self.controller = [[PDSController alloc] initWithDirectory:self.tempDir
                                                serviceMaxSize:5
                                              userDatabaseSize:5];
    
    // Create test account
    NSError *error = nil;
    NSDictionary *account = [self.controller createAccountForEmail:@"alice@test.com"
                                                         password:@"password"
                                                           handle:@"alice.test"
                                                              did:nil
                                                            error:&error];
    XCTAssertNotNil(account);
    self.did = account[@"did"];
}

- (void)tearDown {
    [self.controller stopServer];
    if (self.tempDir) {
        [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    }
    [super tearDown];
}

- (void)testBroadcastCommitCARContainsRecordBlocks {
    // Create firehose handler
    SubscribeReposHandler *handler = 
        [[SubscribeReposHandler alloc] initWithServiceDatabases:self.controller.serviceDatabases 
                                               userDatabasePool:self.controller.userDatabasePool];
    
    // Attach mock connection
    MockWebSocketConnection *mockConn = [[MockWebSocketConnection alloc] init];
    [handler.attachedConnections addObject:mockConn];
    
    // Create record
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Hello Firehose!",
        @"createdAt": [self currentTimestamp]
    };
    
    NSError *error = nil;
    BOOL success = [self.controller putRecord:@"app.bsky.feed.post"
                                         rkey:@"post1"
                                        value:record
                                       forDid:self.did
                               validationMode:PDSValidationModeOff
                                        error:&error];
    XCTAssertTrue(success);
    
    // Wait for broadcast
    XCTestExpectation *expectation = [self expectationWithDescription:@"Broadcast received"];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (int i = 0; i < 20; i++) {
            if (mockConn.messageCount > 0) {
                [expectation fulfill];
                break;
            }
            [NSThread sleepForTimeInterval:0.1];
        }
    });
    
    [self waitForExpectationsWithTimeout:3.0 handler:nil];
    
    // Verify message contains CAR with record blocks
    XCTAssertGreaterThan(mockConn.messageCount, 0);
    NSData *message = mockConn.lastMessage;
    
    // Decode CBOR message
    id decoded = [ATProtoDagCBOR decodeData:message error:&error];
    XCTAssertNotNil(decoded);
    
    // Extract CAR data
    NSDictionary *payload = decoded[@"payload"];
    NSData *carData = payload[@"blocks"];
    XCTAssertNotNil(carData);
    
    // Verify CAR contains record
    CARReader *reader = [CARReader readFromData:carData error:&error];
    XCTAssertGreaterThanOrEqual(reader.blocks.count, 2, @"Should contain commit and record blocks");
    
    // Find record block
    BOOL foundRecord = NO;
    for (CARBlock *block in reader.blocks) {
        id obj = [ATProtoDagCBOR decodeData:block.data error:nil];
        if ([obj isKindOfClass:[NSDictionary class]]) {
            if ([obj[@"text"] isEqualToString:@"Hello Firehose!"]) {
                foundRecord = YES;
                break;
            }
        }
    }
    XCTAssertTrue(foundRecord, @"CAR should contain the record block");
}

@end
```

## PLC Integration Tests

September includes dedicated PLC (Public Ledger of Credentials) integration tests that run against a real PLC server:

### PLC Test Environment

Located in `ATProtoPDS/Tests/plc_e2e/`:

```yaml
# docker-compose.yml
services:
  plc-db:
    image: postgres:15-alpine
    container_name: plc_test_db
    environment:
      POSTGRES_USER: plc
      POSTGRES_PASSWORD: plc_secret
      POSTGRES_DB: plc
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U plc -d plc"]
      interval: 5s
      timeout: 5s
      retries: 5

  plc-server:
    build:
      context: ./plc-server
      dockerfile: Dockerfile
    container_name: plc_test_server
    environment:
      DATABASE_URL: postgresql://plc:plc_secret@plc-db:5432/plc?sslmode=disable
      PORT: 2582
    depends_on:
      plc-db:
        condition: service_healthy
    ports:
      - "2582:2582"
```

### Running PLC Integration Tests

```bash
# Start PLC test environment
cd ATProtoPDS/Tests/plc_e2e
docker compose up -d

# Wait for services to be ready
sleep 5

# Run PLC-specific tests
cd ../../..
./build/tests/AllTests -XCTest PLCServerTests,PLCOperationTests,DIDPLCResolverTests

# Cleanup
cd ATProtoPDS/Tests/plc_e2e
docker compose down
```

## CI/CD Integration

### GitHub Actions Workflows

September uses GitHub Actions for continuous integration:

#### Main CI Workflow (`.github/workflows/ci.yml`)

```yaml
jobs:
  macos-build-and-test:
    name: macOS Build & Test
    runs-on: macos-14
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      
      - name: Configure CMake
        run: |
          cmake -B build \
            -DCMAKE_BUILD_TYPE=Debug \
            -DCMAKE_OBJC_COMPILER=clang \
            -DBUILD_SECP256K1=ON \
            -DBUILD_TESTS=ON \
            -DBUILD_FUZZERS=OFF
      
      - name: Build
        run: |
          cmake --build build --parallel 4 --target atprotopds-cli AllTests
      
      - name: Run Tests
        run: |
          ctest --test-dir build --output-on-failure

  linux-gnustep-build-and-test:
    name: Linux GNUstep Build & Test
    runs-on: ubuntu-24.04
    timeout-minutes: 45
    needs: macos-build-and-test
    steps:
      - uses: actions/checkout@v4
      
      - name: Install GNUstep
        run: |
          sudo apt-get update
          sudo apt-get install -y gnustep-devel
      
      - name: Configure CMake
        run: |
          cmake -B build-linux \
            -DCMAKE_BUILD_TYPE=Debug \
            -DCMAKE_OBJC_COMPILER=clang \
            -DBUILD_SECP256K1=ON \
            -DBUILD_TESTS=ON \
            -DBUILD_FUZZERS=OFF
      
      - name: Build (GNUstep)
        run: |
          cmake --build build-linux --parallel 4 --target september AllTests
      
      - name: Run Tests (GNUstep)
        run: |
          ctest --test-dir build-linux --output-on-failure

  plc-integration-tests:
    name: PLC Integration Tests
    runs-on: macos-14
    timeout-minutes: 15
    needs: macos-build-and-test
    steps:
      - uses: actions/checkout@v4
      
      - name: Start PLC Test Environment
        run: |
          cd ATProtoPDS/Tests/plc_e2e
          docker compose up -d
          sleep 10
      
      - name: Run PLC-specific tests
        run: |
          ctest --test-dir build --output-on-failure -R "PLC|DID|Identity"
      
      - name: Cleanup PLC Environment
        if: always()
        run: |
          cd ATProtoPDS/Tests/plc_e2e
          docker compose down
```

### Test Filtering

CI runs different test subsets:

```bash
# Run all tests
ctest --test-dir build --output-on-failure

# Run specific test pattern
ctest --test-dir build --output-on-failure -R "PLC|DID|Identity"

# Run specific test class
./build/tests/AllTests -XCTest OAuthIntegrationTests
```

## Test Scenarios

### Complete User Workflow

```objective-c
- (void)testCompleteUserWorkflow {
    // 1. Create account
    NSDictionary *account = [self.controller createAccountForEmail:@"user@test.com"
                                                         password:@"password"
                                                           handle:@"user.test"
                                                              did:nil
                                                            error:nil];
    NSString *did = account[@"did"];
    
    // 2. Create session
    NSDictionary *session = [self.controller createSessionForIdentifier:@"user@test.com"
                                                              password:@"password"
                                                                 error:nil];
    NSString *accessToken = session[@"accessJwt"];
    
    // 3. Create post
    NSDictionary *post = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Hello World!",
        @"createdAt": [self currentTimestamp]
    };
    
    BOOL success = [self.controller putRecord:@"app.bsky.feed.post"
                                         rkey:@"post1"
                                        value:post
                                       forDid:did
                               validationMode:PDSValidationModeOff
                                        error:nil];
    XCTAssertTrue(success);
    
    // 4. Retrieve post
    NSDictionary *retrieved = [self.controller getRecord:@"app.bsky.feed.post"
                                                    rkey:@"post1"
                                                  forDid:did
                                                   error:nil];
    XCTAssertEqualObjects(retrieved[@"text"], @"Hello World!");
    
    // 5. Delete post
    success = [self.controller deleteRecord:@"app.bsky.feed.post"
                                       rkey:@"post1"
                                     forDid:did
                                      error:nil];
    XCTAssertTrue(success);
    
    // 6. Verify deletion
    retrieved = [self.controller getRecord:@"app.bsky.feed.post"
                                      rkey:@"post1"
                                    forDid:did
                                     error:nil];
    XCTAssertNil(retrieved);
}
```

### Multi-User Interaction

```objective-c
- (void)testMultiUserInteraction {
    // Create two users
    NSDictionary *alice = [self createUser:@"alice" email:@"alice@test.com"];
    NSDictionary *bob = [self createUser:@"bob" email:@"bob@test.com"];
    
    // Alice creates a post
    [self createPost:@"Hello from Alice!" forDid:alice[@"did"]];
    
    // Bob follows Alice
    [self createFollow:alice[@"did"] fromDid:bob[@"did"]];
    
    // Verify Bob's timeline includes Alice's post
    NSArray *timeline = [self getTimelineForDid:bob[@"did"]];
    XCTAssertGreaterThan(timeline.count, 0);
    
    // Verify firehose broadcasts both events
    XCTAssertEqual(self.firehoseMessages.count, 2);
}
```

## Test Helpers

### Mock WebSocket Connection

```objective-c
@interface MockWebSocketConnection : WebSocketConnection
@property (nonatomic, strong) NSData *lastMessage;
@property (nonatomic, assign) NSInteger messageCount;
@property (nonatomic, strong) NSMutableArray<NSData *> *allMessages;
@end

@implementation MockWebSocketConnection

- (instancetype)init {
    self = [super initWithHost:@"mock" port:0 path:@"/"];
    if (self) {
        _allMessages = [NSMutableArray array];
        _messageCount = 0;
    }
    return self;
}

- (void)sendMessage:(NSData *)data {
    self.lastMessage = data;
    self.messageCount++;
    [self.allMessages addObject:data];
}

@end
```

### Test Utilities

```objective-c
- (NSString *)currentTimestamp {
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | 
                              NSISO8601DateFormatWithFractionalSeconds;
    return [formatter stringFromDate:[NSDate date]];
}

- (NSDictionary *)createUser:(NSString *)handle email:(NSString *)email {
    return [self.controller createAccountForEmail:email
                                        password:@"password"
                                          handle:[NSString stringWithFormat:@"%@.test", handle]
                                             did:nil
                                           error:nil];
}

- (void)waitForCondition:(BOOL (^)(void))condition timeout:(NSTimeInterval)timeout {
    NSDate *timeoutDate = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition() && [timeoutDate timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode 
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
}
```

## Best Practices

1. **Isolation** - Each E2E test should be independent
2. **Cleanup** - Always clean up resources in tearDown
3. **Timeouts** - Use reasonable timeouts for async operations
4. **Temporary Data** - Use unique temporary directories
5. **Real Components** - Use real HTTP servers and databases
6. **Assertions** - Verify complete workflows, not just individual steps
7. **Error Handling** - Test both success and failure paths

## Performance Considerations

E2E tests are slower than unit tests:
- Unit test: ~0.001-0.01 seconds
- Integration test: ~0.1-1 seconds
- E2E test: ~1-10 seconds

Keep E2E test count manageable (~50 tests) and focus on critical workflows.

## See Also

- [Test Organization](test-organization.md) - Test structure and discovery
- [Property-Based Testing](property-based-testing.md) - PBT framework
- [Test Coverage Goals](test-coverage-goals.md) - Coverage targets
- [Troubleshooting](troubleshooting.md) - Common test failures
