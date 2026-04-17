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
    [endpointBases setObject:@"/api/relay" forKey:@"relay"];
    [endpointBases setObject:@"" forKey:@"plc"]; // PLC endpoints at root
    [endpointBases setObject:@"" forKey:@"appview"]; // AppView admin at /admin/backfill/*
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
    if (!baseURL)
        baseURL = @"";
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

// Convenience method for simple fetch
- (void)fetch:(CPString)method path:(CPString)path params:(id)params completion:(Function)completion
{
    var requestPath = path || @"",
        group = @"explore",
        httpMethod = String(method || "GET").toUpperCase(),
        relayPrefix = @"/api/relay",
        queryParams = nil,
        bodyObject = nil;

    // Auto-detect endpoint group based on path.
    if ([requestPath hasPrefix:@"/_"] || [requestPath hasPrefix:@"/did:"]) {
        group = @"plc";
    } else if ([requestPath hasPrefix:relayPrefix]) {
        group = @"relay";

        // Allow callers to pass fully-qualified relay API paths.
        requestPath = [requestPath substringFromIndex:[relayPrefix length]];
        if (!requestPath || requestPath.length === 0)
            requestPath = @"/";
    }

    var methodStr = String(httpMethod || "GET");
    if (methodStr === "GET" || methodStr === "DELETE")
        queryParams = params;
    else
        bodyObject = params;

    [self requestJSONWithPath:requestPath
                endpointGroup:group
                       method:httpMethod
                  queryParams:queryParams
                   bodyObject:bodyObject
                   completion:function(statusCode, payload, errorMessage)
                   {
                       if (!completion)
                           return;

                       if (errorMessage || statusCode < 200 || statusCode >= 300)
                       {
                           var message = errorMessage || ("HTTP " + statusCode);
                           completion(nil, {localizedDescription: message, statusCode: statusCode, payload: payload});
                           return;
                       }

                       completion(payload, nil);
                   }];
}

// Fetch raw text (for Prometheus metrics)
- (void)fetchRaw:(CPString)method path:(CPString)path params:(id)params completion:(Function)completion
{
    var group = @"plc";
    if ([path hasPrefix:@"/api/relay"]) {
        group = @"relay";
    }

    var urlString = [self URLStringForPath:path endpointGroup:group queryParams:params],
        xhr = new XMLHttpRequest();

    xhr.open(String(method), String(urlString), YES);
    xhr.setRequestHeader("Accept", "*/*");

    xhr.onreadystatechange = function()
    {
        if (xhr.readyState !== 4)
            return;

        var statusCode = xhr.status || 0,
            responseText = xhr.responseText || "";

        if (completion)
            completion(responseText, statusCode >= 400 ? {localizedDescription: "HTTP " + statusCode} : nil);
    };

    xhr.onerror = function()
    {
        if (completion)
            completion(nil, {localizedDescription: "Network error"});
    };

    xhr.send();
}

@end
