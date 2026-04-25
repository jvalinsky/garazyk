// JWTMutator.mm - JWT structural custom mutator
// Implements LLVMFuzzerCustomMutator for JWT tokens (header.payload.signature)

#if __has_include("Auth/JWT.h")
#import "Auth/JWT.h"
#endif

#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <cinttypes>

static const char kBase64URLChars[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

static const char kJWTValidMethods[][8] = {
    "HS256", "HS384", "HS512", "RS256", "RS384", "RS512",
    "ES256", "ES384", "ES512", "PS256", "PS384", "PS512", "none"
};

static int isBase64URLChar(char c) {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
           (c >= '0' && c <= '9') || c == '-' || c == '_';
}

static int isValidJWT(const uint8_t *data, size_t size) {
    if (!data || size < 2) return 0;
    size_t dotCount = 0;
    for (size_t i = 0; i < size; i++) {
        if (data[i] == '.') dotCount++;
        if (dotCount > 2) return 0;
    }
    return (dotCount == 2);
}

static size_t findSegmentEnd(const uint8_t *data, size_t size, size_t start) {
    for (size_t i = start; i < size; i++) {
        if (data[i] == '.' || data[i] == '\0') return i;
    }
    return size;
}

static uint32_t xorShift(uint32_t state) {
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    return state;
}

static size_t mutateFlipByte(uint8_t *data, size_t size, size_t pos, uint32_t seed) {
    if (pos >= size) return size;
    data[pos] ^= (seed & 0xFF);
    return size;
}

static size_t mutateDeleteByte(uint8_t *data, size_t size, size_t pos) {
    if (pos >= size || size <= 1) return size;
    memmove(data + pos, data + pos + 1, size - pos - 1);
    return size - 1;
}

static size_t mutateInsertByte(uint8_t *data, size_t size, size_t maxSize, size_t pos, uint32_t seed) {
    if (size >= maxSize || pos > size) return size;
    uint8_t toInsert = kBase64URLChars[seed % strlen(kBase64URLChars)];
    memmove(data + pos + 1, data + pos, size - pos);
    data[pos] = toInsert;
    return size + 1;
}

static size_t mutateSwapSegments(uint8_t *data, size_t size, uint32_t seed) {
    if (!isValidJWT(data, size)) return size;

    size_t firstDot = SIZE_MAX, secondDot = SIZE_MAX;
    for (size_t i = 0; i < size && (firstDot == SIZE_MAX || secondDot == SIZE_MAX); i++) {
        if (data[i] == '.') {
            if (firstDot == SIZE_MAX) firstDot = i;
            else if (secondDot == SIZE_MAX) secondDot = i;
        }
    }
    if (firstDot == SIZE_MAX || secondDot == SIZE_MAX) return size;

    size_t headerLen = firstDot;
    size_t payloadLen = secondDot - firstDot - 1;
    size_t sigStart = secondDot + 1;
    size_t sigLen = size - sigStart;

    if ((seed & 1) && headerLen > 0 && sigLen > 0) {
        uint8_t *header = data;
        uint8_t *sig = data + sigStart;
        uint8_t tmp[256];
        size_t swapLen = headerLen < sizeof(tmp) ? headerLen : sizeof(tmp);
        memcpy(tmp, header, swapLen);
        memcpy(header, sig, swapLen);
        memcpy(sig, tmp, swapLen);
    }

    return size;
}

static size_t mutateTruncateSegment(uint8_t *data, size_t size, uint32_t seed) {
    if (!isValidJWT(data, size)) return size;

    size_t dotPositions[3] = {0, 0, 0};
    size_t dotIdx = 0;
    for (size_t i = 0; i < size && dotIdx < 3; i++) {
        if (data[i] == '.') dotPositions[dotIdx++] = i;
    }
    if (dotIdx < 2) return size;

    int segment = seed % 3;
    size_t segStart = (segment == 0) ? 0 : dotPositions[segment - 1] + 1;
    size_t segEnd = (segment == 2) ? size : dotPositions[segment];
    size_t segLen = segEnd - segStart;

    if (segLen <= 1) return size;

    size_t truncateAt = segStart + (seed % (segLen - 1));
    if (truncateAt >= segEnd) return size;

    int truncateFrom = (seed >> 2) % 2;
    if (truncateFrom) {
        size_t newLen = size - (segEnd - truncateAt);
        if (segment < 2) {
            memmove(data + truncateAt, data + segEnd, size - segEnd);
        } else {
            data[truncateAt] = '\0';
        }
        return newLen;
    } else {
        size_t newLen = size - (truncateAt - segStart);
        memmove(data + segStart, data + truncateAt, size - truncateAt);
        data[segStart] = '.';
        return newLen;
    }
}

static size_t mutateCorruptDelimiter(uint8_t *data, size_t size, uint32_t seed) {
    size_t dotCount = 0;
    for (size_t i = 0; i < size; i++) {
        if (data[i] == '.') dotCount++;
    }
    if (dotCount < 2) return size;

    size_t dotPos = 0;
    size_t dotsSeen = (seed % dotCount);
    for (size_t i = 0; i < size; i++) {
        if (data[i] == '.') {
            if (dotPos == dotsSeen) {
                dotPos = i;
                break;
            }
            dotPos++;
        }
    }

    if (dotPos > 0 && dotPos < size) {
        char replacements[] = {'-', '_', ',', '/', '\\', '#'};
        data[dotPos] = replacements[seed % (sizeof(replacements) / sizeof(char))];
    }

    return size;
}

static size_t addMissingDelimiters(uint8_t *data, size_t size, size_t maxSize, uint32_t seed) {
    if (size >= maxSize - 2 || size < 5) return size;

    size_t dotCount = 0;
    for (size_t i = 0; i < size; i++) {
        if (data[i] == '.') dotCount++;
    }

    if (dotCount == 0 || dotCount == 2) return size;

    if (dotCount == 1) {
        for (size_t i = 0; i < size; i++) {
            if (data[i] == '.') {
                if (i < size - 1 && isBase64URLChar(data[i + 1])) {
                    if (seed % 2 == 0 && size + 1 < maxSize) {
                        memmove(data + i + 2, data + i + 1, size - i - 1);
                        data[i + 1] = '.';
                        return size + 1;
                    }
                }
            }
        }
    }

    return size;
}

static size_t generateRandomJWT(uint8_t *data, size_t maxSize, uint32_t seed) {
    uint32_t r = seed;

    const char *alg = kJWTValidMethods[r % (sizeof(kJWTValidMethods) / sizeof(kJWTValidMethods[0]))];
    r = xorShift(r);

    size_t headerLen = 0;
   snprintf((char *)data, maxSize, "{\"alg\":\"%s\"}", alg);
    headerLen = strlen((char *)data);

    data[headerLen] = '.';
    r = xorShift(r);

    size_t payloadLen = (r % 100) + 10;
    r = xorShift(r);
    for (size_t i = 0; i < payloadLen && (headerLen + 1 + i) < maxSize; i++) {
        data[headerLen + 1 + i] = kBase64URLChars[r % strlen(kBase64URLChars)];
        r = xorShift(r);
    }
    size_t totalLen = headerLen + 1 + payloadLen;

    data[totalLen] = '.';
    r = xorShift(r);

    size_t sigLen = (r % 40) + 10;
    for (size_t i = 0; i < sigLen && (totalLen + 1 + i) < maxSize; i++) {
        data[totalLen + 1 + i] = kBase64URLChars[r % strlen(kBase64URLChars)];
        r = xorShift(r);
    }

    return totalLen + 1 + sigLen;
}

size_t LLVMFuzzerCustomMutator(uint8_t *data, size_t size, size_t maxSize, unsigned seed) {
    if (!data || maxSize < 1) return 0;

    uint32_t s = (uint32_t)seed;
    bool isValid = isValidJWT(data, size);

    int mutationType = s % 10;
    s = xorShift(s);

    switch (mutationType) {
        case 0:
        case 1: {
            if (size > 0 && size <= maxSize) {
                size_t flipPos = s % size;
                size = mutateFlipByte(data, size, flipPos, s);
            }
            break;
        }
        case 2: {
            if (isValid) {
                size = mutateSwapSegments(data, size, s);
            }
            break;
        }
        case 3: {
            if (isValid) {
                size = mutateTruncateSegment(data, size, s);
            }
            break;
        }
        case 4: {
            size_t deletePos = s % (size > 0 ? size : 1);
            size = mutateDeleteByte(data, size, deletePos);
            break;
        }
        case 5: {
            size_t insertPos = s % (size + 1);
            size = mutateInsertByte(data, size, maxSize, insertPos, s);
            break;
        }
        case 6: {
            if (isValid) {
                size = mutateCorruptDelimiter(data, size, s);
            }
            break;
        }
        case 7: {
            if (isValid) {
                size = addMissingDelimiters(data, size, maxSize, s);
            }
            break;
        }
        case 8: {
            size = generateRandomJWT(data, maxSize, s);
            break;
        }
        case 9: {
            if (size < maxSize && size > 0 && (s % 3) == 0) {
                size_t copyFrom = s % size;
                size_t copyLen = (s % (size - copyFrom));
                if (copyLen > 0 && size + copyLen < maxSize) {
                    memcpy(data + size, data + copyFrom, copyLen);
                    size += copyLen;
                }
            }
            break;
        }
    }

    return size;
}

size_t LLVMFuzzerCustomMutator(uint8_t *data, size_t size, size_t maxSize, const uint8_t *addons, size_t addonSize, unsigned seed) {
    return LLVMFuzzerCustomMutator(data, size, maxSize, seed);
}