// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#ifndef ATProtoBaoEncode_h
#define ATProtoBaoEncode_h

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** BLAKE3 root hash (32 bytes). Returns 0 on success. */
int atproto_bao_hash(const uint8_t *data, size_t len, uint8_t out_hash[32]);

/** Allocates Bao outboard bytes; caller frees with free(). */
int atproto_bao_outboard(const uint8_t *data, size_t len, uint8_t **out_bytes, size_t *out_len);

/** Allocates a Bao slice; caller frees with free(). */
int atproto_bao_slice(const uint8_t *data, size_t data_len, const uint8_t *outboard,
                      size_t outboard_len, uint64_t offset, uint64_t length, uint8_t **out_bytes,
                      size_t *out_len);

/**
 Verifies a slice against expected_hash (32 bytes) and returns verified content
 for [offset, offset+length). Caller frees out_content with free().
 Returns 0 ok, -1 truncated/invalid, -2 hash mismatch.
 */
int atproto_bao_verify_slice(const uint8_t *slice, size_t slice_len, const uint8_t expected_hash[32],
                             uint64_t offset, uint64_t length, uint8_t **out_content,
                             size_t *out_content_len);

#ifdef __cplusplus
}
#endif

#endif /* ATProtoBaoEncode_h */
