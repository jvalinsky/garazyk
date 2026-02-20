#import <XCTest/XCTest.h>
#import "Network/XrpcMethodRegistry.h"
#import "App/PDSController.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/CID.h"
// #import "Database/PDSDatabaseBlock.h" // Removed: defined in PDSDatabase.h
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"

@interface CoverageGapTests : XCTestCase
@property (nonatomic, strong) PDSController *controller;
@property (nonatomic, strong) NSString *tempDir;
@end

@implementation CoverageGapTests

- (void)setUp {
    [super setUp];
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    self.controller = [[PDSController alloc] initWithDirectory:self.tempDir serviceMaxSize:5 userDatabaseSize:5];
    NSError *error = nil;
    if (![self.controller startServerWithError:&error]) {
        XCTFail(@"Failed to start server: %@", error);
    }
}

- (void)tearDown {
    [self.controller stopServer];
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    [super tearDown];
}

- (void)testResolveDid {
    // 1. Create a local account using the controller method
    NSError *createError = nil;
    NSDictionary *accountInfo = [self.controller createAccountForEmail:@"test@example.com"
                                                              password:@"password"
                                                                handle:@"testuser.test"
                                                                   did:nil
                                                                 error:&createError];
    XCTAssertNotNil(accountInfo, @"Failed to create account: %@", createError);
    NSString *did = accountInfo[@"did"];
    XCTAssertNotNil(did);
    
    // 2. Resolve DID via HTTP request to the running server
    // Since PDSController starts the server on a random port (or we can configure it), we need the port.
    // PDSController has a `server` property which has `port`.
    // Let's assume we can access it. PDSController.h:
    // @property (nonatomic, strong, readonly) PDSHttpServer *server;
    
    // We need to import PDSHttpServer.h to access port
    // But PDSController hides it.
    // However, PDSConfiguration has serverPort.
    // PDSController init uses standard port if not specified? 
    // `initWithDirectory:...` doesn't take port.
    // It likely uses 2583 or random?
    // Let's check `PDSController.m`.
    
    // Actually, for unit testing, if we can't easily hit the HTTP endpoint, we can test the registry logic directly if we extract it.
    // But `resolveDid` is a static function inside XrpcMethodRegistry.m.
    
    // Alternative: Use `[self.controller.serverDispatch dispatchRequest:...]` if exposed.
    // `PDSController` has `dispatcher`?
    
    // Let's use `NSURLSession` to hit localhost:%lu (default) if we key off that?
    // Or just try to read the port from logs?
    
    // Better: `PDSController` should expose the port it bound to.
    // If not, we can rely on integration test standard (2583).
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%lu/xrpc/com.atproto.identity.resolveDid?did=%@", (unsigned long)self.controller.httpPort, did]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Resolve DID"];
    
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        XCTAssertNil(error);
        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResp.statusCode, 200, @"Should return 200 OK");
        
        if (data) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            XCTAssertEqualObjects(json[@"id"], did);
            NSArray *aka = json[@"alsoKnownAs"];
            XCTAssertTrue([aka containsObject:@"at://testuser.test"], @"alsoKnownAs should contain the handle");
        }
        
        [expectation fulfill];
    }] resume];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testGetBlocks {
    // 1. Create account using the controller method
    NSError *createError = nil;
    NSDictionary *accountInfo = [self.controller createAccountForEmail:@"blocks@test.com"
                                                              password:@"password"
                                                                handle:@"blocks.test"
                                                                   did:nil
                                                                 error:&createError];
    XCTAssertNotNil(accountInfo, @"Failed to create account: %@", createError);
    NSString *did = accountInfo[@"did"];
    XCTAssertNotNil(did);
    
    // 2. Inject blocks into ActorStore
    PDSActorStore *store = [self.controller.userDatabasePool storeForDid:did error:nil];
    XCTAssertNotNil(store);
    
    NSString *cid1Str = @"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu";
    NSString *cid2Str = @"bafyreie5cvv4h45feadgeuwhbcutmh6t2ceseocckahdoe6uat64zmz454"; // Real-ish CIDs
    NSData *data1 = [@"block1" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *data2 = [@"block2" dataUsingEncoding:NSUTF8StringEncoding];
    
    [store transactWithBlock:^(id<PDSActorStoreTransactor> transactor, NSError **err) {
        PDSDatabaseBlock *b1 = [[PDSDatabaseBlock alloc] init];
        b1.cid = [CID cidFromString:cid1Str].bytes;
        b1.blockData = data1;
        [transactor putBlock:b1 forDid:did error:nil];
        
        PDSDatabaseBlock *b2 = [[PDSDatabaseBlock alloc] init];
        b2.cid = [CID cidFromString:cid2Str].bytes;
        b2.blockData = data2;
        [transactor putBlock:b2 forDid:did error:nil];
    } error:nil];
    
    // 3. Request getBlocks
    // URL: /xrpc/com.atproto.sync.getBlocks?did=...&cids=...&cids=...
    NSString *urlString = [NSString stringWithFormat:@"http://localhost:%lu/xrpc/com.atproto.sync.getBlocks?did=%@&cids=%@&cids=%@", (unsigned long)self.controller.httpPort, did, cid1Str, cid2Str];
    NSURL *url = [NSURL URLWithString:urlString];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    
    XCTestExpectation *exp = [self expectationWithDescription:@"Get Blocks"];
    
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResp.statusCode, 200, @"Should return 200 OK");
        XCTAssertEqualObjects(httpResp.allHeaderFields[@"Content-Type"], @"application/vnd.ipld.car");
        
        // Basic check: data should at least contain "block1" and "block2" string/bytes
        // Parsing CAR in test is complex without CARReader.
        // We just check size > 0 and success.
        XCTAssertGreaterThan(data.length, 0);
        
        [exp fulfill];
    }] resume];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testGetLatestCommit {
    // 1. Create account using the controller method
    NSError *createError = nil;
    NSDictionary *accountInfo = [self.controller createAccountForEmail:@"commit@test.com"
                                                              password:@"password"
                                                                handle:@"commit.test"
                                                                   did:nil
                                                                 error:&createError];
    XCTAssertNotNil(accountInfo, @"Failed to create account: %@", createError);
    NSString *did = accountInfo[@"did"];
    XCTAssertNotNil(did);
    
    // 2. Inject Repo Root
    NSError *storeError = nil;
    PDSActorStore *store = [self.controller.userDatabasePool storeForDid:did error:&storeError];
    XCTAssertNotNil(store, @"Failed to get actor store: %@", storeError);
    
    NSString *rootCidStr = @"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu";
    NSData *rootBytes = [CID cidFromString:rootCidStr].bytes;
    XCTAssertNotNil(rootBytes, @"Failed to create CID bytes");
    
    NSError *transactError = nil;
    [store transactWithBlock:^(id<PDSActorStoreTransactor> transactor, NSError **err) {
        BOOL result = [transactor updateRepoRoot:did rootCid:rootBytes rev:@"3k55555" error:err];
        XCTAssertTrue(result, @"Failed to update repo root");
    } error:&transactError];
    XCTAssertNil(transactError, @"Transaction error: %@", transactError);
    
    // 3. Verify we can read back the data
    __block NSString *verifyCid = nil;
    [store transactWithBlock:^(id<PDSActorStoreTransactor> transactor, NSError **err) {
        id<PDSActorStoreReader> reader = (id<PDSActorStoreReader>)transactor;
        NSData *rootCidBytes = [reader getRepoRootForDid:did error:err];
        if (rootCidBytes) {
            CID *cid = [CID cidFromBytes:rootCidBytes];
            verifyCid = cid.stringValue;
        }
    } error:&transactError];
    XCTAssertEqualObjects(verifyCid, rootCidStr, @"Root CID not stored correctly");
    
    // 4. Request getLatestCommit via HTTP
    NSString *urlString = [NSString stringWithFormat:@"http://localhost:%lu/xrpc/com.atproto.sync.getLatestCommit?did=%@", (unsigned long)self.controller.httpPort, did];
    NSURL *url = [NSURL URLWithString:urlString];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    
    XCTestExpectation *exp = [self expectationWithDescription:@"Get Latest Commit"];
    
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResp.statusCode, 200);
        
        if (httpResp.statusCode == 200 && data) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            XCTAssertEqualObjects(json[@"cid"], rootCidStr);
            XCTAssertEqualObjects(json[@"rev"], @"3k55555");
        }
        
        [exp fulfill];
    }] resume];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

@end
