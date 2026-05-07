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

- (void)testUnknownNSIDInRequiredMode {
    ATProtoLexiconRegistry *registry = [[ATProtoLexiconRegistry alloc] init];
    ATProtoLexiconValidator *validator = [[ATProtoLexiconValidator alloc] initWithRegistry:registry];

    NSDictionary *record = @{
        @"$type": @"com.example.unknown",
        @"value": @"test"
    };
    NSError *error = nil;
    BOOL result = [validator validateRecord:record
                                collection:@"com.example.unknown"
                                      mode:ATProtoValidationModeRequired
                                     error:&error];
    XCTAssertFalse(result, @"Unknown NSID should fail in required mode");
    XCTAssertNotNil(error);
}

- (void)testUnknownNSIDInOptimisticMode {
    ATProtoLexiconRegistry *registry = [[ATProtoLexiconRegistry alloc] init];
    ATProtoLexiconValidator *validator = [[ATProtoLexiconValidator alloc] initWithRegistry:registry];

    NSDictionary *record = @{
        @"$type": @"com.example.unknown",
        @"value": @"test"
    };
    NSError *error = nil;
    BOOL result = [validator validateRecord:record
                                collection:@"com.example.unknown"
                                      mode:ATProtoValidationModeOptimistic
                                     error:&error];
    XCTAssertTrue(result, @"Unknown NSID should pass in optimistic mode");
}

- (void)testValidationModeOff {
    ATProtoLexiconRegistry *registry = [[ATProtoLexiconRegistry alloc] init];
    ATProtoLexiconValidator *validator = [[ATProtoLexiconValidator alloc] initWithRegistry:registry];

    NSDictionary *record = @{
        @"$type": @"com.example.anything",
        @"value": @"test"
    };
    NSError *error = nil;
    BOOL result = [validator validateRecord:record
                                collection:@"com.example.anything"
                                      mode:ATProtoValidationModeOff
                                     error:&error];
    XCTAssertTrue(result, @"Off mode should always pass");
}

- (void)testSchemaWithArrayConstraints {
    NSString *json = @"{ \"lexicon\": 1, \"id\": \"com.example.arrays\", \"defs\": { \"main\": { \"type\": \"object\", \"properties\": { \"items\": { \"type\": \"array\", \"items\": { \"type\": \"string\" }, \"minItems\": 1, \"maxItems\": 5 } } } } }";
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    ATProtoLexiconSchema *schema = [ATProtoLexiconSchema schemaFromJSONData:data error:&error];

    XCTAssertNotNil(schema);
    XCTAssertNil(error);

    ATProtoLexiconRegistry *registry = [[ATProtoLexiconRegistry alloc] init];
    [registry registerSchema:schema];
    ATProtoLexiconValidator *validator = [[ATProtoLexiconValidator alloc] initWithRegistry:registry];

    // Valid array
    NSDictionary *validRecord = @{
        @"$type": @"com.example.arrays",
        @"items": @[@"a", @"b", @"c"]
    };
    BOOL result = [validator validateRecord:validRecord
                                collection:@"com.example.arrays"
                                      mode:ATProtoValidationModeRequired
                                     error:&error];
    XCTAssertTrue(result, @"Array within bounds should pass");

    // Empty array (violates minItems: 1)
    NSDictionary *emptyArrayRecord = @{
        @"$type": @"com.example.arrays",
        @"items": @[]
    };
    error = nil;
    result = [validator validateRecord:emptyArrayRecord
                           collection:@"com.example.arrays"
                                 mode:ATProtoValidationModeRequired
                                error:&error];
    XCTAssertFalse(result, @"Empty array should fail minItems constraint");

    // Array too long (violates maxItems: 5)
    NSDictionary *longArrayRecord = @{
        @"$type": @"com.example.arrays",
        @"items": @[@"1", @"2", @"3", @"4", @"5", @"6"]
    };
    error = nil;
    result = [validator validateRecord:longArrayRecord
                           collection:@"com.example.arrays"
                                 mode:ATProtoValidationModeRequired
                                error:&error];
    XCTAssertFalse(result, @"Array exceeding maxItems should fail");
}

- (void)testStringFormatValidation {
    NSString *json = @"{ \"lexicon\": 1, \"id\": \"com.example.formats\", \"defs\": { \"main\": { \"type\": \"object\", \"properties\": { \"uri\": { \"type\": \"string\", \"format\": \"at-uri\" }, \"datetime\": { \"type\": \"string\", \"format\": \"datetime\" }, \"did\": { \"type\": \"string\", \"format\": \"did\" }, \"handle\": { \"type\": \"string\", \"format\": \"handle\" } } } } }";
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    ATProtoLexiconSchema *schema = [ATProtoLexiconSchema schemaFromJSONData:data error:&error];

    XCTAssertNotNil(schema);
    XCTAssertNil(error);

    ATProtoLexiconRegistry *registry = [[ATProtoLexiconRegistry alloc] init];
    [registry registerSchema:schema];
    ATProtoLexiconValidator *validator = [[ATProtoLexiconValidator alloc] initWithRegistry:registry];

    // Valid at-uri
    NSDictionary *validAtUri = @{
        @"$type": @"com.example.formats",
        @"uri": @"at://did:plc:example/app.bsky.feed.post/123",
        @"datetime": @"2025-01-01T12:00:00.000Z",
        @"did": @"did:plc:example",
        @"handle": @"example.com"
    };
    BOOL result = [validator validateRecord:validAtUri
                                collection:@"com.example.formats"
                                      mode:ATProtoValidationModeRequired
                                     error:&error];
    XCTAssertTrue(result, @"Valid format strings should pass");

    // Invalid at-uri
    NSDictionary *invalidAtUri = @{
        @"$type": @"com.example.formats",
        @"uri": @"not-an-at-uri",
        @"datetime": @"2025-01-01T12:00:00.000Z",
        @"did": @"did:plc:example",
        @"handle": @"example.com"
    };
    error = nil;
    result = [validator validateRecord:invalidAtUri
                           collection:@"com.example.formats"
                                 mode:ATProtoValidationModeRequired
                                error:&error];
    XCTAssertFalse(result, @"Invalid at-uri format should fail");
}

- (void)testBlobRefValidation {
    NSString *json = @"{ \"lexicon\": 1, \"id\": \"com.example.blob\", \"defs\": { \"main\": { \"type\": \"object\", \"properties\": { \"avatar\": { \"type\": \"blob\", \"accept\": [\"image/png\", \"image/jpeg\"], \"maxSize\": 1000000 } } } } }";
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    ATProtoLexiconSchema *schema = [ATProtoLexiconSchema schemaFromJSONData:data error:&error];

    XCTAssertNotNil(schema);
    XCTAssertNil(error);

    ATProtoLexiconRegistry *registry = [[ATProtoLexiconRegistry alloc] init];
    [registry registerSchema:schema];
    ATProtoLexiconValidator *validator = [[ATProtoLexiconValidator alloc] initWithRegistry:registry];

    // Valid blob ref
    NSDictionary *validBlob = @{
        @"$type": @"com.example.blob",
        @"avatar": @{
            @"$type": @"blob",
            @"ref": @{ @"$link": @"bafkreiexample" },
            @"mimeType": @"image/png",
            @"size": @500000
        }
    };
    BOOL result = [validator validateRecord:validBlob
                                collection:@"com.example.blob"
                                      mode:ATProtoValidationModeRequired
                                     error:&error];
    XCTAssertTrue(result, @"Valid blob ref should pass");

    // Missing ref
    NSDictionary *missingRef = @{
        @"$type": @"com.example.blob",
        @"avatar": @{
            @"$type": @"blob",
            @"mimeType": @"image/png",
            @"size": @500000
        }
    };
    error = nil;
    result = [validator validateRecord:missingRef
                           collection:@"com.example.blob"
                                 mode:ATProtoValidationModeRequired
                                error:&error];
    XCTAssertFalse(result, @"Blob ref missing $ref should fail");

    // Missing mimeType
    NSDictionary *missingMime = @{
        @"$type": @"com.example.blob",
        @"avatar": @{
            @"$type": @"blob",
            @"ref": @{ @"$link": @"bafkreiexample" },
            @"size": @500000
        }
    };
    error = nil;
    result = [validator validateRecord:missingMime
                           collection:@"com.example.blob"
                                 mode:ATProtoValidationModeRequired
                                error:&error];
    XCTAssertFalse(result, @"Blob ref missing mimeType should fail");
}

@end
