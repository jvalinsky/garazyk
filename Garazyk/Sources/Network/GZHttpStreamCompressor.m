// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/GZHttpStreamCompressor.h"

#include <stdlib.h>
#include <string.h>
#include <zlib.h>
#include <zstd.h>

NS_ASSUME_NONNULL_BEGIN

static const int kGZHttpCompressionLevel = 3;

static NSError *GZHttpContentEncodingMakeError(GZHttpContentEncodingErrorCode code, NSString *message) {
    return [NSError errorWithDomain:GZHttpContentEncodingErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey : message ?: @"content-encoding error"}];
}

@interface GZHttpStreamCompressor () {
    ZSTD_CCtx *_zstdCtx;
    z_stream _gzipStream;
    BOOL _gzipActive;
    BOOL _finished;
}
@property (nonatomic, assign, readwrite) GZHttpContentEncoding encoding;
@end

@implementation GZHttpStreamCompressor

- (nullable instancetype)initWithEncoding:(GZHttpContentEncoding)encoding
                                    error:(NSError * _Nullable * _Nullable)error {
    self = [super init];
    if (!self) {
        return nil;
    }

    _encoding = encoding;
    _finished = NO;
    _zstdCtx = NULL;
    memset(&_gzipStream, 0, sizeof(_gzipStream));
    _gzipActive = NO;

    if (encoding == GZHttpContentEncodingIdentity) {
        return self;
    }

    if (encoding == GZHttpContentEncodingZstd) {
        _zstdCtx = ZSTD_createCCtx();
        if (!_zstdCtx) {
            if (error) {
                *error = GZHttpContentEncodingMakeError(GZHttpContentEncodingErrorInitFailed,
                                                        @"Failed to create zstd compression context");
            }
            return nil;
        }
        size_t rc = ZSTD_CCtx_setParameter(_zstdCtx, ZSTD_c_compressionLevel, kGZHttpCompressionLevel);
        if (ZSTD_isError(rc)) {
            ZSTD_freeCCtx(_zstdCtx);
            _zstdCtx = NULL;
            if (error) {
                *error = GZHttpContentEncodingMakeError(GZHttpContentEncodingErrorInitFailed,
                                                        @"Failed to set zstd compression level");
            }
            return nil;
        }
        return self;
    }

    if (encoding == GZHttpContentEncodingGzip) {
        int zrc = deflateInit2(&_gzipStream,
                               kGZHttpCompressionLevel,
                               Z_DEFLATED,
                               15 + 16, /* gzip wrapper */
                               8,
                               Z_DEFAULT_STRATEGY);
        if (zrc != Z_OK) {
            if (error) {
                *error = GZHttpContentEncodingMakeError(GZHttpContentEncodingErrorInitFailed,
                                                        @"Failed to initialize gzip (zlib) stream");
            }
            return nil;
        }
        _gzipActive = YES;
        return self;
    }

    if (error) {
        *error = GZHttpContentEncodingMakeError(GZHttpContentEncodingErrorUnsupported,
                                                @"Unsupported content encoding for compressor");
    }
    return nil;
}

- (void)dealloc {
    if (_zstdCtx) {
        ZSTD_freeCCtx(_zstdCtx);
        _zstdCtx = NULL;
    }
    if (_gzipActive) {
        deflateEnd(&_gzipStream);
        _gzipActive = NO;
    }
}

- (nullable NSData *)compressChunk:(NSData *)input
                             error:(NSError * _Nullable * _Nullable)error {
    if (_finished) {
        if (error) {
            *error = GZHttpContentEncodingMakeError(GZHttpContentEncodingErrorCompressFailed,
                                                    @"Compressor already finished");
        }
        return nil;
    }
    if (self.encoding == GZHttpContentEncodingIdentity) {
        return input ?: [NSData data];
    }
    if (input.length == 0) {
        return [NSData data];
    }

    if (self.encoding == GZHttpContentEncodingZstd) {
        return [self zstdProcessInput:input endFrame:NO error:error];
    }
    return [self gzipProcessInput:input finish:NO error:error];
}

- (nullable NSData *)finishWithError:(NSError * _Nullable * _Nullable)error {
    if (_finished) {
        return [NSData data];
    }
    _finished = YES;

    if (self.encoding == GZHttpContentEncodingIdentity) {
        return [NSData data];
    }
    if (self.encoding == GZHttpContentEncodingZstd) {
        return [self zstdProcessInput:[NSData data] endFrame:YES error:error];
    }
    return [self gzipProcessInput:[NSData data] finish:YES error:error];
}

- (nullable NSData *)zstdProcessInput:(NSData *)input
                             endFrame:(BOOL)endFrame
                                error:(NSError * _Nullable * _Nullable)error {
    ZSTD_inBuffer inBuf = {
        .src = input.bytes,
        .size = input.length,
        .pos = 0,
    };

    NSMutableData *outData = [NSMutableData data];
    size_t outCap = ZSTD_CStreamOutSize();
    void *outBufMem = malloc(outCap);
    if (!outBufMem) {
        if (error) {
            *error = GZHttpContentEncodingMakeError(GZHttpContentEncodingErrorCompressFailed,
                                                    @"Out of memory during zstd compression");
        }
        return nil;
    }

    ZSTD_EndDirective directive = endFrame ? ZSTD_e_end : ZSTD_e_continue;
    size_t remaining = 0;
    do {
        ZSTD_outBuffer outBuf = {
            .dst = outBufMem,
            .size = outCap,
            .pos = 0,
        };
        remaining = ZSTD_compressStream2(_zstdCtx, &outBuf, &inBuf, directive);
        if (ZSTD_isError(remaining)) {
            free(outBufMem);
            if (error) {
                *error = GZHttpContentEncodingMakeError(
                    endFrame ? GZHttpContentEncodingErrorFinishFailed
                             : GZHttpContentEncodingErrorCompressFailed,
                    [NSString stringWithFormat:@"zstd compress failed: %s",
                                               ZSTD_getErrorName(remaining)]);
            }
            return nil;
        }
        if (outBuf.pos > 0) {
            [outData appendBytes:outBuf.dst length:outBuf.pos];
        }
    } while (endFrame ? (remaining != 0) : (inBuf.pos < inBuf.size));

    free(outBufMem);
    return [outData copy];
}

- (nullable NSData *)gzipProcessInput:(NSData *)input
                               finish:(BOOL)finish
                                error:(NSError * _Nullable * _Nullable)error {
    _gzipStream.next_in = (Bytef *)(void *)input.bytes;
    _gzipStream.avail_in = (uInt)input.length;

    NSMutableData *outData = [NSMutableData data];
    uint8_t outBuf[64 * 1024];
    int flush = finish ? Z_FINISH : Z_NO_FLUSH;
    int zrc = Z_OK;

    do {
        _gzipStream.next_out = outBuf;
        _gzipStream.avail_out = (uInt)sizeof(outBuf);
        zrc = deflate(&_gzipStream, flush);
        if (zrc != Z_OK && zrc != Z_STREAM_END && zrc != Z_BUF_ERROR) {
            if (error) {
                *error = GZHttpContentEncodingMakeError(
                    finish ? GZHttpContentEncodingErrorFinishFailed
                           : GZHttpContentEncodingErrorCompressFailed,
                    [NSString stringWithFormat:@"gzip deflate failed (%d)", zrc]);
            }
            return nil;
        }
        NSUInteger produced = sizeof(outBuf) - _gzipStream.avail_out;
        if (produced > 0) {
            [outData appendBytes:outBuf length:produced];
        }
    } while (_gzipStream.avail_out == 0 || (finish && zrc != Z_STREAM_END));

    if (finish && zrc != Z_STREAM_END) {
        if (error) {
            *error = GZHttpContentEncodingMakeError(GZHttpContentEncodingErrorFinishFailed,
                                                    @"gzip finish did not reach Z_STREAM_END");
        }
        return nil;
    }

    return [outData copy];
}

@end

NS_ASSUME_NONNULL_END
