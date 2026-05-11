// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSDatabaseTestFixture.h"
#import "PDSDatabaseIntegrationTestUtilities.h"
#import "Database/PDSDatabase.h"

@interface PDSDatabaseTestFixture ()
@property (nonatomic, readwrite, nullable) PDSDatabase *database;
@end

@implementation PDSDatabaseTestFixture

- (instancetype)initWithTestName:(NSString *)testName {
    self = [super init];
    if (self) {
        _testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"PDSDatabaseTest_%@", testName]];
        _databaseURL = [self createTemporaryDatabaseURL];
    }
    return self;
}

- (BOOL)setupDatabaseWithError:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm createDirectoryAtPath:self.testDirectory withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }
    
    self.database = [PDSDatabase databaseAtURL:self.databaseURL];
    return [self.database openWithError:error];
}

- (BOOL)teardownDatabaseWithError:(NSError **)error {
    if (self.database) {
        [self.database close];
        self.database = nil;
    }
    
    NSFileManager *fm = [NSFileManager defaultManager];
    return [fm removeItemAtPath:self.testDirectory error:error];
}

- (NSURL *)createTemporaryDatabaseURL {
    return [NSURL fileURLWithPath:[self.testDirectory stringByAppendingPathComponent:@"test.db"]];
}

- (nullable PDSDatabase *)createInMemoryDatabaseWithError:(NSError **)error {
    return [PDSDatabaseIntegrationTestUtilities createInMemoryDatabaseWithError:error];
}

@end
