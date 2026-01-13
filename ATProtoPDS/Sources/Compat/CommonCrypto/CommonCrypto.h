#ifndef CommonCrypto_Compat_h
#define CommonCrypto_Compat_h

#if defined(__APPLE__)
#include_next <CommonCrypto/CommonCrypto.h>
#else

#include "CommonDigest.h"
#include "CommonHMAC.h"
#include "CommonCryptor.h"
#include "CommonKeyDerivation.h"

#endif
#endif
