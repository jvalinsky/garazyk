// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoMASLDocumentTests.m

 @abstract Tests the bounded MASL document model.
 */

#import <XCTest/XCTest.h>
#import "Core/ATProtoMASLDocument.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"

@interface ATProtoMASLDocumentTests : XCTestCase
@end

@implementation ATProtoMASLDocumentTests

- (CID *)sampleCID {
    NSData *bytes = [NSData dataWithBytes:(const uint8_t[]) {
        0x01, 0x55, 0x12, 0x20,
        0x58, 0x91, 0xb5, 0xb5, 0x22, 0xd5, 0xdf, 0x08,
        0x6d, 0x0f, 0xf0, 0xb1, 0x10, 0xfb, 0xd9, 0xd2,
        0x1b, 0xb4, 0xfc, 0x71, 0x63, 0xaf, 0x34, 0xd0,
        0x82, 0x86, 0xa2, 0xe8, 0x46, 0xf6, 0xbe, 0x03
    } length:36];
    return [CID daslCIDFromBytes:bytes];
}

- (void)testSingleModeRoundTripsAndPreservesApplicationMetadata {
    CID *cid = [self sampleCID];
    NSDictionary *object = @{
        @"$type": @"ing.dasl.masl",
        @"src": cid,
        @"content-type": @"text/plain",
        @"my-app-v1": @{@"label": @"hello"}
    };

    NSError *error = nil;
    ATProtoMASLDocument *document = [ATProtoMASLDocument documentWithObject:object error:&error];
    XCTAssertNotNil(document);
    XCTAssertFalse(document.isBundle);
    XCTAssertEqualObjects(document.src, cid);
    XCTAssertNil(error);

    NSData *encoded = [document DRISLDataWithError:&error];
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);

    ATProtoMASLDocument *decoded = [ATProtoMASLDocument documentWithDRISLData:encoded error:&error];
    XCTAssertNotNil(decoded);
    XCTAssertNil(error);
    XCTAssertEqualObjects(decoded.object, object);
}

- (void)testBundleRequiresRootAndResourceSources {
    CID *cid = [self sampleCID];
    NSError *error = nil;
    NSDictionary *missingRoot = @{
        @"resources": @{@"/index.html": @{@"src": cid}}
    };
    XCTAssertNil([ATProtoMASLDocument documentWithObject:missingRoot error:&error]);
    XCTAssertEqual(error.code, ATProtoMASLErrorInvalidResourcePath);

    error = nil;
    NSDictionary *missingSource = @{
        @"resources": @{@"/": @{@"content-type": @"text/html"}}
    };
    XCTAssertNil([ATProtoMASLDocument documentWithObject:missingSource error:&error]);
    XCTAssertEqual(error.code, ATProtoMASLErrorInvalidResource);

    error = nil;
    NSDictionary *bundle = @{
        @"resources": @{
            @"/": @{@"src": cid, @"content-type": @"text/html"},
            @"/app.js": @{@"src": cid, @"content-type": @"text/javascript"}
        }
    };
    ATProtoMASLDocument *document = [ATProtoMASLDocument documentWithObject:bundle error:&error];
    XCTAssertNotNil(document);
    XCTAssertTrue(document.isBundle);
    XCTAssertNil(error);
}

- (void)testResourcesModeTakesPrecedenceOverRootSource {
    CID *cid = [self sampleCID];
    NSError *error = nil;
    NSDictionary *object = @{
        @"src": cid,
        @"resources": @{@"/": @{@"src": cid}}
    };
    ATProtoMASLDocument *document = [ATProtoMASLDocument documentWithObject:object error:&error];
    XCTAssertNotNil(document);
    XCTAssertTrue(document.isBundle);
    XCTAssertNil(document.src);
    XCTAssertNil(error);
}

- (void)testBundleDRISLRoundTrips {
    CID *cid = [self sampleCID];
    NSDictionary *object = @{
        @"name": @"bundle",
        @"resources": @{
            @"/": @{@"src": cid, @"content-type": @"text/html"},
            @"/app.js": @{@"src": cid, @"content-type": @"text/javascript"}
        }
    };
    NSError *error = nil;
    ATProtoMASLDocument *document = [ATProtoMASLDocument documentWithObject:object error:&error];
    NSData *encoded = [document DRISLDataWithError:&error];
    ATProtoMASLDocument *decoded = [ATProtoMASLDocument documentWithDRISLData:encoded error:&error];
    NSData *reencoded = [decoded DRISLDataWithError:&error];
    XCTAssertNotNil(decoded);
    XCTAssertEqualObjects(reencoded, encoded);
    XCTAssertNil(error);
}

- (void)testInvalidRootSourceIsIgnoredInBundleMode {
    CID *cid = [self sampleCID];
    NSError *error = nil;
    NSDictionary *object = @{
        @"src": @"not-a-cid",
        @"resources": @{@"/": @{@"src": cid}}
    };
    ATProtoMASLDocument *document = [ATProtoMASLDocument documentWithObject:object error:&error];
    XCTAssertNotNil(document);
    XCTAssertTrue(document.isBundle);
    XCTAssertNil(error);
}

- (void)testBundleRejectsRelativeResourcePath {
    CID *cid = [self sampleCID];
    NSError *error = nil;
    NSDictionary *object = @{
        @"resources": @{
            @"/": @{@"src": cid},
            @"index.html": @{@"src": cid}
        }
    };
    XCTAssertNil([ATProtoMASLDocument documentWithObject:object error:&error]);
    XCTAssertEqual(error.code, ATProtoMASLErrorInvalidResourcePath);
}

- (void)testHeaderProjectionIsAllowListedAndPathAware {
    CID *cid = [self sampleCID];
    NSDictionary *object = @{
        @"content-type": @"text/plain",
        @"Content-Type": @"text/html",
        @"set-cookie": @"secret",
        @"sourcemap": @"/missing.map",
        @"src": cid
    };
    NSError *error = nil;
    ATProtoMASLDocument *single = [ATProtoMASLDocument documentWithObject:object error:&error];
    XCTAssertNotNil(single);
    NSDictionary *headers = [single httpHeadersForPath:nil error:&error];
    XCTAssertEqualObjects(headers, @{@"content-type": @"text/plain"});
    XCTAssertNil(error);

    NSDictionary *bundleObject = @{
        @"content-type": @"ignored-at-root",
        @"resources": @{
            @"/": @{@"src": cid, @"content-type": @"text/html", @"sourcemap": @"/app.map", @"speculation-rules": @"/rules.json"},
            @"/app.map": @{@"src": cid, @"content-type": @"application/json"},
            @"/rules.json": @{@"src": cid, @"content-type": @"application/json"}
        }
    };
    ATProtoMASLDocument *bundle = [ATProtoMASLDocument documentWithObject:bundleObject error:&error];
    XCTAssertNotNil(bundle);
    headers = [bundle httpHeadersForPath:@"/" error:&error];
    XCTAssertEqualObjects(headers, (@{@"content-type": @"text/html", @"sourcemap": @"/app.map", @"speculation-rules": @"/rules.json"}));
    XCTAssertNil(error);
}

- (void)testManifestReferencesMustNameBundleResources {
    CID *cid = [self sampleCID];
    NSDictionary *object = @{
        @"icons": @[@{@"src": @"/missing.svg"}],
        @"resources": @{@"/": @{@"src": cid}}
    };
    NSError *error = nil;
    ATProtoMASLDocument *document = [ATProtoMASLDocument documentWithObject:object error:&error];
    XCTAssertNil(document);
    XCTAssertEqual(error.code, ATProtoMASLErrorInvalidReference);

    NSDictionary *validObject = @{
        @"icons": @[@{@"src": @"/icon.svg"}],
        @"screenshots": @[@{@"src": @"/shot.png"}],
        @"resources": @{
            @"/": @{@"src": cid},
            @"/icon.svg": @{@"src": cid},
            @"/shot.png": @{@"src": cid}
        }
    };
    error = nil;
    XCTAssertNotNil([ATProtoMASLDocument documentWithObject:validObject error:&error]);
    XCTAssertNil(error);
}

- (void)testRejectsNonStringTopLevelKeys {
    CID *cid = [self sampleCID];
    NSError *error = nil;
    NSDictionary *object = @{@1: cid};
    XCTAssertNil([ATProtoMASLDocument documentWithObject:object error:&error]);
    XCTAssertEqual(error.code, ATProtoMASLErrorInvalidDocument);
}

- (void)testCARCompatibilityRequiresVersionOneAndCIDRoots {
    CID *cid = [self sampleCID];
    NSError *error = nil;
    ATProtoMASLDocument *valid = [ATProtoMASLDocument documentWithObject:@{
        @"version": @1,
        @"roots": @[cid],
        @"src": cid
    } error:&error];
    XCTAssertTrue([valid validateForCARWithError:&error]);
    XCTAssertNil(error);

    ATProtoMASLDocument *invalid = [ATProtoMASLDocument documentWithObject:@{
        @"version": @2,
        @"roots": @[]
    } error:&error];
    XCTAssertNotNil(invalid);
    XCTAssertFalse([invalid validateForCARWithError:&error]);
    XCTAssertEqual(error.code, ATProtoMASLErrorNotCARCompatible);

    ATProtoMASLDocument *booleanVersion = [ATProtoMASLDocument documentWithObject:@{
        @"version": @YES, @"roots": @[]
    } error:&error];
    XCTAssertFalse([booleanVersion validateForCARWithError:&error]);
    XCTAssertEqual(error.code, ATProtoMASLErrorNotCARCompatible);

    ATProtoMASLDocument *floatingVersion = [ATProtoMASLDocument documentWithObject:@{
        @"version": @1.0, @"roots": @[]
    } error:&error];
    XCTAssertFalse([floatingVersion validateForCARWithError:&error]);
    XCTAssertEqual(error.code, ATProtoMASLErrorNotCARCompatible);
}

- (void)testPrevAndTypeAreValidated {
    CID *cid = [self sampleCID];
    NSError *error = nil;
    ATProtoMASLDocument *document = [ATProtoMASLDocument documentWithObject:@{
        @"$type": @"ing.dasl.masl", @"src": cid, @"prev": cid
    } error:&error];
    XCTAssertNotNil(document);
    XCTAssertEqualObjects(document.prev, cid);

    XCTAssertNil(([ATProtoMASLDocument documentWithObject:@{
        @"$type": @"wrong.type", @"src": cid
    } error:&error]));
    XCTAssertEqual(error.code, ATProtoMASLErrorInvalidField);
}

@end
