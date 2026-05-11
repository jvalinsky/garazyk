// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#ifndef CommonCrypto_h
#define CommonCrypto_h

#if defined(__APPLE__)
#include <CommonCrypto/CommonCrypto.h>
#else
#include <CommonCrypto/CommonDigest.h>
#include <CommonCrypto/CommonHMAC.h>
#include <CommonCrypto/CommonKeyDerivation.h>
#include <CommonCrypto/CommonCryptor.h>
#endif

#endif /* CommonCrypto_h */
