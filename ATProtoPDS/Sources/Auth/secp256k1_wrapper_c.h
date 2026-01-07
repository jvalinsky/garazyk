#ifndef SECP256K1_WRAPPER_H
#define SECP256K1_WRAPPER_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SECP256K1_PRIVATE_KEY_SIZE 32
#define SECP256K1_PUBLIC_KEY_SIZE 65
#define SECP256K1_SIGNATURE_SIZE 64
#define SECP256K1_SIGNATURE_RECOVERY_SIZE 65
#define SECP256K1_PUBKEY_COMPRESSED_SIZE 33

typedef struct {
    uint8_t data[SECP256K1_PRIVATE_KEY_SIZE];
} Secp256k1PrivateKey;

typedef struct {
    uint8_t data[SECP256K1_PUBLIC_KEY_SIZE];
} Secp256k1PublicKey;

typedef struct {
    uint8_t data[SECP256K1_SIGNATURE_SIZE];
} Secp256k1Signature;

typedef struct {
    uint8_t data[SECP256K1_SIGNATURE_RECOVERY_SIZE];
} Secp256k1SignatureRecoverable;

typedef enum {
    Secp256k1ErrorNone = 0,
    Secp256k1ErrorInvalidPrivateKey,
    Secp256k1ErrorInvalidPublicKey,
    Secp256k1ErrorInvalidSignature,
    Secp256k1ErrorSigningFailed,
    Secp256k1ErrorVerificationFailed,
    Secp256k1ErrorRecoveryFailed,
    Secp256k1ErrorRandomGenerationFailed
} Secp256k1Error;

const char* secp256k1_error_string(Secp256k1Error error);

Secp256k1Error secp256k1_wrapper_generate_key_pair(Secp256k1PrivateKey *out_private_key,
                                                    Secp256k1PublicKey *out_public_key);

Secp256k1Error secp256k1_wrapper_sign(const Secp256k1PrivateKey *private_key,
                                       const uint8_t *hash32,
                                       Secp256k1Signature *out_signature);

Secp256k1Error secp256k1_wrapper_verify(const Secp256k1PublicKey *public_key,
                                         const uint8_t *hash32,
                                         const Secp256k1Signature *signature);

Secp256k1Error secp256k1_wrapper_private_key_parse(const uint8_t *input32,
                                                    Secp256k1PrivateKey *out_private_key);

Secp256k1Error secp256k1_wrapper_public_key_parse(const uint8_t *input65,
                                                   Secp256k1PublicKey *out_public_key);

void secp256k1_wrapper_public_key_serialize_compressed(const Secp256k1PublicKey *public_key,
                                                        uint8_t *out_compressed33);

bool secp256k1_wrapper_public_key_is_valid(const Secp256k1PublicKey *public_key);

bool secp256k1_wrapper_signature_is_valid(const Secp256k1Signature *signature);

#ifdef __cplusplus
}
#endif

#endif /* SECP256K1_WRAPPER_H */
