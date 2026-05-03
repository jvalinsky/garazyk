/*
 * objc_interpreter.c
 * Thin Objective-C interpreter for the Jupyter WASM kernel.
 *
 * Recursive-descent parser that evaluates ObjC source against the
 * real GNUstep libobjc2 runtime. See objc_interpreter.h for scope.
 */

#include "objc_interpreter.h"
#include "objc_interp_types.h"
#include "objc_interp_globals.h"
#include "objc_interp_parser.h"

/* We need the runtime headers for Class, SEL, id, etc. */
#include "runtime.h"
#include "slot.h"

#include <string.h>

/* Forward declarations for functions in extracted modules. */
extern Value parse_primary(struct Parser *p);
extern struct AstNode *parse_block_ast(struct Parser *p);

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

/* ── Forward declarations from objc_interp_format.c (nslog_append* only;
 * format_value and fmt_append* declared after Value typedef below) ── */
extern void nslog_append(const char *text, unsigned int len);
extern void nslog_append_char(char ch);
extern void nslog_append_int(int value);
extern void nslog_append_long(long value);
extern void objc_interp_gc_strings(void);

/* ── Centralized interpreter context ────────────────────────────── */

#include "objc_interp_context.h"
InterpContext g_ctx = {0};

/* ── NSLog ring buffer ──────────────────────────────────────────── */

char g_nslog_buffer[OBJC_INTERP_NSLOG_BUFFER_SIZE];
unsigned int g_nslog_offset = 0;

/* ── Interpreter state ──────────────────────────────────────────── */

void set_error_from_parser(struct Parser *p);

char g_result_buffer[512];


#define OBJC_INTERP_MAX_BLOCKS_CAPTURED 32

InterpVar g_vars[OBJC_INTERP_MAX_VARS];
unsigned int g_var_count = 0;
unsigned int g_var_scope_base = 0; /* base index for variable scoping during method execution */


/* ── Type definitions ───────────────────────────────────────────── */

TypeDef g_typedefs[64];
unsigned int g_typedef_count = 0;

/* Look up a typedef alias and return the base type, or the original name if not found. */
const char *typedef_resolve(const char *name) {
    if (!name) return 0;
    unsigned int i;
    for (i = 0; i < g_typedef_count; i++) {
        if (cstr_eq(g_typedefs[i].alias, name)) {
            return g_typedefs[i].base_type;
        }
    }
    return name;
}



static void lexer_init(Lexer *lex, const char *source, unsigned int length,
                        unsigned int line_offset) {
    lex->source = source;
    lex->source_len = length;
    lex->pos = 0;
    lex->token_start = 0;
    lex->line = 1;
    lex->column = 1;
    lex->lex_line_offset = line_offset;
    lex->current.type = TOK_EOF;
    lex->current.text[0] = '\0';
}

static char lexer_peek(Lexer *lex) {
    if (lex->pos >= lex->source_len) return '\0';
    return lex->source[lex->pos];
}

static char lexer_next(Lexer *lex) {
    char ch;
    if (lex->pos >= lex->source_len) return '\0';
    ch = lex->source[lex->pos];
    lex->pos++;
    if (ch == '\n') {
        lex->line++;
        lex->column = 1;
    } else {
        lex->column++;
    }
    return ch;
}

static int is_alpha(char ch) {
    return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_';
}

static int is_digit(char ch) {
    return ch >= '0' && ch <= '9';
}

static int is_alnum(char ch) {
    return is_alpha(ch) || is_digit(ch);
}

static void lexer_skip_whitespace_and_comments(Lexer *lex) {
    while (lex->pos < lex->source_len) {
        char ch = lexer_peek(lex);
        if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') {
            lexer_next(lex);
        } else if (ch == '/' && lex->pos + 1 < lex->source_len &&
                   lex->source[lex->pos + 1] == '/') {
            /* Single-line comment */
            while (lex->pos < lex->source_len && lexer_peek(lex) != '\n') {
                lexer_next(lex);
            }
        } else if (ch == '/' && lex->pos + 1 < lex->source_len &&
                   lex->source[lex->pos + 1] == '*') {
            /* Multi-line comment */
            lexer_next(lex); /* / */
            lexer_next(lex); /* * */
            while (lex->pos + 1 < lex->source_len) {
                if (lexer_peek(lex) == '*' && lex->source[lex->pos + 1] == '/') {
                    lexer_next(lex); /* * */
                    lexer_next(lex); /* / */
                    break;
                }
                lexer_next(lex);
            }
        } else {
            break;
        }
    }
}

static Token lexer_next_token(Lexer *lex) {
    Token tok;
    unsigned int i = 0;

    lexer_skip_whitespace_and_comments(lex);
    lex->token_start = lex->pos; /* remember where this token begins */
    tok.line = lex->line;
    tok.column = lex->column;
    tok.text[0] = '\0';
    tok.type = TOK_EOF;

    if (lex->pos >= lex->source_len) {
        tok.type = TOK_EOF;
        return tok;
    }

    char ch = lexer_peek(lex);

    /* @-keywords and @"string" */
    if (ch == '@') {
        lexer_next(lex);
        tok.text[0] = '@';
        tok.text[1] = '\0';
        i = 1;

        if (lexer_peek(lex) == '"') {
            /* @"string literal" */
            lexer_next(lex); /* skip opening " */
            while (lex->pos < lex->source_len && lexer_peek(lex) != '"') {
                char c = lexer_next(lex);
                if (c == '\\' && lex->pos < lex->source_len) {
                    c = lexer_next(lex);
                    if (c == 'n') c = '\n';
                    else if (c == 't') c = '\t';
                    else if (c == '\\') c = '\\';
                    else if (c == '"') c = '"';
                }
                if (i + 1 < OBJC_INTERP_MAX_TOKEN) {
                    tok.text[i++] = c;
                }
            }
            if (lex->pos < lex->source_len) lexer_next(lex); /* skip closing " */
            tok.text[i] = '\0';
            tok.type = TOK_STRING_LITERAL;
            return tok;
        }

        /* @keyword: @interface, @implementation, @end, @class, @protocol */
        while (lex->pos < lex->source_len && is_alpha(lexer_peek(lex))) {
            if (i + 1 < OBJC_INTERP_MAX_TOKEN) {
                tok.text[i++] = lexer_next(lex);
            } else {
                lexer_next(lex);
            }
        }
        tok.text[i] = '\0';
        tok.type = TOK_AT_KEYWORD;
        return tok;
    }

    /* String literal (C string, not ObjC) */
    if (ch == '"') {
        lexer_next(lex);
        i = 0;
        while (lex->pos < lex->source_len && lexer_peek(lex) != '"') {
            char c = lexer_next(lex);
            if (c == '\\' && lex->pos < lex->source_len) {
                c = lexer_next(lex);
                if (c == 'n') c = '\n';
                else if (c == 't') c = '\t';
                else if (c == '\\') c = '\\';
                else if (c == '"') c = '"';
            }
            if (i + 1 < OBJC_INTERP_MAX_TOKEN) {
                tok.text[i++] = c;
            }
        }
        if (lex->pos < lex->source_len) lexer_next(lex); /* skip closing " */
        tok.text[i] = '\0';
        tok.type = TOK_STRING_LITERAL;
        return tok;
    }

    /* Identifier or keyword */
    if (is_alpha(ch)) {
        while (lex->pos < lex->source_len && is_alnum(lexer_peek(lex))) {
            if (i + 1 < OBJC_INTERP_MAX_TOKEN) {
                tok.text[i++] = lexer_next(lex);
            } else {
                lexer_next(lex);
            }
        }
        tok.text[i] = '\0';
        tok.type = TOK_IDENTIFIER;
        /* Check for reserved keywords */
        if (cstr_eq(tok.text, "return")) {
            tok.type = TOK_RETURN;
        } else if (cstr_eq(tok.text, "if")) {
            tok.type = TOK_IF;
        } else if (cstr_eq(tok.text, "else")) {
            tok.type = TOK_ELSE;
        } else if (cstr_eq(tok.text, "while")) {
            tok.type = TOK_WHILE;
        } else if (cstr_eq(tok.text, "for")) {
            tok.type = TOK_FOR;
        } else if (cstr_eq(tok.text, "do")) {
            tok.type = TOK_DO;
        } else if (cstr_eq(tok.text, "break")) {
            tok.type = TOK_BREAK;
        } else if (cstr_eq(tok.text, "continue")) {
            tok.type = TOK_CONTINUE;
        } else if (cstr_eq(tok.text, "in")) {
            tok.type = TOK_IN;
        } else if (cstr_eq(tok.text, "switch")) {
            tok.type = TOK_SWITCH;
        } else if (cstr_eq(tok.text, "case")) {
            tok.type = TOK_CASE;
        } else if (cstr_eq(tok.text, "default")) {
            tok.type = TOK_DEFAULT;
        } else if (cstr_eq(tok.text, "YES") || cstr_eq(tok.text, "TRUE")) {
            /* Boolean true → integer 1 */
            tok.text[0] = '1'; tok.text[1] = '\0';
            tok.type = TOK_INT_LITERAL;
        } else if (cstr_eq(tok.text, "NO") || cstr_eq(tok.text, "FALSE")) {
            /* Boolean false → integer 0 */
            tok.text[0] = '0'; tok.text[1] = '\0';
            tok.type = TOK_INT_LITERAL;
        }
        return tok;
    }

    /* Integer / float literal */
    if (is_digit(ch)) {
        while (lex->pos < lex->source_len && is_digit(lexer_peek(lex))) {
            if (i + 1 < OBJC_INTERP_MAX_TOKEN) {
                tok.text[i++] = lexer_next(lex);
            } else {
                lexer_next(lex);
            }
        }
        /* Check for decimal point → float literal */
        if (lex->pos < lex->source_len && lexer_peek(lex) == '.') {
            if (i + 1 < OBJC_INTERP_MAX_TOKEN) {
                tok.text[i++] = lexer_next(lex); /* consume . */
            } else {
                lexer_next(lex);
            }
            while (lex->pos < lex->source_len && is_digit(lexer_peek(lex))) {
                if (i + 1 < OBJC_INTERP_MAX_TOKEN) {
                    tok.text[i++] = lexer_next(lex);
                } else {
                    lexer_next(lex);
                }
            }
            tok.text[i] = '\0';
            tok.type = TOK_FLOAT_LITERAL;
            return tok;
        }
        tok.text[i] = '\0';
        tok.type = TOK_INT_LITERAL;
        return tok;
    }

    /* Two-character operators */
    lexer_next(lex);
    tok.text[0] = ch;
    tok.text[1] = '\0';

    if (lex->pos < lex->source_len) {
        char next = lexer_peek(lex);
        if (ch == '=' && next == '=') {
            lexer_next(lex);
            tok.text[0] = '='; tok.text[1] = '='; tok.text[2] = '\0';
            tok.type = TOK_EQ;
            return tok;
        }
        if (ch == '!' && next == '=') {
            lexer_next(lex);
            tok.text[0] = '!'; tok.text[1] = '='; tok.text[2] = '\0';
            tok.type = TOK_NEQ;
            return tok;
        }
        if (ch == '&' && next == '&') {
            lexer_next(lex);
            tok.text[0] = '&'; tok.text[1] = '&'; tok.text[2] = '\0';
            tok.type = TOK_AND;
            return tok;
        }
        if (ch == '|' && next == '|') {
            lexer_next(lex);
            tok.text[0] = '|'; tok.text[1] = '|'; tok.text[2] = '\0';
            tok.type = TOK_OR;
            return tok;
        }
        if (ch == '+' && next == '+') {
            lexer_next(lex);
            tok.text[0] = '+'; tok.text[1] = '+'; tok.text[2] = '\0';
            tok.type = TOK_PLUS_PLUS;
            return tok;
        }
        if (ch == '-' && next == '-') {
            lexer_next(lex);
            tok.text[0] = '-'; tok.text[1] = '-'; tok.text[2] = '\0';
            tok.type = TOK_MINUS_MINUS;
            return tok;
        }
        if (ch == '<' && next == '=') {
            lexer_next(lex);
            tok.text[0] = '<'; tok.text[1] = '='; tok.text[2] = '\0';
            tok.type = TOK_LE;
            return tok;
        }
        if (ch == '>' && next == '=') {
            lexer_next(lex);
            tok.text[0] = '>'; tok.text[1] = '='; tok.text[2] = '\0';
            tok.type = TOK_GE;
            return tok;
        }
        if (ch == '+' && next == '=') {
            lexer_next(lex);
            tok.text[0] = '+'; tok.text[1] = '='; tok.text[2] = '\0';
            tok.type = TOK_PLUS_ASSIGN;
            return tok;
        }
        if (ch == '-' && next == '=') {
            lexer_next(lex);
            tok.text[0] = '-'; tok.text[1] = '='; tok.text[2] = '\0';
            tok.type = TOK_MINUS_ASSIGN;
            return tok;
        }
        if (ch == '-' && next == '>') {
            lexer_next(lex);
            tok.text[0] = '-'; tok.text[1] = '>'; tok.text[2] = '\0';
            tok.type = TOK_ARROW;
            return tok;
        }
        if (ch == '*' && next == '=') {
            lexer_next(lex);
            tok.text[0] = '*'; tok.text[1] = '='; tok.text[2] = '\0';
            tok.type = TOK_STAR_ASSIGN;
            return tok;
        }
        if (ch == '/' && next == '=') {
            lexer_next(lex);
            tok.text[0] = '/'; tok.text[1] = '='; tok.text[2] = '\0';
            tok.type = TOK_SLASH_ASSIGN;
            return tok;
        }
        if (ch == '%' && next == '=') {
            lexer_next(lex);
            tok.text[0] = '%'; tok.text[1] = '='; tok.text[2] = '\0';
            tok.type = TOK_PERCENT_ASSIGN;
            return tok;
        }
    }

    /* Single-character tokens */
    switch (ch) {
        case '[': tok.type = TOK_OPEN_BRACKET; break;
        case ']': tok.type = TOK_CLOSE_BRACKET; break;
        case '{': tok.type = TOK_OPEN_BRACE; break;
        case '}': tok.type = TOK_CLOSE_BRACE; break;
        case '(': tok.type = TOK_OPEN_PAREN; break;
        case ')': tok.type = TOK_CLOSE_PAREN; break;
        case ';': tok.type = TOK_SEMICOLON; break;
        case ':': tok.type = TOK_COLON; break;
        case ',': tok.type = TOK_COMMA; break;
        case '.': tok.type = TOK_DOT; break;
        case '*': tok.type = TOK_STAR; break;
        case '&': tok.type = TOK_AMPERSAND; break;
        case '=': tok.type = TOK_ASSIGN; break;
        case '+': tok.type = TOK_PLUS; break;
        case '-': tok.type = TOK_MINUS; break;
        case '/': tok.type = TOK_SLASH; break;
        case '%': tok.type = TOK_PERCENT; break;
        case '<': tok.type = TOK_LT; break;
        case '>': tok.type = TOK_GT; break;
        case '!': tok.type = TOK_NOT; break;
        case '?': tok.type = TOK_QUESTION; break;
        case '^': tok.type = TOK_CARET; break;
        case '|': tok.type = TOK_UNKNOWN; break; /* || handled above, bare | not supported */
        default: tok.type = TOK_UNKNOWN; break;
    }

    return tok;
}


void set_error_from_parser(Parser *p) {
    g_ctx.error_code = p->error;
    cstr_copy(g_ctx.error_buffer, p->error_msg, OBJC_INTERP_ERROR_SIZE);
    g_ctx.error_line = p->lex.line + p->lex.lex_line_offset;
    g_ctx.error_column = p->lex.column;
}

void parser_init(Parser *p, const char *source, unsigned int length,
                        unsigned int line_offset) {
    lexer_init(&p->lex, source, length, line_offset);
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
            unsigned int line = p->lex.line + p->lex.lex_line_offset;
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
/* Copy identifier with truncation error check. Returns 0 on success, 1 if truncated. */
int copy_identifier_or_error(Parser *p, char *dst, const char *src,
                             unsigned int capacity, const char *kind) {
    unsigned int ci = 0;
    if (dst == 0 || src == 0 || capacity == 0) return 0;
    while (src[ci] != '\0' && ci + 1 < capacity) { dst[ci] = src[ci]; ci++; }
    dst[ci] = '\0';
    if (src[ci] == '\0') return 0; /* no truncation */
    {
        char buf[OBJC_INTERP_ERROR_SIZE];
        unsigned int pos = 0;
        const char *prefix = kind ? kind : "identifier";
        unsigned int pi = 0;
        unsigned int max_chars = capacity > 0 ? capacity - 1 : 0;
        while (prefix[pi] != '\0' && pos < sizeof(buf) - 1) buf[pos++] = prefix[pi++];
        { const char *s = " name too long (max "; pi = 0; while (s[pi] != '\0' && pos < sizeof(buf) - 1) buf[pos++] = s[pi++]; }
        { unsigned int n = max_chars; char digits[10]; int dcount = 0; if (n == 0) digits[dcount++] = '0'; while (n > 0 && dcount < 10) { digits[dcount++] = '0' + (n % 10); n /= 10; } while (dcount > 0 && pos < sizeof(buf) - 1) buf[pos++] = digits[--dcount]; }
        { const char *s = "): '"; pi = 0; while (s[pi] != '\0' && pos < sizeof(buf) - 1) buf[pos++] = s[pi++]; }
        pi = 0; while (dst[pi] != '\0' && pos < sizeof(buf) - 5) buf[pos++] = dst[pi++];
        if (pos < sizeof(buf) - 5) { buf[pos++] = '.'; buf[pos++] = '.'; buf[pos++] = '.'; buf[pos++] = '\''; }
        buf[pos] = '\0';
        parser_error(p, buf);
    }
    return 1;
}

/* ── Variable table ─────────────────────────────────────────────── */

InterpVar *interp_find_var(const char *name) {
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

InterpVar *interp_create_var(const char *name) {
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
    g_var_count++;
    return &g_vars[g_var_count - 1];
}

InterpVar *interp_get_or_create_var(const char *name) {
    InterpVar *v = interp_find_var(name);
    if (v) return v;
    return interp_create_var(name);
}

/* ── NSLog implementation ────────────────────────────────────────── */
/* nslog_append, nslog_append_char, nslog_append_int, nslog_append_long
 * are defined in objc_interp_format.c */


/* ── Forward declarations from objc_interp_format.c (depend on Value) ── */
extern void fmt_append_char(char *buf, unsigned int capacity, unsigned int *offset, char ch);
extern void fmt_append_str(char *buf, unsigned int capacity, unsigned int *offset, const char *str);
extern void fmt_append_uint(char *buf, unsigned int capacity, unsigned int *offset, unsigned int val);
extern void fmt_append_hex(char *buf, unsigned int capacity, unsigned int *offset, unsigned long ptr);
extern void format_value(Value v, char *buf, unsigned int capacity);

/* ── Method dispatch state ─────────────────────────────────────── */

/* Return value flag — set by return statement, checked by method dispatch */
int g_return_pending = 0;
Value g_return_value;

/* String pool for string literals and Foundation object encoding.
 * Shared between parse_primary (string literals) and parse_message_send
 * (Foundation stubs like NSNumber, stringByAppendingString). */
#define OBJC_INTERP_STRING_POOL_SIZE 65536
char g_string_pool[OBJC_INTERP_STRING_POOL_SIZE];
unsigned int g_string_pool_offset = 0;
unsigned int g_parse_depth = 0;

#define MAX_STRING_POOL_MARKS 4096

#define MAX_PARSE_DEPTH 64

/* Allocate `size` bytes from the string pool.
 * Returns pointer to the start of the allocation, or 0 if the pool is full.
 * The pool is append-only — strings persist for the lifetime of the kernel.
 * This is safe because the interpreter never frees string pool entries. */


#define MAX_METHODS 64
MethodImpl g_methods[MAX_METHODS];
unsigned int g_method_count = 0;


PropertyDecl g_properties[64];
unsigned int g_property_count = 0;


#define MAX_INSTANCE_VARS 256
InstanceVar g_instance_vars[MAX_INSTANCE_VARS];
unsigned int g_instance_var_count = 0;


#define MAX_COLLECTIONS 64
#define MAX_COLL_ENTRIES 512

unsigned int g_next_coll_id = 1;
CollEntry g_coll_entries[MAX_COLL_ENTRIES];
unsigned int g_coll_entry_count = 0;

/* Count entries for a given collection ID. */

/* Add an entry to a collection. Returns 0 on success, -1 if table full. */

/* Find an entry in a collection by key (for dicts/sets). Returns index or -1. */

/* Remove an entry at index. */

/* Remove all entries for a collection ID. */

/* Insert an entry at a logical position within a collection.
 * Shifts existing entries at that position and later to make room.
 * Returns 0 on success, -1 if table full or position invalid. */
int coll_insert_at(unsigned int coll_id, unsigned int pos, Value key, Value value);

/* Get the Nth entry for a collection (for array indexing). Returns index or -1. */

/* Parse a collection ID from a marker string like "NSDict:5" or "NSMutArr:12".
 * Returns the ID, or 0 if not a valid collection marker. */

/* Create a collection marker string in the string pool. */


#define MAX_BLOCKS 32
BlockImpl g_blocks[MAX_BLOCKS];
unsigned int g_block_count = 0;
unsigned int g_next_block_id = 1;

/* Look up a block by its ID. Returns pointer or 0. */

/* Parse a block ID from a marker string like "NSBlock:5". */

/* Create a block marker string in the string pool. */

/* Look up an instance variable in the side table.
 * Returns pointer to the value (mutable), or 0 if not found. */

/* Store an instance variable in the side table.
 * Overwrites existing entry for (object, prop_name), or adds new. */

/* Check if a property belongs to the receiver's class.
 * For FDObj: markers, extracts the class name and compares against
 * g_properties[pi].class_name. For non-FDObj: receivers (Foundation
 * objects), returns 1 (always match) since Foundation classes don't
 * have user-defined properties. */

/* Check if a variable name is a synthesized ivar name.
 * Returns the property index if found, or -1 if not.
 * This is used to redirect ivar access in method bodies to the side table. */

/* Read a synthesized ivar value from the side table.
 * Returns the value, or value_void() if not found. */

/* Write a synthesized ivar value to the side table. */

/* ── AST nodes for control flow ──────────────────────────────────── */


#define MAX_AST_NODES 1024
AstNode g_ast_arena[MAX_AST_NODES];
unsigned int g_ast_count = 0;

/* Break/continue flags — checked by loop evaluation */
int g_break_pending = 0;
int g_continue_pending = 0;

/* ── Forward declarations ───────────────────────────────────────── */

Value parse_expression(Parser *p);
Value parse_statement(Parser *p);
Value parse_block(Parser *p);
int is_truthy(Value v);
AstNode *parse_statement_ast(Parser *p);
Value eval_source_range(unsigned int start, unsigned int len, const char *source,
                               unsigned int line_offset);
Value eval_ast(AstNode *node, const char *source);
Value parse_type_and_var_decl(Parser *p);

/* ── NSLog format string evaluation ─────────────────────────────── */

/* Evaluate NSLog with format string and arguments.
 * We've already consumed the NSLog identifier and opening paren.
 * The first argument is the format string (@"...").
 * Subsequent arguments are matched to %@, %d, %ld, %f, %% specifiers.
 */

/* ── Message send evaluation ────────────────────────────────────── */

/* Parse a message send: [target selector:arg1 key2:arg2 ...]
 * We've already consumed the [.
 */

/* ── @interface / @implementation ────────────────────────────────── */

/* Parse @interface Name : SuperClass { ivars } methodDecls @end */

/* Method implementation function — called by objc_msgSend */
static id method_impl_trampoline(id self, SEL _cmd, ...) {
    const char *sel_name = sel_getName(_cmd);
    unsigned int i;

    /* Find the MethodImpl for this selector */
    for (i = 0; i < g_method_count; i++) {
        if (g_methods[i].selector == _cmd && g_methods[i].source_len > 0) {
            break;
        }
    }

    if (i >= g_method_count || g_methods[i].source_len == 0) {
        /* No stored body — return self as default */
        return self;
    }

    /* Save current variable count so we can clean up method-local vars */
    unsigned int saved_var_count = g_var_count;

    /* Set up self and _cmd as interpreter variables */
    {
        InterpVar *var;

        var = interp_get_or_create_var("self");
        if (var) {
            var->is_id = 1;
            var->value = self;
            var->is_int = 0;
            var->is_class = 0;
            var->is_sel = 0;
        }

        var = interp_get_or_create_var("_cmd");
        if (var) {
            var->is_sel = 1;
            var->sel = _cmd;
            var->is_int = 0;
            var->is_class = 0;
            var->is_id = 0;
        }
    }

    /* Set up keyword argument variables from the variadic args.
     * The IMP signature is id(id, SEL, ...) — keyword args follow
     * self and _cmd on the stack. We access them via va_list. */
    {
        /* Count colons in selector to determine arg count */
        unsigned int sel_colons = 0;
        unsigned int si;
        for (si = 0; sel_name[si] != '\0'; si++) {
            if (sel_name[si] == ':') sel_colons++;
        }

        if (sel_colons > 0 && g_methods[i].arg_count > 0) {
            /* Access variadic arguments */
            __builtin_va_list ap;
            __builtin_va_start(ap, _cmd);

            unsigned int ai;
            for (ai = 0; ai < sel_colons && ai < g_methods[i].arg_count && ai < 8; ai++) {
                id arg_val = __builtin_va_arg(ap, id);
                InterpVar *var = interp_get_or_create_var(g_methods[i].arg_names[ai]);
                if (var) {
                    var->is_id = 1;
                    var->value = arg_val;
                    var->is_int = 0;
                    var->is_class = 0;
                    var->is_sel = 0;
                }
            }

            __builtin_va_end(ap);
        }
    }

    /* Execute the method body */
    g_return_pending = 0;
    {
        Value v = eval_source_range(0, g_methods[i].source_len, g_methods[i].source, 0);
        (void)v; /* errors are captured in g_ctx.error_buffer */
    }

    /* Determine return value */
    {
        id return_val;

        if (g_return_pending) {
            /* Explicit return statement */
            if (g_return_value.is_id) return_val = g_return_value.obj_val;
            else if (g_return_value.is_class) return_val = (id)g_return_value.cls_val;
            else if (g_return_value.is_int) return_val = (id)(long)g_return_value.int_val;
            else return_val = self;
        } else {
            /* No explicit return — default to self */
            return_val = self;
        }

        /* Clean up method-local variables (remove any added after saved count) */
        g_var_count = saved_var_count;
        g_return_pending = 0;

        return return_val;
    }
}

/* Parse @implementation Name methodDefs @end */

/* ── Expression parser ──────────────────────────────────────────── */

static Value parse_multiplicative(Parser *p) {
    Value left = parse_primary(p);
    if (p->error) return left;

    while (parser_current(p).type == TOK_STAR ||
           parser_current(p).type == TOK_SLASH ||
           parser_current(p).type == TOK_PERCENT) {
        TokenType op = parser_current(p).type;
        parser_advance(p);
        {
            Value right = parse_primary(p);
            if (p->error) return right;
            if (left.is_int && right.is_int) {
                if (op == TOK_STAR) left.int_val *= right.int_val;
                else if (op == TOK_SLASH && right.int_val != 0) left.int_val /= right.int_val;
                else if (op == TOK_PERCENT && right.int_val != 0) left.int_val %= right.int_val;
            } else if ((left.is_float || left.is_int) && (right.is_float || right.is_int)) {
                /* Promote to float arithmetic */
                double lv = left.is_float ? left.float_val : (double)left.int_val;
                double rv = right.is_float ? right.float_val : (double)right.int_val;
                if (op == TOK_STAR) { left.float_val = lv * rv; left.is_float = 1; left.is_int = 0; }
                else if (op == TOK_SLASH && rv != 0.0) { left.float_val = lv / rv; left.is_float = 1; left.is_int = 0; }
                /* % not supported for floats — skip */
            }
        }
    }

    return left;
}

static Value parse_additive(Parser *p) {
    Value left = parse_multiplicative(p);
    if (p->error) return left;

    while (parser_current(p).type == TOK_PLUS ||
           parser_current(p).type == TOK_MINUS) {
        TokenType op = parser_current(p).type;
        parser_advance(p);
        {
            Value right = parse_multiplicative(p);
            if (p->error) return right;
            if (left.is_int && right.is_int) {
                if (op == TOK_PLUS) left.int_val += right.int_val;
                else if (op == TOK_MINUS) left.int_val -= right.int_val;
            } else if ((left.is_float || left.is_int) && (right.is_float || right.is_int)) {
                /* Promote to float arithmetic */
                double lv = left.is_float ? left.float_val : (double)left.int_val;
                double rv = right.is_float ? right.float_val : (double)right.int_val;
                if (op == TOK_PLUS) { left.float_val = lv + rv; left.is_float = 1; left.is_int = 0; }
                else if (op == TOK_MINUS) { left.float_val = lv - rv; left.is_float = 1; left.is_int = 0; }
            }
        }
    }

    return left;
}

static Value parse_comparison(Parser *p) {
    Value left = parse_additive(p);
    if (p->error) return left;

    while (parser_current(p).type == TOK_LT ||
           parser_current(p).type == TOK_GT ||
           parser_current(p).type == TOK_LE ||
           parser_current(p).type == TOK_GE ||
           parser_current(p).type == TOK_EQ ||
           parser_current(p).type == TOK_NEQ) {
        TokenType op = parser_current(p).type;
        parser_advance(p);
        {
            Value right = parse_additive(p);
            if (p->error) return right;
            if (left.is_int && right.is_int) {
                int result = 0;
                if (op == TOK_LT) result = left.int_val < right.int_val;
                else if (op == TOK_GT) result = left.int_val > right.int_val;
                else if (op == TOK_LE) result = left.int_val <= right.int_val;
                else if (op == TOK_GE) result = left.int_val >= right.int_val;
                else if (op == TOK_EQ) result = left.int_val == right.int_val;
                else if (op == TOK_NEQ) result = left.int_val != right.int_val;
                left = value_from_int(result);
            } else if ((left.is_float || left.is_int) && (right.is_float || right.is_int)) {
                double lv = left.is_float ? left.float_val : (double)left.int_val;
                double rv = right.is_float ? right.float_val : (double)right.int_val;
                int result = 0;
                if (op == TOK_LT) result = lv < rv;
                else if (op == TOK_GT) result = lv > rv;
                else if (op == TOK_LE) result = lv <= rv;
                else if (op == TOK_GE) result = lv >= rv;
                else if (op == TOK_EQ) result = lv == rv;
                else if (op == TOK_NEQ) result = lv != rv;
                left = value_from_int(result);
            }
        }
    }

    return left;
}

/* ── Truthiness helper ──────────────────────────────────────────── */

/* ── Logical operators ───────────────────────────────────────────── */

static Value parse_logical_and(Parser *p) {
    Value left = parse_comparison(p);
    if (p->error) return left;

    while (parser_current(p).type == TOK_AND) {
        parser_advance(p);
        {
            Value right = parse_comparison(p);
            if (p->error) return right;
            left = value_from_int(is_truthy(left) && is_truthy(right) ? 1 : 0);
        }
    }

    return left;
}

static Value parse_logical_or(Parser *p) {
    Value left = parse_logical_and(p);
    if (p->error) return left;

    while (parser_current(p).type == TOK_OR) {
        parser_advance(p);
        {
            Value right = parse_logical_and(p);
            if (p->error) return right;
            left = value_from_int(is_truthy(left) || is_truthy(right) ? 1 : 0);
        }
    }

    return left;
}

/* Ternary conditional: cond ? true_expr : false_expr
 * Right-associative, lowest precedence above assignment. */
static Value parse_ternary(Parser *p) {
    Value cond = parse_logical_or(p);
    if (p->error) return cond;

    if (parser_current(p).type == TOK_QUESTION) {
        parser_advance(p);
        {
            Value true_val = parse_ternary(p); /* right-associative */
            if (p->error) return true_val;
            if (parser_current(p).type != TOK_COLON) {
                p->error = 1;
                cstr_copy(g_ctx.error_buffer, "expected ':' in ternary expression", OBJC_INTERP_ERROR_SIZE);
                return cond;
            }
            parser_advance(p); /* skip : */
            {
                Value false_val = parse_ternary(p); /* right-associative */
                if (p->error) return false_val;
                return is_truthy(cond) ? true_val : false_val;
            }
        }
    }

    return cond;
}

static Value parse_assignment(Parser *p) {
    Value target = parse_ternary(p);
    if (p->error) return target;

    if (parser_current(p).type == TOK_ASSIGN) {
        parser_advance(p);
        {
            Value value = parse_assignment(p);
            if (p->error) return value;
            /* Assignment to variable */
            return value;
        }
    }

    return target;
}

/* ── Statement parser ───────────────────────────────────────────── */

/* ── Block parser ───────────────────────────────────────────────── */

/* ── AST-based statement parser (for control flow) ─────────────── */

/* Parse a block of statements into AST nodes.
 * Returns an AST_BLOCK node containing all children. */

/* Parse a single statement into an AST node.
 * Control flow (if/while/for) → true AST nodes
 * Everything else → source range nodes (re-parsed on evaluation) */

/* ── AST evaluation ─────────────────────────────────────────────── */

/* Count newlines in source[0..pos) to compute line offset for error reporting. */
static unsigned int count_lines_up_to(const char *source, unsigned int pos) {
    unsigned int lines = 0;
    unsigned int i;
    for (i = 0; i < pos; i++) {
        if (source[i] == '\n') lines++;
    }
    return lines;
}

/* Evaluate a source range by re-parsing it.
 * This creates a temporary parser over the source substring.
 * line_offset is added to the lexer's line number for error reporting. */

/* Evaluate an AST node. source is the original full source string. */

/* ── Value formatting for REPL display ─────────────────────────── */
/* fmt_append_char, fmt_append_str, fmt_append_uint, fmt_append_hex,
 * format_value, and objc_interp_gc_strings are defined in objc_interp_format.c */

void objc_interp_init(void) {
    g_nslog_offset = 0;
    g_nslog_buffer[0] = '\0';
    g_ctx.error_code = OBJC_INTERP_OK;
    g_ctx.error_buffer[0] = '\0';
    g_ctx.error_line = 0;
    g_ctx.error_column = 0;
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
    g_ctx.interp_initialized = 1;
}

int objc_interp(const char *source, unsigned int length) {
    Parser p;

    /* Reset per-execution state */
    g_nslog_offset = 0;
    g_nslog_buffer[0] = '\0';
    g_ctx.error_code = OBJC_INTERP_OK;
    g_ctx.error_buffer[0] = '\0';
    g_ctx.error_line = 0;
    g_ctx.error_column = 0;
    g_result_buffer[0] = '\0';
    g_return_pending = 0;
    g_break_pending = 0;
    g_continue_pending = 0;
    g_ast_count = 0;
    g_parse_depth = 0;

    /* Don't reset variable table — it persists across cells */

    parser_init(&p, source, length, 0);

    /* Two-phase execution: parse into AST, then evaluate.
     * This enables control flow (if/while/for) to re-evaluate
     * conditions and loop bodies. */
    {
        AstNode *root = parse_block_ast(&p);

        if (p.error) {
            if (cstr_eq(p.error_msg, "Execution interrupted")) {
                g_ctx.error_code = OBJC_INTERP_INTERRUPTED;
            } else {
                g_ctx.error_code = p.error;
            }
            cstr_copy(g_ctx.error_buffer, p.error_msg, OBJC_INTERP_ERROR_SIZE);
            g_ctx.error_line = p.lex.line;
            g_ctx.error_column = p.lex.column;
            return p.error;
        }

        if (!root) {
            g_ctx.error_code = OBJC_INTERP_MEMORY_ERROR;
            cstr_copy(g_ctx.error_buffer, "AST allocation failed", OBJC_INTERP_ERROR_SIZE);
            return OBJC_INTERP_MEMORY_ERROR;
        }

        /* Evaluate the AST */
        {
            Value last = eval_ast(root, source);

            if (p.error) {
                if (cstr_eq(p.error_msg, "Execution interrupted")) {
                    g_ctx.error_code = OBJC_INTERP_INTERRUPTED;
                } else {
                    g_ctx.error_code = p.error;
                }
                cstr_copy(g_ctx.error_buffer, p.error_msg, OBJC_INTERP_ERROR_SIZE);
                g_ctx.error_line = p.lex.line;
                g_ctx.error_column = p.lex.column;
                return p.error;
            }

            if (g_ctx.error_code != OBJC_INTERP_OK) {
                return g_ctx.error_code;
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
    return g_ctx.error_buffer;
}

int objc_interp_get_error_code(void) {
    return g_ctx.error_code;
}

const char *objc_interp_get_result(void) {
    return g_result_buffer;
}

void objc_interp_reset(void) {
    g_nslog_offset = 0;
    g_nslog_buffer[0] = '\0';
    g_ctx.error_code = OBJC_INTERP_OK;
    g_ctx.error_buffer[0] = '\0';
    g_ctx.error_line = 0;
    g_ctx.error_column = 0;
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
    return g_ctx.error_line;
}

unsigned int objc_interp_get_error_column(void) {
    return g_ctx.error_column;
}
