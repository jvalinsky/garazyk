#import <XCTest/XCTest.h>
#import "Lexicon/ATProtoLexiconValidator.h"
#import "Lexicon/ATProtoLexiconRegistry.h"
#import "Lexicon/ATProtoLexiconSchema.h"
#import "Lexicon/ATProtoLexiconDef.h"
#import "Lexicon/ATProtoLexiconConstraints.h"

@interface LexiconValidationTests : XCTestCase
@end

@implementation LexiconValidationTests

- (void)testSchemaParsing {
    NSString *json = @"{ \"lexicon\": 1, \"id\": \"com.example.test\", \"defs\": { \"main\": { \"type\": \"string\", \"maxLength\": 10 } } }";
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    ATProtoLexiconSchema *schema = [ATProtoLexiconSchema schemaFromJSONData:data error:&error];
    
    XCTAssertNotNil(schema);
    XCTAssertNil(error);
    XCTAssertEqualObjects(schema.nsid, @"com.example.test");
    XCTAssertNotNil(schema.defs[@"main"]);
    XCTAssertEqual(schema.defs[@"main"].type, ATProtoLexiconDefTypeString);
    
    ATProtoLexiconStringConstraints *constraints = schema.defs[@"main"].constraints;
    XCTAssertTrue([constraints isKindOfClass:[ATProtoLexiconStringConstraints class]]);
    XCTAssertEqualObjects(constraints.maxLength, @10);
}

- (void)testPostValidation {
    // Locate Resources directory
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *cwd = [fm currentDirectoryPath];
    NSString *resourcesPath = nil;
    
    // Search for Resources directory relative to CWD (build dir)
    NSArray *candidates = @[
        @"Garazyk/Resources",
        @"../Garazyk/Resources",
        @"../../Garazyk/Resources",
        @"../../../Garazyk/Resources"
    ];
    
    for (NSString *candidate in candidates) {
        NSString *path = [cwd stringByAppendingPathComponent:candidate];
        if ([fm fileExistsAtPath:path]) {
            resourcesPath = path;
            break;
        }
    }
    
    XCTAssertNotNil(resourcesPath, @"Could not find Garazyk/Resources directory");
    
    // Construct path to post.json
    NSString *schemaPath = [resourcesPath stringByAppendingPathComponent:@"lexicons/app/bsky/feed/post.json"];
    XCTAssertTrue([fm fileExistsAtPath:schemaPath], @"Schema file not found at %@", schemaPath);
    
    // Create isolated registry and load file
    ATProtoLexiconRegistry *registry = [[ATProtoLexiconRegistry alloc] init];
    NSError *loadError = nil;
    BOOL loaded = [registry loadLexiconFromFile:schemaPath error:&loadError];
    
    XCTAssertTrue(loaded, @"Failed to load schema: %@", loadError);
    XCTAssertTrue([registry hasSchemaForNSID:@"app.bsky.feed.post"], @"Schema not registered after loading");

    ATProtoLexiconValidator *validator = [[ATProtoLexiconValidator alloc] initWithRegistry:registry];
    
    // 1. Valid Record
    NSDictionary *validRecord = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Hello World",
        @"createdAt": @"2025-01-01T12:00:00Z"
    };
    NSError *error = nil;
    BOOL result = [validator validateRecord:validRecord collection:@"app.bsky.feed.post" mode:ATProtoValidationModeRequired error:&error];
    XCTAssertTrue(result);
    XCTAssertNil(error);

    // 2. Missing Required Field
    NSDictionary *invalidRecord1 = @{
        @"$type": @"app.bsky.feed.post",
        @"createdAt": @"2025-01-01T12:00:00Z"
    };
    result = [validator validateRecord:invalidRecord1 collection:@"app.bsky.feed.post" mode:ATProtoValidationModeRequired error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    
    // 3. Text Too Long (Graphemes)
    NSMutableString *longText = [NSMutableString string];
    for (int i=0; i<301; i++) [longText appendString:@"a"];
    NSDictionary *invalidRecord2 = @{
        @"$type": @"app.bsky.feed.post",
        @"text": longText,
        @"createdAt": @"2025-01-01T12:00:00Z"
    };
    result = [validator validateRecord:invalidRecord2 collection:@"app.bsky.feed.post" mode:ATProtoValidationModeRequired error:&error];
    XCTAssertFalse(result);
    // XCTAssertTrue([error.localizedDescription containsString:@"maxGraphemes"]); // Depending on implementation
}

@end
