// CBORMutator.mm - CBOR structural custom mutator
// Implements LLVMFuzzerCustomMutator for CBOR encoding

#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <math.h>

static const uint8_t kCBORTypes[] = {
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
    0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
    0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27,
    0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47,
    0x58, 0x59, 0x5A, 0x5B,
    0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67,
    0x78, 0x79, 0x7A, 0x7B,
    0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
    0x98, 0x99, 0x9A, 0x9B,
    0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7,
    0xB8, 0xB9, 0xBA, 0xBB,
    0xC0, 0xC1, 0xC2, 0xD8, 0xD9,
    0xE0, 0xE1, 0xE2, 0xE3, 0xE4, 0xF4, 0xF5, 0xF6, 0xF7,
    0xF8, 0xF9, 0xFA, 0xFB, 0xFC, 0xFD, 0xFE, 0xFF
};

static uint32_t xorShift(uint32_t state) {
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    return state;
}

static size_t isValidCBOR(const uint8_t *data, size_t size) {
    if (!data || size < 1) return 0;
    uint8_t initial = data[0];
    if ((initial & 0xE0) == 0x00) return 1;
    if ((initial & 0xE0) == 0x20) return 1;
    if ((initial & 0xE0) == 0x40) return 1;
    if ((initial & 0xE0) == 0x60) return 1;
    if (initial == 0x80 || initial == 0x81 || initial == 0x82) return 1;
    if (initial >= 0x80 && initial <= 0x9F) return 1;
    if (initial == 0xA0 || initial == 0xA1 || initial == 0xA2) return 1;
    if (initial >= 0xA0 && initial <= 0xBF) return 1;
    if (initial >= 0xC0 && initial <= 0xDF) return 1;
    if (initial >= 0xE0 && initial <= 0xFB) return 1;
    return 0;
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
    uint8_t toInsert = kCBORTypes[seed % (sizeof(kCBORTypes) / sizeof(uint8_t))];
    memmove(data + pos + 1, data + pos, size - pos);
    data[pos] = toInsert;
    return size + 1;
}

static size_t mutateSwapMajorType(uint8_t *data, size_t size, uint32_t seed) {
    if (size < 1 || !isValidCBOR(data, size)) return size;
    uint8_t initial = data[0];
    uint8_t majorType = initial & 0xE0;
    uint8_t info = initial & 0x1F;
    switch (seed % 6) {
        case 0: majorType = 0x00; break;
        case 1: majorType = 0x20; break;
        case 2: majorType = 0x40; break;
        case 3: majorType = 0x60; break;
        case 4: majorType = 0x80; break;
        case 5: majorType = 0xA0; break;
    }
    data[0] = majorType | info;
    return size;
}

static size_t incrementMinorBytes(uint8_t *data, size_t size, uint32_t seed) {
    if (size < 2) return size;
    if ((data[0] & 0xE0) == 0x00) {
        if (data[0] < 0x18 && size > 1) data[1]++;
        else if (data[0] == 0x19 && size > 2) {
            data[1]++; data[2] += (data[1] == 0);
        } else if (data[0] == 0x1A && size > 4) {
            uint32_t val = (data[1] << 24) | (data[2] << 16) | (data[3] << 8) | data[4];
            val++;
            data[1] = (val >> 24) & 0xFF;
            data[2] = (val >> 16) & 0xFF;
            data[3] = (val >> 8) & 0xFF;
            data[4] = val & 0xFF;
        }
    }
    return size;
}

static size_t corruptMagicNumber(uint8_t *data, size_t size, uint32_t seed) {
    if (size < 1) return size;
    uint8_t corruptions[] = {0xFF, 0xFE, 0x00, 0x1F, 0xE0, 0x3F};
    data[0] = corruptions[seed % 6];
    return size;
}

static size_t mutateMapKey(uint8_t *data, size_t size, uint32_t seed) {
    for (size_t i = 0; i < size; i++) {
        if ((data[i] & 0xE0) == 0x60) {
            data[i] ^= (seed & 0xFF);
            break;
        }
    }
    return size;
}

static size_t mutateArrayLength(uint8_t *data, size_t size, uint32_t seed) {
    if (size < 1) return size;
    if (data[0] >= 0x80 && data[0] <= 0x9F) {
        uint8_t len = (seed % 16);
        data[0] = (data[0] & 0xF0) | len;
    } else if (data[0] == 0x9F || data[0] == 0xBF) {
        data[0] ^= 1;
    }
    return size;
}

static size_t generateRandomCBOR(uint8_t *data, size_t maxSize, uint32_t seed) {
    uint32_t r = seed;
    size_t pos = 0;
    
    int type = r % 9;
    r = xorShift(r);
    
    switch (type) {
        case 0: {
            data[pos++] = 0x00 + (r & 0x1F);
            break;
        }
        case 1: {
            data[pos++] = 0x20 + (r & 0x1F);
            break;
        }
        case 2: {
            uint8_t len = r % 24;
            data[pos++] = 0x40 + len;
            for (uint8_t i = 0; i < len && pos < maxSize; i++) {
                data[pos++] = r & 0xFF;
                r = xorShift(r);
            }
            break;
        }
        case 3: {
            uint8_t len = r % 24;
            data[pos++] = 0x60 + len;
            for (uint8_t i = 0; i < len && pos < maxSize; i++) {
                data[pos++] = 'a' + (r % 26);
                r = xorShift(r);
            }
            break;
        }
        case 4: {
            uint8_t cnt = (r % 4) + 1;
            data[pos++] = 0x80 + cnt;
            for (uint8_t i = 0; i < cnt && pos < maxSize; i++) {
                data[pos++] = r & 0xFF;
                r = xorShift(r);
            }
            break;
        }
        case 5: {
            uint8_t cnt = (r % 4) + 1;
            data[pos++] = 0xA0 + cnt;
            for (uint8_t i = 0; i < cnt * 2 && pos < maxSize; i++) {
                data[pos++] = r & 0xFF;
                r = xorShift(r);
            }
            break;
        }
        case 6: {
            data[pos++] = 0xD8 + (r & 7);
            data[pos++] = r & 0xFF;
            break;
        }
        case 7: {
            data[pos++] = 0xF8 + (r % 8);
            if ((data[0] & 0xF7) == 0xF9 && pos < maxSize) {
                data[pos++] = 0;
                data[pos++] = 0;
            }
            break;
        }
        case 8: {
            data[pos++] = 0x1A;
            data[pos++] = 0;
            data[pos++] = 0;
            data[pos++] = 0;
            data[pos++] = r & 0xFF;
            break;
        }
    }
    return pos;
}

size_t LLVMFuzzerCustomMutator(uint8_t *data, size_t size, size_t maxSize, unsigned seed) {
    if (!data || maxSize < 1) return 0;
    
    uint32_t s = (uint32_t)seed;
    int isValid = isValidCBOR(data, size);
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
            size = mutateDeleteByte(data, size, deletePos);
            break;
        }
        case 3: {
            size_t insertPos = s % (size + 1);
            size = mutateInsertByte(data, size, maxSize, insertPos, s);
            break;
        }
        case 4: {
            if (isValid) {
                size = mutateSwapMajorType(data, size, s);
            }
            break;
        }
        case 5: {
            if (isValid) {
                size = incrementMinorBytes(data, size, s);
            }
            break;
        }
        case 6: {
            size = corruptMagicNumber(data, size, s);
            break;
        }
        case 7: {
            if (isValid) {
                size = mutateMapKey(data, size, s);
            }
            break;
        }
        case 8: {
            if (isValid) {
                size = mutateArrayLength(data, size, s);
            }
            break;
        }
        case 9: {
            if (size == 0 || s % 3 == 0) {
                size = generateRandomCBOR(data, maxSize, s);
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