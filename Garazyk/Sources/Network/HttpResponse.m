#import "Network/HttpResponse.h"
#import <stdint.h>

NS_ASSUME_NONNULL_BEGIN

/*! Security header values */
static NSString *const kXContentTypeOptions = @"nosniff";
static NSString *const kXFrameOptions = @"DENY";
static NSString *const kContentSecurityPolicy = @"default-src 'self'; script-src 'self' 'unsafe-inline' https://unpkg.com; style-src 'self' 'unsafe-inline'; img-src 'self' data:;";

static NSDateFormatter *HttpResponseDateFormatter(void) {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
        formatter.dateFormat = @"EEE, dd MMM yyyy HH:mm:ss 'GMT'";
    });
    return formatter;
}

NS_ASSUME_NONNULL_END

@implementation HttpResponse

@synthesize headers = _headers;

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
        _deleteBodyFileAfterSend = NO;
        _chunkedTransferEncoding = NO;
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
    [self.headers setObject:value forKey:key.lowercaseString];
}

- (nullable NSString *)headerForKey:(NSString *)key {
    return [self.headers objectForKey:key.lowercaseString];
}

- (void)setJsonBody:(id)json {
    _jsonBody = [json copy];
    NSError *error = nil;
    _body = [NSJSONSerialization dataWithJSONObject:json options:0 error:&error];
    if (error) {
        _body = nil;
    }
    _bodyString = nil;
    _bodyFilePath = nil;
    _deleteBodyFileAfterSend = NO;
    _bodyChunkProducer = nil;
    _chunkedTransferEncoding = NO;
    self.contentType = @"application/json; charset=utf-8";
}

- (void)setBodyString:(NSString *)body {
    _bodyString = [body copy];
    _body = [body dataUsingEncoding:NSUTF8StringEncoding];
    _jsonBody = nil; /*! Clear competing body representations */
    _bodyFilePath = nil;
    _deleteBodyFileAfterSend = NO;
    _bodyChunkProducer = nil;
    _chunkedTransferEncoding = NO;
}

- (void)setBodyData:(NSData *)data {
    _body = [data copy];
    _bodyString = nil; /*! Clear competing body representations */
    _jsonBody = nil;
    _bodyFilePath = nil;
    _deleteBodyFileAfterSend = NO;
    _bodyChunkProducer = nil;
    _chunkedTransferEncoding = NO;
}

- (void)setBodyFileAtPath:(NSString *)path deleteAfterSend:(BOOL)deleteAfterSend {
    _bodyFilePath = [path copy];
    _deleteBodyFileAfterSend = deleteAfterSend;
    _body = nil;
    _bodyString = nil;
    _jsonBody = nil;
    _bodyChunkProducer = nil;
    _chunkedTransferEncoding = NO;
}

- (void)setBodyChunkProducer:(HttpResponseBodyChunkProducer)producer
     chunkedTransferEncoding:(BOOL)chunkedTransferEncoding {
    _bodyChunkProducer = [producer copy];
    _chunkedTransferEncoding = chunkedTransferEncoding;
    _body = nil;
    _bodyString = nil;
    _jsonBody = nil;
    _bodyFilePath = nil;
    _deleteBodyFileAfterSend = NO;
}

- (NSData *)resolveBodyData {
    if (self.jsonBody) {
        NSError *error = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:self.jsonBody options:0 error:&error];
        if (error) {
            return nil;
        }
        return jsonData;
    }
    if (_body) {
        return _body;
    }
    if (self.bodyString) {
        return [self.bodyString dataUsingEncoding:NSUTF8StringEncoding];
    }
    HttpResponseBodyChunkProducer producer = self.bodyChunkProducer;
    if (producer) {
        NSMutableData *collected = [NSMutableData data];
        while (YES) {
            NSError *chunkError = nil;
            NSData *chunk = producer ? producer(&chunkError) : nil;
            if (chunkError) {
                return nil;
            }
            if (chunk.length == 0) {
                break;
            }
            [collected appendData:chunk];
        }
        _body = [collected copy];
        _bodyChunkProducer = nil;
        _chunkedTransferEncoding = NO;
        return _body;
    }
    if (self.bodyFilePath.length > 0) {
        return [NSData dataWithContentsOfFile:self.bodyFilePath];
    }
    return nil;
}

- (NSData *)body {
    if (_body) {
        return _body;
    }
    if (_bodyFilePath.length > 0) {
        _body = [NSData dataWithContentsOfFile:_bodyFilePath];
        return _body;
    }
    if (_bodyChunkProducer) {
        return [self resolveBodyData];
    }
    return nil;
}

- (void)prepareCommonHeadersForBodyLength:(NSUInteger)bodyLength {
    /*! Handle Connection header based on keepAlive setting */
    if (!_headers[@"Connection"]) {
        if (self.keepAlive) {
            [self setHeader:@"keep-alive" forKey:@"Connection"];
        } else {
            [self setHeader:@"close" forKey:@"Connection"];
        }
    }

    /*! 204 No Content MUST NOT have Content-Type, Content-Length, or Transfer-Encoding */
    if (self.statusCode == HttpStatusNoContent) {
        [_headers removeObjectForKey:@"Content-Type"];
        [_headers removeObjectForKey:@"Content-Length"];
        [_headers removeObjectForKey:@"Transfer-Encoding"];
        return;
    }

    /*! Ensure Content-Type is set for JSON responses */
    if (!self.contentType && self.jsonBody) {
        self.contentType = @"application/json; charset=utf-8";
    }

    /*! Add Content-Type header if present */
    if (self.contentType) {
        [self setHeader:self.contentType forKey:@"Content-Type"];
    }

    if (self.chunkedTransferEncoding) {
        [_headers removeObjectForKey:@"Content-Length"];
        [self setHeader:@"chunked" forKey:@"Transfer-Encoding"];
    } else {
        [_headers removeObjectForKey:@"Transfer-Encoding"];
        NSString *contentLength = [NSString stringWithFormat:@"%lu", (unsigned long)bodyLength];
        [self setHeader:contentLength forKey:@"Content-Length"];
    }

    /*! Add Date header */
    [self setHeader:[HttpResponseDateFormatter() stringFromDate:[NSDate date]] forKey:@"Date"];
}

- (NSData *)serializeHeadersForBodyLength:(NSUInteger)bodyLength {
    NSMutableData *result = [NSMutableData data];

    /*! Build status line: HTTP/1.1 CODE MESSAGE\r\n */
    NSString *statusLine = [NSString stringWithFormat:@"HTTP/1.1 %ld %@\r\n", (long)self.statusCode, self.statusMessage];
    [result appendData:[statusLine dataUsingEncoding:NSUTF8StringEncoding]];

    [self prepareCommonHeadersForBodyLength:bodyLength];

    /*! Append all headers in HTTP format */
    for (NSString *key in _headers) {
        NSString *headerLine = [NSString stringWithFormat:@"%@: %@\r\n", key, _headers[key]];
        [result appendData:[headerLine dataUsingEncoding:NSUTF8StringEncoding]];
    }

    /*! End headers section with blank line */
    [result appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    return [result copy];
}

- (NSData *)serialize {
    NSData *bodyData = [self resolveBodyData];
    NSData *headerData = [self serializeHeadersForBodyLength:bodyData ? bodyData.length : 0];
    NSMutableData *result = [NSMutableData dataWithData:headerData];

    /*! 204 No Content MUST NOT include a message body */
    if (bodyData && self.statusCode != HttpStatusNoContent) {
        [result appendData:bodyData];
    }

    return [result copy];
}

+ (NSString *)xContentTypeOptions { return kXContentTypeOptions; }
+ (NSString *)xFrameOptions { return kXFrameOptions; }
+ (NSString *)contentSecurityPolicy { return kContentSecurityPolicy; }

+ (void)applySecurityHeaders:(NSMutableDictionary *)headers {
    headers[@"x-content-type-options"] = self.xContentTypeOptions;
    headers[@"x-frame-options"] = self.xFrameOptions;
    headers[@"content-security-policy"] = self.contentSecurityPolicy;
    // CORS headers (Access-Control-Allow-Origin, Methods, Headers) are set
    // explicitly by each route handler to avoid duplicate header values.
}

@end
