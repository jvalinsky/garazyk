#import <XCTest/XCTest.h>
#import "PLC/PLCServer.h"
#import "PLC/PLCMockStore.h"
#import "PLC/PLCAuditor.h"
#import "PLC/PLCOperation.h"
#import "Auth/Secp256k1.h"
#import "Auth/CryptoUtils.h"

@interface PLCServerTests : XCTestCase
@property (nonatomic, strong) PLCMockStore *store;
@property (nonatomic, strong) PLCAuditor *auditor;
@property (nonatomic, strong) PLCServer *server;
@property (nonatomic, assign) NSUInteger port;
@end

@implementation PLCServerTests

- (void)setUp {
    [super setUp];
    self.store = [[PLCMockStore alloc] init];
    self.auditor = [[PLCAuditor alloc] initWithStore:self.store];
    self.port = 8888;
    self.server = [[PLCServer alloc] initWithStore:self.store auditor:self.auditor port:self.port];
    NSError *error = nil;
    BOOL success = [self.server startWithError:&error];
    XCTAssertTrue(success, @"Failed to start server: %@", error);
}

- (void)tearDown {
    [self.server stop];
    // Give the server a moment to release the port
    [NSThread sleepForTimeInterval:0.1];
    [super tearDown];
}

- (void)testGetDID {
    NSString *did = @"did:plc:test";
    Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:nil];
    NSDictionary *opData = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[[CryptoUtils hexStringFromData:keyPair.compressedPublicKey]],
        @"verificationMethods": @{@"atproto": [CryptoUtils hexStringFromData:keyPair.compressedPublicKey]},
        @"alsoKnownAs": @[@"at://test.com"],
        @"services": @{},
        @"prev": [NSNull null]
    };
    NSData *hash = [self.auditor hashForOperationData:opData];
    NSData *sig = [keyPair signHash:hash error:nil];
    
    PLCOperation *op = [[PLCOperation alloc] init];
    op.did = did;
    op.sig = [CryptoUtils hexStringFromData:sig];
    op.data = opData;
    op.prev = nil;
    [self.store appendOperation:op error:nil];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"GET /:did"];
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%lu/%@", (unsigned long)self.port, did]];
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);
        
        NSError *jsonError = nil;
        NSArray *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        XCTAssertNil(jsonError);
        XCTAssertNotNil(json);
        XCTAssertEqual(json.count, 1);
        XCTAssertEqualObjects(json[0][@"did"], did);
        
        [expectation fulfill];
    }] resume];
    
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testPostDID {
    NSString *did = @"did:plc:testpost";
    Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:nil];
    NSDictionary *opData = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[[CryptoUtils hexStringFromData:keyPair.compressedPublicKey]],
        @"verificationMethods": @{@"atproto": [CryptoUtils hexStringFromData:keyPair.compressedPublicKey]},
        @"alsoKnownAs": @[@"at://test.com"],
        @"services": @{},
        @"prev": [NSNull null]
    };
    NSData *hash = [self.auditor hashForOperationData:opData];
    NSData *sig = [keyPair signHash:hash error:nil];
    
    NSDictionary *payload = @{
        @"did": did,
        @"sig": [CryptoUtils hexStringFromData:sig],
        @"data": opData
    };
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"POST /:did"];
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%lu/%@", (unsigned long)self.port, did]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    [request addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);
        
        NSError *jsonError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        XCTAssertNil(jsonError);
        XCTAssertEqualObjects(json[@"status"], @"ok");
        
        // Verify it's in the store
        NSArray *history = [self.store getHistoryForDID:did error:nil];
        XCTAssertEqual(history.count, 1);
        
        [expectation fulfill];
    }] resume];
    
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testPostInvalidDID {
    NSString *did = @"did:plc:testpost";
    NSString *wrongDid = @"did:plc:wrong";
    Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:nil];
    NSDictionary *opData = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[[CryptoUtils hexStringFromData:keyPair.compressedPublicKey]],
        @"verificationMethods": @{@"atproto": [CryptoUtils hexStringFromData:keyPair.compressedPublicKey]},
        @"alsoKnownAs": @[@"at://test.com"],
        @"services": @{},
        @"prev": [NSNull null]
    };
    NSData *hash = [self.auditor hashForOperationData:opData];
    NSData *sig = [keyPair signHash:hash error:nil];
    
    NSDictionary *payload = @{
        @"did": did, // The DID in payload matches the path param we will send, but we'll see
        @"sig": [CryptoUtils hexStringFromData:sig],
        @"data": opData
    };
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"POST /:did (wrong DID)"];
    
    // We send to wrongDid path, but payload has did.
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%lu/%@", (unsigned long)self.port, wrongDid]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    [request addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 400); // Bad Request
        
        [expectation fulfill];
    }] resume];
    
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

@end
