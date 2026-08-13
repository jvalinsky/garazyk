// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 Wire-compatible Bao outboard/slice using BLAKE3 tree hashing.
 Duplicates blake3.c INLINE helpers because they are not exported.
 */
#include "Core/ATProtoBaoEncode.h"

#include <stdlib.h>
#include <string.h>

#include "Security/Space/Vendor/BLAKE3/blake3.h"
#include "Security/Space/Vendor/BLAKE3/blake3_impl.h"

enum {
  ATPROTO_BAO_CHUNK = BLAKE3_CHUNK_LEN,
  ATPROTO_BAO_PARENT = 2 * BLAKE3_OUT_LEN,
  ATPROTO_BAO_HEADER = 8
};

typedef struct {
  uint32_t input_cv[8];
  uint64_t counter;
  uint8_t block[BLAKE3_BLOCK_LEN];
  uint8_t block_len;
  uint8_t flags;
} atproto_bao_output_t;

typedef struct {
  uint8_t *bytes;
  size_t len;
  size_t cap;
} atproto_bao_buf;

static int atproto_bao_buf_reserve(atproto_bao_buf *b, size_t need) {
  if (b->len + need <= b->cap) return 0;
  size_t ncap = b->cap ? b->cap : 64;
  while (ncap < b->len + need) ncap *= 2;
  uint8_t *n = (uint8_t *)realloc(b->bytes, ncap);
  if (!n) return -1;
  b->bytes = n;
  b->cap = ncap;
  return 0;
}

static int atproto_bao_buf_append(atproto_bao_buf *b, const void *p, size_t n) {
  if (n == 0) return 0;
  if (atproto_bao_buf_reserve(b, n) != 0) return -1;
  memcpy(b->bytes + b->len, p, n);
  b->len += n;
  return 0;
}

static void atproto_bao_chunk_state_init(blake3_chunk_state *self, const uint32_t key[8],
                                         uint8_t flags) {
  memcpy(self->cv, key, BLAKE3_KEY_LEN);
  self->chunk_counter = 0;
  memset(self->buf, 0, BLAKE3_BLOCK_LEN);
  self->buf_len = 0;
  self->blocks_compressed = 0;
  self->flags = flags;
}

static uint8_t atproto_bao_maybe_start(const blake3_chunk_state *self) {
  return self->blocks_compressed == 0 ? CHUNK_START : 0;
}

static void atproto_bao_chunk_state_update(blake3_chunk_state *self, const uint8_t *input,
                                           size_t input_len) {
  if (self->buf_len > 0) {
    size_t take = BLAKE3_BLOCK_LEN - (size_t)self->buf_len;
    if (take > input_len) take = input_len;
    memcpy(self->buf + self->buf_len, input, take);
    self->buf_len = (uint8_t)(self->buf_len + take);
    input += take;
    input_len -= take;
    if (input_len > 0) {
      blake3_compress_in_place(self->cv, self->buf, BLAKE3_BLOCK_LEN, self->chunk_counter,
                               self->flags | atproto_bao_maybe_start(self));
      self->blocks_compressed += 1;
      self->buf_len = 0;
      memset(self->buf, 0, BLAKE3_BLOCK_LEN);
    }
  }
  while (input_len > BLAKE3_BLOCK_LEN) {
    blake3_compress_in_place(self->cv, input, BLAKE3_BLOCK_LEN, self->chunk_counter,
                             self->flags | atproto_bao_maybe_start(self));
    self->blocks_compressed += 1;
    input += BLAKE3_BLOCK_LEN;
    input_len -= BLAKE3_BLOCK_LEN;
  }
  if (input_len > 0) {
    memcpy(self->buf + self->buf_len, input, input_len);
    self->buf_len = (uint8_t)(self->buf_len + input_len);
  }
}

static atproto_bao_output_t atproto_bao_make_output(const uint32_t input_cv[8],
                                                    const uint8_t block[BLAKE3_BLOCK_LEN],
                                                    uint8_t block_len, uint64_t counter,
                                                    uint8_t flags) {
  atproto_bao_output_t ret;
  memcpy(ret.input_cv, input_cv, 32);
  memcpy(ret.block, block, BLAKE3_BLOCK_LEN);
  ret.block_len = block_len;
  ret.counter = counter;
  ret.flags = flags;
  return ret;
}

static atproto_bao_output_t atproto_bao_chunk_output(const blake3_chunk_state *self) {
  uint8_t flags = (uint8_t)(self->flags | atproto_bao_maybe_start(self) | CHUNK_END);
  return atproto_bao_make_output(self->cv, self->buf, self->buf_len, self->chunk_counter, flags);
}

static atproto_bao_output_t atproto_bao_parent_output(const uint8_t block[BLAKE3_BLOCK_LEN],
                                                     const uint32_t key[8]) {
  return atproto_bao_make_output(key, block, BLAKE3_BLOCK_LEN, 0, PARENT);
}

static void atproto_bao_output_cv(const atproto_bao_output_t *self, uint8_t cv[32]) {
  uint32_t cv_words[8];
  memcpy(cv_words, self->input_cv, 32);
  blake3_compress_in_place(cv_words, self->block, self->block_len, self->counter, self->flags);
  store_cv_words(cv, cv_words);
}

static void atproto_bao_output_root(const atproto_bao_output_t *self, uint8_t out[32]) {
  uint8_t wide[64];
  blake3_compress_xof(self->input_cv, self->block, self->block_len, 0,
                       (uint8_t)(self->flags | ROOT), wide);
  memcpy(out, wide, 32);
}

static void atproto_bao_hash_chunk(uint8_t out[32], const uint8_t *data, size_t len,
                                   uint64_t counter, int is_root) {
  blake3_chunk_state state;
  atproto_bao_chunk_state_init(&state, IV, 0);
  state.chunk_counter = counter;
  if (len > 0) {
    atproto_bao_chunk_state_update(&state, data, len);
  }
  atproto_bao_output_t output = atproto_bao_chunk_output(&state);
  if (is_root) {
    atproto_bao_output_root(&output, out);
  } else {
    atproto_bao_output_cv(&output, out);
  }
}

static void atproto_bao_hash_parent(uint8_t out[32], const uint8_t left[32], const uint8_t right[32],
                                    int is_root) {
  uint8_t block[BLAKE3_BLOCK_LEN];
  memcpy(block, left, 32);
  memcpy(block + 32, right, 32);
  atproto_bao_output_t output = atproto_bao_parent_output(block, IV);
  if (is_root) {
    atproto_bao_output_root(&output, out);
  } else {
    atproto_bao_output_cv(&output, out);
  }
}

static size_t atproto_bao_left_len(size_t content_len) {
  size_t full_chunks = (content_len - 1) / ATPROTO_BAO_CHUNK;
  return (size_t)round_down_to_power_of_2((uint64_t)full_chunks) * ATPROTO_BAO_CHUNK;
}

static uint64_t atproto_bao_count_chunks(uint64_t content_len) {
  if (content_len == 0) return 1;
  return (content_len + ATPROTO_BAO_CHUNK - 1) / ATPROTO_BAO_CHUNK;
}

static size_t atproto_bao_outboard_subtree_size(uint64_t content_len) {
  uint64_t chunks = atproto_bao_count_chunks(content_len);
  return (size_t)((chunks - 1) * ATPROTO_BAO_PARENT);
}

static int atproto_bao_encode_subtree_pre(const uint8_t *data, size_t content_len, uint64_t counter,
                                          int is_root, uint8_t cv_out[32], atproto_bao_buf *out) {
  if (content_len <= ATPROTO_BAO_CHUNK) {
    atproto_bao_hash_chunk(cv_out, data, content_len, counter, is_root);
    return 0;
  }
  size_t left_size = atproto_bao_left_len(content_len);
  atproto_bao_buf left_parents = {0};
  atproto_bao_buf right_parents = {0};
  uint8_t left_cv[32];
  uint8_t right_cv[32];
  int rc = atproto_bao_encode_subtree_pre(data, left_size, counter, 0, left_cv, &left_parents);
  if (rc != 0) {
    free(left_parents.bytes);
    return rc;
  }
  uint64_t right_counter = counter + (left_size / ATPROTO_BAO_CHUNK);
  rc = atproto_bao_encode_subtree_pre(data + left_size, content_len - left_size, right_counter, 0,
                                      right_cv, &right_parents);
  if (rc != 0) {
    free(left_parents.bytes);
    free(right_parents.bytes);
    return rc;
  }
  uint8_t parent[ATPROTO_BAO_PARENT];
  memcpy(parent, left_cv, 32);
  memcpy(parent + 32, right_cv, 32);
  atproto_bao_hash_parent(cv_out, left_cv, right_cv, is_root);
  rc = atproto_bao_buf_append(out, parent, ATPROTO_BAO_PARENT);
  if (rc == 0) rc = atproto_bao_buf_append(out, left_parents.bytes, left_parents.len);
  if (rc == 0) rc = atproto_bao_buf_append(out, right_parents.bytes, right_parents.len);
  free(left_parents.bytes);
  free(right_parents.bytes);
  return rc;
}

int atproto_bao_hash(const uint8_t *data, size_t len, uint8_t out_hash[32]) {
  if (!out_hash) return -1;
  if (!data && len > 0) return -1;
  blake3_hasher hasher;
  blake3_hasher_init(&hasher);
  if (len > 0) {
    blake3_hasher_update(&hasher, data, len);
  }
  blake3_hasher_finalize(&hasher, out_hash, 32);
  return 0;
}

int atproto_bao_outboard(const uint8_t *data, size_t len, uint8_t **out_bytes, size_t *out_len) {
  if (!out_bytes || !out_len) return -1;
  *out_bytes = NULL;
  *out_len = 0;
  atproto_bao_buf parents = {0};
  uint8_t cv[32];
  const uint8_t *ptr = data ? data : (const uint8_t *)"";
  if (atproto_bao_encode_subtree_pre(ptr, len, 0, 1, cv, &parents) != 0) {
    free(parents.bytes);
    return -1;
  }
  size_t total = ATPROTO_BAO_HEADER + parents.len;
  uint8_t *buf = (uint8_t *)malloc(total);
  if (!buf) {
    free(parents.bytes);
    return -1;
  }
  uint64_t le = (uint64_t)len;
  memcpy(buf, &le, 8);
  if (parents.len > 0) {
    memcpy(buf + 8, parents.bytes, parents.len);
  }
  free(parents.bytes);
  *out_bytes = buf;
  *out_len = total;
  (void)cv;
  return 0;
}

typedef struct {
  const uint8_t *data;
  const uint8_t *ob;
  size_t ob_len;
  size_t ob_pos;
  atproto_bao_buf out;
} atproto_bao_slice_ctx;

static int atproto_bao_ob_read(atproto_bao_slice_ctx *ctx, void *dst, size_t n) {
  if (ctx->ob_pos + n > ctx->ob_len) return -1;
  memcpy(dst, ctx->ob + ctx->ob_pos, n);
  ctx->ob_pos += n;
  return 0;
}

static int atproto_bao_ob_skip(atproto_bao_slice_ctx *ctx, size_t n) {
  if (ctx->ob_pos + n > ctx->ob_len) return -1;
  ctx->ob_pos += n;
  return 0;
}

static int atproto_bao_ranges_overlap(uint64_t a0, uint64_t a1, uint64_t b0, uint64_t b1) {
  return a0 < b1 && b0 < a1;
}

static int atproto_bao_extract_subtree(atproto_bao_slice_ctx *ctx, size_t content_off,
                                       size_t content_len, uint64_t counter, uint64_t slice_start,
                                       uint64_t slice_end) {
  if (content_len <= ATPROTO_BAO_CHUNK) {
    uint64_t chunk_end = content_off + content_len;
    if (!atproto_bao_ranges_overlap(content_off, chunk_end, slice_start, slice_end)) {
      return 0;
    }
    return atproto_bao_buf_append(&ctx->out, ctx->data + content_off, content_len);
  }
  size_t left_size = atproto_bao_left_len(content_len);
  uint8_t parent[ATPROTO_BAO_PARENT];
  if (atproto_bao_ob_read(ctx, parent, ATPROTO_BAO_PARENT) != 0) return -1;

  uint64_t left_start = content_off;
  uint64_t left_end = content_off + left_size;
  uint64_t right_start = left_end;
  uint64_t right_end = content_off + content_len;
  int left_needed = atproto_bao_ranges_overlap(left_start, left_end, slice_start, slice_end);
  int right_needed = atproto_bao_ranges_overlap(right_start, right_end, slice_start, slice_end);

  if (left_needed || right_needed) {
    if (atproto_bao_buf_append(&ctx->out, parent, ATPROTO_BAO_PARENT) != 0) return -1;
  }

  if (left_needed) {
    if (atproto_bao_extract_subtree(ctx, content_off, left_size, counter, slice_start, slice_end) !=
        0) {
      return -1;
    }
  } else if (atproto_bao_ob_skip(ctx, atproto_bao_outboard_subtree_size(left_size)) != 0) {
    return -1;
  }

  uint64_t right_counter = counter + (left_size / ATPROTO_BAO_CHUNK);
  if (right_needed) {
    if (atproto_bao_extract_subtree(ctx, content_off + left_size, content_len - left_size,
                                    right_counter, slice_start, slice_end) != 0) {
      return -1;
    }
  } else if (atproto_bao_ob_skip(ctx, atproto_bao_outboard_subtree_size(content_len - left_size)) !=
             0) {
    return -1;
  }
  return 0;
}

int atproto_bao_slice(const uint8_t *data, size_t data_len, const uint8_t *outboard,
                      size_t outboard_len, uint64_t offset, uint64_t length, uint8_t **out_bytes,
                      size_t *out_len) {
  if (!out_bytes || !out_len || !outboard || outboard_len < ATPROTO_BAO_HEADER) return -1;
  *out_bytes = NULL;
  *out_len = 0;
  uint64_t content_len = 0;
  memcpy(&content_len, outboard, 8);
  if (content_len != (uint64_t)data_len) return -1;
  if (offset > content_len) return -1;
  uint64_t available = content_len - offset;
  uint64_t take = length < available ? length : available;
  uint64_t slice_end = offset + take;
  if (take == 0 && content_len > 0) {
    slice_end = offset + 1;
    if (slice_end > content_len) slice_end = content_len;
  }

  atproto_bao_slice_ctx ctx;
  memset(&ctx, 0, sizeof(ctx));
  ctx.data = data ? data : (const uint8_t *)"";
  ctx.ob = outboard + ATPROTO_BAO_HEADER;
  ctx.ob_len = outboard_len - ATPROTO_BAO_HEADER;

  uint8_t header[8];
  memcpy(header, &content_len, 8);
  if (atproto_bao_buf_append(&ctx.out, header, 8) != 0) {
    free(ctx.out.bytes);
    return -1;
  }
  if (atproto_bao_extract_subtree(&ctx, 0, (size_t)content_len, 0, offset, slice_end) != 0) {
    free(ctx.out.bytes);
    return -1;
  }
  *out_bytes = ctx.out.bytes;
  *out_len = ctx.out.len;
  return 0;
}

typedef struct {
  const uint8_t *bytes;
  size_t len;
  size_t pos;
  atproto_bao_buf content;
} atproto_bao_verify_ctx;

static int atproto_bao_vread(atproto_bao_verify_ctx *ctx, void *dst, size_t n) {
  if (ctx->pos + n > ctx->len) return -1;
  memcpy(dst, ctx->bytes + ctx->pos, n);
  ctx->pos += n;
  return 0;
}

static int atproto_bao_verify_subtree(atproto_bao_verify_ctx *ctx, size_t content_off,
                                      size_t content_len, uint64_t counter, int is_root,
                                      const uint8_t expected_cv[32], uint64_t slice_start,
                                      uint64_t slice_end) {
  if (content_len <= ATPROTO_BAO_CHUNK) {
    uint64_t chunk_end = content_off + content_len;
    if (!atproto_bao_ranges_overlap(content_off, chunk_end, slice_start, slice_end)) {
      return 0;
    }
    uint8_t *chunk = (uint8_t *)malloc(content_len > 0 ? content_len : 1);
    if (!chunk) return -1;
    if (content_len > 0) {
      if (atproto_bao_vread(ctx, chunk, content_len) != 0) {
        free(chunk);
        return -1;
      }
    }
    uint8_t cv[32];
    atproto_bao_hash_chunk(cv, chunk, content_len, counter, is_root);
    int ok = memcmp(cv, expected_cv, 32) == 0;
    if (ok) {
      uint64_t o0 = content_off > slice_start ? content_off : slice_start;
      uint64_t o1 = chunk_end < slice_end ? chunk_end : slice_end;
      if (o0 < o1) {
        size_t local = (size_t)(o0 - content_off);
        size_t n = (size_t)(o1 - o0);
        if (atproto_bao_buf_append(&ctx->content, chunk + local, n) != 0) ok = 0;
      }
    }
    free(chunk);
    return ok ? 0 : -2;
  }

  size_t left_size = atproto_bao_left_len(content_len);
  uint64_t left_start = content_off;
  uint64_t left_end = content_off + left_size;
  uint64_t right_start = left_end;
  uint64_t right_end = content_off + content_len;
  int left_needed = atproto_bao_ranges_overlap(left_start, left_end, slice_start, slice_end);
  int right_needed = atproto_bao_ranges_overlap(right_start, right_end, slice_start, slice_end);
  if (!left_needed && !right_needed) {
    return 0;
  }

  uint8_t parent[ATPROTO_BAO_PARENT];
  if (atproto_bao_vread(ctx, parent, ATPROTO_BAO_PARENT) != 0) return -1;
  uint8_t left_cv[32];
  uint8_t right_cv[32];
  memcpy(left_cv, parent, 32);
  memcpy(right_cv, parent + 32, 32);
  uint8_t merged[32];
  atproto_bao_hash_parent(merged, left_cv, right_cv, is_root);
  if (memcmp(merged, expected_cv, 32) != 0) return -2;

  if (left_needed) {
    int rc = atproto_bao_verify_subtree(ctx, content_off, left_size, counter, 0, left_cv,
                                        slice_start, slice_end);
    if (rc != 0) return rc;
  }
  if (right_needed) {
    uint64_t right_counter = counter + (left_size / ATPROTO_BAO_CHUNK);
    int rc = atproto_bao_verify_subtree(ctx, content_off + left_size, content_len - left_size,
                                        right_counter, 0, right_cv, slice_start, slice_end);
    if (rc != 0) return rc;
  }
  return 0;
}

int atproto_bao_verify_slice(const uint8_t *slice, size_t slice_len, const uint8_t expected_hash[32],
                             uint64_t offset, uint64_t length, uint8_t **out_content,
                             size_t *out_content_len) {
  if (!slice || !expected_hash || !out_content || !out_content_len) return -1;
  *out_content = NULL;
  *out_content_len = 0;
  if (slice_len < ATPROTO_BAO_HEADER) return -1;
  uint64_t content_len = 0;
  memcpy(&content_len, slice, 8);
  if (offset > content_len) return -1;
  uint64_t available = content_len - offset;
  uint64_t take = length < available ? length : available;
  uint64_t slice_end = offset + take;
  if (take == 0 && content_len > 0) {
    slice_end = offset + 1;
    if (slice_end > content_len) slice_end = content_len;
  }

  atproto_bao_verify_ctx ctx;
  memset(&ctx, 0, sizeof(ctx));
  ctx.bytes = slice;
  ctx.len = slice_len;
  ctx.pos = ATPROTO_BAO_HEADER;

  if (content_len == 0) {
    uint8_t cv[32];
    atproto_bao_hash_chunk(cv, (const uint8_t *)"", 0, 0, 1);
    if (memcmp(cv, expected_hash, 32) != 0) return -2;
    *out_content = (uint8_t *)calloc(1, 1);
    *out_content_len = 0;
    return *out_content ? 0 : -1;
  }

  int rc = atproto_bao_verify_subtree(&ctx, 0, (size_t)content_len, 0, 1, expected_hash, offset,
                                      slice_end);
  if (rc != 0) {
    free(ctx.content.bytes);
    return rc;
  }
  *out_content = ctx.content.bytes;
  *out_content_len = ctx.content.len;
  if (!*out_content && *out_content_len == 0) {
    *out_content = (uint8_t *)calloc(1, 1);
  }
  return *out_content || *out_content_len == 0 ? 0 : -1;
}
