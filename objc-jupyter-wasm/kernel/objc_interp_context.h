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
    /* ── Error state ───────────────────────────────────────── */
    char error_buffer[OBJC_INTERP_ERROR_SIZE];
    int error_code;
    unsigned int error_line;
    unsigned int error_column;

    /* ── Interpreter state ───────────────────────────────────── */
    int interp_initialized;
    char result_buffer[512];

    /* ── NSLog ring buffer ──────────────────────────────────── */
    char nslog_buffer[OBJC_INTERP_NSLOG_BUFFER_SIZE];
    unsigned int nslog_offset;

    /* ── Variable table ───────────────────────────────────── */
    InterpVar vars[OBJC_INTERP_MAX_VARS];
    unsigned int var_count;
    unsigned int var_scope_base;

    /* ── Type definitions ──────────────────────────────────── */
    TypeDef typedefs[64];
    unsigned int typedef_count;

    /* ── Method dispatch state ────────────────────────────── */
    int return_pending;
    Value return_value;
    MethodImpl methods[64];
    unsigned int method_count;

    /* ── Property declarations ─────────────────────────────── */
    PropertyDecl properties[64];
    unsigned int property_count;

    /* ── Declared class ivars (from @interface { } blocks) ── */
    ClassIvar class_ivars[MAX_CLASS_IVARS];
    unsigned int class_ivar_count;

    /* ── Instance variable side table ───────────────────────── */
    InstanceVar instance_vars[256];
    unsigned int instance_var_count;

    /* ── Collection side table ─────────────────────────────── */
    unsigned int next_coll_id;
    unsigned int coll_generation[MAX_COLLECTIONS]; /* generation counter per slot */
    int coll_slot_active[MAX_COLLECTIONS];         /* 1 if slot is in use, 0 if free */
    int coll_free_list;                            /* head of free slot list (-1 = empty) */
    int coll_free_next[MAX_COLLECTIONS];           /* next pointer for free list */
    CollEntry coll_entries[512];
    unsigned int coll_entry_count;

    /* ── Block side table ─────────────────────────────────── */
    BlockImpl blocks[32];
    unsigned int block_count;
    unsigned int next_block_id;

    /* ── Network Task Registry ────────────────────────────── */
    PendingNetworkTask network_tasks[MAX_NETWORK_TASKS];
    unsigned int network_task_count;
    unsigned int next_network_task_id;

    /* ── Protocol declarations ────────────────────────────── */
    ProtocolDecl protocols[MAX_PROTOCOLS];
    unsigned int protocol_count;

    /* ── Exception/try-catch state ─────────────────────────── */
    TryFrame try_stack[MAX_TRY_DEPTH];
    unsigned int try_depth;
    int exception_pending;
    Value current_exception;

    /* ── Autorelease pool stack ─────────────────────────── */
    AutoreleasePool pools[MAX_AUTORELEASE_POOL_DEPTH];
    unsigned int pool_depth;

    /* ── Current method dispatch context ─────────────────── */
    Class current_class_ptr;  /* class of the currently-executing method (for super dispatch) */

    /* ── Class hierarchy table ─────────────────────────── */
#define MAX_CLASS_HIERARCHY 128
    char class_hierarchy_class[MAX_CLASS_HIERARCHY][64]; /* class_name */
    char class_hierarchy_super[MAX_CLASS_HIERARCHY][64]; /* super_name */
    unsigned int class_hierarchy_count;

    /* ── Class conformance table ────────────────────────── */
    char class_conformances[OBJC_INTERP_MAX_VARS][8][64];
    unsigned int class_conforms_count[OBJC_INTERP_MAX_VARS];

    /* ── Enumerators ────────────────────────────────────── */
    EnumeratorState enumerators[MAX_ENUMERATORS];
    unsigned int next_enumerator_id;

    /* ── Invocations ────────────────────────────────────── */
    InvocationState invocations[MAX_INVOCATIONS];
    unsigned int next_invocation_id;

    /* ── Associations ───────────────────────────────────── */
    Association associations[MAX_ASSOCIATIONS];
    unsigned int association_count;

    /* ── KVO ────────────────────────────────────────────── */
    KVOObserver kvo_observers[MAX_KVO_OBSERVERS];
    unsigned int kvo_count;

    /* ── String pool ────────────────────────────────────── */
    char string_pool[OBJC_INTERP_STRING_POOL_SIZE];
    unsigned int string_pool_offset;
    unsigned int parse_depth;

    /* ── AST arena ──────────────────────────────────────── */
    AstNode ast_arena[1024];
    unsigned int ast_count;
    int break_pending;
    int continue_pending;

    /* ── Side-effect suppression for short-circuit evaluation ── */
    int suppress_side_effects; /* when set, message sends and variable mutations are no-ops */

    /* ── AST evaluation depth counter ── */
    unsigned int eval_depth; /* incremented in eval_ast, checked against MAX_EVAL_DEPTH */

    /* ── Loop iteration guard ── */
    unsigned int loop_iterations; /* total across all loops in one eval, checked against MAX_LOOP_ITERATIONS */
} InterpContext;

/* Global interpreter context, defined in objc_interpreter.c */
extern InterpContext g_ctx;

#endif /* OBJC_INTERP_CONTEXT_H */
