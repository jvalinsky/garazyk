/*
 * UIAPIClientTest.j
 * CappuccinoUI Tests
 */

@import <OJTest/OJTest.j>
@import <Foundation/Foundation.j>
@import "../UIAPIClient.j"

@implementation UIAPIClientTest : OJTestCase
{
    UIAPIClient _client;
}

- (void)setUp
{
    _client = [[UIAPIClient alloc] init];
}

// ---------------------------------------------------------------------------
// baseURLForEndpointGroup:
// ---------------------------------------------------------------------------

- (void)testBaseURLForExploreGroup
{
    [self assert:[_client baseURLForEndpointGroup:@"explore"] equals:@"/api/pds"];
}

- (void)testBaseURLForAdminGroup
{
    [self assert:[_client baseURLForEndpointGroup:@"admin"] equals:@"/admin"];
}

- (void)testBaseURLForMSTGroup
{
    [self assert:[_client baseURLForEndpointGroup:@"mst"] equals:@"/api/mst"];
}

- (void)testBaseURLForXRPCGroup
{
    [self assert:[_client baseURLForEndpointGroup:@"xrpc"] equals:@"/xrpc"];
}

- (void)testBaseURLForOAuthGroup
{
    [self assert:[_client baseURLForEndpointGroup:@"oauth"] equals:@"/oauth"];
}

- (void)testBaseURLForOAuthDemoGroup
{
    [self assert:[_client baseURLForEndpointGroup:@"oauthDemo"] equals:@"/oauth-demo"];
}

- (void)testBaseURLFallsBackToExploreForUnknownGroup
{
    [self assert:[_client baseURLForEndpointGroup:@"nonexistent"] equals:@"/api/pds"
         message:@"Unknown group should fall back to explore base URL"];
}

- (void)testBaseURLFallsBackToExploreForEmptyGroup
{
    [self assert:[_client baseURLForEndpointGroup:@""] equals:@"/api/pds"
         message:@"Empty group should fall back to explore base URL"];
}

// ---------------------------------------------------------------------------
// queryStringFromParams:
// ---------------------------------------------------------------------------

- (void)testQueryStringFromNilParamsIsEmpty
{
    [self assert:[_client queryStringFromParams:nil] equals:@""
         message:@"nil params should produce empty query string"];
}

- (void)testQueryStringFromSingleKeyCPDictionary
{
    var params = [CPDictionary dictionaryWithObject:@"alice" forKey:@"handle"];
    [self assert:[_client queryStringFromParams:params] equals:@"handle=alice"];
}

- (void)testQueryStringFromSingleKeyJSObject
{
    [self assert:[_client queryStringFromParams:{limit: "10"}] equals:@"limit=10"];
}

- (void)testQueryStringEncodesSpecialCharacters
{
    var params = [CPDictionary dictionaryWithObject:@"hello world" forKey:@"q"];
    var result = [_client queryStringFromParams:params];
    [self assert:result equals:@"q=hello%20world"
         message:@"Spaces in values should be percent-encoded"];
}

- (void)testQueryStringEncodesKeyWithSpecialCharacters
{
    var params = [CPDictionary dictionaryWithObject:@"value" forKey:@"my key"];
    var result = [_client queryStringFromParams:params];
    [self assert:result equals:@"my%20key=value"
         message:@"Spaces in keys should be percent-encoded"];
}

- (void)testQueryStringSkipsNilValues
{
    var params = [CPMutableDictionary dictionary];
    [params setObject:@"alice" forKey:@"handle"];
    [params setObject:nil forKey:@"token"];
    var result = [_client queryStringFromParams:params];
    [self assertTrue:(result.indexOf("token") < 0)
             message:@"nil values should be omitted from query string"];
    [self assertTrue:(result.indexOf("handle=alice") >= 0)
             message:@"Non-nil values should appear in query string"];
}

// ---------------------------------------------------------------------------
// URLStringForPath:endpointGroup:queryParams:
// ---------------------------------------------------------------------------

- (void)testURLStringForPathWithLeadingSlash
{
    var url = [_client URLStringForPath:@"/accounts" endpointGroup:@"mst" queryParams:nil];
    [self assert:url equals:@"/api/mst/accounts"];
}

- (void)testURLStringForPathWithoutLeadingSlash
{
    var url = [_client URLStringForPath:@"accounts" endpointGroup:@"mst" queryParams:nil];
    [self assert:url equals:@"/api/mst/accounts"
         message:@"Missing leading slash should be prepended automatically"];
}

- (void)testURLStringForEmptyPath
{
    var url = [_client URLStringForPath:@"" endpointGroup:@"explore" queryParams:nil];
    [self assert:url equals:@"/api/pds"];
}

- (void)testURLStringForNilPath
{
    var url = [_client URLStringForPath:nil endpointGroup:@"explore" queryParams:nil];
    [self assert:url equals:@"/api/pds"];
}

- (void)testURLStringAppendsQueryString
{
    var url = [_client URLStringForPath:@"/records" endpointGroup:@"xrpc" queryParams:{limit: "10"}];
    [self assert:url equals:@"/xrpc/records?limit=10"];
}

- (void)testURLStringWithQueryParamsUsesQuestionMark
{
    var params = [CPDictionary dictionaryWithObject:@"alice" forKey:@"repo"];
    var url = [_client URLStringForPath:@"/listRecords" endpointGroup:@"xrpc" queryParams:params];
    [self assertTrue:(url.indexOf("?") >= 0)
             message:@"Query string should be separated by '?'"];
    [self assertTrue:(url.indexOf("repo=alice") >= 0)];
}

- (void)testURLStringWithNilQueryParamsHasNoQuestionMark
{
    var url = [_client URLStringForPath:@"/records" endpointGroup:@"xrpc" queryParams:nil];
    [self assertTrue:(url.indexOf("?") < 0)
             message:@"nil queryParams should produce no question mark"];
}

// ---------------------------------------------------------------------------
// initWithEndpointBases: (custom bases)
// ---------------------------------------------------------------------------

- (void)testCustomEndpointBases
{
    var bases = [CPMutableDictionary dictionary];
    [bases setObject:@"https://api.example.com/v1" forKey:@"explore"];
    var customClient = [[UIAPIClient alloc] initWithEndpointBases:bases];
    [self assert:[customClient baseURLForEndpointGroup:@"explore"]
               equals:@"https://api.example.com/v1"];
}

@end
