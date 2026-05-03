/*
 * objc_interp_context.h
 * Centralized interpreter state struct for the Objective-C WASM kernel.
 *
 * InterpContext groups all 33 mutable interpreter globals into a single struct,
 * enabling type-safe field access and a single reset point via memset().
 * This reduces cross-module coupling without requiring function signature changes.
 *
 * Currently allocated as a static global; future work can thread InterpContext*
 * through function signatures to enable thread-safety and multi-kernel hosting.
 */

#ifndef OBJC_INTERP_CONTEXT_H
#define OBJC_INTERP_CONTEXT_H

#include "objc_interp_types.h"

typedef struct InterpContext {
    /* ── Error state ─────────────────────────────────────────────── */
    char error_buffer[OBJC_INTERP_ERROR_SIZE];
    int error_code;
    unsigned int error_line;
    unsigned int error_column;

    /* ── Interpreter state ───────────────────────────────────────── */
    int interp_initialized;
    char result_buffer[512];

    /* ── NSLog ring buffer ───────────────────────────────────────── */
    char nslog_buffer[OBJC_INTERP_NSLOG_BUFFER_SIZE];
    unsigned int nslog_offset;

    /* ── Variable table ─────────────────────────────────────────── */
    InterpVar vars[OBJC_INTERP_MAX_VARS];
    unsigned int var_count;
    unsigned int var_scope_base;

    /* ── Type definitions ───────────────────────────────────────── */
    TypeDef typedefs[64];
    unsigned int typedef_count;

    /* ── Method dispatch state ──────────────────────────────────── */
    int return_pending;
    Value return_value;
    MethodImpl methods[64];
    unsigned int method_count;

    /* ── Property declarations ──────────────────────────────────── */
    PropertyDecl properties[64];
    unsigned int property_count;

    /* ── Instance variable side table ───────────────────────────── */
    InstanceVar instance_vars[256];
    unsigned int instance_var_count;

    /* ── Collection side table ──────────────────────────────────── */
    unsigned int next_coll_id;
    CollEntry coll_entries[512];
    unsigned int coll_entry_count;

    /* ── Block side table ───────────────────────────────────────── */
    BlockImpl blocks[32];
    unsigned int block_count;
    unsigned int next_block_id;

    /* ── String pool ────────────────────────────────────────────── */
    char string_pool[OBJC_INTERP_STRING_POOL_SIZE];
    unsigned int string_pool_offset;
    unsigned int parse_depth;

    /* ── AST arena ──────────────────────────────────────────────── */
    AstNode ast_arena[1024];
    unsigned int ast_count;
    int break_pending;
    int continue_pending;
} InterpContext;

/* Global interpreter context, defined in objc_interpreter.c */
extern InterpContext g_ctx;

#endif /* OBJC_INTERP_CONTEXT_H */
