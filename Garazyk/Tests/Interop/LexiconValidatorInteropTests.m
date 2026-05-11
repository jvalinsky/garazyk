// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Lexicon/ATProtoLexiconValidator.h"
#import "Lexicon/ATProtoLexiconRegistry.h"
#import "Lexicon/ATProtoLexiconSchema.h"

@interface LexiconValidatorInteropTests : XCTestCase
@property (nonatomic, strong) ATProtoLexiconRegistry *registry;
@property (nonatomic, strong) ATProtoLexiconValidator *validator;
@end

@implementation LexiconValidatorInteropTests

- (void)setUp {
    [super setUp];
    self.registry = [[ATProtoLexiconRegistry alloc] init];
    
    // Load interop test lexicons
    NSString *catalogPath = [self interopFixturePath:@"lexicon/catalog"];
    XCTAssertNotNil(catalogPath, @"Interop lexicon catalog not found");
    NSError *error = nil;
    [self.registry loadLexiconsFromDirectory:catalogPath error:&error];
    XCTAssertNil(error, @"Failed to load lexicons: %@", error.localizedDescription);
    
    self.validator = [[ATProtoLexiconValidator alloc] initWithRegistry:self.registry];
}

- (nullable NSString *)interopFixturePath:(NSString *)relativePath {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *cwd = fm.currentDirectoryPath;
    NSString *base = @"Garazyk/Tests/fixtures/atproto-interop-tests";
    NSString *sourceFile = @__FILE__;
    NSString *testsDirectory = [[sourceFile stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    NSString *sourceRoot = [testsDirectory stringByDeletingLastPathComponent];
    
    NSArray<NSString *> *candidates = @[
        [[cwd stringByAppendingPathComponent:base] stringByAppendingPathComponent:relativePath],
        [[cwd stringByAppendingPathComponent:@"Tests/fixtures/atproto-interop-tests"] stringByAppendingPathComponent:relativePath],
        [[[sourceRoot stringByAppendingPathComponent:@"Tests/fixtures/atproto-interop-tests"] stringByAppendingPathComponent:relativePath] stringByStandardizingPath]
    ];

    for (NSString *path in candidates) {
        if ([fm fileExistsAtPath:path]) {
            return path;
        }
    }
    return nil;
}

- (void)testValidRecordFixtures {
    NSString *path = [self interopFixturePath:@"lexicon/record-data-valid.json"];
    XCTAssertNotNil(path);
    
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSArray *fixtures = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    
    for (NSDictionary *fixture in fixtures) {
        NSDictionary *record = fixture[@"data"];
        NSString *collection = record[@"$type"];
        // Strip #main if present for registry lookup
        NSRange hashRange = [collection rangeOfString:@"#"];
        if (hashRange.location != NSNotFound) {
            collection = [collection substringToIndex:hashRange.location];
        }
        
        NSError *error = nil;
        BOOL ok = [self.validator validateRecord:record
                                     collection:collection
                                           mode:ATProtoValidationModeRequired
                                          error:&error];
        XCTAssertTrue(ok, @"Fixture '%@' should be valid: %@", fixture[@"name"], error.localizedDescription);
    }
}

- (void)testInvalidRecordFixtures {
    NSString *path = [self interopFixturePath:@"lexicon/record-data-invalid.json"];
    XCTAssertNotNil(path);
    
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSArray *fixtures = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    
    for (NSDictionary *fixture in fixtures) {
        NSDictionary *record = fixture[@"data"];
        NSString *collection = record[@"$type"];
        if (!collection) {
            // Some invalid fixtures might lack $type. Use example.lexicon.record as default for test.
            collection = @"example.lexicon.record";
        } else {
            NSRange hashRange = [collection rangeOfString:@"#"];
            if (hashRange.location != NSNotFound) {
                collection = [collection substringToIndex:hashRange.location];
            }
        }
        
        NSError *error = nil;
        BOOL ok = [self.validator validateRecord:record
                                     collection:collection
                                           mode:ATProtoValidationModeRequired
                                          error:&error];
        XCTAssertFalse(ok, @"Fixture '%@' should be invalid", fixture[@"name"]);
    }
}

@end
