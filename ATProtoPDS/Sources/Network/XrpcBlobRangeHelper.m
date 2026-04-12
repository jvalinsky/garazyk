#import "Network/XrpcBlobRangeHelper.h"

#include <errno.h>

static NSString *trimmedNonEmptyString(NSString *value) {
  if (![value isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSString *trimmed = [value
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]];
  return trimmed.length > 0 ? trimmed : nil;
}

static BOOL parseUnsignedLongLongString(NSString *value,
                                        unsigned long long *result) {
  NSString *trimmed = trimmedNonEmptyString(value);
  if (trimmed.length == 0) {
    return NO;
  }

  errno = 0;
  char *end = NULL;
  unsigned long long parsed = strtoull(trimmed.UTF8String, &end, 10);
  if (errno != 0 || !end || end == trimmed.UTF8String || *end != '\0') {
    return NO;
  }

  if (result) {
    *result = parsed;
  }
  return YES;
}

@implementation XrpcBlobRangeHelper

+ (BOOL)parseByteRangeHeader:(nullable NSString *)rangeHeader
                 totalLength:(unsigned long long)totalLength
                    hasRange:(nullable BOOL *)hasRange
                 satisfiable:(nullable BOOL *)satisfiable
                       start:(nullable unsigned long long *)start
                         end:(nullable unsigned long long *)end
               failureReason:(NSString *_Nullable *_Nullable)failureReason {
  if (hasRange) {
    *hasRange = NO;
  }
  if (satisfiable) {
    *satisfiable = YES;
  }
  if (start) {
    *start = 0;
  }
  if (end) {
    *end = totalLength > 0 ? (totalLength - 1) : 0;
  }
  if (failureReason) {
    *failureReason = nil;
  }

  NSString *trimmedRange = trimmedNonEmptyString(rangeHeader);
  if (trimmedRange.length == 0) {
    return YES;
  }

  if (hasRange) {
    *hasRange = YES;
  }

  if (![trimmedRange.lowercaseString hasPrefix:@"bytes="]) {
    if (failureReason) {
      *failureReason = @"Range header must use bytes units";
    }
    return NO;
  }

  NSString *spec = [trimmedRange substringFromIndex:6];
  if ([spec containsString:@","]) {
    if (failureReason) {
      *failureReason = @"Multiple ranges are not supported";
    }
    return NO;
  }

  NSRange dashRange = [spec rangeOfString:@"-"];
  if (dashRange.location == NSNotFound) {
    if (failureReason) {
      *failureReason = @"Range header is malformed";
    }
    return NO;
  }

  NSString *startPart = [spec substringToIndex:dashRange.location];
  NSString *endPart = [spec substringFromIndex:dashRange.location + 1];
  if (startPart.length == 0 && endPart.length == 0) {
    if (failureReason) {
      *failureReason = @"Range header is malformed";
    }
    return NO;
  }

  if (totalLength == 0) {
    if (satisfiable) {
      *satisfiable = NO;
    }
    return YES;
  }

  if (startPart.length > 0) {
    unsigned long long parsedStart = 0;
    if (!parseUnsignedLongLongString(startPart, &parsedStart)) {
      if (failureReason) {
        *failureReason = @"Range start is invalid";
      }
      return NO;
    }

    unsigned long long parsedEnd = totalLength - 1;
    if (endPart.length > 0) {
      if (!parseUnsignedLongLongString(endPart, &parsedEnd)) {
        if (failureReason) {
          *failureReason = @"Range end is invalid";
        }
        return NO;
      }
    }

    if (parsedStart >= totalLength) {
      if (satisfiable) {
        *satisfiable = NO;
      }
      return YES;
    }
    if (parsedEnd < parsedStart) {
      if (satisfiable) {
        *satisfiable = NO;
      }
      return YES;
    }
    if (parsedEnd >= totalLength) {
      parsedEnd = totalLength - 1;
    }

    if (start) {
      *start = parsedStart;
    }
    if (end) {
      *end = parsedEnd;
    }
    return YES;
  }

  unsigned long long suffixLength = 0;
  if (!parseUnsignedLongLongString(endPart, &suffixLength) ||
      suffixLength == 0) {
    if (satisfiable) {
      *satisfiable = NO;
    }
    return YES;
  }

  unsigned long long parsedStart =
      (suffixLength >= totalLength) ? 0 : (totalLength - suffixLength);
  if (start) {
    *start = parsedStart;
  }
  if (end) {
    *end = totalLength - 1;
  }
  return YES;
}

+ (nullable HttpResponseBodyChunkProducer)
    blobFileChunkProducerForPath:(NSString *)path
                     startOffset:(unsigned long long)startOffset
                       endOffset:(unsigned long long)endOffset
                           error:(NSError **)error {
  NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:path];
  if (!fileHandle) {
    if (error) {
      *error = [NSError errorWithDomain:@"XrpcBlobStream"
                                   code:1
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Failed to open blob file for streaming"
                               }];
    }
    return nil;
  }

  @try {
    [fileHandle seekToFileOffset:startOffset];
  } @catch (NSException *exception) {
    @try {
      [fileHandle closeFile];
    } @catch (__unused NSException *closeException) {
    }
    if (error) {
      *error = [NSError errorWithDomain:@"XrpcBlobStream"
                                   code:2
                               userInfo:@{
                                 NSLocalizedDescriptionKey : exception.reason
                                     ?: @"Failed to seek blob file"
                               }];
    }
    return nil;
  }

  __block NSFileHandle *capturedHandle = fileHandle;
  __block unsigned long long bytesRemaining =
      (endOffset >= startOffset) ? (endOffset - startOffset + 1) : 0;
  static const NSUInteger kBlobChunkSize = 64 * 1024;

  return ^NSData *_Nullable(NSError **producerError) {
    if (!capturedHandle || bytesRemaining == 0) {
      if (capturedHandle) {
        @try {
          [capturedHandle closeFile];
        } @catch (__unused NSException *closeException) {
        }
        capturedHandle = nil;
      }
      return nil;
    }

    NSUInteger readLength =
        (NSUInteger)MIN((unsigned long long)kBlobChunkSize, bytesRemaining);
    NSData *chunk = [capturedHandle readDataOfLength:readLength];
    if (chunk.length == 0) {
      @try {
        [capturedHandle closeFile];
      } @catch (__unused NSException *closeException) {
      }
      capturedHandle = nil;
      if (producerError && bytesRemaining > 0) {
        *producerError = [NSError errorWithDomain:@"XrpcBlobStream"
                                             code:3
                                         userInfo:@{
                                           NSLocalizedDescriptionKey :
                                               @"Unexpected end-of-file while streaming blob"
                                         }];
      }
      bytesRemaining = 0;
      return nil;
    }

    bytesRemaining -= (unsigned long long)chunk.length;
    if (bytesRemaining == 0) {
      @try {
        [capturedHandle closeFile];
      } @catch (__unused NSException *closeException) {
      }
      capturedHandle = nil;
    }

    return chunk;
  };
}

@end

