// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>

@interface KaszlakAdminUICompositionTests : XCTestCase
@end

@implementation KaszlakAdminUICompositionTests

- (NSString *)readSourceRelativeToTests:(NSString *)relativePath {
    NSString *testsDirectory = [@__FILE__ stringByDeletingLastPathComponent];
    // Tests/CLI → Tests → Garazyk
    NSString *garazykDirectory = [[testsDirectory stringByDeletingLastPathComponent]
        stringByDeletingLastPathComponent];
    NSString *sourcePath = [garazykDirectory stringByAppendingPathComponent:relativePath];
    return [NSString stringWithContentsOfFile:sourcePath encoding:NSUTF8StringEncoding error:nil];
}

- (void)testServeCommandStartsEmbeddedAdminUIHost {
    NSString *source = [self readSourceRelativeToTests:@"Sources/CLI/PDSCLIServeCommand.m"];
    XCTAssertNotNil(source);
    if (!source) {
        return;
    }

    XCTAssertTrue([source containsString:@"PDSAdminUIStartHost"]);
    XCTAssertTrue([source containsString:@"[adminUIHost stop]"]);
    XCTAssertTrue([source containsString:@"PDS admin UI available at"]);
}

- (void)testBootstrapComposesSixPDSOwnedPacksAndPasswordFallback {
    NSString *testsDirectory = [@__FILE__ stringByDeletingLastPathComponent];
    NSString *garazykDirectory = [[testsDirectory stringByDeletingLastPathComponent]
        stringByDeletingLastPathComponent];
    NSString *sourcePath =
        [garazykDirectory stringByAppendingPathComponent:@"Binaries/kaszlak/PDSAdminUIBootstrap.m"];
    NSString *source = [NSString stringWithContentsOfFile:sourcePath
                                                 encoding:NSUTF8StringEncoding
                                                    error:nil];
    XCTAssertNotNil(source, @"Expected bootstrap at %@", sourcePath);
    if (!source) {
        return;
    }

    XCTAssertTrue([source containsString:@"GZAdminUIHost"]);
    XCTAssertTrue([source containsString:@"GZAdminUIPDSPack"]);
    XCTAssertTrue([source containsString:@"GZAdminUIOzonePack"]);
    XCTAssertTrue([source containsString:@"GZAdminUISecurityPack"]);
    XCTAssertTrue([source containsString:@"GZAdminUIDataExplorerPack"]);
    XCTAssertTrue([source containsString:@"GZAdminUIMSTPack"]);
    XCTAssertTrue([source containsString:@"GZAdminUILabPack"]);
    XCTAssertTrue([source containsString:@"PDS_ADMIN_UI_PASSWORD"]);
    XCTAssertTrue([source containsString:@"PDS_ADMIN_PASSWORD_FILE"]);
    XCTAssertTrue([source containsString:@"PDS_ADMIN_PASSWORD"]);
    XCTAssertTrue([source containsString:@"PDS_ADMIN_UI_HOST"]);
    XCTAssertTrue([source containsString:@"PDS_ADMIN_UI_PORT"]);
    XCTAssertTrue([source containsString:@"adminConfig.serviceIdentifier = @\"pds\""]);
    XCTAssertTrue([source containsString:@"127.0.0.1"]);
    XCTAssertTrue([source containsString:@"2590"]);
}

- (void)testHostOmitsFleetTabsWhenServiceIdentifierIsSet {
    NSString *host = [self readSourceRelativeToTests:@"Sources/AdminUIServer/GZAdminUIHost.m"];
    NSString *backend = [self readSourceRelativeToTests:@"Sources/AdminUIServer/GZAdminUIBackendClient.m"];
    XCTAssertNotNil(host);
    XCTAssertNotNil(backend);
    if (!host || !backend) {
        return;
    }
    XCTAssertTrue([host containsString:@"omitFleetTabs"]);
    XCTAssertTrue([host containsString:@"isEqualToString:@\"overview\""]);
    XCTAssertTrue([host containsString:@"isEqualToString:@\"connections\""]);
    XCTAssertTrue([backend containsString:@"options.allowHTTP = YES"]);
    XCTAssertTrue([backend containsString:@"options.allowPrivateHosts = YES"]);
}

@end
