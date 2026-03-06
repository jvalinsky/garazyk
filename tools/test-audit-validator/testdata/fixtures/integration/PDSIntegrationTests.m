#import <XCTest/XCTest.h>

// Integration test fixture
@interface PDSIntegrationTests : XCTestCase
@end

@implementation PDSIntegrationTests

- (void)testCreateAndRetrieveRecord {
    // Integration test with multiple components and cleanup
    PDSDatabase *db = [[PDSDatabase alloc] initWithPath:@":memory:"];
    PDSRepository *repo = [[PDSRepository alloc] initWithDatabase:db];
    PDSAccount *account = [repo createAccount:@"test.user"];

    NSData *record = [@"test record" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *uri = [repo putRecord:record forAccount:account];

    NSData *retrieved = [repo getRecord:uri];
    XCTAssertEqualObjects(record, retrieved, @"Should retrieve the same record");

    [db close];
}

- (void)testSingleComponentNotIntegration {
    // Misclassified: only uses one component
    NSData *data = [@"hello" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertNotNil(data);
}

@end
