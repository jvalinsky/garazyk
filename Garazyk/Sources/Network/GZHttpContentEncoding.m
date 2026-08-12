// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/GZHttpContentEncoding.h"
#import "Network/GZHttpStreamCompressor.h"

#include <stdlib.h>
#include <string.h>

#if defined(__APPLE__) || defined(__linux__)
#include <strings.h>
#endif

NSString * const GZHttpContentEncodingErrorDomain = @"com.garazyk.http.content-encoding";

NS_ASSUME_NONNULL_BEGIN

static float GZHttpMaxFloat(float a, float b) {
    return a > b ? a : b;
}

static BOOL GZHttpContentEncodingDisabled(void) {
    const char *raw = getenv("PDS_HTTP_CONTENT_ENCODING");
    if (!raw || raw[0] == '\0') {
        return NO;
    }
    return strcmp(raw, "0") == 0
        || strcasecmp(raw, "off") == 0
        || strcasecmp(raw, "false") == 0
        || strcasecmp(raw, "identity") == 0;
}

static float GZHttpParseQValue(NSString * _Nullable paramPart, float fallback) {
    if (paramPart.length == 0) {
        return fallback;
    }
    NSString *trimmed = [paramPart stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (![trimmed.lowercaseString hasPrefix:@"q="]) {
        return fallback;
    }
    NSString *value = [trimmed substringFromIndex:2];
    NSScanner *scanner = [NSScanner scannerWithString:value];
    float q = fallback;
    if (![scanner scanFloat:&q]) {
        return 0.0f;
    }
    if (q < 0.0f) {
        return 0.0f;
    }
    if (q > 1.0f) {
        return 1.0f;
    }
    return q;
}

GZHttpContentEncoding GZHttpContentEncodingFromAcceptEncoding(NSString * _Nullable acceptEncoding) {
    if (GZHttpContentEncodingDisabled()) {
        return GZHttpContentEncodingIdentity;
    }
    if (acceptEncoding.length == 0) {
        return GZHttpContentEncodingIdentity;
    }

    float qZstd = -1.0f;
    float qGzip = -1.0f;
    float qIdentity = -1.0f;
    float qStar = -1.0f;

    NSArray<NSString *> *items = [acceptEncoding componentsSeparatedByString:@","];
    for (NSString *item in items) {
        NSArray<NSString *> *parts = [item componentsSeparatedByString:@";"];
        if (parts.count == 0) {
            continue;
        }
        NSString *token = [[parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
        float q = 1.0f;
        for (NSUInteger i = 1; i < parts.count; i++) {
            if ([[[parts[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString] hasPrefix:@"q="]) {
                q = GZHttpParseQValue(parts[i], 0.0f);
            }
        }

        if ([token isEqualToString:@"zstd"]) {
            qZstd = GZHttpMaxFloat(qZstd, q);
        } else if ([token isEqualToString:@"gzip"] || [token isEqualToString:@"x-gzip"]) {
            qGzip = GZHttpMaxFloat(qGzip, q);
        } else if ([token isEqualToString:@"identity"]) {
            qIdentity = GZHttpMaxFloat(qIdentity, q);
        } else if ([token isEqualToString:@"*"]) {
            qStar = GZHttpMaxFloat(qStar, q);
        }
    }

    if (qZstd < 0.0f && qStar >= 0.0f) {
        qZstd = qStar;
    }
    if (qGzip < 0.0f && qStar >= 0.0f) {
        qGzip = qStar;
    }
    if (qIdentity < 0.0f && qStar >= 0.0f) {
        qIdentity = qStar;
    }

    // Absent encodings count as refused for selection; treat missing as -1.
    float bestQ = -1.0f;
    GZHttpContentEncoding best = GZHttpContentEncodingIdentity;

    // Prefer zstd on ties (Hubble).
    if (qZstd > bestQ) {
        bestQ = qZstd;
        best = GZHttpContentEncodingZstd;
    }
    if (qGzip > bestQ) {
        bestQ = qGzip;
        best = GZHttpContentEncodingGzip;
    }
    if (qIdentity > bestQ) {
        bestQ = qIdentity;
        best = GZHttpContentEncodingIdentity;
    }

    if (bestQ <= 0.0f) {
        return GZHttpContentEncodingIdentity;
    }
    return best;
}

NSString * _Nullable GZHttpContentEncodingHeaderValue(GZHttpContentEncoding encoding) {
    switch (encoding) {
        case GZHttpContentEncodingGzip:
            return @"gzip";
        case GZHttpContentEncodingZstd:
            return @"zstd";
        case GZHttpContentEncodingIdentity:
        default:
            return nil;
    }
}

HttpResponseBodyChunkProducer GZHttpCompressingBodyChunkProducer(
    HttpResponseBodyChunkProducer inner,
    GZHttpContentEncoding encoding) {
    if (!inner) {
        return ^NSData * _Nullable(NSError * _Nullable * _Nullable error) {
            (void)error;
            return [NSData data];
        };
    }
    if (encoding == GZHttpContentEncodingIdentity) {
        return [inner copy];
    }

    NSError *initError = nil;
    GZHttpStreamCompressor *compressor = [[GZHttpStreamCompressor alloc] initWithEncoding:encoding
                                                                                    error:&initError];
    if (!compressor) {
        return ^NSData * _Nullable(NSError * _Nullable * _Nullable error) {
            if (error) {
                *error = initError ?: [NSError errorWithDomain:GZHttpContentEncodingErrorDomain
                                                          code:GZHttpContentEncodingErrorInitFailed
                                                      userInfo:@{NSLocalizedDescriptionKey : @"Compressor init failed"}];
            }
            return nil;
        };
    }

    __block BOOL finished = NO;
    __block NSMutableData *pending = nil;

    return ^NSData * _Nullable(NSError * _Nullable * _Nullable error) {
        while (YES) {
            if (pending.length > 0) {
                NSData *out = [pending copy];
                pending = nil;
                return out;
            }
            if (finished) {
                return [NSData data];
            }

            NSError *innerError = nil;
            NSData *chunk = inner(&innerError);
            if (innerError) {
                if (error) {
                    *error = innerError;
                }
                return nil;
            }

            if (chunk.length > 0) {
                NSError *compressError = nil;
                NSData *compressed = [compressor compressChunk:chunk error:&compressError];
                if (!compressed) {
                    if (error) {
                        *error = compressError;
                    }
                    return nil;
                }
                if (compressed.length == 0) {
                    // Backend buffered; pull more identity input without signaling EOS.
                    continue;
                }
                return compressed;
            }

            NSError *finishError = nil;
            NSData *tail = [compressor finishWithError:&finishError];
            finished = YES;
            if (!tail) {
                if (error) {
                    *error = finishError;
                }
                return nil;
            }
            if (tail.length == 0) {
                return [NSData data];
            }
            pending = nil;
            return tail;
        }
    };
}

void GZHttpResponseSetExportBodyChunkProducer(
    ATProtoHttpResponse *response,
    HttpResponseBodyChunkProducer producer,
    NSString * _Nullable acceptEncodingHeader) {
    GZHttpContentEncoding encoding = GZHttpContentEncodingFromAcceptEncoding(acceptEncodingHeader);
    HttpResponseBodyChunkProducer wrapped = GZHttpCompressingBodyChunkProducer(producer, encoding);

    NSString *contentEncoding = GZHttpContentEncodingHeaderValue(encoding);
    if (contentEncoding) {
        [response setHeader:contentEncoding forKey:@"Content-Encoding"];
    }

    [response setHeader:@"Accept, Accept-Encoding" forKey:@"Vary"];
    [response setBodyChunkProducer:wrapped chunkedTransferEncoding:YES];
}

NS_ASSUME_NONNULL_END
