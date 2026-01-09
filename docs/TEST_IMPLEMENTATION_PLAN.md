# Comprehensive Test Implementation Plan for ATProto PDS Objective-C

## Executive Summary

This plan outlines the implementation of a  test suite for the ATProto PDS Objective-C implementation. The plan prioritizes:
- **Zero external dependencies** - Use only macOS system frameworks
- **Native macOS APIs** - XCTest, Foundation, Security, Dispatch
- **Comprehensive coverage** - Mirror atproto reference implementation patterns
- **Incremental implementation** - Start with critical components, expand coverage

---

## 1. Test Architecture

### 1.1 Frameworks Used

| Framework | Purpose |
|-----------|---------|
| **XCTest** | Core testing framework (assertions, test organization) |
| **Foundation** | Data types, file I/O, networking (NSURLSession) |
| **Security** | Cryptographic operations for token testing |
| **Dispatch** | Concurrency testing (dispatch queues) |
| **ObjectiveC Runtime** | Method introspection for testing utilities |

### 1.2 Test Categories Structure

```
ATProtoPDS/ATProtoPDSTests/
├── Core/                          # Core data type tests
│   ├── CIDTests.h/m
│   ├── TIDTests.h/m
│   ├── DIDTests.h/m
│   └── TestUtilities.h/m
├── Repository/                    # Repository layer tests
│   ├── MSTTests.h/m
│   ├── CARTests.h/m
│   └── RepositoryCRUDTests.h/m
├── Auth/                          # Authentication tests
│   ├── SessionTests.h/m
│   ├── OAuth2Tests.h/m
│   └── JWTTests.h/m
├── Database/                      # Database layer tests
│   ├── DatabaseTests.h/m
│   ├── TransactionTests.h/m
│   └── SchemaTests.h/m
├── Network/                       # Network layer tests
│   ├── HttpServerTests.h/m
│   ├── XrpcTests.h/m
│   └── RateLimiterTests.h/m
└── Integration/                   # Full-stack integration tests
    ├── PDSControllerTests.h/m
    └── EndToEndTests.h/m
```

---

## 2. Test Infrastructure Design

### 2.1 Test Utilities Header (`TestUtilities.h`)

```objc
#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "CID.h"
#import "TID.h"
#import "DID.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Assertion Macros

#define PDS_XCTAssertEqualObjects(a, b, ...) \
    XCTAssertEqualObjects(a, b, ##__VA_ARGS__)

#define PDS_XCTAssertNotNil(a, ...) \
    XCTAssertNotNil(a, ##__VA_ARGS__)

#define PDS_XCTAssertNil(a, ...) \
    XCTAssertNil(a, ##__VA_ARGS__)

#define PDS_XCTAssertTrue(a, ...) \
    XCTAssertTrue(a, ##__VA_ARGS__)

#define PDS_XCTAssertFalse(a, ...) \
    XCTAssertFalse(a, ##__VA_ARGS__)

#pragma mark - Test Fixtures

@interface TestFixture : NSObject

@property (nonatomic, strong, readonly) NSData *testData;
@property (nonatomic, copy, readonly) NSString *testDID;
@property (nonatomic, copy, readonly) NSString *testHandle;
@property (nonatomic, strong, readonly) CID *testCID;
@property (nonatomic, strong, readonly) TID *testTID;

+ (instancetype)sharedFixture;

- (NSData *)randomDataOfLength:(NSUInteger)length;
- (NSString *)randomStringOfLength:(NSUInteger)length;
- (CID *)generateRandomCID;
- (NSString *)generateRandomHandle;

@end

#pragma mark - Mock Server

@interface MockHTTPServer : NSObject

@property (nonatomic, assign, readonly) UInt16 port;
@property (nonatomic, assign, readonly, getter=isRunning) BOOL running;

+ (nullable instancetype)serverWithPort:(UInt16)port error:(NSError **)error;

- (BOOL)startWithError:(NSError **)error;
- (void)stop;
- (void)addRouteForMethod:(NSString *)method
                     path:(NSString *)path
               handler:(void (^)(NSDictionary *request, void (^response)(NSInteger status, NSDictionary *headers, NSData *body)))handler;

@end

#pragma mark - Test Database

@interface TestDatabase : NSObject

@property (nonatomic, strong, readonly) NSURL *databaseURL;
@property (nonatomic, strong, readonly) class PDSDatabase;

+ (nullable instancetype)inMemoryDatabaseWithError:(NSError **)error;
+ (nullable instancetype)temporaryDatabaseWithError:(NSError **)error;

- (BOOL)resetWithError:(NSError **)error;
- (void)close;

@end

#pragma mark - Concurrency Helpers

@interface ConcurrencyTestHelper : NSObject

+ (dispatch_queue_t)createTestQueue;
+ (void)waitForQueue:(dispatch_queue_t)queue timeout:(NSTimeInterval)timeout;
+ (void)runSynchronousBlock:(void (^)(void))block timeout:(NSTimeInterval)timeout;

@end

NS_ASSUME_NONNULL_END
```

### 2.2 Test Utilities Implementation (`TestUtilities.m`)

```objc
#import "TestUtilities.h"
#import "PDSDatabase.h"

#pragma mark - TestFixture Implementation

@implementation TestFixture

+ (instancetype)sharedFixture {
    static TestFixture *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[TestFixture alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _testData = [@"Test data for unit tests" dataUsingEncoding:NSUTF8StringEncoding];
        _testDID = @"did:plc:test1234567890";
        _testHandle = @"test.example.com";
        _testCID = [self generateRandomCID];
        _testTID = [TID tid];
    }
    return self;
}

- (NSData *)randomDataOfLength:(NSUInteger)length {
    uint8_t *bytes = malloc(length);
    arc4random_buf(bytes, length);
    NSData *data = [NSData dataWithBytes:bytes length:length];
    free(bytes);
    return data;
}

- (NSString *)randomStringOfLength:(NSUInteger)length {
    NSString *alphabet = @"abcdefghijklmnopqrstuvwxyz234567";
    NSMutableString *result = [NSMutableString stringWithCapacity:length];
    for (NSUInteger i = 0; i < length; i++) {
        unichar c = [alphabet characterAtIndex:arc4random_uniform((uint32_t)alphabet.length)];
        [result appendFormat:@"%C", c];
    }
    return result;
}

- (CID *)generateRandomCID {
    uint8_t multihash[36] = {0x12, 0x20};  // sha2-256 prefix
    arc4random_buf(&multihash[2], 34);
    NSData *mh = [NSData dataWithBytes:multihash length:sizeof(multihash)];
    return [CID cidWithMultihash:mh codec:0x71];
}

- (NSString *)generateRandomHandle {
    NSString *randomPart = [self randomStringOfLength:8];
    return [NSString stringWithFormat:@"%@.test", randomPart];
}

@end

#pragma mark - MockHTTPServer Implementation

@interface MockHTTPServer ()
@property (nonatomic, strong) NSHTTPServer *httpServer;
@property (nonatomic, strong) NSMutableDictionary<NSString *, void (^)(NSDictionary *, void (^)(NSInteger, NSDictionary *, NSData *))> *routes;
@property (nonatomic, assign) UInt16 port;
@property (nonatomic, assign, readwrite, getter=isRunning) BOOL running;
@end

@implementation MockHTTPServer

+ (nullable instancetype)serverWithPort:(UInt16)port error:(NSError **)error {
    MockHTTPServer *server = [[MockHTTPServer alloc] init];
    server.port = port;
    server.routes = [NSMutableDictionary dictionary];
    server.httpServer = [[NSHTTPServer alloc] init];
    [server.httpServer setType:@"_http._tcp"];
    
    NSError *bindError = nil;
    [server.httpServer setPort:port];
    if (![server.httpServer startListening:&bindError]) {
        if (error) *error = bindError;
        return nil;
    }
    return server;
}

- (BOOL)startWithError:(NSError **)error {
    if (self.running) return YES;
    return [self.httpServer startListening:error];
}

- (void)stop {
    [self.httpServer stop];
    self.running = NO;
}

- (void)addRouteForMethod:(NSString *)method
                     path:(NSString *)path
               handler:(void (^)(NSDictionary *request, void (^response)(NSInteger status, NSDictionary *headers, NSData *body)))handler {
    NSString *key = [NSString stringWithFormat:@"%@ %@", method.uppercaseString, path];
    self.routes[key] = handler;
}

@end

#pragma mark - TestDatabase Implementation

@interface TestDatabase ()
@property (nonatomic, strong) PDSDatabase *database;
@end

@implementation TestDatabase

+ (nullable instancetype)inMemoryDatabaseWithError:(NSError **)error {
    TestDatabase *td = [[TestDatabase alloc] init];
    td.database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:@":memory:"]];
    if (![td.database openWithError:error]) {
        return nil;
    }
    return td;
}

+ (nullable instancetype)temporaryDatabaseWithError:(NSError **)error {
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"test_%@.db", [[NSUUID UUID] UUIDString]]];
    TestDatabase *td = [[TestDatabase alloc] init];
    td.database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:tempPath]];
    if (![td.database openWithError:error]) {
        return nil;
    }
    return td;
}

- (BOOL)resetWithError:(NSError **)error {
    [self.database close];
    return [self.database openWithError:error];
}

- (void)close {
    [self.database close];
}

- (class)PDSDatabase {
    return [PDSDatabase class];
}

@end

#pragma mark - ConcurrencyTestHelper Implementation

@implementation ConcurrencyTestHelper

+ (dispatch_queue_t)createTestQueue {
    return dispatch_queue_create("com.atproto.pds.test.concurrent",
                                  DISPATCH_QUEUE_CONCURRENT);
}

+ (void)waitForQueue:(dispatch_queue_t)queue timeout:(NSTimeInterval)timeout {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    dispatch_async(queue, ^{
        dispatch_semaphore_signal(semaphore);
    });
    dispatch_time_t timeoutTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC));
    dispatch_semaphore_wait(semaphore, timeoutTime);
}

+ (void)runSynchronousBlock:(void (^)(void))block timeout:(NSTimeInterval)timeout {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        block();
        dispatch_semaphore_signal(semaphore);
    });
    dispatch_time_t timeoutTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC));
    dispatch_semaphore_wait(semaphore, timeoutTime);
}

@end
```

---

## 3. Module-by-Module Test Design

### 3.1 MST Tests (`MSTTests.h/m`)

```objc
#import <XCTest/XCTest.h>
#import "Repository/MST.h"
#import "CID.h"

NS_ASSUME_NONNULL_BEGIN

@interface MSTTests : XCTestCase

@property (nonatomic, strong) MST *emptyMST;
@property (nonatomic, strong) NSMutableDictionary<NSString *, CID *> *testData;
@property (nonatomic, strong) NSMutableArray<NSString *> *testKeys;

@end

@implementation MSTTests

- (void)setUp {
    [super setUp];
    self.emptyMST = [[MST alloc] initWithRootCID:nil];
    self.testData = [NSMutableDictionary dictionary];
    self.testKeys = [NSMutableArray array];
    
    // Generate 100 test entries
    for (NSInteger i = 0; i < 100; i++) {
        NSString *key = [NSString stringWithFormat:@"app.bsky.actor.profile/%@",
                        [[NSUUID UUID] UUIDString]];
        CID *cid = [[TestFixture sharedFixture] generateRandomCID];
        self.testData[key] = cid;
        [self.testKeys addObject:key];
    }
}

#pragma mark - Basic Operations

- (void)testEmptyMSTHasNilRoot {
    XCTAssertNil(self.emptyMST.rootCID);
}

- (void)testEmptyMSTHasZeroEntries {
    XCTAssertEqual([self.emptyMST allEntries].count, 0);
}

- (void)testEmptyMSTHasCorrectEmptyTreeHash {
    NSData *expectedHash = [self.emptyMST emptyTreeHash];
    XCTAssertNotNil(expectedHash);
    XCTAssertEqual(expectedHash.length, 32);  // SHA-256
}

- (void)testAddIncreasesEntryCount {
    MST *mst = self.emptyMST;
    NSArray *keys = [self.testData allKeys];
    
    for (NSInteger i = 0; i < keys.count; i++) {
        NSString *key = keys[i];
        CID *cid = self.testData[key];
        mst = [mst put:key valueCID:cid];
    }
    
    XCTAssertEqual([mst allEntries].count, self.testData.count);
}

- (void)testGetReturnsCorrectCID {
    MST *mst = self.emptyMST;
    
    for (NSString *key in self.testData) {
        CID *expectedCID = self.testData[key];
        CID *retrievedCID = [mst get:key];
        XCTAssertNil(retrievedCID);
        
        mst = [mst put:key valueCID:expectedCID];
    }
    
    for (NSString *key in self.testData) {
        CID *expectedCID = self.testData[key];
        CID *retrievedCID = [mst get:key];
        XCTAssertNotNil(retrievedCID);
        XCTAssertTrue([expectedCID isEqualToCID:retrievedCID]);
    }
}

- (void)testDeleteRemovesEntry {
    NSArray *keys = [self.testData allKeys];
    MST *mst = self.emptyMST;
    
    // Add all entries
    for (NSString *key in keys) {
        mst = [mst put:key valueCID:self.testData[key]];
    }
    
    // Delete first half
    for (NSInteger i = 0; i < keys.count / 2; i++) {
        NSString *keyToDelete = keys[i];
        mst = [mst delete:keyToDelete];
    }
    
    // Verify deleted entries are gone
    for (NSInteger i = 0; i < keys.count / 2; i++) {
        XCTAssertNil([mst get:keys[i]]);
    }
    
    // Verify remaining entries still exist
    for (NSInteger i = keys.count / 2; i < keys.count; i++) {
        CID *expectedCID = self.testData[keys[i]];
        CID *retrievedCID = [mst get:keys[i]];
        XCTAssertNotNil(retrievedCID);
        XCTAssertTrue([expectedCID isEqualToCID:retrievedCID]);
    }
}

#pragma mark - Update Operations

- (void)testUpdateReplacesExistingValue {
    NSString *key = @"app.bsky.actor.profile/self";
    CID *originalCID = [[TestFixture sharedFixture] generateRandomCID];
    CID *updatedCID = [[TestFixture sharedFixture] generateRandomCID];
    
    MST *mst = [self.emptyMST put:key valueCID:originalCID];
    XCTAssertTrue([[mst get:key] isEqualToCID:originalCID]);
    
    mst = [mst put:key valueCID:updatedCID];
    XCTAssertTrue([[mst get:key] isEqualToCID:updatedCID]);
    XCTAssertFalse([[mst get:key] isEqualToCID:originalCID]);
}

#pragma mark - Order Independence

- (void)testOrderIndependentAdd {
    NSArray *keys = [self.testData allKeys];
    NSMutableArray *shuffled = [keys mutableCopy];
    
    // Fisher-Yates shuffle
    for (NSInteger i = shuffled.count - 1; i > 0; i--) {
        NSInteger j = arc4random_uniform((uint32_t)(i + 1));
        [shuffled exchangeObjectAtIndex:i withObjectAtIndex:j];
    }
    
    // Add in shuffled order
    MST *mst1 = self.emptyMST;
    for (NSString *key in shuffled) {
        mst1 = [mst1 put:key valueCID:self.testData[key]];
    }
    
    // Add in reverse order
    NSArray *reverse = [[keys reverseObjectEnumerator] allObjects];
    MST *mst2 = self.emptyMST;
    for (NSString *key in reverse) {
        mst2 = [mst2 put:key valueCID:self.testData[key]];
    }
    
    // Both should have same root CID
    XCTAssertEqualObjects(mst1.rootCID, mst2.rootCID);
    
    // Both should return same entries
    NSArray *entries1 = [mst1 allEntries];
    NSArray *entries2 = [mst2 allEntries];
    XCTAssertEqual(entries1.count, entries2.count);
}

#pragma mark - Serialization

- (void)testCARExportImport {
    MST *original = self.emptyMST;
    for (NSString *key in self.testData) {
        original = [original put:key valueCID:self.testData[key]];
    }
    
    NSData *carData = [original exportCAR];
    XCTAssertNotNil(carData);
    XCTAssertGreaterThan(carData.length, 0);
    
    // Reconstruct from CAR
    MST *recovered = [MST deserializeFromCBOR:carData];
    XCTAssertNotNil(recovered);
    
    // Verify all entries
    for (NSString *key in self.testData) {
        CID *originalCID = [original get:key];
        CID *recoveredCID = [recovered get:key];
        XCTAssertTrue([originalCID isEqualToCID:recoveredCID]);
    }
}

#pragma mark - Prefix Queries

- (void)testEntriesWithPrefix {
    NSString *prefix = @"app.bsky.feed.";
    NSMutableDictionary *feedEntries = [NSMutableDictionary dictionary];
    
    // Add mixed entries
    for (NSString *key in self.testData) {
        MST *mst = [self.emptyMST put:key valueCID:self.testData[key]];
        if ([key hasPrefix:prefix]) {
            feedEntries[key] = self.testData[key];
        }
    }
    
    NSArray *prefixEntries = [self.emptyMST entriesWithPrefix:prefix];
    
    // Verify only prefix-matching entries are returned
    for (MSTEntry *entry in prefixEntries) {
        XCTAssertTrue([entry.key hasPrefix:prefix]);
    }
    XCTAssertEqual(prefixEntries.count, feedEntries.count);
}

#pragma mark - Performance Tests

- (void)testBulkOperationsPerformance {
    NSUInteger count = 1000;
    NSMutableArray *keys = [NSMutableArray arrayWithCapacity:count];
    NSMutableArray *cids = [NSMutableArray arrayWithCapacity:count];
    
    for (NSUInteger i = 0; i < count; i++) {
        NSString *key = [NSString stringWithFormat:@"app.bsky.actor.profile/%08lu", (unsigned long)i];
        CID *cid = [[TestFixture sharedFixture] generateRandomCID];
        [keys addObject:key];
        [cids addObject:cid];
    }
    
    [self measureBlock:^{
        MST *mst = self.emptyMST;
        for (NSUInteger i = 0; i < count; i++) {
            mst = [mst put:keys[i] valueCID:cids[i]];
        }
        
        // Verify all
        for (NSUInteger i = 0; i < count; i++) {
            XCTAssertNotNil([mst get:keys[i]]);
        }
    }];
}

@end

NS_ASSUME_NONNULL_END
```

### 3.2 CAR Tests (`CARTests.h/m`)

```objc
#import <XCTest/XCTest.h>
#import "Repository/CAR.h"
#import "CID.h"

NS_ASSUME_NONNULL_BEGIN

@interface CARTests : XCTestCase

@property (nonatomic, strong) NSMutableArray<CARBlock *> *testBlocks;
@property (nonatomic, strong) CID *rootCID;

@end

@implementation CARTests

- (void)setUp {
    [super setUp];
    self.testBlocks = [NSMutableArray array];
    
    // Create 10 test blocks
    for (NSInteger i = 0; i < 10; i++) {
        NSData *data = [[TestFixture sharedFixture] randomDataOfLength:64];
        CID *cid = [[TestFixture sharedFixture] generateRandomCID];
        CARBlock *block = [CARBlock blockWithCID:cid data:data];
        [self.testBlocks addObject:block];
    }
    
    // Last block is root
    self.rootCID = self.testBlocks.lastObject.cid;
}

#pragma mark - Block Tests

- (void)testBlockCreation {
    NSData *data = [@"test data" dataUsingEncoding:NSUTF8StringEncoding];
    CID *cid = [[TestFixture sharedFixture] generateRandomCID];
    
    CARBlock *block = [CARBlock blockWithCID:cid data:data];
    
    XCTAssertNotNil(block);
    XCTAssertTrue([cid isEqualToCID:block.cid]);
    XCTAssertEqualObjects(block.data, data);
}

#pragma mark - Writer Tests

- (void)testCARWriterCreation {
    CARWriter *writer = [CARWriter writerWithRootCID:self.rootCID];
    
    XCTAssertNotNil(writer);
    XCTAssertTrue([self.rootCID isEqualToCID:writer.rootCID]);
    XCTAssertEqual(writer.blocks.count, 0);
}

- (void)testCARWriterAddBlocks {
    CARWriter *writer = [CARWriter writerWithRootCID:self.rootCID];
    
    for (CARBlock *block in self.testBlocks) {
        [writer addBlock:block];
    }
    
    XCTAssertEqual(writer.blocks.count, self.testBlocks.count);
}

- (void)testCARWriterSerialization {
    CARWriter *writer = [CARWriter writerWithRootCID:self.rootCID];
    for (CARBlock *block in self.testBlocks) {
        [writer addBlock:block];
    }
    
    NSData *carData = [writer serialize];
    XCTAssertNotNil(carData);
    XCTAssertGreaterThan(carData.length, 0);
}

#pragma mark - Reader Tests

- (void)testCARReaderFromData {
    CARWriter *writer = [CARWriter writerWithRootCID:self.rootCID];
    for (CARBlock *block in self.testBlocks) {
        [writer addBlock:block];
    }
    NSData *carData = [writer serialize];
    
    NSError *error = nil;
    CARReader *reader = [CARReader readFromData:carData error:&error];
    
    XCTAssertNotNil(reader);
    XCTAssertNil(error);
    XCTAssertTrue([self.rootCID isEqualToCID:reader.rootCID]);
    XCTAssertEqual(reader.blocks.count, self.testBlocks.count);
}

- (void)testCARReaderGetBlock {
    CARWriter *writer = [CARWriter writerWithRootCID:self.rootCID];
    for (CARBlock *block in self.testBlocks) {
        [writer addBlock:block];
    }
    NSData *carData = [writer serialize];
    
    NSError *error = nil;
    CARReader *reader = [CARReader readFromData:carData error:&error];
    
    // Test retrieving each block
    for (CARBlock *expectedBlock in self.testBlocks) {
        CARBlock *retrievedBlock = [reader blockWithCID:expectedBlock.cid];
        XCTAssertNotNil(retrievedBlock);
        XCTAssertTrue([expectedBlock.cid isEqualToCID:retrievedBlock.cid]);
        XCTAssertEqualObjects(expectedBlock.data, retrievedBlock.data);
    }
}

- (void)testCARReaderMissingBlock {
    CARWriter *writer = [CARWriter writerWithRootCID:self.rootCID];
    for (CARBlock *block in self.testBlocks) {
        [writer addBlock:block];
    }
    NSData *carData = [writer serialize];
    
    NSError *error = nil;
    CARReader *reader = [CARReader readFromData:carData error:&error];
    
    // Try to get a block that doesn't exist
    CID *nonExistentCID = [[TestFixture sharedFixture] generateRandomCID];
    CARBlock *missingBlock = [reader blockWithCID:nonExistentCID];
    XCTAssertNil(missingBlock);
}

#pragma mark - Round-trip Tests

- (void)testRoundTripAllData {
    CARWriter *writer = [CARWriter writerWithRootCID:self.rootCID];
    NSMutableDictionary *originalData = [NSMutableDictionary dictionary];
    
    for (CARBlock *block in self.testBlocks) {
        [writer addBlock:block];
        originalData[block.cid] = block.data;
    }
    
    NSData *carData = [writer serialize];
    
    NSError *error = nil;
    CARReader *reader = [CARReader readFromData:carData error:&error];
    
    // Verify all data matches
    for (CID *cid in originalData) {
        NSData *original = originalData[cid];
        CARBlock *retrieved = [reader blockWithCID:cid];
        XCTAssertNotNil(retrieved);
        XCTAssertEqualObjects(original, retrieved.data);
    }
}

@end

NS_ASSUME_NONNULL_END
```

### 3.3 Session/OAuth Tests (`SessionTests.h/m`)

```objc
#import <XCTest/XCTest.h>
#import "Auth/Session.h"
#import "Auth/OAuth2.h"
#import "Auth/JWT.h"

NS_ASSUME_NONNULL_BEGIN

@interface SessionTests : XCTestCase

@property (nonatomic, copy) NSString *testDID;
@property (nonatomic, copy) NSString *testHandle;
@property (nonatomic, copy) NSString *testScope;

@end

@implementation SessionTests

- (void)setUp {
    [super setUp];
    self.testDID = @"did:plc:test1234567890";
    self.testHandle = @"test.example.com";
    self.testScope = @"atproto";
}

#pragma mark - SessionToken Tests

- (void)testSessionTokenCreation {
    NSString *tokenValue = @"test-token-value";
    NSTimeInterval expiresIn = 3600;
    
    SessionToken *token = [SessionToken tokenWithValue:tokenValue
                                              expiresIn:expiresIn
                                                  scope:self.testScope
                                          isRefreshToken:NO];
    
    XCTAssertNotNil(token);
    XCTAssertEqualObjects(token.value, tokenValue);
    XCTAssertEqualObjects(token.scope, self.testScope);
    XCTAssertFalse(token.isRefreshToken);
    XCTAssertNotNil(token.issuedAt);
    XCTAssertNotNil(token.expiresAt);
}

- (void)testSessionTokenIsExpired {
    // Create a token that expired 1 hour ago
    NSString *tokenValue = @"expired-token";
    SessionToken *token = [[SessionToken alloc] init];
    token.value = tokenValue;
    token.issuedAt = [NSDate dateWithTimeIntervalSinceNow:-7200];  // 2 hours ago
    token.expiresAt = [NSDate dateWithTimeIntervalSinceNow:-3600];  // 1 hour ago
    token.isRefreshToken = NO;
    
    XCTAssertTrue([token isExpired]);
    
    // Create a token that expires in 1 hour
    SessionToken *validToken = [SessionToken tokenWithValue:@"valid-token"
                                                   expiresIn:3600
                                                       scope:nil
                                               isRefreshToken:NO];
    XCTAssertFalse([validToken isExpired]);
}

- (void)testSessionTokenIsValid {
    // Valid token
    SessionToken *validToken = [SessionToken tokenWithValue:@"valid-token"
                                                   expiresIn:3600
                                                       scope:nil
                                               isRefreshToken:NO];
    XCTAssertTrue([validToken isValid]);
    
    // Expired token
    SessionToken *expiredToken = [[SessionToken alloc] init];
    expiredToken.value = @"expired";
    expiredToken.issuedAt = [NSDate dateWithTimeIntervalSinceNow:-7200];
    expiredToken.expiresAt = [NSDate dateWithTimeIntervalSinceNow:-3600];
    XCTAssertFalse([expiredToken isValid]);
}

#pragma mark - Session Tests

- (void)testSessionCreation {
    Session *session = [Session sessionWithDID:self.testDID
                                        handle:self.testHandle
                                         scope:self.testScope];
    
    XCTAssertNotNil(session);
    XCTAssertNotNil(session.sessionID);
    XCTAssertEqualObjects(session.did, self.testDID);
    XCTAssertEqualObjects(session.handle, self.testHandle);
    XCTAssertEqualObjects(session.scope, self.testScope);
    XCTAssertNotNil(session.accessToken);
    XCTAssertNotNil(session.refreshToken);
    XCTAssertEqualObjects(session.tokenType, @"DPoP");
}

- (void)testSessionTokenResponse {
    Session *session = [Session sessionWithDID:self.testDID
                                        handle:self.testHandle
                                         scope:self.testScope];
    
    NSDictionary *response = [session toTokenResponse];
    
    XCTAssertNotNil(response[@"access_token"]);
    XCTAssertNotNil(response[@"refresh_token"]);
    XCTAssertEqualObjects(response[@"token_type"], @"DPoP");
    XCTAssertNotNil(response[@"expires_in"]);
    XCTAssertEqualObjects(response[@"scope"], self.testScope);
}

#pragma mark - SessionStore Tests

- (void)testSessionStoreCreateSession {
    SessionStore *store = [SessionStore sharedStore];
    
    NSDictionary *dpopJWK = @{@"kty": @"RSA", @"n": @"test", @"e": @"AQAB"};
    
    NSError *error = nil;
    Session *session = [store createSessionForDID:self.testDID
                                           handle:self.testHandle
                                            scope:self.testScope
                                          dpopJWK:dpopJWK
                                            error:&error];
    
    XCTAssertNotNil(session);
    XCTAssertNil(error);
    XCTAssertEqualObjects(session.did, self.testDID);
    XCTAssertEqualObjects(session.handle, self.testHandle);
}

- (void)testSessionStoreRetrieveByAccessToken {
    SessionStore *store = [SessionStore sharedStore];
    
    NSError *error = nil;
    Session *original = [store createSessionForDID:self.testDID
                                            handle:self.testHandle
                                             scope:self.testScope
                                           dpopJWK:nil
                                             error:&error];
    
    Session *retrieved = [store getSessionByAccessToken:original.accessToken error:&error];
    
    XCTAssertNotNil(retrieved);
    XCTAssertNil(error);
    XCTAssertEqualObjects(retrieved.sessionID, original.sessionID);
}

- (void)testSessionStoreRetrieveByRefreshToken {
    SessionStore *store = [SessionStore sharedStore];
    
    NSError *error = nil;
    Session *original = [store createSessionForDID:self.testDID
                                            handle:self.testHandle
                                             scope:self.testScope
                                           dpopJWK:nil
                                             error:&error];
    
    Session *retrieved = [store getSessionByRefreshToken:original.refreshToken error:&error];
    
    XCTAssertNotNil(retrieved);
    XCTAssertEqualObjects(retrieved.sessionID, original.sessionID);
}

- (void)testSessionStoreRevokeSession {
    SessionStore *store = [SessionStore sharedStore];
    
    NSError *error = nil;
    Session *session = [store createSessionForDID:self.testDID
                                           handle:self.testHandle
                                            scope:self.testScope
                                          dpopJWK:nil
                                            error:&error];
    
    BOOL revoked = [store revokeSession:session.sessionID error:&error];
    XCTAssertTrue(revoked);
    
    // Verify session is gone
    Session *retrieved = [store getSessionByAccessToken:session.accessToken error:&error];
    XCTAssertNil(retrieved);
}

- (void)testSessionStoreRefreshSession {
    SessionStore *store = [SessionStore sharedStore];
    
    NSError *error = nil;
    Session *original = [store createSessionForDID:self.testDID
                                            handle:self.testHandle
                                             scope:self.testScope
                                           dpopJWK:nil
                                             error:&error];
    
    Session *newSession = nil;
    BOOL refreshed = [store refreshSession:original.sessionID
                                     scope:nil
                                   dpopJWK:nil
                               newSession:&newSession
                                     error:&error];
    
    XCTAssertTrue(refreshed);
    XCTAssertNotNil(newSession);
    XCTAssertNotEqualObjects(newSession.accessToken, original.accessToken);
    XCTAssertNotEqualObjects(newSession.refreshToken, original.refreshToken);
}

@end

NS_ASSUME_NONNULL_END
```

### 3.4 Database Tests (`DatabaseTests.h/m`)

```objc
#import <XCTest/XCTest.h>
#import "Database/PDSDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@interface DatabaseTests : XCTestCase

@property (nonatomic, strong) TestDatabase *database;

@end

@implementation DatabaseTests

- (void)setUp {
    [super setUp];
    NSError *error = nil;
    self.database = [TestDatabase inMemoryDatabaseWithError:&error];
    XCTAssertNotNil(self.database);
}

- (void)tearDown {
    [self.database close];
    [super tearDown];
}

#pragma mark - Basic Operations

- (void)testDatabaseOpen {
    XCTAssertTrue(self.database.database.isOpen);
}

- (void)testDatabaseExecuteRawSQL {
    NSError *error = nil;
    BOOL success = [self.database.database executeRawSQL:@"SELECT 1" error:&error];
    XCTAssertTrue(success);
    XCTAssertNil(error);
}

- (void)testDatabaseExecuteQuery {
    NSError *error = nil;
    NSArray *results = [self.database.database executeQuery:@"SELECT 1 as value" error:&error];
    XCTAssertNotNil(results);
    XCTAssertEqual(results.count, 1);
    XCTAssertEqualObjects(results[0][@"value"], @1);
}

#pragma mark - Account Operations

- (void)testCreateAccount {
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = @"did:plc:test1234567890";
    account.handle = @"test.example.com";
    account.email = @"test@example.com";
    account.createdAt = [NSDate date];
    account.updatedAt = [NSDate date];
    
    NSError *error = nil;
    BOOL created = [self.database.database createAccount:account error:&error];
    
    XCTAssertTrue(created);
    XCTAssertNil(error);
}

- (void)testGetAccountByDID {
    // Create account first
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = @"did:plc:test1234567890";
    account.handle = @"test.example.com";
    [self.database.database createAccount:account error:nil];
    
    // Retrieve account
    NSError *error = nil;
    PDSDatabaseAccount *retrieved = [self.database.database getAccountByDID:account.did error:&error];
    
    XCTAssertNotNil(retrieved);
    XCTAssertEqualObjects(retrieved.did, account.did);
    XCTAssertEqualObjects(retrieved.handle, account.handle);
}

- (void)testGetAccountByHandle {
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = @"did:plc:handle1234567890";
    account.handle = @"handle.example.com";
    [self.database.database createAccount:account error:nil];
    
    NSError *error = nil;
    PDSDatabaseAccount *retrieved = [self.database.database getAccountByHandle:account.handle error:&error];
    
    XCTAssertNotNil(retrieved);
    XCTAssertEqualObjects(retrieved.handle, account.handle);
}

- (void)testGetAllAccounts {
    for (NSInteger i = 0; i < 5; i++) {
        PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
        account.did = [NSString stringWithFormat:@"did:plc:alltest%ld", (long)i];
        account.handle = [NSString stringWithFormat:@"alltest%ld.example.com", (long)i];
        [self.database.database createAccount:account error:nil];
    }
    
    NSError *error = nil;
    NSArray *allAccounts = [self.database.database getAllAccountsWithError:&error];
    
    XCTAssertEqual(allAccounts.count, 5);
}

- (void)testUpdateAccount {
    // Create account
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = @"did:plc:updatetest123456";
    account.handle = @"updatetest.example.com";
    [self.database.database createAccount:account error:nil];
    
    // Update account
    account.email = @"updated@example.com";
    BOOL updated = [self.database.database updateAccount:account error:nil];
    XCTAssertTrue(updated);
    
    // Verify update
    PDSDatabaseAccount *retrieved = [self.database.database getAccountByDID:account.did error:nil];
    XCTAssertEqualObjects(retrieved.email, @"updated@example.com");
}

- (void)testDeleteAccount {
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = @"did:plc:deletetest123456";
    account.handle = @"deletetest.example.com";
    [self.database.database createAccount:account error:nil];
    
    BOOL deleted = [self.database.database deleteAccount:account.did error:nil];
    XCTAssertTrue(deleted);
    
    // Verify deletion
    PDSDatabaseAccount *retrieved = [self.database.database getAccountByDID:account.did error:nil];
    XCTAssertNil(retrieved);
}

#pragma mark - Repository Operations

- (void)testCreateRepo {
    PDSDatabaseRepo *repo = [[PDSDatabaseRepo alloc] init];
    repo.ownerDid = @"did:plc:repotest123456";
    repo.rootCid = [@"test-root-cid" dataUsingEncoding:NSUTF8StringEncoding];
    
    NSError *error = nil;
    BOOL created = [self.database.database createRepo:repo error:&error];
    
    XCTAssertTrue(created);
    XCTAssertNil(error);
}

- (void)testGetRepoForDID {
    PDSDatabaseRepo *repo = [[PDSDatabaseRepo alloc] init];
    repo.ownerDid = @"did:plc:getrepo123456";
    repo.rootCid = [@"test-root" dataUsingEncoding:NSUTF8StringEncoding];
    [self.database.database createRepo:repo error:nil];
    
    NSError *error = nil;
    PDSDatabaseRepo *retrieved = [self.database.database getRepoForDID:repo.ownerDid error:&error];
    
    XCTAssertNotNil(retrieved);
    XCTAssertEqualObjects(retrieved.ownerDid, repo.ownerDid);
}

#pragma mark - Transaction Tests

- (void)testBeginCommitTransaction {
    NSError *error = nil;
    
    BOOL began = [self.database.database beginTransactionWithError:&error];
    XCTAssertTrue(began);
    
    // Perform operations
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = @"did:plc:txntest123456";
    account.handle = @"txntest.example.com";
    [self.database.database createAccount:account error:nil];
    
    BOOL committed = [self.database.database commitTransactionWithError:&error];
    XCTAssertTrue(committed);
    
    // Verify
    PDSDatabaseAccount *retrieved = [self.database.database getAccountByDID:account.did error:nil];
    XCTAssertNotNil(retrieved);
}

- (void)testRollbackTransaction {
    NSError *error = nil;
    
    [self.database.database beginTransactionWithError:&error];
    
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = @"did:plc:rallback123456";
    account.handle = @"rollback.example.com";
    [self.database.database createAccount:account error:nil];
    
    [self.database.database rollbackTransactionWithError:&error];
    
    // Should not exist
    PDSDatabaseAccount *retrieved = [self.database.database getAccountByDID:account.did error:nil];
    XCTAssertNil(retrieved);
}

@end

NS_ASSUME_NONNULL_END
```

---

## 4. Implementation Phases

### Phase 1: Foundation (Week 1)
1. Create `TestUtilities.h/m` - Shared test infrastructure
2. Create `XCTestCase` base class for common setup/teardown
3. Verify build integration with existing test runner

### Phase 2: Core Data Types (Week 2)
1. `CIDTests` - CID creation, encoding, comparison
2. `TIDTests` - TID generation, parsing, ordering
3. `DIDTests` - DID validation, parsing

### Phase 3: Repository Layer (Week 3)
1. `MSTTests` - Core MST operations
2. `CARTests` - CAR serialization/deserialization
3. `RepositoryCRUDTests` - Record operations

### Phase 4: Authentication (Week 4)
1. `SessionTests` - Session creation, retrieval, refresh
2. `OAuth2Tests` - OAuth flow tests
3. `JWTTests` - JWT creation, verification

### Phase 5: Database (Week 5)
1. `DatabaseTests` - CRUD operations
2. `TransactionTests` - Transaction handling
3. `SchemaTests` - Schema validation

### Phase 6: Network (Week 6)
1. `HttpServerTests` - HTTP request/response
2. `XrpcTests` - XRPC dispatch
3. `RateLimiterTests` - Rate limiting logic

---

## 5. Build Configuration

### Update `Makefile` to include tests:

```makefile
# Test targets
TEST_BUNDLE = ATProtoPDSTests.xctest
TEST_SOURCES = $(wildcard ATProtoPDS/ATProtoPDSTests/*.m)
TEST_OBJECTS = $(patsubst %.m,%.o,$(TEST_SOURCES))

$(TEST_BUNDLE): $(TEST_OBJECTS) $(HEADERS)
	xcodebuild -project ATProtoPDS.xcodeproj \
		-target ATProtoPDSTests \
		-configuration Debug \
		build

test: $(TEST_BUNDLE)
	xcodebuild test -project ATProtoPDS.xcodeproj \
		-target ATProtoPDSTests \
		-configuration Debug \
		-scheme ATProtoPDSTests

test-coverage:
	xcodebuild test -project ATProtoPDS.xcodeproj \
		-target ATProtoPDSTests \
		-configuration Debug \
		-scheme ATProtoPDSTests \
		-enableCodeCoverage YES
```

---

## 6. Running Tests

```bash
# Run all tests
make test

# Run specific test class
make test TEST_CLASS=MSTTests

# Run with coverage
make test-coverage

# Run from Xcode
xcodebuild test -scheme ATProtoPDSTests
```

---

## 7. Success Criteria

| Metric | Target |
|--------|--------|
| Test Files | 15+ |
| Test Cases | 200+ |
| Core Type Coverage | 100% |
| Repository Layer Coverage | 90% |
| Auth Layer Coverage | 80% |
| Database Layer Coverage | 80% |
| Network Layer Coverage | 70% |
| Build Success | 100% |
| CI Pass Rate | 100% |

---

## 8. Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Test complexity | High | Start with simple tests, incrementally add complexity |
| Build integration | Medium | Verify build after each phase |
| Test flakiness | Medium | Use explicit waits, avoid timing assumptions |
| Coverage gaps | Low | Regular coverage analysis, add missing tests |

---

## 9. Dependencies Summary

| Component | Dependencies Used | Justification |
|-----------|------------------|---------------|
| XCTest | Apple-provided | Native testing framework |
| Foundation | Apple-provided | Data types, I/O, networking |
| Security | Apple-provided | Cryptographic operations |
| Dispatch | Apple-provided | Concurrency |
| Test Fixtures | Custom (no deps) | Self-contained utilities |

**Total external dependencies: 0**

---

## 10. Next Steps

1. Create `TestUtilities.h/m` with shared infrastructure
2. Implement `MSTTests` as the highest priority gap
3. Add tests to `Makefile` build targets
4. Verify all tests pass in CI
5. Iterate based on coverage reports
