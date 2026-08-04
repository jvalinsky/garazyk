// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Admin/Diagnostics/PDSSystemDiagnosticsHandler.h"
#import "Admin/Diagnostics/PDSSequencerHealthHandler.h"
#import "Admin/Diagnostics/PDSBlobAuditHandler.h"
#import "Admin/Diagnostics/PDSRateLimitAdminHandler.h"
#import "Admin/Diagnostics/BlobAudit/PDSBlobAuditManager.h"
#import "Blob/BlobStorage.h"
#import "Blob/PDSDiskBlobProvider.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/Service/ServiceDatabases.h"

@interface PDSSystemDiagnosticsHandlerTests : XCTestCase
@property (nonatomic, strong) PDSSystemDiagnosticsHandler *handler;
@property (nonatomic, strong) PDSBlobAuditManager *auditManager;
@property (nonatomic, strong) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, strong) PDSDatabasePool *userDatabasePool;
@property (nonatomic, copy) NSString *tempDirectory;
@end

@implementation PDSSystemDiagnosticsHandlerTests

- (void)setUp {
    [super setUp];
    self.handler = [[PDSSystemDiagnosticsHandler alloc] init];

    // The blob routes answer 503 until an audit manager is supplied, so the
    // routing and forwarding tests need a real one to reach the handler.
    self.tempDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"SystemDiagnosticsTests_%@", [[NSUUID UUID] UUIDString]]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    self.serviceDatabases = [[PDSServiceDatabases alloc] initWithDirectory:self.tempDirectory
                                                            serviceMaxSize:4
                                                           didCacheMaxSize:2
                                                          sequencerMaxSize:2];

    NSString *userDbDir = [self.tempDirectory stringByAppendingPathComponent:@"users"];
    self.userDatabasePool = [[PDSDatabasePool alloc] initWithDbDirectory:userDbDir maxSize:4];

    NSURL *blobURL = [NSURL fileURLWithPath:[self.tempDirectory stringByAppendingPathComponent:@"blobs"]];
    PDSDiskBlobProvider *provider = [[PDSDiskBlobProvider alloc] initWithStorageDirectory:blobURL];
    BlobStorage *blobStorage = [[BlobStorage alloc] initWithDatabasePool:self.userDatabasePool
                                                                provider:provider];
    self.auditManager = [[PDSBlobAuditManager alloc] initWithBlobStorage:blobStorage
                                                        serviceDatabases:self.serviceDatabases];
    self.handler.auditManager = self.auditManager;
}

- (void)tearDown {
    [self.auditManager.auditQueue cancelAllOperations];
    [self.serviceDatabases closeAll];
    [self.userDatabasePool closeAll];
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDirectory error:nil];
    [super tearDown];
}

- (void)testSharedHandlerReturnsSameInstance {
    PDSSystemDiagnosticsHandler *first = [PDSSystemDiagnosticsHandler sharedHandler];
    PDSSystemDiagnosticsHandler *second = [PDSSystemDiagnosticsHandler sharedHandler];
    XCTAssertNotNil(first);
    XCTAssertTrue(first == second);
}

- (void)testUnknownPathReturns404 {
    NSInteger statusCode = 0;
    NSString *contentType = nil;
    NSString *body = [self.handler handleRequestWithMethod:1
                                                     path:@"/unknown"
                                                  headers:@{}
                                                     body:nil
                                               statusCode:&statusCode
                                              contentType:&contentType];
    XCTAssertEqual(statusCode, 404);
    XCTAssertEqualObjects(contentType, @"application/json");
    XCTAssertTrue([body containsString:@"Not Found"]);
}

- (void)testSequencerPathRoutesToSequencerHandler {
    NSInteger statusCode = 0;
    NSString *contentType = nil;
    NSString *body = [self.handler handleRequestWithMethod:1
                                                     path:@"/sequencer/stats"
                                                  headers:@{}
                                                     body:nil
                                               statusCode:&statusCode
                                              contentType:&contentType];
    XCTAssertEqual(statusCode, 200);
    XCTAssertEqualObjects(contentType, @"application/json");
    NSData *jsonData = [body dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertNotNil(jsonData);
    NSError *jsonError = nil;
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&jsonError];
    XCTAssertNil(jsonError);
    XCTAssertNotNil(dict);
    XCTAssertTrue(dict[@"currentSeq"] != nil, @"Response should contain currentSeq");
}

- (void)testBlobsPathRoutesToBlobAuditHandler {
    NSInteger statusCode = 0;
    NSString *contentType = nil;
    NSData *requestBody = [NSJSONSerialization dataWithJSONObject:@{@"auditType": @"orphans", @"dryRun": @YES}
                                                          options:0
                                                            error:nil];
    NSString *body = [self.handler handleRequestWithMethod:1
                                                     path:@"/blobs/audit"
                                                  headers:@{}
                                                     body:requestBody
                                               statusCode:&statusCode
                                              contentType:&contentType];
    XCTAssertEqual(statusCode, 200);
    XCTAssertEqualObjects(contentType, @"application/json");
    XCTAssertTrue([body containsString:@"jobId"], @"Expected job response from blob audit route");
}

- (void)testRateLimitsPathRoutesToRateLimitHandler {
    NSInteger statusCode = 0;
    NSString *contentType = nil;
    NSString *body = [self.handler handleRequestWithMethod:1
                                                     path:@"/ratelimits/top"
                                                  headers:@{}
                                                     body:nil
                                               statusCode:&statusCode
                                              contentType:&contentType];
    XCTAssertEqual(statusCode, 200);
    XCTAssertEqualObjects(contentType, @"application/json");
    XCTAssertNotNil(body);
}

- (void)testAuditManagerIsForwardedToBlobHandler {
    NSInteger statusCode = 0;
    NSData *requestBody = [NSJSONSerialization dataWithJSONObject:@{@"auditType": @"orphans", @"dryRun": @YES}
                                                          options:0
                                                            error:nil];
    [self.handler handleRequestWithMethod:1
                                     path:@"/blobs/audit"
                                  headers:@{}
                                     body:requestBody
                               statusCode:&statusCode
                              contentType:NULL];
    XCTAssertEqual(statusCode, 200);
}

- (void)testSequencerHistoryRoutePassesHoursParameter {
    NSInteger statusCode = 0;
    NSString *contentType = nil;
    NSString *body = [self.handler handleRequestWithMethod:1
                                                     path:@"/sequencer/history?hours=48"
                                                  headers:@{}
                                                     body:nil
                                               statusCode:&statusCode
                                              contentType:&contentType];
    XCTAssertEqual(statusCode, 200);
    NSData *jsonData = [body dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
    XCTAssertNotNil(dict);
    XCTAssertEqualObjects(dict[@"hours"], @48);
    XCTAssertNotNil(dict[@"dataPoints"]);
}

@end
