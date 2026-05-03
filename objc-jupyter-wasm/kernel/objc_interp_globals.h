/* objc_interp_globals.h — Shared global variable declarations
 *
 * This header declares all interpreter global variables as `extern`.
 * The definitions live in objc_interpreter.c (the main implementation file).
 * Extracted modules include this header to access shared state.
 *
 * Strategy: globals start as `static` in objc_interpreter.c. When a module
 * is extracted that needs a global, `static` is removed from the definition
 * in objc_interpreter.c and the module includes this header.
 *
 * All globals are process-wide singletons — safe for single-threaded WASM.
 * Do NOT use from concurrent threads without synchronization.
 */

#ifndef OBJC_INTERP_GLOBALS_H
#define OBJC_INTERP_GLOBALS_H

#include "objc_interp_types.h"

/* ── Error state ──────────────────────────────────────────────── */

extern char g_error_buffer[];       /* error message buffer */
extern int g_error_code;            /* OBJC_INTERP_OK or error code */
extern unsigned int g_error_line;   /* line number of last error */
extern unsigned int g_error_column; /* column number of last error */

/* ── Interpreter state ────────────────────────────────────────── */

extern char g_result_buffer[];      /* expression result display buffer */

/* ── NSLog buffer ─────────────────────────────────────────────── */

extern char g_nslog_buffer[];       /* NSLog output buffer */
extern unsigned int g_nslog_offset; /* current write offset */

/* ── Variable table ───────────────────────────────────────────── */

extern InterpVar g_vars[];          /* variable storage */
extern unsigned int g_var_count;     /* number of active variables */
extern unsigned int g_var_scope_base; /* base index for method scope */

/* ── Type definitions ─────────────────────────────────────────── */

extern TypeDef g_typedefs[];        /* typedef storage */
extern unsigned int g_typedef_count; /* number of active typedefs */

/* ── Method dispatch state ────────────────────────────────────── */

extern int g_return_pending;        /* 1 after return statement */
extern Value g_return_value;        /* value from return statement */
extern MethodImpl g_methods[];      /* registered method implementations */
extern unsigned int g_method_count; /* number of registered methods */

/* ── Property declarations ────────────────────────────────────── */

extern PropertyDecl g_properties[];  /* registered @property declarations */
extern unsigned int g_property_count; /* number of registered properties */

/* ── Instance variable side table ─────────────────────────────── */

extern InstanceVar g_instance_vars[];  /* per-object property storage */
extern unsigned int g_instance_var_count; /* number of instance vars */

/* ── Collection side table ────────────────────────────────────── */

extern unsigned int g_next_coll_id;  /* next collection ID */
extern CollEntry g_coll_entries[];    /* collection key-value/element storage */
extern unsigned int g_coll_entry_count; /* number of collection entries */

/* ── Block side table ─────────────────────────────────────────── */

extern BlockImpl g_blocks[];         /* registered block implementations */
extern unsigned int g_block_count;   /* number of registered blocks */
extern unsigned int g_next_block_id; /* next block ID */

/* ── String pool ──────────────────────────────────────────────── */

extern char g_string_pool[];         /* string literal + Foundation marker pool */
extern unsigned int g_string_pool_offset; /* current write offset */
extern unsigned int g_parse_depth;   /* nesting depth counter */

/* ── AST arena ────────────────────────────────────────────────── */

extern AstNode g_ast_arena[];        /* AST node storage */
extern unsigned int g_ast_count;     /* number of allocated AST nodes */
extern int g_break_pending;          /* 1 after break statement */
extern int g_continue_pending;       /* 1 after continue statement */

#endif /* OBJC_INTERP_GLOBALS_H */
