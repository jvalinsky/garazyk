/*!
 @file HttpChunkedBodyParser.m

 @abstract Implements parser logic for HTTP chunked transfer-encoded request bodies.

 @discussion Processes chunk-size framing and chunk data sequencing according to HTTP chunked transfer rules, including malformed framing detection. Supplies parsed body data to higher layers without handling route logic.
 */

#import "HttpChunkedBodyParser.h"

static const NSUInteger kDefaultMaxBodySize = 50 * 1024 * 1024;

typedef NS_ENUM(NSInteger, HttpChunkedParserState) {
    HttpChunkedParserStateReadingChunkSize,
    HttpChunkedParserStateReadingChunkData,
    HttpChunkedParserStateReadingFinalCRLF,
    HttpChunkedParserStateComplete,
    HttpChunkedParserStateError
};

@interface HttpChunkedBodyParser ()

@property (nonatomic, assign) NSUInteger maxSize;
@property (nonatomic, assign) HttpChunkedParserState state;
@property (nonatomic, strong) NSMutableData *outputData;
@property (nonatomic, strong) NSMutableData *workingBuffer;
@property (nonatomic, assign) NSUInteger currentChunkSize;
@property (nonatomic, assign) NSUInteger bytesReadInCurrentChunk;
@property (nonatomic, copy, nullable) NSString *errorMessage;
@property (nonatomic, assign) NSInteger errorCode;

@end

@implementation HttpChunkedBodyParser

- (instancetype)init {
    return [self initWithMaxSize:kDefaultMaxBodySize];
}

- (instancetype)initWithMaxSize:(NSUInteger)maxSize {
    self = [super init];
    if (self) {
        _maxSize = maxSize;
        _outputData = [NSMutableData data];
        _workingBuffer = [NSMutableData data];
        _state = HttpChunkedParserStateReadingChunkSize;
        _currentChunkSize = 0;
        _bytesReadInCurrentChunk = 0;
    }
    return self;
}

- (NSInteger)appendData:(NSData *)data error:(NSError **)error {
    if (self.state == HttpChunkedParserStateComplete || self.state == HttpChunkedParserStateError) {
        return 0;
    }

    [self.workingBuffer appendData:data];
    NSUInteger totalConsumed = 0;

    while (self.workingBuffer.length > 0) {
        BOOL shouldBreak = NO;
        switch (self.state) {
            case HttpChunkedParserStateReadingChunkSize: {
                NSRange crlfRange = [self.workingBuffer rangeOfData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]
                                                             options:0
                                                               range:NSMakeRange(0, MIN((NSUInteger)256, self.workingBuffer.length))];
                if (crlfRange.location == NSNotFound) {
                    if (self.workingBuffer.length > 256) {
                        self.errorMessage = @"Chunk size line too long";
                        self.errorCode = 400;
                        self.state = HttpChunkedParserStateError;
                        if (error) {
                            *error = [self createError];
                        }
                        return -1;
                    }
                    shouldBreak = YES;
                    break;
                }

                NSData *sizeLineData = [self.workingBuffer subdataWithRange:NSMakeRange(0, crlfRange.location)];
                NSString *sizeLine = [[NSString alloc] initWithData:sizeLineData encoding:NSUTF8StringEncoding];

                if (!sizeLine) {
                    self.errorMessage = @"Invalid chunk size encoding";
                    self.errorCode = 400;
                    self.state = HttpChunkedParserStateError;
                    if (error) {
                        *error = [self createError];
                    }
                    return -1;
                }

                NSString *trimmedSize = [self parseChunkSizeFromLine:sizeLine];
                if (!trimmedSize) {
                    self.errorMessage = @"Invalid chunk size format";
                    self.errorCode = 400;
                    self.state = HttpChunkedParserStateError;
                    if (error) {
                        *error = [self createError];
                    }
                    return -1;
                }

                NSScanner *scanner = [NSScanner scannerWithString:trimmedSize];
                unsigned int chunkSizeValue = 0;
                if (![scanner scanHexInt:&chunkSizeValue]) {
                    self.errorMessage = @"Invalid hex chunk size";
                    self.errorCode = 400;
                    self.state = HttpChunkedParserStateError;
                    if (error) {
                        *error = [self createError];
                    }
                    return -1;
                }

                self.currentChunkSize = (NSUInteger)chunkSizeValue;
                [self.workingBuffer replaceBytesInRange:NSMakeRange(0, crlfRange.location + 2) withBytes:NULL length:0];
                totalConsumed += crlfRange.location + 2;

                if (self.currentChunkSize == 0) {
                    self.state = HttpChunkedParserStateReadingFinalCRLF;
                } else {
                    if (self.maxSize > 0 && self.outputData.length + self.currentChunkSize > self.maxSize) {
                        self.errorMessage = @"Body exceeds maximum size";
                        self.errorCode = 413;
                        self.state = HttpChunkedParserStateError;
                        if (error) {
                            *error = [self createError];
                        }
                        return -1;
                    }
                    self.bytesReadInCurrentChunk = 0;
                    self.state = HttpChunkedParserStateReadingChunkData;
                }
                break;
            }

            case HttpChunkedParserStateReadingChunkData: {
                NSUInteger remainingInChunkAndCRLF = (self.currentChunkSize - self.bytesReadInCurrentChunk) + 2;
                NSUInteger available = self.workingBuffer.length;
                
                if (available >= remainingInChunkAndCRLF) {
                    // We have the rest of the chunk plus the CRLF
                    NSUInteger remainingInChunk = self.currentChunkSize - self.bytesReadInCurrentChunk;
                    if (remainingInChunk > 0) {
                        NSData *chunkData = [self.workingBuffer subdataWithRange:NSMakeRange(0, remainingInChunk)];
                        [self.outputData appendData:chunkData];
                    }
                    
                    const uint8_t *bytes = (const uint8_t *)self.workingBuffer.bytes;
                    if (bytes[remainingInChunk] != '\r' || bytes[remainingInChunk + 1] != '\n') {
                        self.errorMessage = @"Missing CRLF after chunk data";
                        self.errorCode = 400;
                        self.state = HttpChunkedParserStateError;
                        if (error) {
                            *error = [self createError];
                        }
                        return -1;
                    }
                    
                    [self.workingBuffer replaceBytesInRange:NSMakeRange(0, remainingInChunk + 2) withBytes:NULL length:0];
                    totalConsumed += remainingInChunk + 2;
                    self.state = HttpChunkedParserStateReadingChunkSize;
                    self.bytesReadInCurrentChunk = 0;
                } else {
                    // Not enough for the CRLF yet, consume what we can of the chunk
                    NSUInteger remainingInChunk = self.currentChunkSize - self.bytesReadInCurrentChunk;
                    NSUInteger toConsume = MIN(available, remainingInChunk);
                    
                    if (toConsume > 0) {
                        NSData *chunkData = [self.workingBuffer subdataWithRange:NSMakeRange(0, toConsume)];
                        [self.outputData appendData:chunkData];
                        self.bytesReadInCurrentChunk += toConsume;
                        [self.workingBuffer replaceBytesInRange:NSMakeRange(0, toConsume) withBytes:NULL length:0];
                        totalConsumed += toConsume;
                    }
                    
                    shouldBreak = YES;
                }
                break;
            }

            case HttpChunkedParserStateReadingFinalCRLF: {
                if (self.workingBuffer.length >= 2) {
                    const uint8_t *bytes = (const uint8_t *)self.workingBuffer.bytes;
                    if (bytes[0] == '\r' && bytes[1] == '\n') {
                        self.state = HttpChunkedParserStateComplete;
                        [self.workingBuffer replaceBytesInRange:NSMakeRange(0, 2) withBytes:NULL length:0];
                        totalConsumed += 2;
                        shouldBreak = YES;
                    } else if (self.workingBuffer.length >= 4 &&
                               bytes[0] == '\r' && bytes[1] == '\n' &&
                               bytes[2] == '\r' && bytes[3] == '\n') {
                        self.state = HttpChunkedParserStateComplete;
                        [self.workingBuffer replaceBytesInRange:NSMakeRange(0, 4) withBytes:NULL length:0];
                        totalConsumed += 4;
                        shouldBreak = YES;
                    } else if (self.workingBuffer.length >= 4) {
                        self.errorMessage = @"Invalid trailer format";
                        self.errorCode = 400;
                        self.state = HttpChunkedParserStateError;
                        if (error) {
                            *error = [self createError];
                        }
                        return -1;
                    } else {
                         shouldBreak = YES; // Need more data to verify trailer
                    }
                } else {
                    shouldBreak = YES;
                }
                break;
            }

            case HttpChunkedParserStateComplete:
                shouldBreak = YES;
                break;

            case HttpChunkedParserStateError:
                if (error && *error == nil) {
                    *error = [self createError];
                }
                return -1;
        }

        if (shouldBreak) {
            break;
        }
    }

    return totalConsumed;
}

- (NSString *)parseChunkSizeFromLine:(NSString *)line {
    NSRange semicolonRange = [line rangeOfString:@";"];
    if (semicolonRange.location != NSNotFound) {
        return [line substringToIndex:semicolonRange.location];
    }
    return line;
}

- (NSError *)createError {
    return [NSError errorWithDomain:@"HttpChunkedBodyParser"
                               code:self.errorCode
                           userInfo:@{NSLocalizedDescriptionKey: self.errorMessage ?: @"Unknown error"}];
}

- (NSData *)parsedData {
    if (self.state == HttpChunkedParserStateComplete) {
        return [self.outputData copy];
    }
    return nil;
}

- (BOOL)isComplete {
    return self.state == HttpChunkedParserStateComplete;
}

- (NSUInteger)parsedLength {
    return self.outputData.length;
}

- (NSUInteger)remainingExpected {
    switch (self.state) {
        case HttpChunkedParserStateReadingChunkSize:
            return 1;
        case HttpChunkedParserStateReadingChunkData:
            return self.currentChunkSize - self.bytesReadInCurrentChunk + 2;
        case HttpChunkedParserStateReadingFinalCRLF:
            return 2;
        default:
            return 0;
    }
}

- (void)reset {
    self.state = HttpChunkedParserStateReadingChunkSize;
    [self.outputData setLength:0];
    [self.workingBuffer setLength:0];
    self.currentChunkSize = 0;
    self.bytesReadInCurrentChunk = 0;
    self.errorMessage = nil;
    self.errorCode = 0;
}

+ (NSUInteger)parseChunkSizeFromData:(NSData *)data
                               offset:(NSUInteger)offset
                                size:(NSUInteger *)size {
    if (offset >= data.length) {
        return NSNotFound;
    }

    const uint8_t *bytes = data.bytes;
    NSUInteger pos = offset;
    NSUInteger chunkSize = 0;
    BOOL foundDigit = NO;

    while (pos < data.length) {
        uint8_t c = bytes[pos];

        if (c >= '0' && c <= '9') {
            chunkSize = chunkSize * 16 + (c - '0');
            foundDigit = YES;
        } else if (c >= 'a' && c <= 'f') {
            chunkSize = chunkSize * 16 + (c - 'a' + 10);
            foundDigit = YES;
        } else if (c >= 'A' && c <= 'F') {
            chunkSize = chunkSize * 16 + (c - 'A' + 10);
            foundDigit = YES;
        } else if (c == '\r') {
            if (foundDigit) {
                if (pos + 1 < data.length && bytes[pos + 1] == '\n') {
                    *size = chunkSize;
                    return pos + 2;
                }
            }
            return NSNotFound;
        } else if (c == ';' || c == ' ' || c == '\t') {
            if (foundDigit) {
                NSUInteger endPos = pos;
                while (endPos < data.length && bytes[endPos] != '\r') {
                    endPos++;
                }
                if (endPos < data.length && bytes[endPos] == '\r' && endPos + 1 < data.length && bytes[endPos + 1] == '\n') {
                    *size = chunkSize;
                    return endPos + 2;
                }
            }
        } else {
            return NSNotFound;
        }

        if (chunkSize > 0xFFFFFFFF) {
            return NSNotFound;
        }

        pos++;
    }

    return NSNotFound;
}

@end
