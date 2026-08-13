// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Repository/ATProtoWebTileMothership.h"
#import "Repository/ATProtoWebTile+CAR.h"
#import "Repository/CAR.h"
#import "Core/ATProtoMASLDocument.h"
#import "Core/CID.h"

@interface ATProtoWebTileMothershipHTTPStub : NSObject <ATProtoWebTileHTTPClient>
@property (nonatomic, copy, nullable) NSData *body;
@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, copy, nullable) NSURL *lastURL;
@end

@implementation ATProtoWebTileMothershipHTTPStub
- (instancetype)init {
    self = [super init];
    if (self) {
        _statusCode = 200;
    }
    return self;
}
- (NSData *)sendSynchronousRequest:(NSURLRequest *)request
                           options:(id)options
                          response:(NSHTTPURLResponse **)response
                             error:(NSError **)error {
    (void)options;
    self.lastURL = request.URL;
    if (response) {
        *response = [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                                statusCode:self.statusCode
                                               HTTPVersion:@"HTTP/1.1"
                                              headerFields:@{}];
    }
    if (self.statusCode != 200) {
        return nil;
    }
    return self.body;
}
@end

@interface ATProtoWebTileMothershipTests : XCTestCase
@end

@implementation ATProtoWebTileMothershipTests

- (ATProtoCID *)cidForData:(NSData *)data {
    return [ATProtoCID cidWithDigest:[ATProtoCID sha256Digest:data] codec:0x55];
}

- (NSData *)fixtureCARWithHTML:(NSData *)html js:(NSData *)js {
    ATProtoCID *htmlCID = [self cidForData:html];
    ATProtoCID *jsCID = [self cidForData:js];
    NSDictionary *object = @{
        @"name": @"Mothership Tile",
        @"version": @1,
        @"roots": @[htmlCID],
        @"resources": @{
            @"/": @{@"src": htmlCID, @"content-type": @"text/html"},
            @"/app.js": @{@"src": jsCID, @"content-type": @"application/javascript"},
        }
    };
    ATProtoMASLDocument *doc = [ATProtoMASLDocument documentWithObject:object error:nil];
    ATProtoCARWriter *writer = [ATProtoCARWriter writerWithMASLDocument:doc error:nil];
    [writer addBlock:[ATProtoCARBlock blockWithCID:htmlCID data:html]];
    [writer addBlock:[ATProtoCARBlock blockWithCID:jsCID data:js]];
    return [writer serialize];
}

- (void)testResolvePathMediation {
    NSData *html = [@"<html>hi</html>" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *js = [@"console.log(1)" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *car = [self fixtureCARWithHTML:html js:js];
    ATProtoWebTile *tile = [ATProtoWebTile tileWithCARData:car strict:YES error:nil];
    ATProtoWebTileMothership *ms = [[ATProtoWebTileMothership alloc] initWithTile:tile];

    NSDictionary *ok = [ms handleRequest:@{
        @"type": @"resolve-path",
        @"path": @"/app.js",
        @"requestId": @7,
    }];
    XCTAssertEqualObjects(ok[@"requestId"], @7);
    XCTAssertEqual([ok[@"response"][@"status"] integerValue], 200);
    XCTAssertEqualObjects(ok[@"response"][@"body"], js);

    NSDictionary *missing = [ms handleRequest:@{@"type": @"resolve-path", @"path": @"/nope"}];
    XCTAssertEqual([missing[@"response"][@"status"] integerValue], 404);

    NSDictionary *unknown = [ms handleRequest:@{@"type": @"ping", @"requestId": @1}];
    XCTAssertNotNil(unknown[@"error"]);
    XCTAssertEqualObjects(unknown[@"requestId"], @1);
}

- (void)testGetBlobLoadsTile {
    NSData *html = [@"<html/>" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *js = [@"x" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *car = [self fixtureCARWithHTML:html js:js];
    ATProtoWebTileMothershipHTTPStub *stub = [[ATProtoWebTileMothershipHTTPStub alloc] init];
    stub.body = car;
    NSError *error = nil;
    ATProtoWebTile *tile =
        [ATProtoWebTileMothership tileWithGetBlobFromPDSBaseURL:@"http://127.0.0.1:2583/"
                                                            did:@"did:plc:tester"
                                                            cid:@"bafyTileCid"
                                                     httpClient:stub
                                                          error:&error];
    XCTAssertNotNil(tile, @"%@", error);
    XCTAssertTrue([stub.lastURL.path containsString:@"com.atproto.sync.getBlob"]);
    XCTAssertTrue([stub.lastURL.query containsString:@"did=did"]);
    ATProtoWebTileMothership *ms = [[ATProtoWebTileMothership alloc] initWithTile:tile];
    NSDictionary *root = [ms resolvePath:@"/"];
    XCTAssertEqual([root[@"status"] integerValue], 200);
    XCTAssertEqualObjects(root[@"body"], html);
}

@end
