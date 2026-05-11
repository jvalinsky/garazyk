// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file secp256k1_wrapper_c.h
 *
 * @brief C wrapper for secp256k1 elliptic curve operations.
 *
 * Provides simplified C interface to Bitcoin's secp256k1 library for
 * ATProto repository commit signing. Wraps key generation, ECDSA signing,
 * and signature verification using the secp256k1 curve.
 *
 * Thread-safety: Functions are thread-safe with independent key/signature structures.
 *
 * @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#ifndef SECP256K1_WRAPPER_H
#define SECP256K1_WRAPPER_H

#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Private key size (32 bytes). */
#define SECP256K1_PRIVATE_KEY_SIZE 32

/** Uncompressed public key size (65 bytes, 0x04 prefix + x + y). */
#define SECP256K1_PUBLIC_KEY_SIZE 65

/** Compact signature size (64 bytes, r + s). */
#define SECP256K1_SIGNATURE_SIZE 64

/** Recoverable signature size (65 bytes, r + s + recovery id). */
#define SECP256K1_SIGNATURE_RECOVERY_SIZE 65

/** Compressed public key size (33 bytes, prefix + x). */
#define SECP256K1_PUBKEY_COMPRESSED_SIZE 33

/** secp256k1 private key (32 bytes). */
typedef struct {
    uint8_t data[SECP256K1_PRIVATE_KEY_SIZE];
} Secp256k1PrivateKey;

/** secp256k1 public key (65 bytes uncompressed). */
typedef struct {
    uint8_t data[SECP256K1_PUBLIC_KEY_SIZE];
} Secp256k1PublicKey;

/** secp256k1 compact signature (64 bytes). */
typedef struct {
    uint8_t data[SECP256K1_SIGNATURE_SIZE];
} Secp256k1Signature;

/** secp256k1 recoverable signature (65 bytes). */
typedef struct {
    uint8_t data[SECP256K1_SIGNATURE_RECOVERY_SIZE];
} Secp256k1SignatureRecoverable;

/**
 * @enum Secp256k1Error
 * @brief Error codes for secp256k1 operations.
 */
typedef enum {
    Secp256k1ErrorNone = 0,                      /**< No error. */
    Secp256k1ErrorInvalidPrivateKey,             /**< Private key format invalid. */
    Secp256k1ErrorInvalidPublicKey,              /**< Public key not on curve. */
    Secp256k1ErrorInvalidSignature,              /**< Signature format invalid. */
    Secp256k1ErrorSigningFailed,                 /**< Signing operation failed. */
    Secp256k1ErrorVerificationFailed,            /**< Signature verification failed. */
    Secp256k1ErrorRecoveryFailed,                /**< Public key recovery failed. */
    Secp256k1ErrorRandomGenerationFailed         /**< Random number generation failed. */
} Secp256k1Error;

/**
 * @brief Get error message string for error code.
 *
 * @param error Error code.
 * @return Human-readable error message.
 */
const char* secp256k1_error_string(Secp256k1Error error);

/**
 * @brief Generate new secp256k1 key pair.
 *
 * Uses secure random number generation for private key.
 *
 * @param out_private_key Pointer to receive private key.
 * @param out_public_key Pointer to receive public key.
 * @return Secp256k1ErrorNone on success, error code on failure.
 */
Secp256k1Error secp256k1_wrapper_generate_key_pair(Secp256k1PrivateKey *out_private_key,
                                                    Secp256k1PublicKey *out_public_key);

/**
 * @brief Sign 32-byte hash with private key.
 *
 * Generates deterministic ECDSA signature per RFC 6979.
 *
 * @param private_key Private key for signing.
 * @param hash32 32-byte hash to sign (e.g., SHA-256).
 * @param out_signature Pointer to receive 64-byte signature.
 * @return Secp256k1ErrorNone on success, error code on failure.
 */
Secp256k1Error secp256k1_wrapper_sign(const Secp256k1PrivateKey *private_key,
                                       const uint8_t *hash32,
                                       Secp256k1Signature *out_signature);

/**
 * @brief Verify signature against hash and public key.
 *
 * @param public_key Public key for verification.
 * @param hash32 32-byte hash that was signed.
 * @param signature 64-byte signature to verify.
 * @return Secp256k1ErrorNone if valid, Secp256k1ErrorVerificationFailed if invalid.
 */
Secp256k1Error secp256k1_wrapper_verify(const Secp256k1PublicKey *public_key,
                                         const uint8_t *hash32,
                                         const Secp256k1Signature *signature);

/**
 * @brief Parse 32-byte private key data.
 *
 * Validates key is within valid secp256k1 range.
 *
 * @param input32 32-byte private key data.
 * @param out_private_key Pointer to receive parsed key.
 * @return Secp256k1ErrorNone on success, Secp256k1ErrorInvalidPrivateKey on failure.
 */
Secp256k1Error secp256k1_wrapper_private_key_parse(const uint8_t *input32,
                                                    Secp256k1PrivateKey *out_private_key);

/**
 * @brief Parse 65-byte uncompressed public key.
 *
 * Validates key is on secp256k1 curve.
 *
 * @param input65 65-byte uncompressed public key (0x04 prefix).
 * @param out_public_key Pointer to receive parsed key.
 * @return Secp256k1ErrorNone on success, Secp256k1ErrorInvalidPublicKey on failure.
 */
Secp256k1Error secp256k1_wrapper_public_key_parse(const uint8_t *input65,
                                                   Secp256k1PublicKey *out_public_key);

/**
 * @brief Derive uncompressed public key from private key.
 *
 * @param private_key Valid private key.
 * @param out_public_key Pointer to receive 65-byte uncompressed public key.
 * @return Secp256k1ErrorNone on success, error code on failure.
 */
Secp256k1Error secp256k1_wrapper_public_key_from_private_key(const Secp256k1PrivateKey *private_key,
                                                              Secp256k1PublicKey *out_public_key);

/**
 * @brief Serialize public key to compressed format.
 *
 * Compresses 65-byte key to 33-byte format (prefix + x coordinate).
 *
 * @param public_key Public key to compress.
 * @param out_compressed33 Pointer to receive 33-byte compressed key.
 */
void secp256k1_wrapper_public_key_serialize_compressed(const Secp256k1PublicKey *public_key,
                                                        uint8_t *out_compressed33);

/**
 * @brief Check if public key is valid (on curve).
 *
 * @param public_key Public key to validate.
 * @return true if valid, false otherwise.
 */
bool secp256k1_wrapper_public_key_is_valid(const Secp256k1PublicKey *public_key);

/**
 * @brief Normalize a public key into 65-byte uncompressed form.
 *
 * Accepts either 33-byte compressed or 65-byte uncompressed input, validates
 * it on-curve, and serializes to uncompressed output.
 *
 * @param input Public key bytes (33 or 65 bytes).
 * @param input_len Length of input.
 * @param out_uncompressed65 Pointer to receive 65-byte uncompressed key.
 * @return Secp256k1ErrorNone on success, Secp256k1ErrorInvalidPublicKey on failure.
 */
Secp256k1Error secp256k1_wrapper_public_key_normalize(const uint8_t *input,
                                                      size_t input_len,
                                                      uint8_t *out_uncompressed65);

/**
 * @brief Check if signature format is valid.
 *
 * @param signature Signature to validate.
 * @return true if valid format, false otherwise.
 */
bool secp256k1_wrapper_signature_is_valid(const Secp256k1Signature *signature);

#ifdef __cplusplus
}
#endif

#endif /* SECP256K1_WRAPPER_H */
