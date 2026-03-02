#import "Network/Http1Parser.h"
#import "Network/HttpParsing.h"
#import "Network/HttpChunkedBodyParser.h"

#if defined(__APPLE__)
#import <CFNetwork/CFNetwork.h>
#else
#import <CoreFoundation/CoreFoundation.h>
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
            BOOL shouldContinue = [self.chunkedBodyParser appendData:bodyChunk error:&parseError];

            if (parseError) {
                [self setErrorWithStatusCode:400 errorCode:@"BadRequest" message:@"Invalid chunked body"];
                return YES;
            }

            if (!shouldContinue) {
                return NO;
            }

            if (!self.chunkedBodyParser.isComplete) {
                return NO;
            }

            bodyData = self.chunkedBodyParser.parsedData;
            // For chunked body, the unconsumed data logic is tricky because we might over-read. 
            // Currently HttpChunkedBodyParser consumes all available data if no error. 
            // In a real robust implementation, HttpChunkedBodyParser would return exactly how many bytes it consumed.
            // For now we'll match the existing logic which assumes it consumes the whole buffer.
            consumedOffset = self.buffer.length;
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
#if defined(__APPLE__)
    NSURL *url = urlRef ? CFBridgingRelease(urlRef) : nil;
#else
    NSURL *url = CFURLToNSURL(urlRef);
    if (urlRef) CFURLRelease(urlRef);
#endif
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
