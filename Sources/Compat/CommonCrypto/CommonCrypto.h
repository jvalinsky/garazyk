#ifndef CommonCrypto_h
#define CommonCrypto_h

#if defined(__APPLE__)
#include <CommonCrypto/CommonCrypto.h>
#else
#include <CommonCrypto/CommonDigest.h>
#include <CommonCrypto/CommonHMAC.h>
#include <CommonCrypto/CommonKeyDerivation.h>
#endif

#endif /* CommonCrypto_h */
