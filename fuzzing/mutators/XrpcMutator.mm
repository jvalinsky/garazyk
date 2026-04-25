// XrpcMutator.mm - XRPC protocol custom mutator
// Implements LLVMFuzzerCustomMutator for XRPC encoding

#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

static const char kXRPCMethods[][48] = {
    "com.atproto.server.createSession",
    "com.atproto.server.refreshSession",
    "com.atproto.server.getSession",
    "com.atproto.identity.resolveHandle",
    "com.atproto.identity.resolveByHandle",
    "com.atproto.repo.getRecord",
    "com.atproto.repo.listRecords",
    "com.atproto.repo.putRecord",
    "com.atproto.repo.deleteRecord",
    "com.atproto.sync.getHead",
    "app.bsky.actor.getProfile",
    "app.bsky.feed.getTimeline",
    "app.bsky.feed.getPosts",
    "app.bsky.graph.getFollows",
    "app.bsky.graph.getFollowers"
};

static const char *kJSONKeys[] = {
    "identifier", "password", "did", "repo", "collection", 
    "rkey", "record", "limit", "cursor", "actor",
    "handle", "email", "subject", "uri", "depth"
};

static uint32_t xorShift(uint32_t state) {
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    return state;
}

static int isValidJSON(const uint8_t *data, size_t size) {
    if (!data || size < 2) return 0;
    return (data[0] == '{' || data[0] == '[' || data[0] == '"');
}

static int isJSONObject(const uint8_t *data, size_t size) {
    for (size_t i = 0; i < size; i++) {
        if (data[i] == '{') return 1;
        if (data[i] == '[') return 1;
    }
    return 0;
}

static size_t findColon(const uint8_t *data, size_t size, size_t start) {
    for (size_t i = start; i < size; i++) {
        if (data[i] == ':') return i;
    }
    return SIZE_MAX;
}

static size_t findBrace(const uint8_t *data, size_t size, size_t start, int open) {
    int depth = 0;
    for (size_t i = start; i < size; i++) {
        if (data[i] == '{' || data[i] == '[') depth++;
        else if (data[i] == '}' || data[i] == ']') depth--;
        if ((open && depth == 1) || (!open && depth == 0)) return i;
    }
    return SIZE_MAX;
}

static size_t mutateFlipByte(uint8_t *data, size_t size, size_t pos, uint32_t seed) {
    if (pos >= size) return size;
    data[pos] ^= (seed & 0xFF);
    return size;
}

static size_t mutateDeleteChar(uint8_t *data, size_t size, size_t pos) {
    if (pos >= size || size <= 1) return size;
    memmove(data + pos, data + pos + 1, size - pos - 1);
    return size - 1;
}

static size_t mutateInsertChar(uint8_t *data, size_t size, size_t maxSize, size_t pos, uint32_t seed) {
    if (size >= maxSize || pos > size) return size;
    const char insertions[] = {"{}\":[]\"-_,."};
    char toInsert = insertions[seed % 8];
    memmove(data + pos + 1, data + pos, size - pos);
    data[pos] = toInsert;
    return size + 1;
}

static size_t mutateJSONKey(uint8_t *data, size_t size, uint32_t seed) {
    if (!isValidJSON(data, size)) return size;
    for (size_t i = 0; i < size - 1; i++) {
        if (data[i] == '"' && data[i + 1] != '"') {
            size_t colonPos = findColon(data, size, i + 1);
            if (colonPos != SIZE_MAX && colonPos - i - 1 < 20) {
                const char *newKey = kJSONKeys[seed % 15];
                size_t keyLen = strlen(newKey);
                if (keyLen < 20 && i + 1 + keyLen < size) {
                    memcpy(data + i + 1, newKey, keyLen);
                    data[i + 1 + keyLen] = '"';
                    break;
                }
            }
        }
    }
    return size;
}

static size_t mutateJSONValue(uint8_t *data, size_t size, uint32_t seed) {
    if (!isValidJSON(data, size)) return size;
    for (size_t i = 0; i < size; i++) {
        if (data[i] == ':' && i < size - 1) {
            size_t nextNonSpace = i + 1;
            while (nextNonSpace < size && data[nextNonSpace] == ' ') nextNonSpace++;
            if (nextNonSpace < size) {
                const char *replacements[] = {"null", "true", "false", "0", "1", "\"\""};
                const char *rep = replacements[seed % 6];
                size_t repLen = strlen(rep);
                if (repLen < size - nextNonSpace) {
                    memset(data + nextNonSpace, ' ', repLen);
                    memcpy(data + nextNonSpace, rep, repLen);
                    break;
                }
            }
        }
    }
    return size;
}

static size_t mutateArrayIndex(uint8_t *data, size_t size, uint32_t seed) {
    if (!isValidJSON(data, size)) return size;
    size_t depth = 0;
    size_t idx = 0;
    for (size_t i = 0; i < size; i++) {
        if (data[i] == '[') {
            depth++;
            if (depth == 1 && seed % 2 == 0) {
                idx = i + 1;
            }
        } else if (data[i] == ']') {
            if (depth == 1 && idx > 0) {
                char indices[] = {"0123456789"};
                data[idx] = indices[seed % 10];
            }
            depth--;
        }
    }
    return size;
}

static size_t corruptJSONSyntax(uint8_t *data, size_t size, uint32_t seed) {
    if (size < 2) return size;
    size_t pos = seed % size;
    char corruptions[] = {'{', '}', '[', ']', ':', ',', '"', '\\'};
    data[pos] = corruptions[seed % 8];
    return size;
}

static size_t mutateQuotes(uint8_t *data, size_t size, uint32_t seed) {
    if (!isValidJSON(data, size)) return size;
    int quoteCount = 0;
    for (size_t i = 0; i < size; i++) {
        if (data[i] == '"') quoteCount++;
    }
    if (quoteCount > 2 && quoteCount % 2 == 0) {
        size_t quotePos = seed % size;
        for (size_t i = quotePos; i < size; i++) {
            if (data[i] == '"' && i > 0) {
                data[i] = seed % 2 == 0 ? '}' : ']';
                break;
            }
        }
    }
    return size;
}

static size_t mutateNestedBrace(uint8_t *data, size_t size, uint32_t seed) {
    if (!isJSONObject(data, size)) return size;
    if (seed % 2 == 0) {
        for (size_t i = size / 2; i < size; i++) {
            if (data[i] == '{') {
                data[i] = '[';
                break;
            }
        }
    } else {
        for (size_t i = size / 2; i < size; i++) {
            if (data[i] == '[') {
                data[i] = '{';
                break;
            }
        }
    }
    return size;
}

static size_t generateRandomXrpc(uint8_t *data, size_t maxSize, uint32_t seed) {
    uint32_t r = seed;
    size_t pos = 0;
    
    data[pos++] = '{';
    
    const char *method = kXRPCMethods[r % 15];
    r = xorShift(r);
    
    memcpy(data + pos, "{\"method\":\"", 11);
    pos += 11;
    size_t methodLen = strlen(method);
    memcpy(data + pos, method, methodLen);
    pos += methodLen;
    data[pos++] = '"';
    data[pos++] = ',';
    
    const char *key = kJSONKeys[r % 15];
    r = xorShift(r);
    data[pos++] = '"';
    memcpy(data + pos, key, strlen(key));
    pos += strlen(key);
    data[pos++] = '"';
    data[pos++] = ':';
    
    if (r % 2 == 0) {
        data[pos++] = '"';
        for (size_t i = 0; i < 8 && pos < maxSize - 2; i++) {
            data[pos++] = 'a' + (r % 26);
            r = xorShift(r);
        }
        data[pos++] = '"';
    } else {
        char num[16];
        snprintf(num, sizeof(num), "%u", r % 10000);
        size_t numLen = strlen(num);
        memcpy(data + pos, num, numLen);
        pos += numLen;
    }
    
    data[pos++] = '}';
    
    return pos;
}

size_t LLVMFuzzerCustomMutator(uint8_t *data, size_t size, size_t maxSize, unsigned seed) {
    if (!data || maxSize < 1) return 0;
    
    uint32_t s = (uint32_t)seed;
    int isValid = isValidJSON(data, size);
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
            size_t deletePos = s % (size > 0 ? size : 1);
            size = mutateDeleteChar(data, size, deletePos);
            break;
        }
        case 3: {
            size_t insertPos = s % (size + 1);
            size = mutateInsertChar(data, size, maxSize, insertPos, s);
            break;
        }
        case 4: {
            if (isValid) {
                size = mutateJSONKey(data, size, s);
            }
            break;
        }
        case 5: {
            if (isValid) {
                size = mutateJSONValue(data, size, s);
            }
            break;
        }
        case 6: {
            if (isValid) {
                size = corruptJSONSyntax(data, size, s);
            }
            break;
        }
        case 7: {
            if (isValid) {
                size = mutateArrayIndex(data, size, s);
            }
            break;
        }
        case 8: {
            size = generateRandomXrpc(data, maxSize, s);
            break;
        }
        case 9: {
            if (isValid) {
                size = mutateNestedBrace(data, size, s);
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