/*
 * objc_interpreter.c
 * Thin Objective-C interpreter for the Jupyter WASM kernel.
 *
 * Recursive-descent parser that evaluates ObjC source against the
 * real GNUstep libobjc2 runtime. See objc_interpreter.h for scope.
 */

#include "objc_interp_types.h"
#include "objc_interp_globals.h"

/* Runtime functions exported from the WASM module but not declared
 * in the headers we include (they're in NSObject.h normally). */
extern Class object_getClass(id);
extern id objc_lookUpClass(const char *name);

/* objc_lookUpClass is declared in runtime.h with return type id,
 * which is compatible with Class. We use it to check if a class
 * name is registered in the runtime. */

/* Browser / Node host imports for streaming and cooperative interrupts. */
extern void objc_kernel_host_stream(int kind, const char *ptr, unsigned int len)
    __attribute__((import_module("objc_kernel_host"), import_name("stream")));
extern int objc_kernel_host_should_interrupt(void)
    __attribute__((import_module("objc_kernel_host"), import_name("should_interrupt")));

/* ── NSLog ring buffer ──────────────────────────────────────────── */

char g_nslog_buffer[OBJC_INTERP_NSLOG_BUFFER_SIZE];
unsigned int g_nslog_offset = 0;

/* ── Interpreter state ──────────────────────────────────────────── */

char g_error_buffer[OBJC_INTERP_ERROR_SIZE];
int g_error_code = OBJC_INTERP_OK;
unsigned int g_error_line = 0;
unsigned int g_error_column = 0;
int g_interp_initialized = 0;

/* Forward declaration — Parser struct defined below */
void set_error_from_parser(struct Parser *p);

char g_result_buffer[512];

/* ── Interpreter helpers (extracted to objc_interp_state.c) ────── */

#include "objc_interp_state.h"

/* ── Interpreter state globals ──────────────────────────────────── */

InterpVar g_vars[OBJC_INTERP_MAX_VARS];
unsigned int g_var_count = 0;
unsigned int g_var_scope_base = 0; /* base index for variable scoping during method execution */

TypeDef g_typedefs[OBJC_INTERP_MAX_TYPEDEFS];
unsigned int g_typedef_count = 0;

/* ── Lexer (extracted to objc_interp_lexer.c) ─────────────────── */

#include "objc_interp_lexer.h"
#include "objc_interp_format.h"
#include "objc_interp_ast.h"
#include "objc_interp_class.h"
#include "objc_interp_dispatch.h"
#include "objc_interp_parser.h"

/* ── Parser ─────────────────────────────────────────────────────── */

typedef struct Parser {
    Lexer lex;
    int error;
    char error_msg[OBJC_INTERP_ERROR_SIZE];
} Parser;

void set_error_from_parser(Parser *p) {
    g_error_code = p->error;
    cstr_copy(g_error_buffer, p->error_msg, OBJC_INTERP_ERROR_SIZE);
    g_error_line = p->lex.line;
    g_error_column = p->lex.column;
}

void parser_init(Parser *p, const char *source, unsigned int length) {
    lexer_init(&p->lex, source, length);
    p->error = 0;
    p->error_msg[0] = '\0';
    p->lex.current = lexer_next_token(&p->lex);
}

Token parser_current(Parser *p) {
    return p->lex.current;
}

void parser_advance(Parser *p) {
    p->lex.current = lexer_next_token(&p->lex);
}

int parser_expect(Parser *p, TokenType type) {
    if (p->lex.current.type == type) {
        parser_advance(p);
        return 1;
    }
    p->error = OBJC_INTERP_SYNTAX_ERROR;
    return 0;
}

void parser_error(Parser *p, const char *msg) {
    p->error = OBJC_INTERP_SYNTAX_ERROR;
    /* Format: "line N, column M: <message>" */
    {
        char buf[OBJC_INTERP_ERROR_SIZE];
        unsigned int pos = 0;
        const char *prefix = "line ";
        unsigned int pi = 0;
        while (prefix[pi] != '\0' && pos < OBJC_INTERP_ERROR_SIZE - 1) {
            buf[pos++] = prefix[pi++];
        }
        /* Write line number */
        {
            unsigned int line = p->lex.line;
            char digits[10];
            int dcount = 0;
            if (line == 0) line = 1;
            while (line > 0 && dcount < 10) {
                digits[dcount++] = '0' + (line % 10);
                line /= 10;
            }
            if (dcount == 0) digits[dcount++] = '0';
            while (dcount > 0 && pos < OBJC_INTERP_ERROR_SIZE - 1) {
                buf[pos++] = digits[--dcount];
            }
        }
        if (pos < OBJC_INTERP_ERROR_SIZE - 2) {
            buf[pos++] = ',';
            buf[pos++] = ' ';
        }
        const char *col_prefix = "column ";
        pi = 0;
        while (col_prefix[pi] != '\0' && pos < OBJC_INTERP_ERROR_SIZE - 1) {
            buf[pos++] = col_prefix[pi++];
        }
        /* Write column number */
        {
            unsigned int col = p->lex.column;
            char digits[10];
            int dcount = 0;
            if (col == 0) col = 1;
            while (col > 0 && dcount < 10) {
                digits[dcount++] = '0' + (col % 10);
                col /= 10;
            }
            if (dcount == 0) digits[dcount++] = '0';
            while (dcount > 0 && pos < OBJC_INTERP_ERROR_SIZE - 1) {
                buf[pos++] = digits[--dcount];
            }
        }
        if (pos < OBJC_INTERP_ERROR_SIZE - 2) {
            buf[pos++] = ':';
            buf[pos++] = ' ';
        }
        /* Append the original message */
        {
            unsigned int mi = 0;
            while (msg[mi] != '\0' && pos < OBJC_INTERP_ERROR_SIZE - 1) {
                buf[pos++] = msg[mi++];
            }
        }
        buf[pos] = '\0';
        cstr_copy(p->error_msg, buf, OBJC_INTERP_ERROR_SIZE);
    }
}

/* Copy an identifier into a fixed-size field, raising a parser error if
 * the identifier does not fit. Silent truncation is a correctness hazard:
 * later table lookups compare the full source name against the truncated
 * stored copy and miss. `kind` is a short noun ("class", "super",
 * "property", "ivar", "argument", "variable") used in the error message. */
int copy_identifier_or_error(Parser *p, char *dst, const char *src,
                                    unsigned int capacity, const char *kind) {
    char buf[OBJC_INTERP_ERROR_SIZE];
    unsigned int pos = 0;
    const char *prefix;
    unsigned int pi;
    unsigned int max_chars;
    if (cstr_copy_checked(dst, src, capacity) == 0) return 0;
    /* Truncation: format "<kind> name too long (max N): '<truncated>...'" */
    max_chars = capacity > 0 ? capacity - 1 : 0;
    prefix = kind ? kind : "identifier";
    pi = 0;
    while (prefix[pi] != '\0' && pos < sizeof(buf) - 1) buf[pos++] = prefix[pi++];
    {
        const char *suffix = " name too long (max ";
        pi = 0;
        while (suffix[pi] != '\0' && pos < sizeof(buf) - 1) buf[pos++] = suffix[pi++];
    }
    {
        unsigned int n = max_chars;
        char digits[10];
        int dcount = 0;
        if (n == 0) digits[dcount++] = '0';
        while (n > 0 && dcount < 10) { digits[dcount++] = '0' + (n % 10); n /= 10; }
        while (dcount > 0 && pos < sizeof(buf) - 1) buf[pos++] = digits[--dcount];
    }
    {
        const char *mid = "): '";
        pi = 0;
        while (mid[pi] != '\0' && pos < sizeof(buf) - 1) buf[pos++] = mid[pi++];
    }
    pi = 0;
    while (dst[pi] != '\0' && pos < sizeof(buf) - 5) buf[pos++] = dst[pi++];
    if (pos < sizeof(buf) - 5) {
        buf[pos++] = '.'; buf[pos++] = '.'; buf[pos++] = '.'; buf[pos++] = '\'';
    }
    buf[pos] = '\0';
    parser_error(p, buf);
    return 1;
}

/* ── Variable table ─────────────────────────────────────────────── */

static InterpVar *interp_find_var(const char *name) {
    /* Search backwards — most recently created variable first.
     * This implements variable shadowing: a method-local variable
     * with the same name as a top-level variable takes precedence.
     * g_var_scope_base limits the search to the current scope
     * (set during method execution to isolate method-local variables). */
    unsigned int i;
    if (g_var_count == 0) return 0;
    for (i = g_var_count; i > g_var_scope_base; i--) {
        if (cstr_eq(g_vars[i - 1].name, name)) {
            return &g_vars[i - 1];
        }
    }
    return 0;
}

static InterpVar *interp_create_var(const char *name) {
    if (g_var_count >= OBJC_INTERP_MAX_VARS) return 0;
    cstr_copy(g_vars[g_var_count].name, name, 64);
    g_vars[g_var_count].value = 0;
    g_vars[g_var_count].cls = 0;
    g_vars[g_var_count].sel = 0;
    g_vars[g_var_count].is_int = 0;
    g_vars[g_var_count].int_value = 0;
    g_vars[g_var_count].is_float = 0;
    g_vars[g_var_count].float_value = 0.0;
    g_vars[g_var_count].is_class = 0;
    g_vars[g_var_count].is_sel = 0;
    g_vars[g_var_count].is_id = 0;
    g_vars[g_var_count].is_block_captured = 0;
    g_vars[g_var_count].is_static = 0;
    g_var_count++;
    return &g_vars[g_var_count - 1];
}

static InterpVar *interp_get_or_create_var(const char *name) {
    InterpVar *v = interp_find_var(name);
    if (v) return v;
    return interp_create_var(name);
}

/* Look up a typedef alias and return the base type, or the original name if not found */
const char *typedef_resolve(const char *name) {
    if (!name) return 0;
    unsigned int i;
    for (i = 0; i < g_typedef_count; i++) {
        if (cstr_eq(g_typedefs[i].alias, name)) {
            return g_typedefs[i].base_type;
        }
    }
    return name; /* Return original if not found */
}

/* ── NSLog implementation ────────────────────────────────────────── */

/* ── nslog_append (extracted to objc_interp_format.c) */

/* ── nslog_append_char (extracted to objc_interp_format.c) */

/* ── nslog_append_int (extracted to objc_interp_format.c) */

/* ── nslog_append_long (extracted to objc_interp_format.c) */

/* ── Value helpers (extracted to objc_interp_state.c) ─────────── */

/* ── Method dispatch state ─────────────────────────────────────── */

/* Return value flag — set by return statement, checked by method dispatch */
int g_return_pending = 0;
Value g_return_value;

/* String pool for string literals and Foundation object encoding.
 * Shared between parse_primary (string literals) and parse_message_send
 * (Foundation stubs like NSNumber, stringByAppendingString). */
char g_string_pool[OBJC_INTERP_STRING_POOL_SIZE];
unsigned int g_string_pool_offset = 0;
unsigned int g_parse_depth = 0;

/* String pool allocation (extracted to objc_interp_state.c) */

MethodImpl g_methods[MAX_METHODS];
unsigned int g_method_count = 0;

PropertyDecl g_properties[MAX_PROPERTIES];
unsigned int g_property_count = 0;

InstanceVar g_instance_vars[MAX_INSTANCE_VARS];
unsigned int g_instance_var_count = 0;

/* ── Collection side table (extracted to objc_interp_state.c) ──── */

/* ── Block side table (extracted to objc_interp_state.c) ──────── */

/* ── Instance variable side table (extracted to objc_interp_state.c) */

/* ── AST arena ─────────────────────────────────────────────────── */

AstNode g_ast_arena[MAX_AST_NODES];
unsigned int g_ast_count = 0;

/* Break/continue flags — checked by loop evaluation */
int g_break_pending = 0;
int g_continue_pending = 0;

/* ── ast_alloc (extracted to objc_interp_ast.c) */


/* ── ast_make_if (extracted to objc_interp_ast.c) */


/* ── ast_make_while (extracted to objc_interp_ast.c) */


/* ── ast_make_do_while (extracted to objc_interp_ast.c) */


/* ── ast_make_for (extracted to objc_interp_ast.c) */


/* ── ast_make_block (extracted to objc_interp_ast.c) */


/* ── ast_block_add (extracted to objc_interp_ast.c) */


/* ── ast_make_source (extracted to objc_interp_ast.c) */


/* Create a no-op AST node for declarations already executed during parsing
 * (@interface, @implementation, @class, @protocol).
 * eval_ast skips these — they must not be re-executed via eval_source_range. */
/* ── ast_make_noop (extracted to objc_interp_ast.c) */


/* ── Forward declarations ───────────────────────────────────────── */

Value parse_expression(Parser *p);
/* ── parse_expression_safe (extracted to objc_interp_parser.c) */

Value parse_statement(Parser *p);
Value parse_block(Parser *p);
int is_truthy(Value v);
AstNode *parse_statement_ast(Parser *p);
Value eval_source_range(unsigned int start, unsigned int len, const char *source);
Value eval_ast(AstNode *node, const char *source);
Value parse_type_and_var_decl(Parser *p);

/* is_string_pool_pointer and class_for_fdobj_marker extracted to objc_interp_state.c */

/* ── interpreter_method_matches (extracted to objc_interp_dispatch.c) */

/* ── find_interpreter_method (extracted to objc_interp_dispatch.c) */

/* ── bind_method_var (extracted to objc_interp_dispatch.c) */

/* ── inject_synthesized_ivars (extracted to objc_interp_dispatch.c) */

/* ── write_back_synthesized_ivars (extracted to objc_interp_dispatch.c) */

/* ── execute_interpreter_method (extracted to objc_interp_dispatch.c) */

/* ── NSLog format string evaluation ─────────────────────────────── */

/* Evaluate NSLog with format string and arguments.
 * We've already consumed the NSLog identifier and opening paren.
 * The first argument is the format string (@"...").
 * Subsequent arguments are matched to %@, %d, %ld, %f, %% specifiers.
 */
/* ── eval_nslog (extracted to objc_interp_dispatch.c) */

/* ── Message send evaluation ────────────────────────────────────── */

/* Format values into a string pool entry, similar to NSLog but without
 * the trailing newline and host stream output. Returns the string pool
 * pointer as an id value. */
/* ── format_warn_missing_argument (extracted to objc_interp_format.c) */

/* ── format_values_to_pool (extracted to objc_interp_format.c) */

/* Parse a message send: [target selector:arg1 key2:arg2 ...]
 * We've already consumed the [.
 */
/* ── parse_message_send (extracted to objc_interp_messages.c) */
/* ── @interface / @implementation ────────────────────────────────── */

/* ── parse_interface (extracted to objc_interp_class.c) */

/* ── method_impl_trampoline (extracted to objc_interp_class.c) */

/* ── parse_implementation (extracted to objc_interp_class.c) */

/* ── Expression parser ──────────────────────────────────────────── */

/* ── parse_primary (extracted to objc_interp_primary.c) */

/* ── parse_expression and statement precedence (extracted to objc_interp_parser.c) */

/* ── parse_block_ast / parse_statement_ast (extracted to objc_interp_ast.c) */

/* ── AST evaluation ─────────────────────────────────────────────── */

/* Evaluate a source range by re-parsing it.
 * This creates a temporary parser over the source substring. */
/* ── eval_source_range (extracted to objc_interp_ast.c) */

/* Evaluate an AST node. source is the original full source string. */
/* ── eval_ast (extracted to objc_interp_ast.c) */

/* ── Value formatting for REPL display ─────────────────────────── */

/* ── fmt_append_char (extracted to objc_interp_format.c) */

/* ── fmt_append_str (extracted to objc_interp_format.c) */

/* ── fmt_append_uint (extracted to objc_interp_format.c) */

/* ── fmt_append_hex (extracted to objc_interp_format.c) */

/* ── format_value (extracted to objc_interp_format.c) */

/* ── objc_interp_gc_strings (extracted to objc_interp_format.c) */

void objc_interp_init(void) {
    g_interp_initialized = 1;
    g_nslog_offset = 0;
    g_nslog_buffer[0] = '\0';
    g_error_code = OBJC_INTERP_OK;
    g_error_buffer[0] = '\0';
    g_error_line = 0;
    g_error_column = 0;
    g_result_buffer[0] = '\0';
    g_var_count = 0;
    g_method_count = 0;
    g_property_count = 0;
    g_instance_var_count = 0;
    g_next_coll_id = 1;
    g_coll_entry_count = 0;
    g_next_block_id = 1;
    g_block_count = 0;

    /* Register Foundation class names as variables with is_class=1.
     * We don't call objc_allocateClassPair (it can cause WASM traps).
     * Instead, we store a sentinel class pointer and dispatch by name
     * in parse_message_send. The sentinel is (Class)1 — any non-null
     * value that won't collide with real class pointers. */
    {
        static const char * const foundation_classes[] = {
            "NSObject", "NSString", "NSNumber",
            "NSArray", "NSMutableArray", "NSDictionary",
            "NSMutableDictionary", "NSSet", "NSData"
        };
        unsigned int i;
        for (i = 0; i < sizeof(foundation_classes) / sizeof(foundation_classes[0]); i++) {
            InterpVar *var = interp_get_or_create_var(foundation_classes[i]);
            if (var) {
                var->is_class = 1;
                var->cls = (Class)(long)(i + 1); /* sentinel: 1..9 */
                var->is_id = 0;
                var->is_int = 0;
                var->is_sel = 0;
            }
        }
    }
}

int objc_interp(const char *source, unsigned int length) {
    Parser p;

    if (!g_interp_initialized) {
        g_error_code = OBJC_INTERP_RUNTIME_ERROR;
        cstr_copy(g_error_buffer, "Objective-C interpreter was not initialized; call objc_kernel_init() first", OBJC_INTERP_ERROR_SIZE);
        g_error_line = 1;
        g_error_column = 1;
        return OBJC_INTERP_RUNTIME_ERROR;
    }

    /* Reset per-execution state */
    g_nslog_offset = 0;
    g_nslog_buffer[0] = '\0';
    g_error_code = OBJC_INTERP_OK;
    g_error_buffer[0] = '\0';
    g_error_line = 0;
    g_error_column = 0;
    g_result_buffer[0] = '\0';
    g_return_pending = 0;
    g_break_pending = 0;
    g_continue_pending = 0;
    g_ast_count = 0;
    g_parse_depth = 0;

    /* Don't reset variable table — it persists across cells */

    parser_init(&p, source, length);

    /* Two-phase execution: parse into AST, then evaluate.
     * This enables control flow (if/while/for) to re-evaluate
     * conditions and loop bodies. */
    {
        AstNode *root = parse_block_ast(&p);

        if (p.error) {
            if (cstr_eq(p.error_msg, "Execution interrupted")) {
                g_error_code = OBJC_INTERP_INTERRUPTED;
            } else {
                g_error_code = p.error;
            }
            cstr_copy(g_error_buffer, p.error_msg, OBJC_INTERP_ERROR_SIZE);
            g_error_line = p.lex.line;
            g_error_column = p.lex.column;
            return p.error;
        }

        if (!root) {
            g_error_code = OBJC_INTERP_MEMORY_ERROR;
            cstr_copy(g_error_buffer, "AST allocation failed", OBJC_INTERP_ERROR_SIZE);
            return OBJC_INTERP_MEMORY_ERROR;
        }

        /* Evaluate the AST */
        {
            Value last = eval_ast(root, source);

            if (p.error) {
                if (cstr_eq(p.error_msg, "Execution interrupted")) {
                    g_error_code = OBJC_INTERP_INTERRUPTED;
                } else {
                    g_error_code = p.error;
                }
                cstr_copy(g_error_buffer, p.error_msg, OBJC_INTERP_ERROR_SIZE);
                g_error_line = p.lex.line;
                g_error_column = p.lex.column;
                return p.error;
            }

            if (g_error_code != OBJC_INTERP_OK) {
                return g_error_code;
            }

            /* Format the last expression result for REPL display */
            format_value(last, g_result_buffer, 512);
        }
    }

    objc_interp_gc_strings();

    return OBJC_INTERP_OK;
}

const char *objc_interp_get_nslog_output(void) {
    return g_nslog_buffer;
}

unsigned int objc_interp_get_nslog_length(void) {
    return g_nslog_offset;
}

const char *objc_interp_get_error(void) {
    return g_error_buffer;
}

int objc_interp_get_error_code(void) {
    return g_error_code;
}

const char *objc_interp_get_result(void) {
    return g_result_buffer;
}

void objc_interp_reset(void) {
    g_nslog_offset = 0;
    g_nslog_buffer[0] = '\0';
    g_error_code = OBJC_INTERP_OK;
    g_error_buffer[0] = '\0';
    g_error_line = 0;
    g_error_column = 0;
    g_result_buffer[0] = '\0';
    /* Don't reset g_var_count — variables persist across cells */
    /* Don't reset g_method_count — methods persist across cells */
}

/* ── Variable table accessors for tab completion ──────────────── */

unsigned int objc_interp_get_var_count(void) {
    return g_var_count;
}

const char *objc_interp_get_var_name(unsigned int index) {
    if (index >= g_var_count) return 0;
    return g_vars[index].name;
}

int objc_interp_get_var_is_class(unsigned int index) {
    if (index >= g_var_count) return 0;
    return g_vars[index].is_class;
}

unsigned int objc_interp_get_error_line(void) {
    return g_error_line;
}

unsigned int objc_interp_get_error_column(void) {
    return g_error_column;
}
