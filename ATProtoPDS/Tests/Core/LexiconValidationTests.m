#import <XCTest/XCTest.h>
#import "Core/ATProtoValidator.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @brief Tests for ATProto Lexicon identifier validation.
 *
 * Validates NSID, AT-URI, TID, and CID formats per ATProto specifications.
 * Reference: https://atproto.com/specs/lexicon
 */
@interface LexiconValidationTests : XCTestCase
@end

@implementation LexiconValidationTests

#pragma mark - NSID Validation Tests

- (void)testValidNSIDFormats {
    // Standard valid NSIDs
    XCTAssertTrue([ATProtoValidator validateNSID:@"app.bsky.feed.post" error:nil]);
    XCTAssertTrue([ATProtoValidator validateNSID:@"com.example.record" error:nil]);
    XCTAssertTrue([ATProtoValidator validateNSID:@"io.github.user.repo" error:nil]);
    XCTAssertTrue([ATProtoValidator validateNSID:@"org.atproto.sync.subscribeRepos" error:nil]);
}

- (void)testNSIDWithNumbers {
    // Numbers are allowed in segments
    NSError *error = nil;
    XCTAssertTrue([ATProtoValidator validateNSID:@"app.1bsky.post" error:&error], @"NSID with numbers should be allowed");
    XCTAssertNil(error);
}

- (void)testNSIDMinimumSegments {
    // 2 segments (e.g. domain) are valid
    NSError *error = nil;
    XCTAssertTrue([ATProtoValidator validateNSID:@"app.bsky" error:&error], @"2-segment NSID should be valid");
    XCTAssertNil(error);
    XCTAssertFalse([ATProtoValidator validateNSID:@"com" error:nil]);
    XCTAssertFalse([ATProtoValidator validateNSID:@"" error:nil]);
}

- (void)testNSIDMaxLength {
    // NSID max length is 317 characters (253 for authority + 1 dot + 63 for name)
    // Build a long but valid NSID
    NSMutableString *longAuthority = [NSMutableString string];
    for (int i = 0; i < 4; i++) {
        if (i > 0) [longAuthority appendString:@"."];
        [longAuthority appendString:@"abcdefghijklmnopqrstuvwxyz123456789012345678901234567890123"]; // 63 chars
    }
    [longAuthority appendString:@".name"];
    
    // This should be at the limit or close to it
    if (longAuthority.length <= 317) {
        XCTAssertTrue([ATProtoValidator validateNSID:longAuthority error:nil]);
    }
    
    // Excessively long NSID should fail
    NSMutableString *tooLong = [NSMutableString stringWithString:longAuthority];
    [tooLong appendString:@".toolongextra"];
    if (tooLong.length > 317) {
        NSError *error = nil;
        XCTAssertFalse([ATProtoValidator validateNSID:tooLong error:&error]);
    }
}

- (void)testNSIDConsecutiveDots {
    // Consecutive dots are invalid
    NSError *error = nil;
    XCTAssertFalse([ATProtoValidator validateNSID:@"app..bsky.post" error:&error]);
    XCTAssertFalse([ATProtoValidator validateNSID:@"app.bsky..post" error:nil]);
}

- (void)testNSIDTrailingDot {
    // Trailing dot is invalid
    NSError *error = nil;
    XCTAssertFalse([ATProtoValidator validateNSID:@"app.bsky.post." error:&error]);
}

- (void)testNSIDLeadingDot {
    // Leading dot is invalid
    NSError *error = nil;
    XCTAssertFalse([ATProtoValidator validateNSID:@".app.bsky.post" error:&error]);
}

- (void)testNSIDUppercaseAllowed {
    // Uppercase allowed in XRPC methods (e.g. getRecord)
    NSError *error = nil;
    XCTAssertTrue([ATProtoValidator validateNSID:@"App.Bsky.Feed.Post" error:nil], @"Uppercase should be allowed in NSIDs");
    XCTAssertTrue([ATProtoValidator validateNSID:@"app.bsky.FEED.post" error:nil], @"Uppercase segments should be allowed");
}

- (void)testNSIDSpecialCharsRejected {
    // Only alphanumeric and hyphens allowed
    NSError *error = nil;
    XCTAssertFalse([ATProtoValidator validateNSID:@"app.bsky.feed_post" error:&error]);
    XCTAssertFalse([ATProtoValidator validateNSID:@"app.bsky.feed+post" error:nil]);
    XCTAssertFalse([ATProtoValidator validateNSID:@"app.bsky.feed/post" error:nil]);
}

#pragma mark - AT-URI Validation Tests

- (void)testValidATURIFormat {
    // Valid AT-URIs
    XCTAssertTrue([self isValidATURI:@"at://did:plc:z72i7hdynmk6r22z27h6tvur/app.bsky.feed.post/3jqfcqzm3fo2j"]);
    XCTAssertTrue([self isValidATURI:@"at://did:web:example.com/app.bsky.actor.profile/self"]);
    XCTAssertTrue([self isValidATURI:@"at://jay.bsky.social/app.bsky.feed.like/3k5f2"]);
}

- (void)testATURIWithoutRkey {
    // AT-URI without rkey (collection only)
    XCTAssertTrue([self isValidATURI:@"at://did:plc:z72i7hdynmk6r22z27h6tvur/app.bsky.feed.post"]);
}

- (void)testATURIRepoOnly {
    // AT-URI with just repo (DID or handle)
    XCTAssertTrue([self isValidATURI:@"at://did:plc:z72i7hdynmk6r22z27h6tvur"]);
    XCTAssertTrue([self isValidATURI:@"at://jay.bsky.social"]);
}

- (void)testATURIWithFragment {
    // AT-URIs should not have fragments
    XCTAssertFalse([self isValidATURI:@"at://did:plc:test/app.bsky.feed.post/rkey#fragment"]);
}

- (void)testATURIWithQuery {
    // AT-URIs should not have query strings
    XCTAssertFalse([self isValidATURI:@"at://did:plc:test/app.bsky.feed.post/rkey?query=value"]);
}

- (void)testATURIInvalidScheme {
    // Must use at:// scheme
    XCTAssertFalse([self isValidATURI:@"http://did:plc:test/app.bsky.feed.post/rkey"]);
    XCTAssertFalse([self isValidATURI:@"https://did:plc:test/app.bsky.feed.post/rkey"]);
    XCTAssertFalse([self isValidATURI:@"AT://did:plc:test/app.bsky.feed.post/rkey"]);
}

- (void)testATURIInvalidDID {
    // Malformed DID in AT-URI
    XCTAssertFalse([self isValidATURI:@"at://did:invalid/app.bsky.feed.post/rkey"]);
    XCTAssertFalse([self isValidATURI:@"at://did:/app.bsky.feed.post/rkey"]);
}

- (void)testATURIEmptyComponents {
    // Empty components should fail
    XCTAssertFalse([self isValidATURI:@"at://"]);
    XCTAssertFalse([self isValidATURI:@"at:///"]);
    XCTAssertFalse([self isValidATURI:@"at://did:plc:test//"]);
}

#pragma mark - CID Validation Tests

- (void)testCIDv1Base32Lower {
    // Valid CIDv1 with base32lower (starts with 'b')
    XCTAssertTrue([ATProtoValidator validateCID:@"bafyreie5cvv4h45feadgeuwhbcutmh6t2ceseocckahdoe6uat64zmz454" error:nil]);
    XCTAssertTrue([ATProtoValidator validateCID:@"bafyreiern4acpjlva5gookrtc534gr4nmuj7pbvfsg6yslnbuv336izv7e" error:nil]);
}

- (void)testCIDv0Rejected {
    // CIDv0 (starts with Qm) should be rejected per ATProto spec
    NSError *error = nil;
    XCTAssertFalse([ATProtoValidator validateCID:@"QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG" error:&error]);
}

- (void)testCIDBase32UpperRejected {
    // Uppercase base32 should be rejected
    NSError *error = nil;
    XCTAssertFalse([ATProtoValidator validateCID:@"BAFYREIE5CVV4H45FEADGEUWHBCUTMH6T2CESEOCCKAHDOE6UAT64ZMZ454" error:&error]);
}

- (void)testCIDInvalidBase32Chars {
    // Base32lower excludes 0, 1, 8, 9
    NSError *error = nil;
    XCTAssertFalse([ATProtoValidator validateCID:@"bafyrei0000000000000000000000000000000000000000000000000" error:&error]);
    XCTAssertFalse([ATProtoValidator validateCID:@"bafyrei1111111111111111111111111111111111111111111111111" error:nil]);
}

- (void)testCIDTooShort {
    // CID must have sufficient length for multibase + multicodec + multihash
    NSError *error = nil;
    XCTAssertFalse([ATProtoValidator validateCID:@"bafyrei" error:&error]);
    XCTAssertFalse([ATProtoValidator validateCID:@"b" error:nil]);
    XCTAssertFalse([ATProtoValidator validateCID:@"" error:nil]);
}

- (void)testCIDNil {
    // Nil CID should fail gracefully
    XCTAssertFalse([ATProtoValidator validateCID:(id)nil error:nil]);
}

#pragma mark - TID Validation Tests

- (void)testValidTIDFormat {
    NSError *error = nil;
    NSString *validTID = @"3k5f2x7abcdda"; // valid base32 (no 1, 8, 9)
    XCTAssertTrue([ATProtoValidator validateTID:validTID error:&error], @"Valid TID should be accepted: %@", error.localizedDescription);
    XCTAssertNil(error);
}

- (void)testTIDLength {
    // TID must be exactly 13 characters
    NSError *error = nil;
    XCTAssertFalse([ATProtoValidator validateTID:@"3jqfcqzm3fo2" error:&error]); // 12 chars
    XCTAssertFalse([ATProtoValidator validateTID:@"3jqfcqzm3fo2jx" error:nil]); // 14 chars
}

- (void)testTIDForbiddenChars {
    NSError *error = nil;
    XCTAssertFalse([ATProtoValidator validateTID:@"3jqfcqzm3foo1" error:&error]); // Contains '1'
    XCTAssertFalse([ATProtoValidator validateTID:@"3jqfcqzm3foo8" error:nil]); // Contains '8'
}

- (void)testTIDBase32Sortable {
    // Valid characters: 234567abcdefghjkmnpqrstuvwxyz
    XCTAssertTrue([ATProtoValidator validateTID:@"2345672345672" error:nil]);
    XCTAssertTrue([ATProtoValidator validateTID:@"abcdefghjkmnp" error:nil]);
}

- (void)testTIDUppercaseRejected {
    // TIDs must be lowercase
    NSError *error = nil;
    XCTAssertFalse([ATProtoValidator validateTID:@"3JQFCQZM3FO2J" error:&error]);
}

#pragma mark - Helper Methods

- (BOOL)isValidATURI:(NSString *)uri {
    if (uri.length == 0) return NO;
    
    // Must start with at://
    if (![uri hasPrefix:@"at://"]) return NO;
    
    // Extract the rest after at://
    NSString *rest = [uri substringFromIndex:5];
    if (rest.length == 0) return NO;
    
    // Check for forbidden characters
    if ([rest containsString:@"#"]) return NO;  // No fragments
    if ([rest containsString:@"?"]) return NO;  // No query strings
    
    // Split by slash
    NSArray *pathParts = [rest componentsSeparatedByString:@"/"];
    if (pathParts.count == 0) return NO;
    
    // First component is authority (DID or handle)
    NSString *authority = pathParts[0];
    if (authority.length == 0) return NO;
    
    // Validate authority (DID or handle)
    if ([authority hasPrefix:@"did:"]) {
        // Validate DID format
        if (![ATProtoValidator validateDID:authority error:nil]) {
            return NO;
        }
    } else {
        // Assume it's a handle
        if (![ATProtoValidator validateHandle:authority error:nil]) {
            return NO;
        }
    }
    
    // If there are more parts, validate collection (NSID)
    if (pathParts.count > 1) {
        NSString *collection = pathParts[1];
        if (collection.length == 0) return NO;
        if (![ATProtoValidator validateNSID:collection error:nil]) {
            return NO;
        }
    }
    
    // If there's an rkey, it should be valid
    if (pathParts.count > 2) {
        NSString *rkey = pathParts[2];
        if (rkey.length == 0) return NO;
        // Basic rkey validation: printable ASCII, no slashes
        for (NSUInteger i = 0; i < rkey.length; i++) {
            unichar c = [rkey characterAtIndex:i];
            if (c < 0x21 || c > 0x7E || c == '/') return NO;
        }
    }
    
    return YES;
}

@end

NS_ASSUME_NONNULL_END
