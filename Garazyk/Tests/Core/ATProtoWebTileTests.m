// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Core/ATProtoWebTile.h"
#import "Core/ATProtoMASLDocument.h"
#import "Core/CID.h"
#import "Repository/ATProtoWebTile+CAR.h"
#import "Repository/CAR.h"

@interface ATProtoWebTileTests : XCTestCase
@end

@implementation ATProtoWebTileTests

- (ATProtoCID *)cidForData:(NSData *)data {
    return [ATProtoCID cidWithDigest:[ATProtoCID sha256Digest:data] codec:0x55];
}

- (void)testValidTileFromMASL {
    NSData *html = [@"<html></html>" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [self cidForData:html];
    NSDictionary *object = @{
        @"name": @"Demo Tile",
        @"version": @1,
        @"roots": @[cid],
        @"resources": @{
            @"/": @{@"src": cid, @"content-type": @"text/html"}
        }
    };
    NSError *error = nil;
    ATProtoMASLDocument *doc = [ATProtoMASLDocument documentWithObject:object error:&error];
    XCTAssertNotNil(doc);
    ATProtoWebTile *tile = [ATProtoWebTile tileWithMASLDocument:doc error:&error];
    XCTAssertNotNil(tile);
    XCTAssertEqualObjects(tile.name, @"Demo Tile");
    XCTAssertEqualObjects(tile.rootResourceCID, cid);
}

- (void)testRejectsMissingNameAndNonBundle {
    NSData *html = [@"x" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [self cidForData:html];
    NSError *error = nil;
    ATProtoMASLDocument *noName = [ATProtoMASLDocument documentWithObject:@{
        @"version": @1,
        @"roots": @[cid],
        @"resources": @{@"/": @{@"src": cid}}
    } error:&error];
    XCTAssertNil([ATProtoWebTile tileWithMASLDocument:noName error:&error]);
    XCTAssertEqual(error.code, ATProtoWebTileErrorMissingName);

    error = nil;
    ATProtoMASLDocument *nonBundle = [ATProtoMASLDocument documentWithObject:@{
        @"name": @"n",
        @"version": @1,
        @"roots": @[cid],
        @"src": cid
    } error:&error];
    XCTAssertNotNil(nonBundle);
    XCTAssertFalse(nonBundle.isBundle);
    XCTAssertNil([ATProtoWebTile tileWithMASLDocument:nonBundle error:&error]);
    XCTAssertEqual(error.code, ATProtoWebTileErrorInvalidDocument);
}

- (void)testTileFromCARIncludesRootBlock {
    NSData *html = [@"<html>hi</html>" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *cid = [self cidForData:html];
    NSDictionary *object = @{
        @"name": @"CAR Tile",
        @"version": @1,
        @"roots": @[cid],
        @"resources": @{
            @"/": @{@"src": cid, @"content-type": @"text/html"}
        }
    };
    NSError *error = nil;
    ATProtoMASLDocument *doc = [ATProtoMASLDocument documentWithObject:object error:&error];
    ATProtoCARWriter *writer = [ATProtoCARWriter writerWithMASLDocument:doc error:&error];
    [writer addBlock:[ATProtoCARBlock blockWithCID:cid data:html]];
    NSData *car = [writer serialize];
    ATProtoWebTile *tile = [ATProtoWebTile tileWithCARData:car strict:YES error:&error];
    XCTAssertNotNil(tile);
    XCTAssertEqualObjects(tile.name, @"CAR Tile");
}

- (void)testResponseForPathResolvesDeclaredResourcesAnd404s {
    NSData *html = [@"<html>root</html>" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *js = [@"console.log(1)" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *htmlCID = [self cidForData:html];
    ATProtoCID *jsCID = [self cidForData:js];
    NSDictionary *object = @{
        @"name": @"Multi",
        @"version": @1,
        @"roots": @[htmlCID],
        @"resources": @{
            @"/": @{@"src": htmlCID, @"content-type": @"text/html"},
            @"/app.js": @{@"src": jsCID, @"content-type": @"text/javascript"}
        }
    };
    NSError *error = nil;
    ATProtoMASLDocument *doc = [ATProtoMASLDocument documentWithObject:object error:&error];
    ATProtoCARWriter *writer = [ATProtoCARWriter writerWithMASLDocument:doc error:&error];
    [writer addBlock:[ATProtoCARBlock blockWithCID:htmlCID data:html]];
    [writer addBlock:[ATProtoCARBlock blockWithCID:jsCID data:js]];
    NSData *car = [writer serialize];
    ATProtoWebTile *tile = [ATProtoWebTile tileWithCARData:car strict:YES error:&error];
    XCTAssertNotNil(tile);

    NSDictionary *root = [tile responseForPath:@"/" error:&error];
    XCTAssertEqual([root[@"status"] integerValue], 200);
    XCTAssertEqualObjects(root[@"body"], html);
    XCTAssertEqualObjects(root[@"headers"][@"content-type"], @"text/html");

    NSDictionary *app = [tile responseForPath:@"/app.js?cache=1#x" error:&error];
    XCTAssertEqual([app[@"status"] integerValue], 200);
    XCTAssertEqualObjects(app[@"body"], js);

    NSDictionary *missing = [tile responseForPath:@"/nope.js" error:&error];
    XCTAssertEqual([missing[@"status"] integerValue], 404);
    XCTAssertEqual([(NSData *)missing[@"body"] length], (NSUInteger)0);
}

@end
