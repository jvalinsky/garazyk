// HTTPMutator.mm - HTTP/1.1 structural custom mutator
// Implements LLVMFuzzerCustomMutator for HTTP requests

#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <ctype.h>

static const char kHTTPMethods[][8] = {
    "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "CONNECT"
};

static const char *kHTTPVersions[] = {"HTTP/1.0", "HTTP/1.1", "HTTP/2", "HTTP/3"};

static const char kCommonHeaders[][32] = {
    "Host", "Content-Type", "Content-Length", "Authorization",
    "Accept", "Accept-Encoding", "Accept-Language",
    "User-Agent", "Cookie", "Set-Cookie",
    "X-Requested-With", "X-Forwarded-For", "X-Real-IP",
    "Referer", "Origin", "Connection", "Keep-Alive"
};

static const uint8_t kCRLF[] = {'\r', '\n'};
static const uint8_t kSP = ' ';

static uint32_t xorShift(uint32_t state) {
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    return state;
}

static size_t findPattern(const uint8_t *data, size_t size, const uint8_t *pattern, size_t patLen) {
    if (!data || !pattern || size < patLen || patLen == 0) return SIZE_MAX;
    for (size_t i = 0; i <= size - patLen; i++) {
        if (memcmp(data + i, pattern, patLen) == 0) return i;
    }
    return SIZE_MAX;
}

static size_t countOccurrences(const uint8_t *data, size_t size, const uint8_t *pattern, size_t patLen) {
    size_t count = 0;
    size_t pos = 0;
    while ((pos = findPattern(data + pos, size - pos, pattern, patLen)) != SIZE_MAX) {
        count++;
        pos += patLen;
    }
    return count;
}

static int looksLikeHTTP(const uint8_t *data, size_t size) {
    if (!data || size < 8) return 0;
    size_t crlf2 = findPattern(data, size, kCRLF, 2);
    if (crlf2 == SIZE_MAX) return 0;
    for (size_t i = 0; i < 4 && i < crlf2; i++) {
        if (!isupper(data[i]) && data[i] != '/') return 0;
    }
    return 1;
}

static size_t extractMethodEnd(const uint8_t *data, size_t size) {
    for (size_t i = 0; i < size; i++) {
        if (data[i] == ' ' || data[i] == '\t') return i;
    }
    return SIZE_MAX;
}

static size_t extractPathEnd(const uint8_t *data, size_t size, size_t methodEnd) {
    for (size_t i = methodEnd + 1; i < size; i++) {
        if (data[i] == ' ' || data[i] == '\r' || data[i] == '\n') return i;
    }
    return SIZE_MAX;
}

static size_t extractVersionEnd(const uint8_t *data, size_t size) {
    size_t crlf = findPattern(data, size, kCRLF, 2);
    if (crlf == SIZE_MAX) return SIZE_MAX;
    for (size_t i = crlf - 1; i > 0; i--) {
        if (data[i] == ' ') return i;
    }
    return SIZE_MAX;
}

static size_t findHeaderBlockEnd(const uint8_t *data, size_t size) {
    return findPattern(data, size, kCRLF, 2);
}

static size_t findBodyStart(const uint8_t *data, size_t size) {
    size_t crlf2 = findPattern(data, size, kCRLF, 2);
    if (crlf2 == SIZE_MAX) return SIZE_MAX;
    size_t crlf4 = findPattern(data + crlf2 + 2, size - crlf2 - 2, kCRLF, 2);
    if (crlf4 == SIZE_MAX) return SIZE_MAX;
    return crlf2 + 2 + crlf4 + 2;
}

static size_t mutateFlipByte(uint8_t *data, size_t size, size_t pos, uint32_t seed) {
    if (pos >= size) return size;
    data[pos] ^= (seed & 0xFF);
    return size;
}

static size_t mutateMethodName(uint8_t *data, size_t size, size_t methodEnd, uint32_t seed) {
    if (methodEnd == SIZE_MAX || methodEnd == 0 || methodEnd > size) return size;
    size_t methodLen = methodEnd;
    size_t r = seed % 10;
    if (r < 4) {
        data[seed % methodLen] ^= (seed & 0xFF);
    } else if (r < 6 && methodLen < 8) {
        size_t newMethodIdx = (seed >> 8) % (sizeof(kHTTPMethods) / sizeof(kHTTPMethods[0]));
        const char *newMethod = kHTTPMethods[newMethodIdx];
        size_t newLen = strlen(newMethod);
        if (newLen <= methodLen) {
            memcpy(data, newMethod, newLen);
            for (size_t i = newLen; i < methodLen; i++) {
                data[i] = ' ';
            }
        }
    }
    return size;
}

static size_t mutatePath(uint8_t *data, size_t size, size_t pathStart, size_t pathEnd, uint32_t seed) {
    if (pathStart >= size || pathEnd <= pathStart || pathEnd > size) return size;
    size_t pathLen = pathEnd - pathStart;
    int r = seed % 5;
    if (r == 0) {
        size_t pos = (seed >> 8) % pathLen;
        data[pathStart + pos] ^= (seed & 0xFF);
    } else if (r == 1 && pathLen > 1) {
        size_t pos1 = (seed >> 8) % pathLen;
        size_t pos2 = (seed >> 12) % pathLen;
        uint8_t tmp = data[pathStart + pos1];
        data[pathStart + pos1] = data[pathStart + pos2];
        data[pathStart + pos2] = tmp;
    } else if (r == 2 && pathLen < size - 1) {
        data[pathEnd] = '?';
        size_t qpos = pathEnd + 1;
        const char *params[] = {"foo=bar", "id=123", "q=search", "page=1"};
        const char *param = params[(seed >> 10) % 4];
        size_t pLen = strlen(param);
        if (qpos + pLen < size) {
            memcpy(data + qpos, param, pLen);
            return pathEnd + 1 + pLen;
        }
    }
    return size;
}

static size_t mutateHTTPVersion(uint8_t *data, size_t size, size_t versionStart, size_t versionEnd, uint32_t seed) {
    if (versionStart >= size || versionEnd <= versionStart || versionEnd > size) return size;
    size_t versionLen = versionEnd - versionStart;
    const char *newVersion = kHTTPVersions[seed % (sizeof(kHTTPVersions) / sizeof(kHTTPVersions[0]))];
    size_t newLen = strlen(newVersion);
    if (newLen <= versionLen && newLen < size) {
        memcpy(data + versionStart, newVersion, newLen);
        data[versionStart + newLen] = '\r';
        return versionStart + newLen + 1;
    }
    return size;
}

static size_t mutateHeaders(uint8_t *data, size_t size, size_t headerStart, size_t headerEnd, uint32_t seed) {
    if (headerStart >= size || headerEnd <= headerStart) return size;
    size_t headerLen = headerEnd - headerStart;
    size_t colonPos = SIZE_MAX;
    for (size_t i = 0; i < headerLen; i++) {
        if (data[headerStart + i] == ':') {
            colonPos = i;
            break;
        }
    }
    if (colonPos == SIZE_MAX) return size;
    int r = seed % 4;
    if (r == 0) {
        size_t pos = (seed >> 8) % headerLen;
        data[headerStart + pos] ^= (seed & 0xFF);
    } else if (r == 1) {
        size_t nameEnd = headerStart + colonPos;
        size_t valStart = headerStart + colonPos + 1;
        while (valStart < headerEnd && (data[valStart] == ' ' || data[valStart] == '\t')) valStart++;
        if (nameEnd > headerStart && valStart < headerEnd) {
            size_t nameLen = nameEnd - headerStart;
            size_t valLen = headerEnd - valStart;
            if (nameLen < 32 && valLen < 64 && nameLen + valLen < headerLen) {
                data[nameEnd] = ':';
                data[valStart - 1] = '\r';
            }
        }
    }
    return size;
}

static size_t mutateCRLF(uint8_t *data, size_t size, uint32_t seed) {
    size_t crlfCount = countOccurrences(data, size, kCRLF, 2);
    if (crlfCount == 0) return size;
    size_t crlfIdx = seed % crlfCount;
    size_t pos = 0;
    size_t found = 0;
    while (pos < size - 1) {
        size_t next = findPattern(data + pos, size - pos - 1, kCRLF, 2);
        if (next == SIZE_MAX) break;
        if (found == crlfIdx) {
            char replacements[] = {'\n', '\r', ' ', '\0'};
            data[pos + next] = replacements[seed % 4];
            break;
        }
        found++;
        pos += next + 2;
    }
    return size;
}

static size_t insertHeader(uint8_t *data, size_t size, size_t maxSize, size_t insertPos, uint32_t seed) {
    if (size >= maxSize - 64 || insertPos > size) return size;
    const char *header = kCommonHeaders[seed % (sizeof(kCommonHeaders) / sizeof(kCommonHeaders[0]))];
    const char *value = "test";
    char headerLine[64];
    snprintf(headerLine, sizeof(headerLine), "%s: %s\r\n", header, value);
    size_t headerLen = strlen(headerLine);
    if (size + headerLen >= maxSize) return size;
    memmove(data + insertPos + headerLen, data + insertPos, size - insertPos);
    memcpy(data + insertPos, headerLine, headerLen);
    return size + headerLen;
}

static size_t removeHeader(uint8_t *data, size_t size, size_t headerBlockStart, size_t headerBlockEnd, uint32_t seed) {
    if (headerBlockStart >= size || headerBlockEnd <= headerBlockStart || headerBlockEnd > size) return size;
    size_t crlfCount = countOccurrences(data + headerBlockStart, headerBlockEnd - headerBlockStart, kCRLF, 2);
    if (crlfCount < 2) return size;
    size_t targetCrlf = seed % crlfCount;
    size_t crlfIdx = 0;
    size_t lineStart = headerBlockStart;
    for (size_t i = headerBlockStart; i < headerBlockEnd - 1 && crlfIdx <= targetCrlf; i++) {
        if (data[i] == '\r' && data[i + 1] == '\n') {
            if (crlfIdx == targetCrlf) {
                size_t lineEnd = i;
                size_t lineStart2 = lineStart;
                size_t nextCrlf = findPattern(data + i + 2, headerBlockEnd - i - 2, kCRLF, 2);
                if (nextCrlf != SIZE_MAX) lineEnd = i + 2 + nextCrlf;
                else lineEnd = headerBlockEnd;
                if (lineEnd <= size) {
                    memmove(data + lineStart2, data + lineEnd, size - lineEnd);
                    return size - (lineEnd - lineStart2);
                }
            }
            crlfIdx++;
            lineStart = i + 2;
        }
    }
    return size;
}

static size_t mutateBody(uint8_t *data, size_t size, size_t bodyStart, uint32_t seed) {
    if (bodyStart >= size || bodyStart >= size || size < bodyStart) return size;
    size_t bodyLen = size - bodyStart;
    if (bodyLen == 0) return size;
    int r = seed % 4;
    if (r == 0) {
        size_t pos = (seed >> 8) % bodyLen;
        data[bodyStart + pos] ^= (seed & 0xFF);
    } else if (r == 1 && bodyLen > 1) {
        size_t pos1 = (seed >> 8) % bodyLen;
        size_t pos2 = (seed >> 12) % bodyLen;
        uint8_t tmp = data[bodyStart + pos1];
        data[bodyStart + pos1] = data[bodyStart + pos2];
        data[bodyStart + pos2] = tmp;
    } else if (r == 2 && bodyLen < size - bodyStart - 1) {
        const char *bodyValues[] = {"{}", "[]", "null", "\"test\"", "123", "true", "false"};
        const char *newBody = bodyValues[seed % 7];
        size_t newBodyLen = strlen(newBody);
        if (bodyStart + newBodyLen <= size) {
            memcpy(data + bodyStart, newBody, newBodyLen);
            return bodyStart + newBodyLen;
        }
    }
    return size;
}

static size_t generateRandomHTTP(uint8_t *data, size_t maxSize, uint32_t seed) {
    uint32_t r = seed;
    size_t pos = 0;
    const char *method = kHTTPMethods[r % (sizeof(kHTTPMethods) / sizeof(kHTTPMethods[0]))];
    r = xorShift(r);
    size_t methodLen = strlen(method);
    memcpy(data + pos, method, methodLen);
    pos += methodLen;
    data[pos++] = ' ';
    const char *path = r % 2 == 0 ? "/" : "/api/v1/resource";
    size_t pathLen = strlen(path);
    memcpy(data + pos, path, pathLen);
    pos += pathLen;
    data[pos++] = ' ';
    const char *version = kHTTPVersions[r % (sizeof(kHTTPVersions) / sizeof(kHTTPVersions[0]))];
    r = xorShift(r);
    size_t versionLen = strlen(version);
    memcpy(data + pos, version, versionLen);
    pos += versionLen;
    data[pos++] = '\r';
    data[pos++] = '\n';
    const char *headers[] = {"Host: example.com\r\n", "Content-Type: application/json\r\n"};
    const char *h = headers[r % 2];
    size_t hLen = strlen(h);
    memcpy(data + pos, h, hLen);
    pos += hLen;
    data[pos++] = '\r';
    data[pos++] = '\n';
    if (r % 2 == 0) {
        const char *body = "{\"test\":true}";
        size_t bodyLen = strlen(body);
        if (pos + bodyLen < maxSize) {
            memcpy(data + pos, body, bodyLen);
            pos += bodyLen;
        }
    }
    return pos;
}

size_t LLVMFuzzerCustomMutator(uint8_t *data, size_t size, size_t maxSize, unsigned seed) {
    if (!data || maxSize < 1) return 0;
    if (size == 0) {
        return generateRandomHTTP(data, maxSize, seed);
    }
    uint32_t s = (uint32_t)seed;
    int isHTTP = looksLikeHTTP(data, size);
    int mutationType = s % 12;
    s = xorShift(s);
    switch (mutationType) {
        case 0: {
            if (size > 0 && size <= maxSize) {
                size_t flipPos = s % size;
                size = mutateFlipByte(data, size, flipPos, s);
            }
            break;
        }
        case 1: {
            if (isHTTP) {
                size_t methodEnd = extractMethodEnd(data, size);
                size_t pathStart = methodEnd + 1;
                size_t pathEnd = extractPathEnd(data, size, methodEnd);
                size = mutatePath(data, size, pathStart, pathEnd, s);
            }
            break;
        }
        case 2: {
            if (isHTTP) {
                size_t headerEnd = findHeaderBlockEnd(data, size);
                if (headerEnd != SIZE_MAX && headerEnd > 0) {
                    size = mutateHeaders(data, size, 0, headerEnd, s);
                }
            }
            break;
        }
        case 3: {
            if (isHTTP) {
                size_t bodyStart = findBodyStart(data, size);
                if (bodyStart != SIZE_MAX) {
                    size = mutateBody(data, size, bodyStart, s);
                }
            }
            break;
        }
        case 4: {
            size = mutateCRLF(data, size, s);
            break;
        }
        case 5: {
            if (isHTTP && maxSize > size + 32) {
                size_t headerEnd = findHeaderBlockEnd(data, size);
                if (headerEnd != SIZE_MAX) {
                    size = insertHeader(data, size, maxSize, headerEnd, s);
                }
            }
            break;
        }
        case 6: {
            if (isHTTP) {
                size_t methodEnd = extractMethodEnd(data, size);
                size = mutateMethodName(data, size, methodEnd, s);
            }
            break;
        }
        case 7: {
            if (isHTTP) {
                size_t versionStart = SIZE_MAX, versionEnd = SIZE_MAX;
                for (size_t i = 0; i < size - 7; i++) {
                    if (memcmp(data + i, "HTTP/", 5) == 0) {
                        versionStart = i;
                        versionEnd = extractVersionEnd(data, size);
                        break;
                    }
                }
                if (versionStart != SIZE_MAX && versionEnd != SIZE_MAX) {
                    size = mutateHTTPVersion(data, size, versionStart, versionEnd, s);
                }
            }
            break;
        }
        case 8: {
            size = isHTTP ? size : generateRandomHTTP(data, maxSize, s);
            break;
        }
        case 9: {
            if (size < maxSize && size > 0 && (s % 3) == 0 && isHTTP) {
                size_t copyFrom = s % size;
                size_t copyLen = (s % (size - copyFrom));
                if (copyLen > 0 && size + copyLen < maxSize) {
                    memcpy(data + size, data + copyFrom, copyLen);
                    size += copyLen;
                }
            }
            break;
        }
        case 10: {
            if (isHTTP) {
                size_t headerEnd = findHeaderBlockEnd(data, size);
                if (headerEnd != SIZE_MAX && headerEnd > 0) {
                    size = removeHeader(data, size, 0, headerEnd, s);
                }
            }
            break;
        }
        case 11: {
            if (isHTTP) {
                size_t methodEnd = extractMethodEnd(data, size);
                size_t pathStart = methodEnd + 1;
                size_t pathEnd = extractPathEnd(data, size, methodEnd);
                if (pathEnd < size - 1) {
                    data[pathEnd] = '\0';
                    size_t newPathEnd = pathStart + (s % (pathEnd - pathStart));
                    data[newPathEnd] = '/';
                    size = newPathEnd + 1;
                }
            }
            break;
        }
    }
    if (size > maxSize) size = maxSize;
    return size;
}

size_t LLVMFuzzerCustomMutator(uint8_t *data, size_t size, size_t maxSize, const uint8_t *addons, size_t addonSize, unsigned seed) {
    return LLVMFuzzerCustomMutator(data, size, maxSize, seed);
}