/*
 * UIAPIClient.j
 * CappuccinoUI
 */

@import <Foundation/Foundation.j>

@implementation UIAPIClient : CPObject
{
    CPDictionary _endpointBases @accessors(property=endpointBases);
}

- (id)init
{
    var endpointBases = [CPMutableDictionary dictionary];
    [endpointBases setObject:@"/api/pds" forKey:@"explore"];
    [endpointBases setObject:@"/admin" forKey:@"admin"];
    [endpointBases setObject:@"/api/mst" forKey:@"mst"];
    [endpointBases setObject:@"/xrpc" forKey:@"xrpc"];
    [endpointBases setObject:@"/oauth" forKey:@"oauth"];
    [endpointBases setObject:@"/oauth-demo" forKey:@"oauthDemo"];
    return [self initWithEndpointBases:endpointBases];
}

- (id)initWithEndpointBases:(CPDictionary)endpointBases
{
    self = [super init];
    if (self)
    {
        _endpointBases = endpointBases;
    }
    return self;
}

- (CPString)baseURLForEndpointGroup:(CPString)group
{
    var baseURL = [_endpointBases objectForKey:group];
    if (!baseURL)
        baseURL = [_endpointBases objectForKey:@"explore"];
    return baseURL;
}

- (CPString)queryStringFromParams:(id)queryParams
{
    if (!queryParams)
        return @"";

    var pairs = [],
        keys = nil,
        i = 0;

    if (queryParams.isa && [queryParams respondsToSelector:@selector(allKeys)])
        keys = [queryParams allKeys];

    if (keys)
    {
        for (i = 0; i < [keys count]; i++)
        {
            var key = [keys objectAtIndex:i],
                value = [queryParams objectForKey:key];

            if (value === nil || value === undefined)
                continue;

            pairs.push(encodeURIComponent(String(key)) + "=" + encodeURIComponent(String(value)));
        }
    }
    else
    {
        for (var prop in queryParams)
        {
            if (!queryParams.hasOwnProperty(prop))
                continue;

            var propValue = queryParams[prop];
            if (propValue === nil || propValue === undefined)
                continue;

            pairs.push(encodeURIComponent(String(prop)) + "=" + encodeURIComponent(String(propValue)));
        }
    }

    return pairs.join("&");
}

- (CPString)URLStringForPath:(CPString)path endpointGroup:(CPString)group queryParams:(id)queryParams
{
    var normalizedPath = path || @"";
    if (normalizedPath.length > 0 && ![normalizedPath hasPrefix:@"/"])
        normalizedPath = [@"/" stringByAppendingString:normalizedPath];

    var baseURL = [self baseURLForEndpointGroup:group],
        urlString = [baseURL stringByAppendingString:normalizedPath],
        queryString = [self queryStringFromParams:queryParams];

    if (queryString.length > 0)
        urlString = [urlString stringByAppendingFormat:@"?%@", queryString];

    return urlString;
}

- (CPURLRequest)requestWithPath:(CPString)path endpointGroup:(CPString)group method:(CPString)method
{
    var urlString = [self URLStringForPath:path endpointGroup:group queryParams:nil];
    var request = [CPURLRequest requestWithURL:[CPURL URLWithString:urlString]];
    [request setHTTPMethod:(method || @"GET")];
    return request;
}

- (CPURLRequest)requestWithPath:(CPString)path endpointGroup:(CPString)group
{
    return [self requestWithPath:path endpointGroup:group method:@"GET"];
}

- (CPURLRequest)requestWithPath:(CPString)path
{
    // Backward-compatible default to explore API group.
    return [self requestWithPath:path endpointGroup:@"explore" method:@"GET"];
}

- (void)requestJSONWithPath:(CPString)path
              endpointGroup:(CPString)group
                     method:(CPString)method
                queryParams:(id)queryParams
                 bodyObject:(id)bodyObject
                 completion:(Function)completion
{
    var httpMethod = method || @"GET",
        urlString = [self URLStringForPath:path endpointGroup:group queryParams:queryParams],
        xhr = new XMLHttpRequest(),
        bodyJSON = nil;

    xhr.open(String(httpMethod), String(urlString), YES);
    xhr.setRequestHeader("Accept", "application/json");

    if (bodyObject !== nil && bodyObject !== undefined)
    {
        xhr.setRequestHeader("Content-Type", "application/json");
        bodyJSON = JSON.stringify(bodyObject);
    }

    xhr.onreadystatechange = function()
    {
        if (xhr.readyState !== 4)
            return;

        var statusCode = xhr.status || 0,
            responseText = xhr.responseText || "",
            payload = nil,
            parseError = nil;

        if (responseText.length > 0)
        {
            try
            {
                payload = JSON.parse(responseText);
            }
            catch (e)
            {
                if (statusCode >= 200 && statusCode < 300)
                    payload = {rawText: responseText};
                else
                    parseError = "Failed to parse JSON response";
            }
        }

        if (!payload && responseText.length === 0)
            payload = {};

        var errorMessage = nil;
        if (statusCode < 200 || statusCode >= 300)
            errorMessage = (payload && payload.error) ? payload.error : ("HTTP " + statusCode);
        else if (parseError)
            errorMessage = parseError;

        if (completion)
            completion(statusCode, payload, errorMessage);
    };

    xhr.onerror = function()
    {
        if (completion)
            completion(0, nil, "Network error");
    };

    xhr.send(bodyJSON);
}

- (void)getJSONWithPath:(CPString)path
          endpointGroup:(CPString)group
            queryParams:(id)queryParams
             completion:(Function)completion
{
    [self requestJSONWithPath:path
                endpointGroup:group
                       method:@"GET"
                  queryParams:queryParams
                   bodyObject:nil
                   completion:completion];
}

- (void)getJSONWithPath:(CPString)path queryParams:(id)queryParams completion:(Function)completion
{
    [self getJSONWithPath:path endpointGroup:@"explore" queryParams:queryParams completion:completion];
}

@end
