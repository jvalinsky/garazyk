#import <XCTest/XCTest.h>

#import "AppView/ActorService.h"
#import "App/Services/PDSRecordService.h"
#import "Database/PDSDatabase.h"
#import "Database/Pool/DatabasePool.h"

@interface FollowersCountIntegrationTests : XCTestCase
@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) PDSDatabasePool *databasePool;
@property (nonatomic, strong) PDSRecordService *recordService;
@property (nonatomic, strong) PDSDatabase *serviceDatabase;
@property (nonatomic, strong) ActorService *actorService;
@end

@implementation FollowersCountIntegrationTests

- (void)setUp {
    [super setUp];

    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory withIntermediateDirectories:YES attributes:nil error:nil];

    self.databasePool = [[PDSDatabasePool alloc] initWithDbDirectory:self.testDirectory maxSize:10];
    self.recordService = [[PDSRecordService alloc] initWithDatabasePool:self.databasePool];

    NSString *serviceDbPath = [self.testDirectory stringByAppendingPathComponent:@"service.db"];
    self.serviceDatabase = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:serviceDbPath]];
    NSError *dbError = nil;
    XCTAssertTrue([self.serviceDatabase openWithError:&dbError], @"Failed to open service database: %@", dbError);
    self.actorService = [[ActorService alloc] initWithDatabase:self.serviceDatabase];
}

- (void)tearDown {
    [self.serviceDatabase close];
    self.actorService = nil;
    self.serviceDatabase = nil;
    self.recordService = nil;
    self.databasePool = nil;

    [[NSFileManager defaultManager] removeItemAtPath:self.testDirectory error:nil];
    self.testDirectory = nil;

    [super tearDown];
}

- (void)testFollowerCountIncrementsWhenFollowRecordWritten {
    NSString *subjectDid = @"did:plc:subject1";

    NSError *error = nil;
    BOOL ok = [self.recordService putRecord:@"app.bsky.graph.follow"
                                       rkey:@"r1"
                                      value:@{@"subject": subjectDid}
                                     forDid:@"__service__"
                             validationMode:PDSValidationModeOff
                                      error:&error];
    XCTAssertTrue(ok, @"putRecord failed: %@", error);

    NSInteger count = [self.actorService getFollowersCountForDID:subjectDid error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(count, 1);

    error = nil;
    ok = [self.recordService putRecord:@"app.bsky.graph.follow"
                                  rkey:@"r2"
                                 value:@{@"subject": @{@"did": subjectDid}}
                                forDid:@"__service__"
                        validationMode:PDSValidationModeOff
                                 error:&error];
    XCTAssertTrue(ok, @"putRecord failed: %@", error);

    count = [self.actorService getFollowersCountForDID:subjectDid error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(count, 2);
}

@end

