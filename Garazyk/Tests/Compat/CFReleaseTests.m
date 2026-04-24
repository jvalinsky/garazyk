#import <XCTest/XCTest.h>
#import "Compat/PlatformShims/CoreFoundation/CFRelease.h"

@interface CFReleaseTests : XCTestCase
@end

@implementation CFReleaseTests

- (void)testCFReleaseNullIsSafe {
    CFStringRef nullRef = NULL;
    CF_RELEASE(nullRef);
    XCTAssertNil((__bridge NSString *)nullRef);
}

- (void)testCFReleaseZerosPointer {
    CFStringRef s = (__bridge CFStringRef)@"hello";
    CF_RELEASE(s);
    XCTAssertEqual(s, NULL);
}

- (void)testCFReleaseTollFreeBridged {
    NSString *str = @"test string";
    CFStringRef cfStr = (__bridge CFStringRef)str;
    XCTAssertNotEqual(cfStr, NULL);
    CF_RELEASE(cfStr);
    XCTAssertEqual(cfStr, NULL);
}

#if !defined(__APPLE__)
- (void)testSecKeyReleaseNullIsSafe {
    SecKeyRef nullRef = NULL;
    SecKeyRelease(nullRef);
    XCTAssertEqual(nullRef, NULL);
}
#endif

@end
