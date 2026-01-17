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

- (NSString *)base64URLEncode:(NSData *)data {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return base64;
}

- (void)tearDown {
    [self.server stop];
    // Give the server a moment to release the port
    [NSThread sleepForTimeInterval:0.1];
    [super tearDown];
}

- (void)testGetDID {
    Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:nil];
    NSDictionary *opData = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[[keyPair didKeyString]],
        @"verificationMethods": @{@"atproto": [keyPair didKeyString]},
        @"alsoKnownAs": @[@"at://test.com"],
        @"services": @{},
        @"prev": [NSNull null]
    };
    NSData *hash = [self.auditor hashForOperationData:opData];
    NSData *sig = [[Secp256k1 shared] signHash:hash withPrivateKey:keyPair.privateKey error:nil];
    
    NSMutableDictionary *payload = [opData mutableCopy];
    payload[@"sig"] = [self base64URLEncode:sig];
    NSString *did = [PLCOperation calculateDIDForData:opData];

    PLCOperation *op = [[PLCOperation alloc] init];
    op.did = did;
    op.sig = payload[@"sig"];
    op.data = opData;
    op.prev = nil;
    [self.store appendOperation:op nullifyCIDs:@[] error:nil];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"GET /:did"];
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%lu/%@", (unsigned long)self.port, did]];
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);
        
        NSError *jsonError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        XCTAssertNil(jsonError);
        XCTAssertNotNil(json);
        XCTAssertEqualObjects(json[@"id"], did);
        XCTAssertNotNil(json[@"verificationMethod"]);
        
        [expectation fulfill];
    }] resume];
    
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testPostDID {
    Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:nil];
    NSDictionary *opData = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[[keyPair didKeyString]],
        @"verificationMethods": @{@"atproto": [keyPair didKeyString]},
        @"alsoKnownAs": @[@"at://test.com"],
        @"services": @{},
        @"prev": [NSNull null]
    };
    NSData *hash = [self.auditor hashForOperationData:opData];
    NSData *sig = [[Secp256k1 shared] signHash:hash withPrivateKey:keyPair.privateKey error:nil];
    
    NSMutableDictionary *payload = [opData mutableCopy];
    payload[@"sig"] = [self base64URLEncode:sig];
    NSString *did = [PLCOperation calculateDIDForData:opData];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"POST /:did"];
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%lu/%@", (unsigned long)self.port, did]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    [request addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSLog(@"POST failed: %@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
        }
        XCTAssertEqual(httpResponse.statusCode, 200);
        
        NSError *jsonError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        XCTAssertNil(jsonError);
        XCTAssertEqualObjects(json[@"status"], @"ok");
        
        // Verify it's in the store
        NSArray *history = [self.store getHistoryForDID:did includeNullified:NO error:nil];
        XCTAssertEqual(history.count, 1);
        
        [expectation fulfill];
    }] resume];
    
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testPostInvalidDID {
    NSString *wrongDid = @"did:plc:wrong";
    Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:nil];
    NSDictionary *opData = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[[keyPair didKeyString]],
        @"verificationMethods": @{@"atproto": [keyPair didKeyString]},
        @"alsoKnownAs": @[@"at://test.com"],
        @"services": @{},
        @"prev": [NSNull null]
    };
    NSData *hash = [self.auditor hashForOperationData:opData];
    NSData *sig = [[Secp256k1 shared] signHash:hash withPrivateKey:keyPair.privateKey error:nil];
    
    NSMutableDictionary *payload = [opData mutableCopy];
    payload[@"sig"] = [self base64URLEncode:sig];
    NSString *did = [PLCOperation calculateDIDForData:opData];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"POST /:did (invalid sig)"];
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%lu/%@", (unsigned long)self.port, wrongDid]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    [request addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 400); // Bad Request (Audit failed)
        
        [expectation fulfill];
    }] resume];
    
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

@end
