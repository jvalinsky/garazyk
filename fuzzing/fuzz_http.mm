//
//  fuzz_http.mm
//  Comprehensive HTTP fuzzing harness for ATProto PDS
//
//  Tests:
//  1. HTTP request parsing (various methods, paths, headers)
//  2. HTTP response serialization
//  3. Query string parsing
//  4. JSON body parsing
//  5. Multipart form data
//  6. Edge cases and malformed inputs
//

#import <Foundation/Foundation.h>
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size == 0 || size > 100000) {
        return 0;
    }

    @autoreleasepool {
                NSData *inputData = [NSData dataWithBytes:data length:size];

        // Test 1: Basic HTTP request parsing
        HttpRequest *request = [HttpRequest requestWithData:inputData];

        HttpMethod method = request.method;
        NSString *methodString = request.methodString;
        NSString *path = request.path;
        NSString *queryString = request.queryString;
        NSString *version = request.version;
        NSDictionary *headers = request.headers;
        NSData *body = request.body;
        NSDictionary *queryParams = request.queryParams;
        NSDictionary *jsonBody = request.jsonBody;

        (void)method;
        (void)methodString;
        (void)queryString;
        (void)queryParams;
        (void)jsonBody;

                // Test 2: HTTP response serialization
        HttpResponse *response = [[HttpResponse alloc] init];
        response.statusCode = HttpStatusOK;
        response.statusMessage = @"OK";
        response.contentType = @"application/json";
        [response setHeader:@"application/json" forKey:@"Content-Type"];
        [response setHeader:@"fuzz-test" forKey:@"X-Request-ID"];
        response.body = body;

        NSData *serialized = [response serialize];
        (void)serialized;

                // Test 3: Various status codes
        NSArray *statusCodes = @[
            @(HttpStatusOK),
            @(HttpStatusCreated),
            @(HttpStatusNoContent),
            @(HttpStatusBadRequest),
            @(HttpStatusUnauthorized),
            @(HttpStatusForbidden),
            @(HttpStatusNotFound),
            @(HttpStatusInternalServerError),
            @(HttpStatusServiceUnavailable)
        ];

        for (NSNumber *statusNum in statusCodes) {
            HttpResponse *statusResponse = [[HttpResponse alloc] init];
            statusResponse.statusCode = (HttpStatusCode)[statusNum integerValue];
            statusResponse.statusMessage = @"Test";
            statusResponse.contentType = @"text/plain";
            NSData *statusSerialized = [statusResponse serialize];
            (void)statusSerialized;
        }

                // Test 4: Header access methods
        if (headers.count > 0) {
            for (NSString *key in headers) {
                NSString *value = [request headerForKey:key];
                (void)value;
            }
        }

                // Test 5: Query parameter access
        if (queryParams.count > 0) {
            for (NSString *key in queryParams) {
                NSString *value = [request queryParamForKey:key];
                (void)value;
            }
        }

                // Test 6: Partial request parsing
        if (size > 0) {
            NSUInteger partialLength = MIN(size, 50);
            NSData *partialData = [NSData dataWithBytes:data length:partialLength];
            HttpRequest *partialRequest = [HttpRequest requestWithData:partialData];
            (void)partialRequest;
        }

                // Test 7: Different encoding attempts
        NSString *rawRequest = [[NSString alloc] initWithData:inputData
                                                    encoding:NSUTF8StringEncoding];
        if (!rawRequest) {
            rawRequest = [[NSString alloc] initWithData:inputData
                                               encoding:NSISOLatin1StringEncoding];
        }

        if (rawRequest) {
            NSData *utf8Data = [rawRequest dataUsingEncoding:NSUTF8StringEncoding];
            if (utf8Data) {
                HttpRequest *utf8Request = [HttpRequest requestWithData:utf8Data];
                (void)utf8Request;
            }
        }

                // Test 8: Malformed JSON body handling
        if (body.length > 0) {
            HttpRequest *jsonRequest = [[HttpRequest alloc] initWithMethod:method
                                                              methodString:methodString
                                                                    path:path
                                                             queryString:queryString
                                                              queryParams:queryParams
                                                                  version:version
                                                                  headers:headers
                                                                     body:body
                                                            remoteAddress:nil];
            (void)jsonRequest;
        }

                // Test 9: Empty and minimal requests
        NSData *emptyData = [NSData data];
        HttpRequest *emptyRequest = [HttpRequest requestWithData:emptyData];
        (void)emptyRequest;

        NSData *minimalData = [@"GET / HTTP/1.1\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
        HttpRequest *minimalRequest = [HttpRequest requestWithData:minimalData];
        (void)minimalRequest;

                // Test 10: Large body handling
        if (size > 1000 && size < 50000) {
            HttpRequest *largeRequest = [HttpRequest requestWithData:inputData];
            if (largeRequest.body.length > 0) {
                NSDictionary *largeJson = largeRequest.jsonBody;
                (void)largeJson;
            }
        }

                // Test 11: Various Content-Types
        NSArray *contentTypes = @[
            @"application/json",
            @"application/cbor",
            @"text/plain",
            @"text/html",
            @"application/x-www-form-urlencoded",
            @"multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW"
        ];

        for (NSString *contentType in contentTypes) {
            HttpResponse *typeResponse = [[HttpResponse alloc] init];
            typeResponse.statusCode = HttpStatusOK;
            typeResponse.contentType = contentType;
            NSData *typeSerialized = [typeResponse serialize];
            (void)typeSerialized;
        }

                // Test 12: Header injection attempts (should be sanitized)
        NSString *injectionHeader = @"Header-Value\r\nInject: test\r\n";
        HttpResponse *injectResponse = [[HttpResponse alloc] init];
        injectResponse.statusCode = HttpStatusOK;
        [injectResponse setHeader:injectionHeader forKey:@"X-Custom"];
        NSData *injectSerialized = [injectResponse serialize];
        (void)injectSerialized;

        return 0;
    }
}

