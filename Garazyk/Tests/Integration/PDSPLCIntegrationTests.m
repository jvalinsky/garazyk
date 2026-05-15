// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "App/PDSController.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Database/PDSDatabase.h"
#import "Database/Pool/DatabasePool.h"

@interface PDSPLCIntegrationTests : XCTestCase

@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) PDSController *controller;
@property (nonatomic, strong) NSURL *tempURL;
@property (nonatomic, strong) NSTask *plcTask;
@property (nonatomic, assign) NSUInteger plcPort;

@end

@implementation PDSPLCIntegrationTests

- (void)setUp {
    [super setUp];

    self.plcPort = 2582 + (arc4random_uniform(100)); // Use a random port to avoid conflicts
    
    // Start atproto-plc
    self.plcTask = [[NSTask alloc] init];
    // Find the binary path
    NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
    NSArray *candidates = @[
        @"build/bin/atproto-plc",
        @"bin/atproto-plc",
        @"../build/bin/atproto-plc",
        @"build/Debug/atproto-plc"
    ];

    NSString *binaryPath = nil;
    for (NSString *candidate in candidates) {
        NSString *path = [cwd stringByAppendingPathComponent:candidate];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            binaryPath = path;
            break;
        }
    }
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:binaryPath]) {
        self.plcTask = nil;
        XCTSkip(@"atproto-plc binary not found (searched: %@); build the atproto-plc target to run this test",
                [candidates componentsJoinedByString:@", "]);
        return;
    }

    self.plcTask.launchPath = binaryPath;
    self.plcTask.arguments = @[@"--port", [NSString stringWithFormat:@"%lu", (unsigned long)self.plcPort]];
    
    // Redirect output to a file for debugging
    NSString *logPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"atproto-plc.log"];
    [[NSFileManager defaultManager] removeItemAtPath:logPath error:nil];
    [[NSFileManager defaultManager] createFileAtPath:logPath contents:nil attributes:nil];
    self.plcTask.standardOutput = [NSFileHandle fileHandleForWritingAtPath:logPath];
    self.plcTask.standardError = [NSFileHandle fileHandleForWritingAtPath:logPath];
    
    NSError *error = nil;
    if (@available(macOS 10.13, *)) {
        if (![self.plcTask launchAndReturnError:&error]) {
            self.plcTask = nil;
            XCTSkip(@"Failed to launch atproto-plc: %@", error);
            return;
        }
    } else {
        [self.plcTask launch];
    }
    
    // Give it a moment to start
    [NSThread sleepForTimeInterval:1.0];

    self.tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    self.tempURL = [self.tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    self.tempURL = [self.tempURL URLByAppendingPathExtension:@"db"];

    self.database = [PDSDatabase databaseAtURL:self.tempURL];
    [self.database openWithError:nil];

    self.controller = [[PDSController alloc] initWithDirectory:[self.tempURL.path stringByDeletingLastPathComponent]
                                                serviceMaxSize:100
                                              userDatabaseSize:1000];
    
    // Configure controller to use our test PLC server
    self.controller.plcServerURL = [NSString stringWithFormat:@"http://127.0.0.1:%lu", (unsigned long)self.plcPort];
    
    ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
    config.plcURL = self.controller.plcServerURL;

    // If the environment can't open listeners (EPERM) or can't reach localhost, skip.
    NSURL *probeURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/", self.controller.plcServerURL]];
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    __block NSURLResponse *probeResponse = nil;
    __block NSError *probeError = nil;
    [[[NSURLSession sharedSession] dataTaskWithURL:probeURL completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        (void)data;
        probeResponse = response;
        probeError = error;
        dispatch_semaphore_signal(sema);
    }] resume];
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)));

    if (probeResponse == nil || probeError != nil) {
        XCTSkip(@"Skipping PLC integration test: local PLC server not reachable (%@)", probeError);
    }
}

- (void)tearDown {
    if (self.plcTask && self.plcTask.isRunning) {
        [self.plcTask terminate];
    }
    [self.database close];
    
    ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
    config.plcURL = @"mock";
    
    [super tearDown];
}

- (void)testAccountCreationWithRealPLC {
    NSError *error = nil;
    NSString *handle = [NSString stringWithFormat:@"test-%u.test", arc4random_uniform(10000)];
    NSDictionary *accountResult = [self.controller createAccountForEmail:@"test@example.com"
                                                               password:@"testpass123"
                                                                handle:handle
                                                                   did:nil
                                                                 error:&error];

    XCTAssertNotNil(accountResult, @"Account should be created: %@", error);
    XCTAssertNil(error, @"No error should occur: %@", error);
    if (!accountResult || error) {
        return;
    }

    NSString *did = accountResult[@"did"];
    XCTAssertTrue([did hasPrefix:@"did:plc:"], @"DID should be a PLC DID, got %@", did);
    if (![did hasPrefix:@"did:plc:"]) {
        return;
    }

    // Verify DID can be resolved via PLC server directly
    NSURL *resolveURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/%@", self.controller.plcServerURL, did]];
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    __block NSData *responseData = nil;
    __block NSHTTPURLResponse *httpResponse = nil;
    
    [[[NSURLSession sharedSession] dataTaskWithURL:resolveURL completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        responseData = data;
        httpResponse = (NSHTTPURLResponse *)response;
        dispatch_semaphore_signal(sema);
    }] resume];
    
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)));
    
    XCTAssertNotNil(httpResponse);
    if (httpResponse.statusCode != 200) {
        NSString *errorBody = responseData ? [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] : @"";
        XCTFail(@"PLC resolution failed with status %ld: %@", (long)httpResponse.statusCode, errorBody);
        return;
    }
    XCTAssertEqual(httpResponse.statusCode, 200, @"PLC resolution should succeed");
    
    NSDictionary *didDoc = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:nil];
    XCTAssertNotNil(didDoc);
    XCTAssertEqualObjects(didDoc[@"id"], did);
    XCTAssertNotNil(didDoc[@"verificationMethod"]);
    XCTAssertNotNil(didDoc[@"service"]);
    
    // Also verify log endpoint
    NSURL *logURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/%@/log", self.controller.plcServerURL, did]];
    sema = dispatch_semaphore_create(0);
    responseData = nil;
    httpResponse = nil;
    
    [[[NSURLSession sharedSession] dataTaskWithURL:logURL completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        responseData = data;
        httpResponse = (NSHTTPURLResponse *)response;
        dispatch_semaphore_signal(sema);
    }] resume];
    
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)));
    XCTAssertEqual(httpResponse.statusCode, 200);
    
    NSArray *ops = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:nil];
    XCTAssertNotNil(ops);
    XCTAssertGreaterThan(ops.count, 0);
    if (ops.count == 0) {
        return;
    }
    
    NSDictionary *genesisOp = ops[0];
    XCTAssertEqualObjects(genesisOp[@"type"], @"plc_operation");
}

@end
