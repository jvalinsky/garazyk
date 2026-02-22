/**
 * @file SecRandom.h
 * @brief SecRandomCopyBytes compatibility shim.
 *
 * Provides SecRandomCopyBytes implementation for platforms without Security framework:
 * - macOS: Native Security framework SecRandom
 * - Linux: arc4random_buf and arc4random_uniform wrapper
 *
 * @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#ifndef SecRandom_h
#define SecRandom_h

#include <stdlib.h>
#include <stdint.h>

#ifdef __APPLE__
#import <Security/SecRandom.h>
#else

/** Placeholder for default random number generator. */
#define kSecRandomDefault 0

/** Success error code. */
#define errSecSuccess 0

/**
 * @brief Generate cryptographically secure random bytes (Linux implementation).
 *
 * Uses arc4random_buf for secure random generation on Linux/BSD.
 *
 * @param drbg Unused (for API compatibility).
 * @param count Number of bytes to generate.
 * @param bytes Buffer to receive random bytes.
 * @return errSecSuccess (always succeeds).
 */
int SecRandomCopyBytes(int *drbg, size_t count, void *bytes);

/**
 * @brief Generate a random 32-bit integer.
 *
 * @return Random 32-bit integer.
 */
uint32_t arc4random(void);

/**
 * @brief Generate a random 32-bit integer in range [0, upper_bound].
 *
 * @param upper_bound Upper bound (exclusive).
 * @return Random integer in [0, upper_bound].
 */
uint32_t arc4random_uniform(uint32_t upper_bound);

#endif

#endif /* SecRandom_h */
