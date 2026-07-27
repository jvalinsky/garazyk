// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Compat/XCTest/XCTest.h"
#import <objc/runtime.h>
#include <stdlib.h>
#include <unistd.h>

@interface SecItemLinuxStoreTestObserver : NSObject <XCTestObservation>
@property (nonatomic, assign) NSUInteger failureCount;
@end

@implementation SecItemLinuxStoreTestObserver

- (void)testCaseWillStart:(XCTestCase *)testCase {
    fprintf(stderr, "RUN %s\n", testCase.name.UTF8String);
}

- (void)testCase:(XCTestCase *)testCase
didFailWithDescription:(NSString *)description
          inFile:(NSString *)filePath
          atLine:(NSUInteger)lineNumber {
    self.failureCount++;
    fprintf(stderr, "%s: %s\n", testCase.name.UTF8String, description.UTF8String);
}

@end

int main(void) {
    @autoreleasepool {
        setenv("PDS_RUNNING_TESTS", "1", 1);
        setenv("PDS_LINUX_KEYCHAIN_KEY", "test-linux-keychain-key-123", 1);
        NSString *dbPath = [NSTemporaryDirectory()
            stringByAppendingPathComponent:[NSString stringWithFormat:@"garazyk-keychain-%d.db", getpid()]];
        setenv("PDS_LINUX_KEYCHAIN_DB_PATH", dbPath.fileSystemRepresentation, 1);

        Class testClass = NSClassFromString(@"SecItemPersistenceTests");
        if (!testClass) {
            fprintf(stderr, "SecItemPersistenceTests was not linked\n");
            return 1;
        }

        XCTestSuite *suite = [XCTestSuite testSuiteWithName:@"SecItemLinuxStoreTests"];
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(testClass, &methodCount);
        for (unsigned int i = 0; i < methodCount; i++) {
            SEL selector = method_getName(methods[i]);
            if ([NSStringFromSelector(selector) hasPrefix:@"test"]) {
                XCTestCase *testCase = [[testClass alloc] initWithSelector:selector];
                [suite addTest:testCase];
            }
        }
        free(methods);

        SecItemLinuxStoreTestObserver *observer = [[SecItemLinuxStoreTestObserver alloc] init];
        [[XCTestObservationCenter sharedTestObservationCenter] addTestObserver:observer];
        @try {
            [suite performTest:nil];
        } @catch (NSException *exception) {
            observer.failureCount++;
            fprintf(stderr, "UNEXPECTED %s: %s\n", exception.name.UTF8String, exception.reason.UTF8String);
        }
        [[XCTestObservationCenter sharedTestObservationCenter] removeTestObserver:observer];

        fprintf(stderr, "SecItemLinuxStoreTests: %lu test(s), %lu failure(s)\n",
                (unsigned long)suite.testCaseCount, (unsigned long)observer.failureCount);
        return observer.failureCount == 0 ? 0 : 1;
    }
}
