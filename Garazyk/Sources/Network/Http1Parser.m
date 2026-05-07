/*!
 @file Http1Parser.m

 @abstract Implements HTTP/1.x parser state transitions and token extraction logic.

 @discussion Executes request-line, header, and body parsing with explicit state progression and malformed-input detection. Produces parser results consumed by protocol/session layers and does not perform application routing.
 */

#import "Network/Http1Parser.h"
#import "Network/HttpParsing.h"
#import "Network/HttpChunkedBodyParser.h"

#if defined(__APPLE__)
#import <CFNetwork/CFNetwork.h>
#endif

@implementation Http1ParserError

- (instancetype)initWithStatusCode:(NSUInteger)statusCode
                         errorCode:(NSString *)errorCode
                           message:(NSString *)message {
    self = [super init];
    if (self) {
        _statusCode = statusCode;
        _errorCode = [errorCode copy];
        _message = [message copy];
    }
    return self;
}

@end

#if defined(__APPLE__)
// ============================================================================
// macOS implementation using CFHTTPMessage (Apple native API)
// ============================================================================

@interface Http1Parser ()

@property (nonatomic, assign, readwrite) Http1ParserState state;
@property (nonatomic, strong) NSMutableData *buffer;
@property (nonatomic, assign) CFHTTPMessageRef message;
@property (nonatomic, assign) BOOL headersComplete;
@property (nonatomic, assign) NSUInteger expectedBodyLength;
@property (nonatomic, assign) NSUInteger headerEndOffset;
@property (nonatomic, assign) BOOL isChunkedEncoding;
@property (nonatomic, strong, nullable) HttpChunkedBodyParser *chunkedBodyParser;
@property (nonatomic, strong, nullable) HttpRequest *parsedRequest;
@property (nonatomic, strong, nullable) Http1ParserError *currentError;
@property (nonatomic, assign) NSUInteger consumedOffset;

@end

@implementation Http1Parser

- (instancetype)init {
    self = [super init];
    if (self) {
        _maxHeaderBytes = 16 * 1024; // 16KB
        _maxBodyBytes = 50 * 1024 * 1024; // 50MB
        _buffer = [NSMutableData data];
        _message = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, true);
        _state = Http1ParserStateReadingHeaders;
        _headersComplete = NO;
        _expectedBodyLength = 0;
        _headerEndOffset = 0;
        _isChunkedEncoding = NO;
        _consumedOffset = 0;
    }
    return self;
}

- (void)dealloc {
    if (_message) {
        CFRelease(_message);
        _message = NULL;
    }
}

- (void)reset {
    if (_message) {
        CFRelease(_message);
    }
    _message = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, true);
    _state = Http1ParserStateReadingHeaders;
    _headersComplete = NO;
    _expectedBodyLength = 0;
    _headerEndOffset = 0;
    [_buffer setLength:0];
    _isChunkedEncoding = NO;
    _chunkedBodyParser = nil;
    _parsedRequest = nil;
    _currentError = nil;
    _consumedOffset = 0;
}

- (NSRange)headerEndRangeInData:(NSData *)data {
    const uint8_t *bytes = data.bytes;
    for (NSUInteger i = 0; i + 3 < data.length; i++) {
        if (bytes[i] == '\r' && bytes[i + 1] == '\n' &&
            bytes[i + 2] == '\r' && bytes[i + 3] == '\n') {
            return NSMakeRange(i, 4);
        }
    }
    return NSMakeRange(NSNotFound, 0);
}

- (NSUInteger)contentLengthForMessage:(CFHTTPMessageRef)message {
    NSString *contentLengthString = (__bridge_transfer NSString *)CFHTTPMessageCopyHeaderFieldValue(message, CFSTR("Content-Length"));
    if (!contentLengthString) {
        return 0;
    }
    return (NSUInteger)[contentLengthString longLongValue];
}

- (NSDictionary<NSString *, NSString *> *)headersFromMessage:(CFHTTPMessageRef)message {
    NSDictionary *rawHeaders = (__bridge_transfer NSDictionary *)CFHTTPMessageCopyAllHeaderFields(message);
    if (!rawHeaders) {
        return @{};
    }
    NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionaryWithCapacity:rawHeaders.count];
    for (NSString *key in rawHeaders) {
        NSString *value = rawHeaders[key];
        if (key && value) {
            headers[key.lowercaseString] = value;
        }
    }
    return [headers copy];
}

- (BOOL)isSupportedTransferEncoding:(NSDictionary<NSString *, NSString *> *)headers {
    NSString *transferEncoding = headers[@"transfer-encoding"];
    if (!transferEncoding || transferEncoding.length == 0) {
        return YES;
    }
    NSString *lowercased = transferEncoding.lowercaseString;
    if ([lowercased isEqualToString:@"identity"]) {
        return YES;
    }
    if ([lowercased isEqualToString:@"chunked"]) {
        return YES;
    }
    return NO;
}

- (void)setErrorWithStatusCode:(NSUInteger)statusCode errorCode:(NSString *)errorCode message:(NSString *)message {
    self.state = Http1ParserStateError;
    self.currentError = [[Http1ParserError alloc] initWithStatusCode:statusCode errorCode:errorCode message:message];
}

- (BOOL)feedData:(NSData *)data {
    if (self.state == Http1ParserStateComplete || self.state == Http1ParserStateError) {
        return YES; // Already done
    }

    [self.buffer appendData:data];

    if (self.state == Http1ParserStateReadingHeaders) {
        if (self.buffer.length > self.maxHeaderBytes) {
            [self setErrorWithStatusCode:413 errorCode:@"RequestTooLarge" message:@"Request headers too large"];
            return YES;
        }

        NSRange headerEndRange = [self headerEndRangeInData:self.buffer];
        if (headerEndRange.location == NSNotFound) {
            return NO;
        }

        NSData *headerData = [self.buffer subdataWithRange:NSMakeRange(0, headerEndRange.location + headerEndRange.length)];
        if (!CFHTTPMessageAppendBytes(self.message, headerData.bytes, headerData.length)) {
            [self setErrorWithStatusCode:400 errorCode:@"BadRequest" message:@"Invalid request"];
            return YES;
        }

        if (!CFHTTPMessageIsHeaderComplete(self.message)) {
            return NO;
        }

        self.headersComplete = YES;
        self.headerEndOffset = headerEndRange.location + headerEndRange.length;
        self.expectedBodyLength = [self contentLengthForMessage:self.message];

        NSDictionary *headers = [self headersFromMessage:self.message];
        NSString *transferEncoding = [[headers objectForKey:@"transfer-encoding"] lowercaseString];
        NSString *contentLengthHeader = headers[@"content-length"];

        if (transferEncoding.length > 0 && contentLengthHeader.length > 0) {
            [self setErrorWithStatusCode:400 errorCode:@"InvalidRequestFraming" message:@"Transfer-Encoding and Content-Length cannot both be present"];
            return YES;
        }

        self.isChunkedEncoding = [transferEncoding containsString:@"chunked"];

        if (self.isChunkedEncoding) {
            self.chunkedBodyParser = [[HttpChunkedBodyParser alloc] initWithMaxSize:self.maxBodyBytes];
            self.expectedBodyLength = 0;
            self.state = Http1ParserStateReadingChunkedBody;
        } else {
            if (self.expectedBodyLength > self.maxBodyBytes) {
                [self setErrorWithStatusCode:413 errorCode:@"RequestTooLarge" message:@"Request body too large"];
                return YES;
            }
            self.state = Http1ParserStateReadingBody;
        }

        NSString *method = (__bridge_transfer NSString *)CFHTTPMessageCopyRequestMethod(self.message);
        HttpMethod methodEnum = [HttpParsing methodFromString:method ?: @""];
        BOOL expectsBody = (methodEnum == HttpMethodPOST || methodEnum == HttpMethodPUT || methodEnum == HttpMethodPATCH);

        if (expectsBody && !self.isChunkedEncoding && contentLengthHeader.length == 0) {
            [self setErrorWithStatusCode:411 errorCode:@"LengthRequired" message:@"Content-Length or Transfer-Encoding: chunked required"];
            return YES;
        }
        
        if (![self isSupportedTransferEncoding:headers]) {
            [self setErrorWithStatusCode:501 errorCode:@"UnsupportedTransferEncoding" message:@"Transfer-Encoding not supported"];
            return YES;
        }
    }

    NSData *bodyData = nil;
    NSUInteger consumedOffset = 0;

    if (self.state == Http1ParserStateReadingChunkedBody) {
        NSUInteger bodyStart = self.headerEndOffset;
        NSUInteger availableBodyLength = self.buffer.length > bodyStart ? self.buffer.length - bodyStart : 0;

        if (availableBodyLength > 0) {
            NSData *bodyChunk = [self.buffer subdataWithRange:NSMakeRange(bodyStart, availableBodyLength)];
            NSError *parseError = nil;
            NSInteger bytesConsumed = [self.chunkedBodyParser appendData:bodyChunk error:&parseError];

            if (parseError || bytesConsumed < 0) {
                [self setErrorWithStatusCode:400 errorCode:@"BadRequest" message:@"Invalid chunked body"];
                return YES;
            }

            if (!self.chunkedBodyParser.isComplete) {
                return NO;
            }

            bodyData = self.chunkedBodyParser.parsedData;
            consumedOffset = bodyStart + bytesConsumed;
        } else {
            return NO;
        }
    } else if (self.state == Http1ParserStateReadingBody) {
        NSUInteger bodyStart = self.headerEndOffset;
        if (self.buffer.length < bodyStart + self.expectedBodyLength) {
            return NO;
        }

        bodyData = [self.buffer subdataWithRange:NSMakeRange(bodyStart, self.expectedBodyLength)];
        consumedOffset = bodyStart + self.expectedBodyLength;
    }

    // If we reached here without returning, we have a complete request
    self.consumedOffset = consumedOffset;
    
    NSString *method = (__bridge_transfer NSString *)CFHTTPMessageCopyRequestMethod(self.message);
    CFURLRef urlRef = CFHTTPMessageCopyRequestURL(self.message);
    NSURL *url = urlRef ? CFBridgingRelease(urlRef) : nil;
    NSString *version = (__bridge_transfer NSString *)CFHTTPMessageCopyVersion(self.message);
    NSDictionary *headers = [self headersFromMessage:self.message];

    NSString *path = url.path ?: @"/";
    NSString *queryString = url.query ?: @"";
    NSDictionary<NSString *, id> *queryParams = [HttpParsing parseQueryString:queryString];
    HttpMethod methodEnum = [HttpParsing methodFromString:method ?: @""];

    self.parsedRequest = [[HttpRequest alloc] initWithMethod:methodEnum
                                                methodString:method ?: @""
                                                        path:path
                                                 queryString:queryString
                                                 queryParams:queryParams ?: @{}
                                                     version:version ?: @"HTTP/1.1"
                                                     headers:headers ?: @{}
                                                        body:bodyData ?: [NSData data]
                                               remoteAddress:self.remoteAddress ?: @""];

    if (!self.parsedRequest) {
        [self setErrorWithStatusCode:400 errorCode:@"BadRequest" message:@"Invalid request"];
        return YES;
    }

    self.state = Http1ParserStateComplete;
    return YES;
}

- (nullable HttpRequest *)completedRequest {
    return self.parsedRequest;
}

- (nullable Http1ParserError *)parseError {
    return self.currentError;
}

- (NSData *)unconsumedData {
    if (self.state == Http1ParserStateComplete && self.consumedOffset < self.buffer.length) {
        return [self.buffer subdataWithRange:NSMakeRange(self.consumedOffset, self.buffer.length - self.consumedOffset)];
    }
    return [NSData data];
}

@end

#else
// ============================================================================
// GNUstep/Linux implementation using deterministic manual parsing
// ============================================================================

@interface Http1Parser ()

@property (nonatomic, assign, readwrite) Http1ParserState state;
@property (nonatomic, strong) NSMutableData *buffer;
@property (nonatomic, assign) BOOL headersComplete;
@property (nonatomic, assign) NSUInteger expectedBodyLength;
@property (nonatomic, assign) NSUInteger headerEndOffset;
@property (nonatomic, assign) BOOL isChunkedEncoding;
@property (nonatomic, strong, nullable) HttpChunkedBodyParser *chunkedBodyParser;
@property (nonatomic, strong, nullable) HttpRequest *parsedRequest;
@property (nonatomic, strong, nullable) Http1ParserError *currentError;
@property (nonatomic, assign) NSUInteger consumedOffset;

// Parsed request line components
@property (nonatomic, strong) NSString *requestMethod;
@property (nonatomic, strong) NSString *requestPath;
@property (nonatomic, strong) NSString *requestVersion;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *parsedHeaders;

@end

@implementation Http1Parser

- (instancetype)init {
    self = [super init];
    if (self) {
        _maxHeaderBytes = 16 * 1024; // 16KB
        _maxBodyBytes = 50 * 1024 * 1024; // 50MB
        _buffer = [NSMutableData data];
        _state = Http1ParserStateReadingHeaders;
        _headersComplete = NO;
        _expectedBodyLength = 0;
        _headerEndOffset = 0;
        _isChunkedEncoding = NO;
        _consumedOffset = 0;
    }
    return self;
}

- (void)reset {
    _state = Http1ParserStateReadingHeaders;
    _headersComplete = NO;
    _expectedBodyLength = 0;
    _headerEndOffset = 0;
    [_buffer setLength:0];
    _isChunkedEncoding = NO;
    _chunkedBodyParser = nil;
    _parsedRequest = nil;
    _currentError = nil;
    _consumedOffset = 0;
    _requestMethod = nil;
    _requestPath = nil;
    _requestVersion = nil;
    _parsedHeaders = nil;
}

- (NSRange)headerEndRangeInData:(NSData *)data {
    const uint8_t *bytes = data.bytes;
    for (NSUInteger i = 0; i + 3 < data.length; i++) {
        if (bytes[i] == '\r' && bytes[i + 1] == '\n' &&
            bytes[i + 2] == '\r' && bytes[i + 3] == '\n') {
            return NSMakeRange(i, 4);
        }
    }
    return NSMakeRange(NSNotFound, 0);
}

- (void)parseRequestLine:(NSString *)line {
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceCharacterSet];
    NSArray *parts = [line componentsSeparatedByCharactersInSet:whitespace];
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    for (NSString *part in parts) {
        if (part.length > 0) {
            [tokens addObject:part];
        }
    }

    if (tokens.count >= 3) {
        _requestMethod = tokens[0];
        _requestPath = tokens[1];
        _requestVersion = tokens[2];
    } else if (tokens.count >= 2) {
        _requestMethod = tokens[0];
        _requestPath = tokens[1];
        _requestVersion = @"HTTP/1.1";
    }
}

- (NSUInteger)contentLengthFromHeaders:(NSDictionary<NSString *, NSString *> *)headers
                                 valid:(BOOL *)valid {
    NSString *contentLengthString = headers[@"content-length"];
    if (!contentLengthString) {
        if (valid) {
            *valid = YES;
        }
        return 0;
    }

    NSString *trimmed = [contentLengthString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSScanner *scanner = [NSScanner scannerWithString:trimmed];
    long long value = 0;
    BOOL parsed = [scanner scanLongLong:&value] && [scanner isAtEnd] && value >= 0;
    if (!parsed) {
        if (valid) {
            *valid = NO;
        }
        return 0;
    }

    if (valid) {
        *valid = YES;
    }
    return (NSUInteger)value;
}

- (NSDictionary<NSString *, NSString *> *)headersFromHeaderData:(NSData *)headerData
                                                   errorMessage:(NSString **)errorMessage {
    NSString *headerText = [[NSString alloc] initWithData:headerData encoding:NSUTF8StringEncoding];
    if (!headerText) {
        headerText = [[NSString alloc] initWithData:headerData encoding:NSISOLatin1StringEncoding];
    }
    if (!headerText) {
        if (errorMessage) {
            *errorMessage = @"Invalid request encoding";
        }
        return nil;
    }

    NSArray<NSString *> *lines = [headerText componentsSeparatedByString:@"\r\n"];
    if (lines.count == 0) {
        if (errorMessage) {
            *errorMessage = @"Empty request";
        }
        return nil;
    }

    NSString *requestLine = lines[0];
    if (requestLine.length == 0) {
        if (errorMessage) {
            *errorMessage = @"Missing request line";
        }
        return nil;
    }
    [self parseRequestLine:requestLine];
    if (!self.requestMethod || self.requestMethod.length == 0 || !self.requestPath || self.requestPath.length == 0) {
        if (errorMessage) {
            *errorMessage = @"Invalid request line";
        }
        return nil;
    }
    if (self.requestVersion.length == 0) {
        self.requestVersion = @"HTTP/1.1";
    }

    NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
    NSCharacterSet *trimSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    for (NSUInteger i = 1; i < lines.count; i++) {
        NSString *line = lines[i];
        if (line.length == 0) {
            continue;
        }

        NSRange colonRange = [line rangeOfString:@":"];
        if (colonRange.location == NSNotFound || colonRange.location == 0) {
            if (errorMessage) {
                *errorMessage = @"Malformed header line";
            }
            return nil;
        }

        NSString *rawName = [line substringToIndex:colonRange.location];
        NSString *rawValue = [line substringFromIndex:colonRange.location + 1];
        NSString *name = [[rawName stringByTrimmingCharactersInSet:trimSet] lowercaseString];
        NSString *value = [rawValue stringByTrimmingCharactersInSet:trimSet];

        if (name.length == 0) {
            if (errorMessage) {
                *errorMessage = @"Empty header name";
            }
            return nil;
        }

        NSString *existing = headers[name];
        if (existing) {
            headers[name] = [NSString stringWithFormat:@"%@, %@", existing, value];
        } else {
            headers[name] = value;
        }
    }

    return [headers copy];
}

- (BOOL)isSupportedTransferEncoding:(NSDictionary<NSString *, NSString *> *)headers {
    NSString *transferEncoding = headers[@"transfer-encoding"];
    if (!transferEncoding || transferEncoding.length == 0) {
        return YES;
    }
    NSString *lowercased = transferEncoding.lowercaseString;
    if ([lowercased isEqualToString:@"identity"]) {
        return YES;
    }
    if ([lowercased isEqualToString:@"chunked"]) {
        return YES;
    }
    return NO;
}

- (void)setErrorWithStatusCode:(NSUInteger)statusCode errorCode:(NSString *)errorCode message:(NSString *)message {
    self.state = Http1ParserStateError;
    self.currentError = [[Http1ParserError alloc] initWithStatusCode:statusCode errorCode:errorCode message:message];
}

- (BOOL)feedData:(NSData *)data {
    if (self.state == Http1ParserStateComplete || self.state == Http1ParserStateError) {
        return YES; // Already done
    }

    [self.buffer appendData:data];

    if (self.state == Http1ParserStateReadingHeaders) {
        if (self.buffer.length > self.maxHeaderBytes) {
            [self setErrorWithStatusCode:413 errorCode:@"RequestTooLarge" message:@"Request headers too large"];
            return YES;
        }

        NSRange headerEndRange = [self headerEndRangeInData:self.buffer];
        if (headerEndRange.location == NSNotFound) {
            return NO;
        }

        NSData *headerData = [self.buffer subdataWithRange:NSMakeRange(0, headerEndRange.location + headerEndRange.length)];
        NSString *headerError = nil;
        NSDictionary<NSString *, NSString *> *headers = [self headersFromHeaderData:headerData errorMessage:&headerError];
        if (!headers) {
            [self setErrorWithStatusCode:400 errorCode:@"BadRequest" message:headerError ?: @"Invalid request headers"];
            return YES;
        }

        self.headersComplete = YES;
        self.headerEndOffset = headerEndRange.location + headerEndRange.length;
        self.parsedHeaders = headers;
        NSString *transferEncoding = [[headers objectForKey:@"transfer-encoding"] lowercaseString];
        NSString *contentLengthHeader = headers[@"content-length"];

        if (transferEncoding.length > 0 && contentLengthHeader.length > 0) {
            [self setErrorWithStatusCode:400 errorCode:@"InvalidRequestFraming" message:@"Transfer-Encoding and Content-Length cannot both be present"];
            return YES;
        }

        BOOL contentLengthValid = YES;
        self.expectedBodyLength = [self contentLengthFromHeaders:headers valid:&contentLengthValid];
        if (!contentLengthValid) {
            [self setErrorWithStatusCode:400 errorCode:@"BadRequest" message:@"Invalid Content-Length"];
            return YES;
        }

        self.isChunkedEncoding = [transferEncoding containsString:@"chunked"];

        if (self.isChunkedEncoding) {
            self.chunkedBodyParser = [[HttpChunkedBodyParser alloc] initWithMaxSize:self.maxBodyBytes];
            self.expectedBodyLength = 0;
            self.state = Http1ParserStateReadingChunkedBody;
        } else {
            if (self.expectedBodyLength > self.maxBodyBytes) {
                [self setErrorWithStatusCode:413 errorCode:@"RequestTooLarge" message:@"Request body too large"];
                return YES;
            }
            self.state = Http1ParserStateReadingBody;
        }

        HttpMethod methodEnum = [HttpParsing methodFromString:self.requestMethod ?: @""];
        BOOL expectsBody = (methodEnum == HttpMethodPOST || methodEnum == HttpMethodPUT || methodEnum == HttpMethodPATCH);

        if (expectsBody && !self.isChunkedEncoding && contentLengthHeader.length == 0) {
            [self setErrorWithStatusCode:411 errorCode:@"LengthRequired" message:@"Content-Length or Transfer-Encoding: chunked required"];
            return YES;
        }
        
        if (![self isSupportedTransferEncoding:headers]) {
            [self setErrorWithStatusCode:501 errorCode:@"UnsupportedTransferEncoding" message:@"Transfer-Encoding not supported"];
            return YES;
        }
    }

    NSData *bodyData = nil;
    NSUInteger consumedOffset = 0;

    if (self.state == Http1ParserStateReadingChunkedBody) {
        NSUInteger bodyStart = self.headerEndOffset;
        NSUInteger availableBodyLength = self.buffer.length > bodyStart ? self.buffer.length - bodyStart : 0;

        if (availableBodyLength > 0) {
            NSData *bodyChunk = [self.buffer subdataWithRange:NSMakeRange(bodyStart, availableBodyLength)];
            NSError *parseError = nil;
            NSInteger bytesConsumed = [self.chunkedBodyParser appendData:bodyChunk error:&parseError];

            if (parseError || bytesConsumed < 0) {
                [self setErrorWithStatusCode:400 errorCode:@"BadRequest" message:@"Invalid chunked body"];
                return YES;
            }

            if (!self.chunkedBodyParser.isComplete) {
                return NO;
            }

            bodyData = self.chunkedBodyParser.parsedData;
            consumedOffset = bodyStart + bytesConsumed;
        } else {
            return NO;
        }
    } else if (self.state == Http1ParserStateReadingBody) {
        NSUInteger bodyStart = self.headerEndOffset;
        if (self.buffer.length < bodyStart + self.expectedBodyLength) {
            return NO;
        }

        bodyData = [self.buffer subdataWithRange:NSMakeRange(bodyStart, self.expectedBodyLength)];
        consumedOffset = bodyStart + self.expectedBodyLength;
    }

    // If we reached here without returning, we have a complete request
    self.consumedOffset = consumedOffset;
    
    NSDictionary<NSString *, NSString *> *headers = self.parsedHeaders ?: @{};
    NSString *path = self.requestPath ?: @"/";

    // Support absolute-form and origin-form request targets.
    NSString *queryString = @"";
    NSString *pathOnly = path;
    if ([path hasPrefix:@"http://"] || [path hasPrefix:@"https://"]) {
        NSURL *absoluteURL = [NSURL URLWithString:path];
        if (absoluteURL) {
            pathOnly = absoluteURL.path ?: @"/";
            queryString = absoluteURL.query ?: @"";
        }
    } else {
        NSRange queryRange = [path rangeOfString:@"?"];
        if (queryRange.location != NSNotFound) {
            queryString = [path substringFromIndex:NSMaxRange(queryRange)];
            pathOnly = [path substringToIndex:queryRange.location];
        }
    }
    if (pathOnly.length == 0) {
        pathOnly = @"/";
    }
    
    NSDictionary<NSString *, id> *queryParams = [HttpParsing parseQueryString:queryString];
    HttpMethod methodEnum = [HttpParsing methodFromString:self.requestMethod ?: @""];

    self.parsedRequest = [[HttpRequest alloc] initWithMethod:methodEnum
                                                methodString:self.requestMethod ?: @""
                                                        path:pathOnly
                                                 queryString:queryString
                                                 queryParams:queryParams ?: @{}
                                                     version:self.requestVersion ?: @"HTTP/1.1"
                                                     headers:headers ?: @{}
                                                        body:bodyData ?: [NSData data]
                                               remoteAddress:self.remoteAddress ?: @""];

    if (!self.parsedRequest) {
        [self setErrorWithStatusCode:400 errorCode:@"BadRequest" message:@"Invalid request"];
        return YES;
    }

    self.state = Http1ParserStateComplete;
    return YES;
}

- (nullable HttpRequest *)completedRequest {
    return self.parsedRequest;
}

- (nullable Http1ParserError *)parseError {
    return self.currentError;
}

- (NSData *)unconsumedData {
    if (self.state == Http1ParserStateComplete && self.consumedOffset < self.buffer.length) {
        return [self.buffer subdataWithRange:NSMakeRange(self.consumedOffset, self.buffer.length - self.consumedOffset)];
    }
    return [NSData data];
}

@end

#endif
