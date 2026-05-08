#include "secp256k1_wrapper_c.h"
#include <secp256k1.h>
#include <string.h>
#include <stdlib.h>

#ifdef LINUX
/* arc4random compat provided by SecRandom.m on Linux */
extern uint32_t arc4random(void);
#endif

const char* secp256k1_error_string(Secp256k1Error error) {
    switch (error) {
        case Secp256k1ErrorNone:
            return "No error";
        case Secp256k1ErrorInvalidPrivateKey:
            return "Invalid private key";
        case Secp256k1ErrorInvalidPublicKey:
            return "Invalid public key";
        case Secp256k1ErrorInvalidSignature:
            return "Invalid signature";
        case Secp256k1ErrorSigningFailed:
            return "Signing failed";
        case Secp256k1ErrorVerificationFailed:
            return "Verification failed";
        case Secp256k1ErrorRecoveryFailed:
            return "Recovery failed";
        case Secp256k1ErrorRandomGenerationFailed:
            return "Random generation failed";
        default:
            return "Unknown error";
    }
}

static secp256k1_context *g_context = NULL;

static secp256k1_context* get_context(void) {
    if (g_context == NULL) {
        g_context = secp256k1_context_create(SECP256K1_CONTEXT_SIGN | SECP256K1_CONTEXT_VERIFY);
    }
    return g_context;
}

Secp256k1Error secp256k1_wrapper_generate_key_pair(Secp256k1PrivateKey *out_private_key,
                                                    Secp256k1PublicKey *out_public_key) {
    secp256k1_pubkey pubkey;

    unsigned char seckey[32];
    for (int i = 0; i < 32; i++) {
        seckey[i] = (unsigned char)(arc4random() & 0xFF);
    }

    int ret = secp256k1_ec_pubkey_create(get_context(), &pubkey, seckey);
    if (!ret) {
        return Secp256k1ErrorRandomGenerationFailed;
    }

    ret = secp256k1_ec_seckey_verify(get_context(), seckey);
    if (!ret) {
        return Secp256k1ErrorRandomGenerationFailed;
    }

    memcpy(out_private_key->data, seckey, 32);

    unsigned char pubkey_bytes[65];
    size_t pubkey_len = sizeof(pubkey_bytes);
    secp256k1_ec_pubkey_serialize(get_context(), pubkey_bytes, &pubkey_len, &pubkey, SECP256K1_EC_UNCOMPRESSED);
    memcpy(out_public_key->data, pubkey_bytes, 65);

    return Secp256k1ErrorNone;
}

Secp256k1Error secp256k1_wrapper_sign(const Secp256k1PrivateKey *private_key,
                                       const uint8_t *hash32,
                                       Secp256k1Signature *out_signature) {
    secp256k1_ecdsa_signature signature;
    int ret = secp256k1_ecdsa_sign(get_context(), &signature, hash32, private_key->data, NULL, NULL);
    if (!ret) {
        return Secp256k1ErrorSigningFailed;
    }

    // ATProto requires low-S signatures
    secp256k1_ecdsa_signature_normalize(get_context(), &signature, &signature);

    unsigned char sig_bytes[64];
    secp256k1_ecdsa_signature_serialize_compact(get_context(), sig_bytes, &signature);
    memcpy(out_signature->data, sig_bytes, 64);

    return Secp256k1ErrorNone;
}

Secp256k1Error secp256k1_wrapper_verify(const Secp256k1PublicKey *public_key,
                                         const uint8_t *hash32,
                                         const Secp256k1Signature *signature) {
    secp256k1_pubkey pubkey;
    if (!secp256k1_ec_pubkey_parse(get_context(), &pubkey, public_key->data, 65)) {
        return Secp256k1ErrorInvalidPublicKey;
    }

    secp256k1_ecdsa_signature sig;
    if (!secp256k1_ecdsa_signature_parse_compact(get_context(), &sig, signature->data)) {
        return Secp256k1ErrorInvalidSignature;
    }

    // ATProto requires low-S signatures.
    // secp256k1_ecdsa_signature_normalize returns 1 if it changed the signature (meaning it was high-S).
    if (secp256k1_ecdsa_signature_normalize(get_context(), NULL, &sig)) {
        return Secp256k1ErrorInvalidSignature;
    }

    int ret = secp256k1_ecdsa_verify(get_context(), &sig, hash32, &pubkey);
    if (!ret) {
        return Secp256k1ErrorVerificationFailed;
    }

    return Secp256k1ErrorNone;
}

Secp256k1Error secp256k1_wrapper_private_key_parse(const uint8_t *input32,
                                                    Secp256k1PrivateKey *out_private_key) {
    int ret = secp256k1_ec_seckey_verify(get_context(), input32);
    if (!ret) {
        return Secp256k1ErrorInvalidPrivateKey;
    }
    memcpy(out_private_key->data, input32, 32);
    return Secp256k1ErrorNone;
}

Secp256k1Error secp256k1_wrapper_public_key_parse(const uint8_t *input65,
                                                   Secp256k1PublicKey *out_public_key) {
    secp256k1_pubkey pubkey;
    if (!secp256k1_ec_pubkey_parse(get_context(), &pubkey, input65, 65)) {
        return Secp256k1ErrorInvalidPublicKey;
    }
    memcpy(out_public_key->data, input65, 65);
    return Secp256k1ErrorNone;
}

Secp256k1Error secp256k1_wrapper_public_key_from_private_key(const Secp256k1PrivateKey *private_key,
                                                              Secp256k1PublicKey *out_public_key) {
    if (!secp256k1_ec_seckey_verify(get_context(), private_key->data)) {
        return Secp256k1ErrorInvalidPrivateKey;
    }

    secp256k1_pubkey pubkey;
    if (!secp256k1_ec_pubkey_create(get_context(), &pubkey, private_key->data)) {
        return Secp256k1ErrorInvalidPrivateKey;
    }

    unsigned char pubkey_bytes[65];
    size_t pubkey_len = sizeof(pubkey_bytes);
    secp256k1_ec_pubkey_serialize(get_context(),
                                  pubkey_bytes,
                                  &pubkey_len,
                                  &pubkey,
                                  SECP256K1_EC_UNCOMPRESSED);
    if (pubkey_len != 65) {
        return Secp256k1ErrorInvalidPublicKey;
    }

    memcpy(out_public_key->data, pubkey_bytes, 65);
    return Secp256k1ErrorNone;
}

void secp256k1_wrapper_public_key_serialize_compressed(const Secp256k1PublicKey *public_key,
                                                        uint8_t *out_compressed33) {
    secp256k1_pubkey pubkey;
    (void)secp256k1_ec_pubkey_parse(get_context(), &pubkey, public_key->data, 65);

    size_t output_len = 33;
    secp256k1_ec_pubkey_serialize(get_context(), out_compressed33, &output_len, &pubkey, SECP256K1_EC_COMPRESSED);
}

bool secp256k1_wrapper_public_key_is_valid(const Secp256k1PublicKey *public_key) {
    secp256k1_pubkey pubkey;
    return secp256k1_ec_pubkey_parse(get_context(), &pubkey, public_key->data, 65);
}

Secp256k1Error secp256k1_wrapper_public_key_normalize(const uint8_t *input,
                                                      size_t input_len,
                                                      uint8_t *out_uncompressed65) {
    if (input_len != 33 && input_len != 65) {
        return Secp256k1ErrorInvalidPublicKey;
    }

    secp256k1_pubkey pubkey;
    if (!secp256k1_ec_pubkey_parse(get_context(), &pubkey, input, input_len)) {
        return Secp256k1ErrorInvalidPublicKey;
    }

    size_t output_len = 65;
    secp256k1_ec_pubkey_serialize(get_context(),
                                  out_uncompressed65,
                                  &output_len,
                                  &pubkey,
                                  SECP256K1_EC_UNCOMPRESSED);
    if (output_len != 65) {
        return Secp256k1ErrorInvalidPublicKey;
    }

    return Secp256k1ErrorNone;
}

bool secp256k1_wrapper_signature_is_valid(const Secp256k1Signature *signature) {
    secp256k1_ecdsa_signature sig;
    if (!secp256k1_ecdsa_signature_parse_compact(get_context(), &sig, signature->data)) {
        return false;
    }
    secp256k1_ecdsa_signature_normalize(get_context(), &sig, &sig);
    return 1;
}
