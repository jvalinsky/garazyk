// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Core/ATProtoPFPProducer.h"
#import "Core/ATProtoPFP.h"
#include <dispatch/dispatch.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

NSString * const ATProtoPFPProducerErrorDomain = @"com.atproto.pfp.producer";

static const float kPFPRCoeff = 0.299f;
static const float kPFPGCoeff = 0.587f;
static const float kPFPBCoeff = 0.114f;
static const float kPFPDCTScale = 0.17677669529663687f; // sqrt(2/64)
static const int kPFPJaroszPasses = 2;
static const int kPFPJaroszDivisor = 128;

static NSError *PFPProducerError(ATProtoPFPProducerErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ATProtoPFPProducerErrorDomain
                                code:code
                            userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void PFPProducerSetError(NSError **error, ATProtoPFPProducerErrorCode code, NSString *message) {
    if (error) *error = PFPProducerError(code, message);
}

static int PFPJaroszWindow(int dimension) {
    return (dimension + kPFPJaroszDivisor - 1) / kPFPJaroszDivisor;
}

static int PFPFloatCmp(const void *a, const void *b) {
    float fa = *(const float *)a;
    float fb = *(const float *)b;
    return (fa > fb) - (fa < fb);
}

static float PFPMedian256(const float *values) {
    float sorted[256];
    memcpy(sorted, values, sizeof(sorted));
    qsort(sorted, 256, sizeof(float), PFPFloatCmp);
    return sorted[127];
}

static void PFPBox1D(const float *invec, int inStart, float *outvec, int outStart,
                     int vectorLength, int stride, int fullWindowSize) {
    int halfWindowSize = (fullWindowSize + 2) / 2;
    int phase1 = halfWindowSize - 1;
    int phase2 = fullWindowSize - halfWindowSize + 1;
    int phase3 = vectorLength - fullWindowSize;
    int phase4 = halfWindowSize - 1;
    int li = 0;
    int ri = 0;
    int oi = 0;
    float sum = 0.0f;
    int currentWindowSize = 0;

    for (int i = 0; i < phase1; i++) {
        sum += invec[inStart + ri];
        currentWindowSize++;
        ri += stride;
    }
    for (int i = 0; i < phase2; i++) {
        sum += invec[inStart + ri];
        currentWindowSize++;
        outvec[outStart + oi] = sum / (float)currentWindowSize;
        ri += stride;
        oi += stride;
    }
    for (int i = 0; i < phase3; i++) {
        sum += invec[inStart + ri];
        sum -= invec[inStart + li];
        outvec[outStart + oi] = sum / (float)currentWindowSize;
        li += stride;
        ri += stride;
        oi += stride;
    }
    for (int i = 0; i < phase4; i++) {
        sum -= invec[inStart + li];
        currentWindowSize--;
        outvec[outStart + oi] = sum / (float)currentWindowSize;
        li += stride;
        oi += stride;
    }
}

static void PFPJaroszFilter(float *buffer1, float *buffer2, int numRows, int numCols,
                            int windowAlongRows, int windowAlongCols) {
    for (int pass = 0; pass < kPFPJaroszPasses; pass++) {
        for (int i = 0; i < numRows; i++) {
            PFPBox1D(buffer1, i * numCols, buffer2, i * numCols, numCols, 1, windowAlongRows);
        }
        for (int j = 0; j < numCols; j++) {
            PFPBox1D(buffer2, j, buffer1, j, numRows, numCols, windowAlongCols);
        }
    }
}

static void PFPDecimate(const float *in, int inRows, int inCols, float out64[64][64]) {
    for (int i = 0; i < 64; i++) {
        int ini = (int)(((i + 0.5) * inRows) / 64.0);
        for (int j = 0; j < 64; j++) {
            int inj = (int)(((j + 0.5) * inCols) / 64.0);
            out64[i][j] = in[ini * inCols + inj];
        }
    }
}

static int PFPQuality(const float buffer64[64][64]) {
    int gradientSum = 0;
    for (int i = 0; i < 63; i++) {
        for (int j = 0; j < 64; j++) {
            float u = buffer64[i][j];
            float v = buffer64[i + 1][j];
            int d = (int)(((u - v) * 100.0f) / 255.0f);
            gradientSum += abs(d);
        }
    }
    for (int i = 0; i < 64; i++) {
        for (int j = 0; j < 63; j++) {
            float u = buffer64[i][j];
            float v = buffer64[i][j + 1];
            int d = (int)(((u - v) * 100.0f) / 255.0f);
            gradientSum += abs(d);
        }
    }
    int quality = gradientSum / 90;
    return quality > 100 ? 100 : quality;
}

static void PFPDCT64To16(const float A[64][64], float T[16][64], float B[16][16],
                         const float D[16][64]) {
    for (int i = 0; i < 16; i++) {
        for (int j = 0; j < 64; j++) {
            float sumk = 0.0f;
            for (int k = 0; k < 64; k++) {
                sumk += D[i][k] * A[k][j];
            }
            T[i][j] = sumk;
        }
    }
    for (int i = 0; i < 16; i++) {
        for (int j = 0; j < 16; j++) {
            float sumk = 0.0f;
            for (int k = 0; k < 64; k++) {
                sumk += T[i][k] * D[j][k];
            }
            B[i][j] = sumk;
        }
    }
}

static void PFPBitsFromDCT(const float dct[16][16], uint8_t out32[32]) {
    float flat[256];
    for (int i = 0; i < 16; i++) {
        for (int j = 0; j < 16; j++) {
            flat[i * 16 + j] = dct[i][j];
        }
    }
    float median = PFPMedian256(flat);
    uint16_t words[16];
    memset(words, 0, sizeof(words));
    for (int i = 0; i < 16; i++) {
        for (int j = 0; j < 16; j++) {
            int k = i * 16 + j;
            if (dct[i][j] > median) {
                words[(k & 255) >> 4] |= (uint16_t)(1u << (k & 15));
            }
        }
    }
    for (int i = 0; i < 16; i++) {
        out32[i * 2] = (uint8_t)(words[i] & 0xff);
        out32[i * 2 + 1] = (uint8_t)((words[i] >> 8) & 0xff);
    }
}

@interface ATProtoPFPHashResult ()
@property (nonatomic, strong, readwrite) ATProtoPFP *pfp;
@property (nonatomic, assign, readwrite) NSInteger quality;
@end

@implementation ATProtoPFPHashResult
@end

@implementation ATProtoPFPProducer

+ (nullable ATProtoPFPHashResult *)hashFloatLumaWidth:(NSUInteger)width
                                               height:(NSUInteger)height
                                              samples:(const float *)samples
                                                error:(NSError **)error {
    if (width == 0 || height == 0 || width > 8192 || height > 8192 || samples == NULL) {
        PFPProducerSetError(error, ATProtoPFPProducerErrorInvalidArgument,
                            @"PDQ producer requires a non-empty luma buffer within bounds");
        return nil;
    }

    NSUInteger count = width * height;
    float *buffer1 = (float *)malloc(count * sizeof(float));
    float *buffer2 = (float *)malloc(count * sizeof(float));
    if (!buffer1 || !buffer2) {
        free(buffer1);
        free(buffer2);
        PFPProducerSetError(error, ATProtoPFPProducerErrorHashFailed, @"PDQ producer out of memory");
        return nil;
    }
    memcpy(buffer1, samples, count * sizeof(float));

    static float DCT[16][64];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        for (int i = 0; i < 16; i++) {
            for (int j = 0; j < 64; j++) {
                DCT[i][j] = (float)(kPFPDCTScale *
                    cos((M_PI / 2.0 / 64.0) * (i + 1) * (2 * j + 1)));
            }
        }
    });

    int winRows = PFPJaroszWindow((int)width);
    int winCols = PFPJaroszWindow((int)height);
    if (winRows < 1) winRows = 1;
    if (winCols < 1) winCols = 1;
    PFPJaroszFilter(buffer1, buffer2, (int)height, (int)width, winRows, winCols);

    float buffer64[64][64];
    float temp16x64[16][64];
    float dct16[16][16];
    PFPDecimate(buffer1, (int)height, (int)width, buffer64);
    int quality = PFPQuality(buffer64);
    PFPDCT64To16(buffer64, temp16x64, dct16, DCT);

    uint8_t digest[32];
    PFPBitsFromDCT(dct16, digest);
    free(buffer1);
    free(buffer2);

    uint8_t framed[34];
    framed[0] = (uint8_t)ATProtoPFPAlgorithmPDQ;
    framed[1] = 32;
    memcpy(framed + 2, digest, 32);
    NSError *parseError = nil;
    ATProtoPFP *pfp = [ATProtoPFP pfpFromBytes:[NSData dataWithBytes:framed length:34]
                                         error:&parseError];
    if (!pfp) {
        if (error) *error = parseError ?: PFPProducerError(ATProtoPFPProducerErrorHashFailed,
                                                           @"PDQ producer failed to mint PFP");
        return nil;
    }

    ATProtoPFPHashResult *result = [[ATProtoPFPHashResult alloc] init];
    result.pfp = pfp;
    result.quality = quality;
    return result;
}

+ (nullable ATProtoPFPHashResult *)hashRGB8Width:(NSUInteger)width
                                          height:(NSUInteger)height
                                     bytesPerRow:(NSUInteger)bytesPerRow
                                          pixels:(const uint8_t *)pixels
                                           error:(NSError **)error {
    if (width == 0 || height == 0 || pixels == NULL || bytesPerRow < width * 3) {
        PFPProducerSetError(error, ATProtoPFPProducerErrorInvalidArgument,
                            @"PDQ producer requires packed RGB8 pixels");
        return nil;
    }
    NSUInteger count = width * height;
    float *luma = (float *)malloc(count * sizeof(float));
    if (!luma) {
        PFPProducerSetError(error, ATProtoPFPProducerErrorHashFailed, @"PDQ producer out of memory");
        return nil;
    }
    for (NSUInteger y = 0; y < height; y++) {
        const uint8_t *row = pixels + y * bytesPerRow;
        for (NSUInteger x = 0; x < width; x++) {
            const uint8_t *px = row + x * 3;
            luma[y * width + x] = kPFPRCoeff * px[0] + kPFPGCoeff * px[1] + kPFPBCoeff * px[2];
        }
    }
    ATProtoPFPHashResult *result = [self hashFloatLumaWidth:width
                                                     height:height
                                                    samples:luma
                                                      error:error];
    free(luma);
    return result;
}

@end
