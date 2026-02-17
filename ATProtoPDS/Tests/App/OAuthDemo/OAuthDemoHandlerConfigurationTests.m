#import <XCTest/XCTest.h>
#import "Network/PDSHttpServerBuilder.h"
#import "App/OAuthDemo/OAuthDemoHandler.h"
#import "App/PDSController.h"

@interface OAuthDemoHandlerConfigurationTests : XCTestCase
@end

@implementation OAuthDemoHandlerConfigurationTests

- (void)setUp {
    [super setUp];
    // Reset singleton state if possible or just be careful.
    // Since we can't easily reset the singleton, we'll verify the *interaction* mostly.
    // However, the builder sets the property on the singleton.
}

- (void)testBuilderSetsDataDirectoryOnOAuthDemoHandler {
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
    NSString *testDir = @"/tmp/test-data-dir";
    builder.dataDirectory = testDir;
    
    // We can't verify the side effect on the singleton directly if we can't read it back efficiently or if it's already set.
    // But OAuthDemoHandler has a `dataDirectory` property (private in .m, but accessible via KVC or we can expose it for testing).
    // Let's check if we can access it via KVC.
    
    // Create a server to trigger the configuration
    NSError *error = nil;
    [builder buildWithError:&error];
    
    OAuthDemoHandler *handler = [OAuthDemoHandler sharedHandler];
    NSString *handlerDataDir = [handler valueForKey:@"dataDirectory"];
    
    XCTAssertEqualObjects(handlerDataDir, testDir, @"Builder should set dataDirectory on OAuthDemoHandler");
}



@end
