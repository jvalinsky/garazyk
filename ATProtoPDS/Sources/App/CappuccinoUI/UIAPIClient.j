/*
 * UIAPIClient.j
 * CappuccinoUI
 */

@import <Foundation/Foundation.j>

@implementation UIAPIClient : CPObject
{
    CPString _baseURL @accessors(property=baseURL);
}

- (id)init
{
    return [self initWithBaseURL:@"/api/v2/ui"];
}

- (id)initWithBaseURL:(CPString)baseURL
{
    self = [super init];
    if (self)
    {
        _baseURL = baseURL;
    }
    return self;
}

- (CPURLRequest)requestWithPath:(CPString)path
{
    var urlString = [_baseURL stringByAppendingString:path];
    var request = [CPURLRequest requestWithURL:[CPURL URLWithString:urlString]];
    [request setHTTPMethod:@"GET"];
    return request;
}

@end
