#import "Network/HttpResponse.h"

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

+ (instancetype)jsonResponse:(NSDictionary *)json statusCode:(HttpStatusCode)statusCode {
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
    }
    return self;
}

+ (NSString *)defaultMessageForCode:(HttpStatusCode)code {
    switch (code) {
        case HttpStatusOK: return @"OK";
        case HttpStatusCreated: return @"Created";
        case HttpStatusAccepted: return @"Accepted";
        case HttpStatusNoContent: return @"No Content";
        case HttpStatusBadRequest: return @"Bad Request";
        case HttpStatusUnauthorized: return @"Unauthorized";
        case HttpStatusForbidden: return @"Forbidden";
        case HttpStatusNotFound: return @"Not Found";
        case HttpStatusMethodNotAllowed: return @"Method Not Allowed";
        case HttpStatusConflict: return @"Conflict";
        case HttpStatusInternalServerError: return @"Internal Server Error";
        case HttpStatusNotImplemented: return @"Not Implemented";
        case HttpStatusServiceUnavailable: return @"Service Unavailable";
        default: return @"Unknown";
    }
}

- (void)setHeader:(NSString *)value forKey:(NSString *)key {
    self.headers[key] = value;
}

- (void)setJsonBody:(NSDictionary *)json {
    _jsonBody = [json copy];
    _body = nil;
    _bodyString = nil;
    self.contentType = @"application/json; charset=utf-8";
}

- (void)setBodyString:(NSString *)body {
    _bodyString = [body copy];
    _body = [body dataUsingEncoding:NSUTF8StringEncoding];
    _jsonBody = nil;
}

- (void)setBodyData:(NSData *)data {
    _body = [data copy];
    _bodyString = nil;
    _jsonBody = nil;
}

- (NSData *)serialize {
    NSMutableData *result = [NSMutableData data];

    NSString *statusLine = [NSString stringWithFormat:@"HTTP/1.1 %ld %@\r\n", (long)self.statusCode, self.statusMessage];
    [result appendData:[statusLine dataUsingEncoding:NSUTF8StringEncoding]];

    if (self.keepAlive) {
        [self setHeader:@"keep-alive" forKey:@"Connection"];
    } else {
        [self setHeader:@"close" forKey:@"Connection"];
    }

    if (!self.contentType && self.jsonBody) {
        self.contentType = @"application/json; charset=utf-8";
    }

    if (self.contentType) {
        [self setHeader:self.contentType forKey:@"Content-Type"];
    }

    NSData *bodyData = nil;
    if (self.jsonBody) {
        NSError *error = nil;
        bodyData = [NSJSONSerialization dataWithJSONObject:self.jsonBody options:0 error:&error];
        if (error) {
            bodyData = nil;
        }
    } else if (self.body) {
        bodyData = self.body;
    } else if (self.bodyString) {
        bodyData = [self.bodyString dataUsingEncoding:NSUTF8StringEncoding];
    }

    if (bodyData) {
        NSString *contentLength = [NSString stringWithFormat:@"%lu", (unsigned long)bodyData.length];
        [self setHeader:contentLength forKey:@"Content-Length"];
    }

    for (NSString *key in self.headers) {
        NSString *headerLine = [NSString stringWithFormat:@"%@: %@\r\n", key, self.headers[key]];
        [result appendData:[headerLine dataUsingEncoding:NSUTF8StringEncoding]];
    }

    [result appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];

    if (bodyData) {
        [result appendData:bodyData];
    }

    return [result copy];
}

@end
