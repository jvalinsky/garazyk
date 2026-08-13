// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "AdminUIServer/UITileLoadingHost.h"
#import "AdminUIServer/UITileExecutionPolicy.h"
#import "Network/HttpResponse.h"

@interface UITileLoadingHostTests : XCTestCase
@end

@implementation UITileLoadingHostTests

- (void)testLoadHostDetection {
    XCTAssertTrue(GZAdminUITileIsLoadHost(@"load.example.test", @"example.test"));
    XCTAssertTrue(GZAdminUITileIsLoadHost(@"LOAD.Example.Test", @".example.test"));
    XCTAssertFalse(GZAdminUITileIsLoadHost(@"example.test", @"example.test"));
    XCTAssertFalse(GZAdminUITileIsLoadHost(@"abc.example.test", @"example.test"));
}

- (void)testUniqueOriginHostDetection {
    XCTAssertTrue(GZAdminUITileIsUniqueOriginHost(@"abcdefghijklmnopqrst.example.test",
                                                   @"example.test"));
    XCTAssertFalse(GZAdminUITileIsUniqueOriginHost(@"abcdefghijklmnopqrs.example.test",
                                                    @"example.test")); // 19 letters
    XCTAssertFalse(GZAdminUITileIsUniqueOriginHost(@"abcdefghijklmnopqrstu.example.test",
                                                    @"example.test")); // 21
    // Host comparison is case-insensitive (labels lowercased).
    XCTAssertTrue(GZAdminUITileIsUniqueOriginHost(@"ABCDEFGHIJKLMNOPQRST.example.test",
                                                   @"example.test"));
    XCTAssertFalse(GZAdminUITileIsUniqueOriginHost(@"load.example.test", @"example.test"));
}

- (void)testRedirectURLShape {
    NSString *url = GZAdminUITileUniqueOriginRedirectURL(@"https", @"example.test",
                                                         @"/.well-known/web-tiles/");
    XCTAssertTrue([url hasPrefix:@"https://"]);
    XCTAssertTrue([url hasSuffix:@".example.test/.well-known/web-tiles/"]);
    NSURL *parsed = [NSURL URLWithString:url];
    NSString *host = parsed.host;
    NSString *label = [host substringToIndex:host.length - @".example.test".length];
    XCTAssertEqual(label.length, (NSUInteger)20);
    XCTAssertTrue(GZAdminUITileIsUniqueOriginHost(host, @"example.test"));
}

- (void)testUniqueOriginHeadersIncludePolicyAndServiceWorkerAllowed {
    ATProtoHttpResponse *response = [[ATProtoHttpResponse alloc] init];
    GZAdminUITileApplyUniqueOriginHeaders(response);
    XCTAssertEqualObjects([response headerForKey:@"service-worker-allowed"], @"/");
    XCTAssertEqualObjects([response headerForKey:@"cross-origin-opener-policy"], @"same-origin");
    XCTAssertEqualObjects([response headerForKey:@"content-security-policy"],
                          GZAdminUITileExecutionContentSecurityPolicy());
}

- (void)testShuttleHTMLIsPresent {
    NSString *html = GZAdminUITileShuttleHTML();
    XCTAssertTrue([html containsString:@"<!DOCTYPE html>"]);
    XCTAssertTrue([html containsString:@"Web Tile Shuttle"]);
    XCTAssertTrue([html containsString:@"/.well-known/web-tiles/shuttle.js"]);
}

- (void)testShuttleAndWorkerScriptsRegisterServiceWorker {
    NSString *shuttle = GZAdminUITileShuttleJavaScript();
    XCTAssertTrue([shuttle containsString:@"navigator.serviceWorker.register"]);
    XCTAssertTrue([shuttle containsString:@"/.well-known/web-tiles/worker.js"]);
    NSString *worker = GZAdminUITileServiceWorkerJavaScript();
    XCTAssertTrue([worker containsString:@"addEventListener('fetch'"]);
    XCTAssertTrue([worker containsString:@"web-tiles"]);
}

- (void)testTrustedEmbedOriginAcceptsUniqueAndLoadHosts {
    XCTAssertTrue(GZAdminUITileIsTrustedEmbedOrigin(@"https://abcdefghijklmnopqrst.example.test",
                                                     @"example.test"));
    XCTAssertTrue(GZAdminUITileIsTrustedEmbedOrigin(@"http://load.example.test",
                                                     @"example.test"));
    XCTAssertFalse(GZAdminUITileIsTrustedEmbedOrigin(@"https://evil.example.test",
                                                      @"example.test"));
    XCTAssertFalse(GZAdminUITileIsTrustedEmbedOrigin(@"https://example.test",
                                                      @"example.test"));
}

- (void)testUniqueOriginURLBuilder {
    NSString *url = GZAdminUITileUniqueOriginURL(@"https", @"example.test", @"abcdefghijklmnopqrst");
    XCTAssertEqualObjects(url, @"https://abcdefghijklmnopqrst.example.test");
}

@end
