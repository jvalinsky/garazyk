#ifndef CFByteOrder_h
#define CFByteOrder_h

#include <stdint.h>
#include <arpa/inet.h>

#if defined(__APPLE__)
#include <CoreFoundation/CFByteOrder.h>
#else

// CFIndex type (from CFBase.h)
#ifndef CFIndex
typedef long CFIndex;
#endif

// CFByteOrder enum
typedef CFIndex CFByteOrder;
enum {
    CFByteOrderUnknown = 0,
    CFByteOrderLittleEndian = 1,
    CFByteOrderBigEndian = 2
};

// Detect host byte order
#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
#define CFByteOrderGetCurrent() CFByteOrderBigEndian
#elif defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
#define CFByteOrderGetCurrent() CFByteOrderLittleEndian
#else
// Assume little-endian for x86/x86_64
#define CFByteOrderGetCurrent() CFByteOrderLittleEndian
#endif

// Primitive swap functions
static inline uint16_t CFSwapInt16(uint16_t arg) {
    return (uint16_t)((arg << 8) | (arg >> 8));
}

static inline uint32_t CFSwapInt32(uint32_t arg) {
    return ((arg & 0xFF) << 24) |
           ((arg & 0xFF00) << 8) |
           ((arg & 0xFF0000) >> 8) |
           ((arg & 0xFF000000) >> 24);
}

static inline uint64_t CFSwapInt64(uint64_t arg) {
    return ((arg & 0x00000000000000FFULL) << 56) |
           ((arg & 0x000000000000FF00ULL) << 40) |
           ((arg & 0x0000000000FF0000ULL) << 24) |
           ((arg & 0x00000000FF000000ULL) << 8) |
           ((arg & 0x000000FF00000000ULL) >> 8) |
           ((arg & 0x0000FF0000000000ULL) >> 24) |
           ((arg & 0x00FF000000000000ULL) >> 40) |
           ((arg & 0xFF00000000000000ULL) >> 56);
}

// Big-endian to host conversions
static inline uint16_t CFSwapInt16BigToHost(uint16_t arg) {
#if CFByteOrderGetCurrent() == CFByteOrderBigEndian
    return arg;
#else
    return CFSwapInt16(arg);
#endif
}

static inline uint32_t CFSwapInt32BigToHost(uint32_t arg) {
#if CFByteOrderGetCurrent() == CFByteOrderBigEndian
    return arg;
#else
    return CFSwapInt32(arg);
#endif
}

static inline uint64_t CFSwapInt64BigToHost(uint64_t arg) {
#if CFByteOrderGetCurrent() == CFByteOrderBigEndian
    return arg;
#else
    return CFSwapInt64(arg);
#endif
}

// Host to big-endian conversions
static inline uint16_t CFSwapInt16HostToBig(uint16_t arg) {
#if CFByteOrderGetCurrent() == CFByteOrderBigEndian
    return arg;
#else
    return CFSwapInt16(arg);
#endif
}

static inline uint32_t CFSwapInt32HostToBig(uint32_t arg) {
#if CFByteOrderGetCurrent() == CFByteOrderBigEndian
    return arg;
#else
    return CFSwapInt32(arg);
#endif
}

static inline uint64_t CFSwapInt64HostToBig(uint64_t arg) {
#if CFByteOrderGetCurrent() == CFByteOrderBigEndian
    return arg;
#else
    return CFSwapInt64(arg);
#endif
}

// Little-endian to host conversions
static inline uint16_t CFSwapInt16LittleToHost(uint16_t arg) {
#if CFByteOrderGetCurrent() == CFByteOrderLittleEndian
    return arg;
#else
    return CFSwapInt16(arg);
#endif
}

static inline uint32_t CFSwapInt32LittleToHost(uint32_t arg) {
#if CFByteOrderGetCurrent() == CFByteOrderLittleEndian
    return arg;
#else
    return CFSwapInt32(arg);
#endif
}

static inline uint64_t CFSwapInt64LittleToHost(uint64_t arg) {
#if CFByteOrderGetCurrent() == CFByteOrderLittleEndian
    return arg;
#else
    return CFSwapInt64(arg);
#endif
}

// Host to little-endian conversions
static inline uint16_t CFSwapInt16HostToLittle(uint16_t arg) {
#if CFByteOrderGetCurrent() == CFByteOrderLittleEndian
    return arg;
#else
    return CFSwapInt16(arg);
#endif
}

static inline uint32_t CFSwapInt32HostToLittle(uint32_t arg) {
#if CFByteOrderGetCurrent() == CFByteOrderLittleEndian
    return arg;
#else
    return CFSwapInt32(arg);
#endif
}

static inline uint64_t CFSwapInt64HostToLittle(uint64_t arg) {
#if CFByteOrderGetCurrent() == CFByteOrderLittleEndian
    return arg;
#else
    return CFSwapInt64(arg);
#endif
}

// OSSwap macros (Apple compatibility)
#define OSSwapBigToHostInt16(x) CFSwapInt16BigToHost(x)
#define OSSwapBigToHostInt32(x) CFSwapInt32BigToHost(x)
#define OSSwapBigToHostInt64(x) CFSwapInt64BigToHost(x)

#define OSSwapHostToBigInt16(x) CFSwapInt16HostToBig(x)
#define OSSwapHostToBigInt32(x) CFSwapInt32HostToBig(x)
#define OSSwapHostToBigInt64(x) CFSwapInt64HostToBig(x)

#define OSSwapLittleToHostInt16(x) CFSwapInt16LittleToHost(x)
#define OSSwapLittleToHostInt32(x) CFSwapInt32LittleToHost(x)
#define OSSwapLittleToHostInt64(x) CFSwapInt64LittleToHost(x)

#define OSSwapHostToLittleInt16(x) CFSwapInt16HostToLittle(x)
#define OSSwapHostToLittleInt32(x) CFSwapInt32HostToLittle(x)
#define OSSwapHostToLittleInt64(x) CFSwapInt64HostToLittle(x)

// Float swapping
typedef struct {
    uint32_t v;
} CFSwappedFloat32;

typedef struct {
    uint64_t v;
} CFSwappedFloat64;

static inline CFSwappedFloat32 CFConvertFloat32HostToSwapped(float arg) {
    CFSwappedFloat32 result;
    result.v = CFSwapInt32HostToBig(*(uint32_t *)&arg);
    return result;
}

static inline float CFConvertFloat32SwappedToHost(CFSwappedFloat32 arg) {
    uint32_t swapped = CFSwapInt32BigToHost(arg.v);
    return *(float *)&swapped;
}

static inline CFSwappedFloat64 CFConvertFloat64HostToSwapped(double arg) {
    CFSwappedFloat64 result;
    result.v = CFSwapInt64HostToBig(*(uint64_t *)&arg);
    return result;
}

static inline double CFConvertFloat64SwappedToHost(CFSwappedFloat64 arg) {
    uint64_t swapped = CFSwapInt64BigToHost(arg.v);
    return *(double *)&swapped;
}

#endif // __APPLE__

#endif /* CFByteOrder_h */
