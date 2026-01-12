#ifndef Endian_h
#define Endian_h

#if defined(__linux__) || defined(__GNUstep__)
#include <endian.h>
#include <byteswap.h>

#define OSSwapHostToBigInt16(x) htobe16(x)
#define OSSwapHostToBigInt32(x) htobe32(x)
#define OSSwapHostToBigInt64(x) htobe64(x)

#define OSSwapBigToHostInt16(x) be16toh(x)
#define OSSwapBigToHostInt32(x) be32toh(x)
#define OSSwapBigToHostInt64(x) be64toh(x)

#else
#import <libkern/OSByteOrder.h>
#endif

#endif /* Endian_h */
