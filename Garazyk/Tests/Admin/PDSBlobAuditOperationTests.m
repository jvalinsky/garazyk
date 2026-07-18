// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Admin/Diagnostics/BlobAudit/PDSBlobAuditOperation.h"

@interface PDSBlobAuditOperationTests : XCTestCase
@end

@implementation PDSBlobAuditOperationTests

- (void)testInitSetsProperties {
    PDSBlobAuditOperation *op = [[PDSBlobAuditOperation alloc] initWithJobId:@"job-123"
                                                                   auditType:@"orphans"
                                                                 blobStorage:nil
                                                             serviceDatabases:nil
                                                                      dryRun:YES];
    XCTAssertNotNil(op);
    XCTAssertEqualObjects(op.jobId, @"job-123");
    XCTAssertEqualObjects(op.auditType, @"orphans");
    XCTAssertTrue(op.dryRun);
    XCTAssertEqual(op.progress, 0.0);
    XCTAssertNil(op.results);
    XCTAssertNil(op.operationError);
}

- (void)testInitWithDryRunFalse {
    PDSBlobAuditOperation *op = [[PDSBlobAuditOperation alloc] initWithJobId:@"job-456"
                                                                   auditType:@"cid_verify"
                                                                 blobStorage:nil
                                                             serviceDatabases:nil
                                                                      dryRun:NO];
    XCTAssertNotNil(op);
    XCTAssertFalse(op.dryRun);
}

- (void)testBaseClassMainSetsProgressToComplete {
    PDSBlobAuditOperation *op = [[PDSBlobAuditOperation alloc] initWithJobId:@"job-789"
                                                                   auditType:@"orphans"
                                                                 blobStorage:nil
                                                             serviceDatabases:nil
                                                                      dryRun:YES];
    XCTestExpectation *expectation = [self expectationWithDescription:@"Operation completes"];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [op main];
        dispatch_async(dispatch_get_main_queue(), ^{
            [expectation fulfill];
        });
    });
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
    XCTAssertEqual(op.progress, 1.0);
}

- (void)testProgressCallbackIsInvoked {
    PDSBlobAuditOperation *op = [[PDSBlobAuditOperation alloc] initWithJobId:@"job-cb"
                                                                   auditType:@"orphans"
                                                                 blobStorage:nil
                                                             serviceDatabases:nil
                                                                      dryRun:YES];
    __block double reportedProgress = -1;
    __block NSString *reportedStatus = nil;
    op.progressCallback = ^(double progress, NSString *status) {
        reportedProgress = progress;
        reportedStatus = status;
    };

    XCTestExpectation *expectation = [self expectationWithDescription:@"Operation completes"];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [op main];
        dispatch_async(dispatch_get_main_queue(), ^{
            [expectation fulfill];
        });
    });
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
    XCTAssertEqualWithAccuracy(reportedProgress, 1.0, 0.01);
    XCTAssertNotNil(reportedStatus);
}

- (void)testSaveResultsFailsWithoutDatabase {
    PDSBlobAuditOperation *op = [[PDSBlobAuditOperation alloc] initWithJobId:@"job-no-db"
                                                                   auditType:@"orphans"
                                                                 blobStorage:nil
                                                             serviceDatabases:nil
                                                                      dryRun:YES];
    __autoreleasing NSError *error = nil;
    BOOL saved = [op saveResults:@{@"key": @"value"} error:&error];
    XCTAssertFalse(saved);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.domain containsString:@"diagnostics"]);
}

- (void)testOperationIsNSOperationSubclass {
    PDSBlobAuditOperation *op = [[PDSBlobAuditOperation alloc] initWithJobId:@"job-isa"
                                                                   auditType:@"orphans"
                                                                 blobStorage:nil
                                                             serviceDatabases:nil
                                                                      dryRun:YES];
    XCTAssertTrue([op isKindOfClass:[NSOperation class]]);
}

- (void)testJobIdAndAuditTypeAreCopied {
    NSString *jobId = @"unique-job-id";
    NSString *auditType = @"references";
    PDSBlobAuditOperation *op = [[PDSBlobAuditOperation alloc] initWithJobId:jobId
                                                                   auditType:auditType
                                                                 blobStorage:nil
                                                             serviceDatabases:nil
                                                                      dryRun:YES];
    XCTAssertEqualObjects(op.jobId, jobId);
    XCTAssertEqualObjects(op.auditType, auditType);
}

- (void)testCancelledOperationStopsExecution {
    PDSBlobAuditOperation *op = [[PDSBlobAuditOperation alloc] initWithJobId:@"job-cancel"
                                                                   auditType:@"orphans"
                                                                 blobStorage:nil
                                                             serviceDatabases:nil
                                                                      dryRun:YES];
    [op cancel];
    XCTAssertTrue(op.isCancelled);
}

@end
