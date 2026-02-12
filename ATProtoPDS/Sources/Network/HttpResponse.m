#import "Network/HttpResponse.h"
#import <stdint.h>

NS_ASSUME_NONNULL_BEGIN

/*! Security header values */
static NSString *const kXContentTypeOptions = @"nosniff";
static NSString *const kXFrameOptions = @"DENY";
static NSString *const kContentSecurityPolicy = @"default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:;";

NS_ASSUME_NONNULL_END

@implementation HttpResponse

+ (instancetype)response {
    return [[self alloc] init];
}

+ (instancetype)responseWithStatusCode:(HttpStatusCode)statusCode {
    HttpResponse *response = [self response];
    response.statusCode = statusCode;
    response.statusMessage = [self defaultMessageForCode:statusCode];
    return response;
}

+ (instancetype)jsonResponse:(id)json statusCode:(HttpStatusCode)statusCode {
    HttpResponse *response = [self responseWithStatusCode:statusCode];
    [response setJsonBody:json];
    return response;
}

+ (instancetype)textResponse:(NSString *)text statusCode:(HttpStatusCode)statusCode {
    HttpResponse *response = [self responseWithStatusCode:statusCode];
    response.contentType = @"text/plain; charset=utf-8";
    [response setBodyString:text];
    return response;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _statusCode = HttpStatusOK;
        _statusMessage = @"OK";
        _headers = [NSMutableDictionary dictionary];
        _keepAlive = YES;
        _contentType = @"application/json; charset=utf-8";
        [[self class] applySecurityHeaders:_headers];
    }
    return self;
}

+ (NSString *)defaultMessageForCode:(HttpStatusCode)code {
    switch (code) {
        case HttpStatusOK: return @"OK";
        case HttpStatusCreated: return @"Created";
        case HttpStatusAccepted: return @"Accepted";
        case HttpStatusNoContent: return @"No Content";
        case 302: return @"Found";
        case HttpStatusBadRequest: return @"Bad Request";
        case HttpStatusUnauthorized: return @"Unauthorized";
        case HttpStatusForbidden: return @"Forbidden";
        case HttpStatusNotFound: return @"Not Found";
        case HttpStatusMethodNotAllowed: return @"Method Not Allowed";
        case HttpStatusConflict: return @"Conflict";
        case 429: return @"Too Many Requests";
        case HttpStatusInternalServerError: return @"Internal Server Error";
        case HttpStatusNotImplemented: return @"Not Implemented";
        case HttpStatusServiceUnavailable: return @"Service Unavailable";
        default: return @"Unknown";
    }
}

- (void)setHeader:(NSString *)value forKey:(NSString *)key {
    self.headers[key] = value;
}

- (void)setJsonBody:(id)json {
    _jsonBody = [json copy];
    NSError *error = nil;
    _body = [NSJSONSerialization dataWithJSONObject:json options:0 error:&error];
    if (error) {
        _body = nil;
    }
    _bodyString = nil;
    self.contentType = @"application/json; charset=utf-8";
}

- (void)setBodyString:(NSString *)body {
    _bodyString = [body copy];
    _body = [body dataUsingEncoding:NSUTF8StringEncoding];
    _jsonBody = nil; /*! Clear competing body representations */
}

- (void)setBodyData:(NSData *)data {
    _body = [data copy];
    _bodyString = nil; /*! Clear competing body representations */
    _jsonBody = nil;
}

- (NSData *)serialize {
    NSMutableData *result = [NSMutableData data];

    /*! Build status line: HTTP/1.1 CODE MESSAGE\r\n */
    NSString *statusLine = [NSString stringWithFormat:@"HTTP/1.1 %ld %@\r\n", (long)self.statusCode, self.statusMessage];
    [result appendData:[statusLine dataUsingEncoding:NSUTF8StringEncoding]];

    if (self.statusCode == 302 || self.statusCode == 429) {
        NSLog(@"[HTTP RESPONSE] Status: %ld, Headers: %@", (long)self.statusCode, self.headers);
    }

    /*! Handle Connection header based on keepAlive setting */
    if (!self.headers[@"Connection"]) {
        if (self.keepAlive) {
            [self setHeader:@"keep-alive" forKey:@"Connection"];
        } else {
            [self setHeader:@"close" forKey:@"Connection"];
        }
    }

    /*! Ensure Content-Type is set for JSON responses */
    if (!self.contentType && self.jsonBody) {
        self.contentType = @"application/json; charset=utf-8";
    }

    /*! Add Content-Type header if present */
    if (self.contentType) {
        [self setHeader:self.contentType forKey:@"Content-Type"];
    }

    /*! Determine body data from highest-priority source */
    NSData *bodyData = nil;
    if (self.jsonBody) {
        NSError *error = nil;
        bodyData = [NSJSONSerialization dataWithJSONObject:self.jsonBody options:0 error:&error];
        if (error) {
            bodyData = nil; /*! Fail-safe: don't send malformed JSON */
        }
    } else if (self.body) {
        bodyData = self.body;
    } else if (self.bodyString) {
        bodyData = [self.bodyString dataUsingEncoding:NSUTF8StringEncoding];
    }

    /*! Add Content-Length header (0 when body is empty) */
    if (bodyData) {
        NSString *contentLength = [NSString stringWithFormat:@"%lu", (unsigned long)bodyData.length];
        [self setHeader:contentLength forKey:@"Content-Length"];
    } else {
        [self setHeader:@"0" forKey:@"Content-Length"];
    }

    /*! Add Date header */
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    dateFormatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
    dateFormatter.dateFormat = @"EEE, dd MMM yyyy HH:mm:ss 'GMT'";
    [self setHeader:[dateFormatter stringFromDate:[NSDate date]] forKey:@"Date"];

    /*! Append all headers in HTTP format */
    for (NSString *key in self.headers) {
        NSString *headerLine = [NSString stringWithFormat:@"%@: %@\r\n", key, self.headers[key]];
        [result appendData:[headerLine dataUsingEncoding:NSUTF8StringEncoding]];
    }

    /*! End headers section with blank line */
    [result appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];

    /*! Append body if present */
    if (bodyData) {
        [result appendData:bodyData];
    }

    return [result copy];
}

+ (NSString *)xContentTypeOptions { return kXContentTypeOptions; }
+ (NSString *)xFrameOptions { return kXFrameOptions; }
+ (NSString *)contentSecurityPolicy { return kContentSecurityPolicy; }

+ (void)applySecurityHeaders:(NSMutableDictionary *)headers {
    headers[@"X-Content-Type-Options"] = self.xContentTypeOptions;
    headers[@"X-Frame-Options"] = self.xFrameOptions;
    headers[@"Content-Security-Policy"] = self.contentSecurityPolicy;
    headers[@"Access-Control-Allow-Origin"] = @"*";
    headers[@"Access-Control-Allow-Methods"] = @"GET, POST, PUT, DELETE, OPTIONS, HEAD";
    headers[@"Access-Control-Allow-Headers"] = @"DPoP, Authorization, Content-Type, *";
}

@end
