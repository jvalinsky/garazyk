/*
 * objc_interpreter.c
 * Thin Objective-C interpreter for the Jupyter WASM kernel.
 *
 * Recursive-descent parser that evaluates ObjC source against the
 * real GNUstep libobjc2 runtime. See objc_interpreter.h for scope.
 */

#include "objc_interpreter.h"

/* We need the runtime headers for Class, SEL, id, etc. */
#include "runtime.h"
#include "slot.h"

#include <string.h>

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

/* ── String helpers (freestanding, no libc) ─────────────────────── */

static unsigned int cstr_len(const char *s) {
    unsigned int n = 0;
    if (s == 0) return 0;
    while (s[n] != '\0') n++;
    return n;
}

static int cstr_eq(const char *a, const char *b) {
    unsigned int i = 0;
    if (a == 0 || b == 0) return a == b;
    while (a[i] != '\0' && b[i] != '\0') {
        if (a[i] != b[i]) return 0;
        i++;
    }
    return a[i] == b[i];
}

static int cstr_eq_n(const char *a, const char *b, unsigned int n) {
    unsigned int i = 0;
    if (a == 0 || b == 0) return 0;
    while (i < n && a[i] != '\0' && b[i] != '\0') {
        if (a[i] != b[i]) return 0;
        i++;
    }
    return i == n;
}

static int cstr_starts(const char *s, const char *prefix) {
    unsigned int i = 0;
    if (s == 0 || prefix == 0) return 0;
    while (prefix[i] != '\0') {
        if (s[i] != prefix[i]) return 0;
        i++;
    }
    return 1;
}

static void cstr_copy(char *dst, const char *src, unsigned int capacity) {
    unsigned int i = 0;
    if (dst == 0 || src == 0) return;
    while (src[i] != '\0' && i + 1 < capacity) {
        dst[i] = src[i];
        i++;
    }
    dst[i] = '\0';
}

/* ── NSLog ring buffer ──────────────────────────────────────────── */

static char g_nslog_buffer[OBJC_INTERP_NSLOG_BUFFER_SIZE];
static unsigned int g_nslog_offset = 0;

/* ── Interpreter state ──────────────────────────────────────────── */

static char g_error_buffer[OBJC_INTERP_ERROR_SIZE];
static int g_error_code = OBJC_INTERP_OK;
static char g_result_buffer[512];

static int interp_should_interrupt(void) {
    return objc_kernel_host_should_interrupt() != 0;
}

static void interp_emit_stream(const char *ptr, unsigned int len) {
    if (ptr == 0 || len == 0u) {
        return;
    }
    objc_kernel_host_stream(1, ptr, len);
}

/* Variable table: name → value (as id) */
typedef struct {
    char name[64];
    id value;
    Class cls;      /* if this is a Class-typed variable */
    SEL sel;        /* if this is a SEL-typed variable */
    int is_int;
    int int_value;
    int is_class;   /* 1 if this holds a Class */
    int is_sel;     /* 1 if this holds a SEL */
    int is_id;      /* 1 if this holds an id */
} InterpVar;

static InterpVar g_vars[OBJC_INTERP_MAX_VARS];
static unsigned int g_var_count = 0;
static unsigned int g_var_scope_base = 0; /* base index for variable scoping during method execution */

/* ── Token types ────────────────────────────────────────────────── */

typedef enum {
    TOK_EOF = 0,
    TOK_IDENTIFIER,
    TOK_AT_KEYWORD,     /* @interface, @implementation, @end, @\"string\" */
    TOK_STRING_LITERAL, /* @\"...\" or \"...\" */
    TOK_INT_LITERAL,
    TOK_OPEN_BRACKET,   /* [ */
    TOK_CLOSE_BRACKET,  /* ] */
    TOK_OPEN_BRACE,     /* { */
    TOK_CLOSE_BRACE,    /* } */
    TOK_OPEN_PAREN,     /* ( */
    TOK_CLOSE_PAREN,    /* ) */
    TOK_SEMICOLON,      /* ; */
    TOK_COLON,          /* : */
    TOK_COMMA,          /* , */
    TOK_DOT,            /* . */
    TOK_ARROW,          /* -> */
    TOK_STAR,           /* * */
    TOK_AMPERSAND,      /* & */
    TOK_ASSIGN,         /* = */
    TOK_EQ,             /* == */
    TOK_NEQ,            /* != */
    TOK_PLUS,           /* + */
    TOK_MINUS,          /* - */
    TOK_SLASH,          /* / */
    TOK_PERCENT,        /* % */
    TOK_LT,            /* < */
    TOK_GT,            /* > */
    TOK_LE,            /* <= */
    TOK_GE,            /* >= */
    TOK_PLUS_ASSIGN,   /* += */
    TOK_MINUS_ASSIGN,  /* -= */
    TOK_STAR_ASSIGN,   /* *= */
    TOK_SLASH_ASSIGN,  /* /= */
    TOK_PERCENT_ASSIGN,/* %= */
    TOK_QUESTION,      /* ? (ternary) */
    TOK_RETURN,        /* return keyword */
    TOK_IF,            /* if keyword */
    TOK_ELSE,          /* else keyword */
    TOK_WHILE,         /* while keyword */
    TOK_FOR,           /* for keyword */
    TOK_DO,            /* do keyword */
    TOK_BREAK,         /* break keyword */
    TOK_CONTINUE,     /* continue keyword */
    TOK_IN,            /* in keyword (for-in) */
    TOK_AND,           /* && */
    TOK_OR,            /* || */
    TOK_NOT,           /* ! (logical not) */
    TOK_PLUS_PLUS,     /* ++ */
    TOK_MINUS_MINUS,   /* -- */
    TOK_CARET,         /* ^ (block literal) */
    TOK_UNKNOWN
} TokenType;

typedef struct {
    TokenType type;
    char text[OBJC_INTERP_MAX_TOKEN];
    unsigned int line;
    unsigned int column;
} Token;

/* ── Lexer ──────────────────────────────────────────────────────── */

typedef struct {
    const char *source;
    unsigned int source_len;
    unsigned int pos;       /* position after current token */
    unsigned int token_start; /* position where current token began */
    unsigned int line;
    unsigned int column;
    Token current;
} Lexer;

static void lexer_init(Lexer *lex, const char *source, unsigned int length) {
    lex->source = source;
    lex->source_len = length;
    lex->pos = 0;
    lex->token_start = 0;
    lex->line = 1;
    lex->column = 1;
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

    /* Integer literal */
    if (is_digit(ch)) {
        while (lex->pos < lex->source_len && is_digit(lexer_peek(lex))) {
            if (i + 1 < OBJC_INTERP_MAX_TOKEN) {
                tok.text[i++] = lexer_next(lex);
            } else {
                lexer_next(lex);
            }
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

/* ── Parser ─────────────────────────────────────────────────────── */

typedef struct {
    Lexer lex;
    int error;
    char error_msg[OBJC_INTERP_ERROR_SIZE];
} Parser;

static void parser_init(Parser *p, const char *source, unsigned int length) {
    lexer_init(&p->lex, source, length);
    p->error = 0;
    p->error_msg[0] = '\0';
    p->lex.current = lexer_next_token(&p->lex);
}

static Token parser_current(Parser *p) {
    return p->lex.current;
}

static void parser_advance(Parser *p) {
    p->lex.current = lexer_next_token(&p->lex);
}

static int parser_expect(Parser *p, TokenType type) {
    if (p->lex.current.type == type) {
        parser_advance(p);
        return 1;
    }
    p->error = OBJC_INTERP_SYNTAX_ERROR;
    return 0;
}

static void parser_error(Parser *p, const char *msg) {
    p->error = OBJC_INTERP_SYNTAX_ERROR;
    cstr_copy(p->error_msg, msg, OBJC_INTERP_ERROR_SIZE);
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
    g_vars[g_var_count].is_class = 0;
    g_vars[g_var_count].is_sel = 0;
    g_vars[g_var_count].is_id = 0;
    g_var_count++;
    return &g_vars[g_var_count - 1];
}

static InterpVar *interp_get_or_create_var(const char *name) {
    InterpVar *v = interp_find_var(name);
    if (v) return v;
    return interp_create_var(name);
}

/* ── NSLog implementation ────────────────────────────────────────── */

static void nslog_append(const char *text, unsigned int len) {
    unsigned int i;
    interp_emit_stream(text, len);
    for (i = 0; i < len && g_nslog_offset + 1 < OBJC_INTERP_NSLOG_BUFFER_SIZE; i++) {
        g_nslog_buffer[g_nslog_offset++] = text[i];
    }
    g_nslog_buffer[g_nslog_offset] = '\0';
}

static void nslog_append_char(char ch) {
    char chunk[1];
    chunk[0] = ch;
    interp_emit_stream(chunk, 1u);
    if (g_nslog_offset + 1 < OBJC_INTERP_NSLOG_BUFFER_SIZE) {
        g_nslog_buffer[g_nslog_offset++] = ch;
        g_nslog_buffer[g_nslog_offset] = '\0';
    }
}

static void nslog_append_int(int value) {
    char buf[16];
    int i = 0;
    int negative = 0;
    unsigned int u;

    if (value < 0) {
        negative = 1;
        u = (unsigned int)(-(value + 1)) + 1u;
    } else {
        u = (unsigned int)value;
    }

    if (u == 0) {
        nslog_append_char('0');
        return;
    }

    while (u > 0 && i < 15) {
        buf[i++] = '0' + (char)(u % 10u);
        u /= 10u;
    }

    if (negative) nslog_append_char('-');
    while (i > 0) {
        i--;
        nslog_append_char(buf[i]);
    }
}

static void nslog_append_long(long value) {
    char buf[22];
    int i = 0;
    int negative = 0;
    unsigned long u;

    if (value < 0) {
        negative = 1;
        u = (unsigned long)(-(value + 1)) + 1ul;
    } else {
        u = (unsigned long)value;
    }

    if (u == 0) {
        nslog_append_char('0');
        return;
    }

    while (u > 0 && i < 21) {
        buf[i++] = '0' + (char)(u % 10ul);
        u /= 10ul;
    }

    if (negative) nslog_append_char('-');
    while (i > 0) {
        i--;
        nslog_append_char(buf[i]);
    }
}

/* ── Value type ─────────────────────────────────────────────────── */

typedef struct {
    id obj_val;
    Class cls_val;
    SEL sel_val;
    int int_val;
    int is_int;
    int is_class;
    int is_sel;
    int is_id;
    int is_void;
} Value;

static Value value_from_id(id obj) {
    Value v;
    v.obj_val = obj;
    v.cls_val = 0;
    v.sel_val = 0;
    v.int_val = 0;
    v.is_int = 0;
    v.is_class = 0;
    v.is_sel = 0;
    v.is_id = 1;
    v.is_void = 0;
    return v;
}

static Value value_from_class(Class cls) {
    Value v;
    v.obj_val = 0;
    v.cls_val = cls;
    v.sel_val = 0;
    v.int_val = 0;
    v.is_int = 0;
    v.is_class = 1;
    v.is_sel = 0;
    v.is_id = 0;
    v.is_void = 0;
    return v;
}

static Value value_from_int(int n) {
    Value v;
    v.obj_val = 0;
    v.cls_val = 0;
    v.sel_val = 0;
    v.int_val = n;
    v.is_int = 1;
    v.is_class = 0;
    v.is_sel = 0;
    v.is_id = 0;
    v.is_void = 0;
    return v;
}

static Value value_from_sel(SEL s) {
    Value v;
    v.obj_val = 0;
    v.cls_val = 0;
    v.sel_val = s;
    v.int_val = 0;
    v.is_int = 0;
    v.is_class = 0;
    v.is_sel = 1;
    v.is_id = 0;
    v.is_void = 0;
    return v;
}

static Value value_void(void) {
    Value v;
    v.obj_val = 0;
    v.cls_val = 0;
    v.sel_val = 0;
    v.int_val = 0;
    v.is_int = 0;
    v.is_class = 0;
    v.is_sel = 0;
    v.is_id = 0;
    v.is_void = 1;
    return v;
}

/* ── Method dispatch state ─────────────────────────────────────── */

/* Return value flag — set by return statement, checked by method dispatch */
static int g_return_pending = 0;
static Value g_return_value;

/* String pool for string literals and Foundation object encoding.
 * Shared between parse_primary (string literals) and parse_message_send
 * (Foundation stubs like NSNumber, stringByAppendingString). */
#define OBJC_INTERP_STRING_POOL_SIZE 65536
static char g_string_pool[OBJC_INTERP_STRING_POOL_SIZE];
static unsigned int g_string_pool_offset = 0;
static unsigned int g_parse_depth = 0;

#define MAX_STRING_POOL_MARKS 4096

typedef struct {
    unsigned int old_off;
    unsigned int new_off;
} RelocEntry;

#define MAX_PARSE_DEPTH 64

/* Allocate `size` bytes from the string pool.
 * Returns pointer to the start of the allocation, or 0 if the pool is full.
 * The pool is append-only — strings persist for the lifetime of the kernel.
 * This is safe because the interpreter never frees string pool entries. */
static char *string_pool_alloc(unsigned int size) {
    if (g_string_pool_offset + size > OBJC_INTERP_STRING_POOL_SIZE) {
        return 0; /* pool full — caller must handle */
    }
    {
        char *ptr = g_string_pool + g_string_pool_offset;
        g_string_pool_offset += size;
        return ptr;
    }
}

/* Method implementation context — stored for interpreter method dispatch */
typedef struct {
    char source[2048]; /* method body source (without outer braces) */
    unsigned int source_len;
    Class class_ptr;
    SEL selector;
    int is_class_method;
    char arg_names[8][64]; /* argument names (up to 8 keyword args) */
    unsigned int arg_count; /* number of keyword arguments */
} MethodImpl;

#define MAX_METHODS 64
static MethodImpl g_methods[MAX_METHODS];
static unsigned int g_method_count = 0;

/* Property declarations — stored during @interface parsing,
 * used by @synthesize to auto-generate getter/setter methods. */
typedef struct {
    char name[64];       /* property name */
    char ivar_name[64];  /* ivar name from @synthesize (e.g., _count from @synthesize count = _count) */
    char type_name[64];  /* type: int, id, Class, SEL, etc. */
    char class_name[64]; /* which class this property belongs to */
    int is_int;          /* 1 if type is int */
    int synthesized;     /* 1 if @synthesize was seen — enables property dispatch */
} PropertyDecl;

static PropertyDecl g_properties[64];
static unsigned int g_property_count = 0;

/* Instance variable side table — per-object property storage.
 * Maps (object pointer, property name) → stored value.
 * This is the interpreter's equivalent of objc_setAssociatedObject:
 * real ObjC runtimes use associated objects for dynamic property
 * storage; we use a simple linear-scan table. */
typedef struct {
    id object;          /* object pointer (receiver) */
    char prop_name[64]; /* property name */
    Value value;        /* stored value */
} InstanceVar;

#define MAX_INSTANCE_VARS 256
static InstanceVar g_instance_vars[MAX_INSTANCE_VARS];
static unsigned int g_instance_var_count = 0;

/* ── Collection side table ────────────────────────────────────────
 * Foundation collections (NSDictionary, NSMutableDictionary, NSMutableArray,
 * NSSet) are stored in a side table. Each collection gets a unique ID
 * and is referenced by a string pool marker like "NSDict:5" or "NSMutArr:12".
 * The collection data (key-value pairs, elements) is stored in
 * g_coll_entries[] with the collection ID as the lookup key. */

typedef struct {
    unsigned int coll_id;     /* which collection this entry belongs to */
    Value key;                /* key (for dicts) or element (for arrays/sets) */
    Value value;              /* value (for dicts only) */
} CollEntry;

#define MAX_COLLECTIONS 64
#define MAX_COLL_ENTRIES 512

static unsigned int g_next_coll_id = 1;
static CollEntry g_coll_entries[MAX_COLL_ENTRIES];
static unsigned int g_coll_entry_count = 0;

/* Count entries for a given collection ID. */
static unsigned int coll_count(unsigned int coll_id) {
    unsigned int i, count = 0;
    for (i = 0; i < g_coll_entry_count; i++) {
        if (g_coll_entries[i].coll_id == coll_id) count++;
    }
    return count;
}

/* Add an entry to a collection. Returns 0 on success, -1 if table full. */
static int coll_add(unsigned int coll_id, Value key, Value value) {
    if (g_coll_entry_count >= MAX_COLL_ENTRIES) return -1;
    if (coll_id >= g_next_coll_id + MAX_COLLECTIONS) return -1;
    g_coll_entries[g_coll_entry_count].coll_id = coll_id;
    g_coll_entries[g_coll_entry_count].key = key;
    g_coll_entries[g_coll_entry_count].value = value;
    g_coll_entry_count++;
    return 0;
}

/* Find an entry in a collection by key (for dicts/sets). Returns index or -1. */
static int coll_find_by_key(unsigned int coll_id, Value *key) {
    unsigned int i;
    for (i = 0; i < g_coll_entry_count; i++) {
        if (g_coll_entries[i].coll_id != coll_id) continue;
        /* Compare keys: int by value, id by string content (not pointer) */
        if (key->is_int && g_coll_entries[i].key.is_int &&
            key->int_val == g_coll_entries[i].key.int_val) return (int)i;
        if (key->is_id && g_coll_entries[i].key.is_id &&
            key->obj_val != 0 && g_coll_entries[i].key.obj_val != 0) {
            /* String content comparison — two different @"key" literals
             * may have different string pool pointers but same content. */
            if (cstr_eq((const char *)key->obj_val, (const char *)g_coll_entries[i].key.obj_val))
                return (int)i;
        }
    }
    return -1;
}

/* Remove an entry at index. */
static void coll_remove_at(unsigned int idx) {
    unsigned int i;
    for (i = (unsigned int)idx; i < g_coll_entry_count - 1; i++) {
        g_coll_entries[i] = g_coll_entries[i + 1];
    }
    g_coll_entry_count--;
}

/* Remove all entries for a collection ID. */
static void coll_remove_all(unsigned int coll_id) {
    unsigned int i = 0;
    while (i < g_coll_entry_count) {
        if (g_coll_entries[i].coll_id == coll_id) {
            coll_remove_at(i);
        } else {
            i++;
        }
    }
}

/* Get the Nth entry for a collection (for array indexing). Returns index or -1. */
static int coll_get_nth(unsigned int coll_id, unsigned int n) {
    unsigned int i, count = 0;
    for (i = 0; i < g_coll_entry_count; i++) {
        if (g_coll_entries[i].coll_id == coll_id) {
            if (count == n) return (int)i;
            count++;
        }
    }
    return -1;
}

/* Parse a collection ID from a marker string like "NSDict:5" or "NSMutArr:12".
 * Returns the ID, or 0 if not a valid collection marker. */
static unsigned int coll_id_from_marker(const char *s, const char *prefix) {
    unsigned int prefix_len = cstr_len(prefix);
    unsigned int id = 0;
    unsigned int i;
    if (!cstr_eq_n(s, prefix, prefix_len)) return 0;
    for (i = prefix_len; s[i] >= '0' && s[i] <= '9'; i++) {
        id = id * 10 + (unsigned int)(s[i] - '0');
    }
    return id;
}

/* Create a collection marker string in the string pool. */
static id coll_make_marker(const char *prefix, unsigned int coll_id) {
    char buf[64];
    unsigned int pos = cstr_len(prefix);
    unsigned int tmp = coll_id;
    unsigned int digits;
    cstr_copy(buf, prefix, 64);
    /* Count digits */
    digits = 0;
    if (tmp == 0) digits = 1;
    else { unsigned int t = tmp; while (t > 0) { digits++; t /= 10; } }
    /* Write digits */
    { unsigned int t = tmp; unsigned int d = digits; do { d--; buf[pos + d] = '0' + (t % 10); t /= 10; } while (t > 0); }
    buf[pos + digits] = '\0';
    {
        char *result = string_pool_alloc(pos + digits + 1);
        if (result == 0) return (id)"";
        cstr_copy(result, buf, pos + digits + 1);
        return (id)result;
    }
}

/* ── Block side table ────────────────────────────────────────────
 * Blocks are stored as source ranges (like method bodies).
 * When a block literal ^{ ... } is parsed, we capture the body
 * source and register it in g_blocks[]. Block objects are
 * referenced by string pool markers like "NSBlock:5".
 * When a block is invoked, we execute the body via eval_source_range. */

typedef struct {
    char name[64];   /* captured variable name */
    Value value;     /* captured value (by-value snapshot) */
} BlockCapture;

typedef struct {
    unsigned int block_id;        /* unique ID */
    char source[2048];            /* block body source (without outer braces) */
    unsigned int source_len;
    char arg_names[8][64];       /* parameter names */
    unsigned int arg_count;
    BlockCapture captures[16];   /* captured variable values */
    unsigned int capture_count;
} BlockImpl;

#define MAX_BLOCKS 32
static BlockImpl g_blocks[MAX_BLOCKS];
static unsigned int g_block_count = 0;
static unsigned int g_next_block_id = 1;

/* Look up a block by its ID. Returns pointer or 0. */
static BlockImpl *block_get(unsigned int block_id) {
    unsigned int i;
    for (i = 0; i < g_block_count; i++) {
        if (g_blocks[i].block_id == block_id) return &g_blocks[i];
    }
    return 0;
}

/* Parse a block ID from a marker string like "NSBlock:5". */
static unsigned int block_id_from_marker(const char *s) {
    return coll_id_from_marker(s, "NSBlock:");
}

/* Create a block marker string in the string pool. */
static id block_make_marker(unsigned int block_id) {
    return coll_make_marker("NSBlock:", block_id);
}

/* Look up an instance variable in the side table.
 * Returns pointer to the value (mutable), or 0 if not found. */
static Value *instance_var_get(id object, const char *prop_name) {
    unsigned int i;
    for (i = 0; i < g_instance_var_count; i++) {
        if (g_instance_vars[i].object == object &&
            cstr_eq(g_instance_vars[i].prop_name, prop_name)) {
            return &g_instance_vars[i].value;
        }
    }
    return 0;
}

/* Store an instance variable in the side table.
 * Overwrites existing entry for (object, prop_name), or adds new. */
static int instance_var_set(id object, const char *prop_name, Value val) {
    unsigned int i;
    for (i = 0; i < g_instance_var_count; i++) {
        if (g_instance_vars[i].object == object &&
            cstr_eq(g_instance_vars[i].prop_name, prop_name)) {
            g_instance_vars[i].value = val;
            return 0;
        }
    }
    /* Add new entry */
    if (g_instance_var_count < MAX_INSTANCE_VARS) {
        g_instance_vars[g_instance_var_count].object = object;
        cstr_copy(g_instance_vars[g_instance_var_count].prop_name, prop_name, 64);
        g_instance_vars[g_instance_var_count].value = val;
        g_instance_var_count++;
        return 0;
    }
    return -1;
}

/* Check if a variable name is a synthesized ivar name.
 * Returns the property index if found, or -1 if not.
 * This is used to redirect ivar access in method bodies to the side table. */
static int find_synthesized_ivar(const char *var_name) {
    unsigned int pi;
    for (pi = 0; pi < g_property_count; pi++) {
        if (g_properties[pi].synthesized &&
            g_properties[pi].ivar_name[0] != '\0' &&
            cstr_eq(var_name, g_properties[pi].ivar_name)) {
            return (int)pi;
        }
    }
    return -1;
}

/* Read a synthesized ivar value from the side table.
 * Returns the value, or value_void() if not found. */
static Value synthesized_ivar_get(id self, const char *var_name) {
    int pi = find_synthesized_ivar(var_name);
    if (pi >= 0) {
        Value *val = instance_var_get(self, g_properties[pi].name);
        if (val) return *val;
    }
    return value_void();
}

/* Write a synthesized ivar value to the side table. */
static int synthesized_ivar_set(id self, const char *var_name, Value val) {
    int pi = find_synthesized_ivar(var_name);
    if (pi >= 0) {
        if (instance_var_set(self, g_properties[pi].name, val) != 0) {
            g_error_code = OBJC_INTERP_RESOURCE_ERROR;
            cstr_copy(g_error_buffer, "instance variable table full (max 256)", OBJC_INTERP_ERROR_SIZE);
            interp_emit_stream("warning: instance variable table full (max 256)\n", cstr_len("warning: instance variable table full (max 256)\n"));
            return -1;
        }
    }
    return 0;
}

/* ── AST nodes for control flow ──────────────────────────────────── */

/* The interpreter is a single-pass parser/evaluator for expressions,
 * but control flow (if/while/for) requires re-evaluating conditions
 * and loop bodies. We use a small AST for control flow nodes only.
 * Expression statements are stored as source ranges and re-parsed
 * when executed (same technique as method body capture). */

typedef enum {
    AST_IF,
    AST_WHILE,
    AST_FOR,
    AST_FOR_IN,
    AST_BLOCK,
    AST_EXPR_STMT,
    AST_VAR_DECL,
    AST_RETURN,
    AST_BREAK,
    AST_CONTINUE
} AstNodeType;

typedef struct AstNode AstNode;

struct AstNode {
    AstNodeType type;
    union {
        struct { /* AST_IF */
            AstNode *condition;
            AstNode *then_branch;
            AstNode *else_branch;
        } if_stmt;
        struct { /* AST_WHILE */
            AstNode *condition;
            AstNode *body;
        } while_stmt;
        struct { /* AST_FOR */
            AstNode *init;
            AstNode *condition;
            AstNode *increment;
            AstNode *body;
        } for_stmt;
        struct { /* AST_FOR_IN */
            char var_name[64];   /* iteration variable name */
            unsigned int collection_start; /* source range for collection expr */
            unsigned int collection_len;
            AstNode *body;
        } for_in;
        struct { /* AST_BLOCK */
            AstNode *children[128];
            unsigned int count;
        } block;
        struct { /* AST_EXPR_STMT, AST_VAR_DECL, AST_RETURN */
            unsigned int source_start;
            unsigned int source_len;
        } source_range;
    };
};

#define MAX_AST_NODES 1024
static AstNode g_ast_arena[MAX_AST_NODES];
static unsigned int g_ast_count = 0;

/* Break/continue flags — checked by loop evaluation */
static int g_break_pending = 0;
static int g_continue_pending = 0;

static AstNode *ast_alloc(void) {
    if (g_ast_count >= MAX_AST_NODES) return 0;
    return &g_ast_arena[g_ast_count++];
}

static AstNode *ast_make_if(AstNode *condition, AstNode *then_branch, AstNode *else_branch) {
    AstNode *n = ast_alloc();
    if (!n) return 0;
    n->type = AST_IF;
    n->if_stmt.condition = condition;
    n->if_stmt.then_branch = then_branch;
    n->if_stmt.else_branch = else_branch;
    return n;
}

static AstNode *ast_make_while(AstNode *condition, AstNode *body) {
    AstNode *n = ast_alloc();
    if (!n) return 0;
    n->type = AST_WHILE;
    n->while_stmt.condition = condition;
    n->while_stmt.body = body;
    return n;
}

static AstNode *ast_make_for(AstNode *init, AstNode *condition, AstNode *increment, AstNode *body) {
    AstNode *n = ast_alloc();
    if (!n) return 0;
    n->type = AST_FOR;
    n->for_stmt.init = init;
    n->for_stmt.condition = condition;
    n->for_stmt.increment = increment;
    n->for_stmt.body = body;
    return n;
}

static AstNode *ast_make_block(void) {
    AstNode *n = ast_alloc();
    if (!n) return 0;
    n->type = AST_BLOCK;
    n->block.count = 0;
    return n;
}

static int ast_block_add(AstNode *block, AstNode *child) {
    if (block && block->type == AST_BLOCK && block->block.count < 128) {
        block->block.children[block->block.count++] = child;
        return 0;
    }
    return -1;
}

static AstNode *ast_make_source(AstNodeType type, unsigned int start, unsigned int len) {
    AstNode *n = ast_alloc();
    if (!n) return 0;
    n->type = type;
    n->source_range.source_start = start;
    n->source_range.source_len = len;
    return n;
}

/* ── Forward declarations ───────────────────────────────────────── */

static Value parse_expression(Parser *p);
static Value parse_expression_safe(Parser *p) {
    Value result;
    if (g_parse_depth >= MAX_PARSE_DEPTH) {
        parser_error(p, "expression too deeply nested (max 64 levels)");
        return value_void();
    }
    g_parse_depth++;
    result = parse_expression(p);
    g_parse_depth--;
    return result;
}
static Value parse_statement(Parser *p);
static Value parse_block(Parser *p);
static int is_truthy(Value v);
static AstNode *parse_statement_ast(Parser *p);
static Value eval_source_range(unsigned int start, unsigned int len, const char *source);
static Value eval_ast(AstNode *node, const char *source);
static Value parse_type_and_var_decl(Parser *p);

/* ── NSLog format string evaluation ─────────────────────────────── */

/* Evaluate NSLog with format string and arguments.
 * We've already consumed the NSLog identifier and opening paren.
 * The first argument is the format string (@"...").
 * Subsequent arguments are matched to %@, %d, %ld, %f, %% specifiers.
 */
static void eval_nslog(Parser *p) {
    Value fmt_val;
    const char *fmt;
    unsigned int fi;
    Value args[16];
    int arg_count = 0;
    int arg_idx = 0;

    /* Parse format string */
    fmt_val = parse_expression_safe(p);
    if (p->error) return;

    /* Extract the C string from the format value.
     * For @"..." literals, the id points to the string pool entry
     * which is a null-terminated C string. */
    fmt = 0;
    if (fmt_val.is_id && fmt_val.obj_val != 0) {
        fmt = (const char *)fmt_val.obj_val;
    }

    /* Parse remaining arguments (comma-separated) */
    while (parser_current(p).type == TOK_COMMA) {
        parser_advance(p); /* skip comma */
        if (arg_count < 16) {
            args[arg_count] = parse_expression_safe(p);
            if (p->error) return;
            arg_count++;
        } else {
            /* Skip excess arguments */
            parse_expression_safe(p);
            if (p->error) return;
        }
    }

    if (parser_current(p).type == TOK_CLOSE_PAREN) {
        parser_advance(p);
    }

    /* Process format string */
    if (fmt == 0) {
        nslog_append("(null)", 6);
        return;
    }

    fi = 0;
    while (fmt[fi] != '\0') {
        if (fmt[fi] == '%' && fmt[fi + 1] != '\0') {
            fi++;
            switch (fmt[fi]) {
                case '%':
                    nslog_append_char('%');
                    break;
                case '@':
                    /* Object — print as pointer or string */
                    if (arg_idx < arg_count) {
                        Value v = args[arg_idx++];
                        if (v.is_id && v.obj_val != 0) {
                            /* Check if it's a string pool entry (@"..." literal) */
                            nslog_append((const char *)v.obj_val,
                                         cstr_len((const char *)v.obj_val));
                        } else if (v.is_class && v.cls_val != 0) {
                            /* Look up class name from variable table
                             * (class_getName crashes on sentinel pointers) */
                            const char *name = 0;
                            {
                                unsigned int vi;
                                for (vi = 0; vi < g_var_count; vi++) {
                                    if (g_vars[vi].is_class && g_vars[vi].cls == v.cls_val) {
                                        name = g_vars[vi].name;
                                        break;
                                    }
                                }
                            }
                            if (name == 0) name = "Class";
                            nslog_append(name, cstr_len(name));
                        } else if (v.is_int) {
                            nslog_append_int(v.int_val);
                        } else {
                            nslog_append("(nil)", 5);
                        }
                    }
                    break;
                case 'd':
                case 'i':
                    /* Integer */
                    if (arg_idx < arg_count) {
                        Value v = args[arg_idx++];
                        if (v.is_int) {
                            nslog_append_int(v.int_val);
                        } else if (v.is_id) {
                            nslog_append_int((int)(long)v.obj_val);
                        }
                    }
                    break;
                case 'l':
                    /* Long — check for %ld */
                    if (fmt[fi + 1] == 'd' || fmt[fi + 1] == 'i') {
                        fi++; /* skip 'l' */
                        /* %ld — same as %d for our purposes */
                        if (arg_idx < arg_count) {
                            Value v = args[arg_idx++];
                            if (v.is_int) {
                                nslog_append_long((long)v.int_val);
                            }
                        }
                    }
                    break;
                case 'u':
                    /* Unsigned integer */
                    if (arg_idx < arg_count) {
                        Value v = args[arg_idx++];
                        if (v.is_int) {
                            nslog_append_int(v.int_val);
                        }
                    }
                    break;
                case 'f':
                    /* Float — we don't have float support yet */
                    if (arg_idx < arg_count) {
                        arg_idx++;
                        nslog_append("(float)", 7);
                    }
                    break;
                case 's':
                    /* C string */
                    if (arg_idx < arg_count) {
                        Value v = args[arg_idx++];
                        if (v.is_id && v.obj_val != 0) {
                            nslog_append((const char *)v.obj_val,
                                         cstr_len((const char *)v.obj_val));
                        }
                    }
                    break;
                case 'p':
                    /* Pointer */
                    if (arg_idx < arg_count) {
                        Value v = args[arg_idx++];
                        nslog_append("0x", 2);
                        if (v.is_id) {
                            /* Print hex pointer */
                            unsigned long ptr = (unsigned long)v.obj_val;
                            char hex[17];
                            int hi = 0;
                            if (ptr == 0) {
                                nslog_append_char('0');
                            } else {
                                while (ptr > 0 && hi < 16) {
                                    hex[hi++] = "0123456789abcdef"[ptr % 16];
                                    ptr /= 16;
                                }
                                while (hi > 0) {
                                    hi--;
                                    nslog_append_char(hex[hi]);
                                }
                            }
                        }
                    }
                    break;
                default:
                    nslog_append_char('%');
                    nslog_append_char(fmt[fi]);
                    break;
            }
            fi++;
        } else {
            nslog_append_char(fmt[fi]);
            fi++;
        }
    }

    /* NSLog always appends a newline */
    nslog_append_char('\n');
}

/* ── Message send evaluation ────────────────────────────────────── */

/* Parse a message send: [target selector:arg1 key2:arg2 ...]
 * We've already consumed the [.
 */
static Value parse_message_send(Parser *p) {
    Value target;
    char sel_name[256];
    unsigned int sel_len;
    id args[16];
    Value keyword_args[16]; /* preserve Value types for interpreter method dispatch */
    unsigned int arg_count;
    Value result;

    /* Parse target */
    target = parse_expression_safe(p);
    if (p->error) return value_void();

    /* Build selector name from the message pattern */
    sel_name[0] = '\0';
    sel_len = 0;
    arg_count = 0;

    /* Parse selector parts and arguments */
    while (parser_current(p).type != TOK_CLOSE_BRACKET &&
           parser_current(p).type != TOK_EOF) {

        if (parser_current(p).type == TOK_IDENTIFIER) {
            /* Selector component */
            char part_buf[OBJC_INTERP_MAX_TOKEN];
            unsigned int part_len;
            cstr_copy(part_buf, parser_current(p).text, OBJC_INTERP_MAX_TOKEN);
            part_len = cstr_len(part_buf);

            /* Append selector component (no extra colon — the colon
             * after each keyword part is added below at line 904) */
            cstr_copy(sel_name + sel_len, part_buf, 256 - sel_len);
            sel_len += part_len;

            parser_advance(p);

            /* If next token is colon, this is a keyword argument */
            if (parser_current(p).type == TOK_COLON) {
                parser_advance(p); /* consume : */

                /* Replace the last part of the selector name to add : */
                sel_name[sel_len] = ':';
                sel_len++;
                sel_name[sel_len] = '\0';

                /* Parse argument */
                if (arg_count < 16) {
                    Value arg = parse_expression_safe(p);
                    if (p->error) return value_void();
                    keyword_args[arg_count] = arg;
                    if (arg.is_int) {
                        args[arg_count] = (id)(long)arg.int_val;
                    } else if (arg.is_class) {
                        args[arg_count] = (id)arg.cls_val;
                    } else {
                        args[arg_count] = arg.obj_val;
                    }
                    arg_count++;
                }
            }
            /* If no colon, this is a unary message (like [obj count]) */
            /* or the last part of the selector */
        } else {
            /* Unexpected token in message send */
            break;
        }
    }

    if (parser_current(p).type == TOK_CLOSE_BRACKET) {
        parser_advance(p);
    }

    /* Register the selector */
    {
        SEL sel = sel_registerName(sel_name);
        id receiver = 0;
        const char *target_class_name = 0; /* for Foundation name-based dispatch */

        if (target.is_id) receiver = target.obj_val;
        else if (target.is_class) receiver = (id)target.cls_val;
        else if (target.is_int) receiver = (id)(long)target.int_val;

        /* Determine target class name for Foundation dispatch.
         * Foundation classes are not registered in the runtime (to avoid
         * WASM traps from objc_allocateClassPair), so we dispatch by name.
         * We look up the variable name from g_vars[].
         * IMPORTANT: We can't call object_getClass on non-ObjC pointers
         * (like C strings from the string pool) — it causes WASM traps.
         * So we only call it for class targets, not id targets. */
        if (target.is_class && target.cls_val) {
            /* Look up class name from variable table.
             * We can't call class_getName on sentinel pointers (crashes in WASM).
             * Sentinel pointers: Foundation classes (1-9), custom classes (100+). */
            {
                unsigned int vi;
                for (vi = 0; vi < g_var_count; vi++) {
                    if (g_vars[vi].is_class && g_vars[vi].cls == target.cls_val) {
                        target_class_name = g_vars[vi].name;
                        break;
                    }
                }
            }
        }
        /* For id targets, we don't call object_getClass because the
         * pointer might not be a valid ObjC object. Instead, we
         * dispatch by selector name alone for Foundation methods. */

        /* Helper: check if target is a Foundation class */
        #define IS_FOUNDATION_CLASS(name) \
            (target_class_name && cstr_eq(target_class_name, name))

        /* Built-in: [ClassName alloc] → return FDObj: marker for all classes.
         * In WASM, class_createInstance crashes on sentinel pointers,
         * so we use the FDObj: marker approach for ALL classes (not just
         * Foundation). Custom classes get sentinel pointers >= 100. */
        if (target.is_class && cstr_eq(sel_name, "alloc")) {
            if (target_class_name) {
                unsigned int name_len = cstr_len(target_class_name);
                unsigned int needed = 6 + name_len + 1;
                char *buf = string_pool_alloc(needed);
                if (buf == 0) return value_from_id((id)"FDObj:overflow");
                cstr_copy(buf, "FDObj:", needed);
                cstr_copy(buf + 6, target_class_name, needed - 6);
                return value_from_id((id)buf);
            }
            return value_from_id((id)0);
        }

        /* Built-in: [ClassName new] → same as alloc (returns FDObj: marker) */
        if (target.is_class && cstr_eq(sel_name, "new")) {
            if (target_class_name) {
                unsigned int name_len = cstr_len(target_class_name);
                unsigned int needed = 6 + name_len + 1;
                char *buf = string_pool_alloc(needed);
                if (buf == 0) return value_from_id((id)"FDObj:overflow");
                cstr_copy(buf, "FDObj:", needed);
                cstr_copy(buf + 6, target_class_name, needed - 6);
                return value_from_id((id)buf);
            }
            return value_from_id((id)0);
        }

        /* Built-in: [obj init] → return self (standard NSObject pattern) */
        if (cstr_eq(sel_name, "init") && target.is_id && receiver != 0) {
            /* Check if receiver is an FDObj: marker for a collection class.
             * If so, create a proper collection marker instead of returning
             * the FDObj: marker. */
            const char *s = (const char *)receiver;
            if (cstr_eq_n(s, "FDObj:", 6)) {
                const char *cls_name = s + 6;
                unsigned int cid = g_next_coll_id++;
                if (cstr_eq(cls_name, "NSMutableArray")) {
                    return value_from_id(coll_make_marker("NSMutArr:", cid));
                }
                if (cstr_eq(cls_name, "NSMutableDictionary")) {
                    return value_from_id(coll_make_marker("NSMutDict:", cid));
                }
                if (cstr_eq(cls_name, "NSArray")) {
                    return value_from_id(coll_make_marker("NSArr:", cid));
                }
                if (cstr_eq(cls_name, "NSDictionary")) {
                    return value_from_id(coll_make_marker("NSDict:", cid));
                }
                if (cstr_eq(cls_name, "NSSet")) {
                    return value_from_id(coll_make_marker("NSSet:", cid));
                }
            }
            return value_from_id(receiver);
        }

        /* Built-in: [obj class] → return the object's class */
        if (cstr_eq(sel_name, "class") && target.is_id && receiver != 0) {
            Class cls = (Class)0;
            cls = object_getClass(receiver);
            return value_from_class(cls);
        }

        /* ── Foundation built-in dispatch ────────────────────────────── */

        /* NSObject: [obj description] → class name */
        if (cstr_eq(sel_name, "description") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            /* Check if it's a Foundation class object (FDObj:ClassName) */
            if (cstr_eq_n(s, "FDObj:", 6)) {
                nslog_append("<", 1);
                nslog_append(s + 6, cstr_len(s + 6));
                nslog_append(">", 1);
            } else if (target_class_name) {
                nslog_append("<", 1);
                nslog_append(target_class_name, cstr_len(target_class_name));
                nslog_append(">", 1);
            } else {
                /* For real ObjC objects, try object_getClass */
                Class cls = object_getClass(receiver);
                if (cls) {
                    const char *name = class_getName(cls);
                    if (name) {
                        nslog_append("<", 1);
                        nslog_append(name, cstr_len(name));
                        nslog_append(">", 1);
                    }
                }
            }
            return value_from_id(receiver);
        }

        /* NSObject: [obj isEqual:other] → 1 if same pointer */
        if (cstr_eq(sel_name, "isEqual:") && target.is_id && arg_count >= 1) {
            int equal = (receiver == args[0]) ? 1 : 0;
            return value_from_int(equal);
        }

        /* NSObject: [obj hash] → pointer as int */
        if (cstr_eq(sel_name, "hash") && target.is_id && receiver != 0) {
            return value_from_int((int)(long)receiver);
        }

        /* NSObject: [obj respondsToSelector:sel] → check if method exists */
        if (cstr_eq(sel_name, "respondsToSelector:") && target.is_id && arg_count >= 1) {
            if (keyword_args[0].is_sel) {
                unsigned int mi;
                for (mi = 0; mi < g_method_count; mi++) {
                    if (g_methods[mi].selector == keyword_args[0].sel_val) {
                        return value_from_int(1);
                    }
                }
            }
            return value_from_int(0);
        }

        /* NSObject: [obj performSelector:sel] → dispatch selector */
        if (cstr_eq(sel_name, "performSelector:") && target.is_id && arg_count >= 1) {
            if (keyword_args[0].is_sel) {
                SEL perf_sel = keyword_args[0].sel_val;
                unsigned int mi;
                int found = 0;
                for (mi = 0; mi < g_method_count; mi++) {
                    if (g_methods[mi].selector == perf_sel && g_methods[mi].source_len > 0 &&
                        !g_methods[mi].is_class_method) {
                        found = 1;
                        break;
                    }
                }
                if (found) {
                    unsigned int saved_var_count = g_var_count;
                    Value return_val;
                    InterpVar *self_var = interp_get_or_create_var("self");
                    if (self_var) { self_var->is_id = 1; self_var->value = receiver; }
                    {
                        InterpVar *cmd_var = interp_get_or_create_var("_cmd");
                        if (cmd_var) { cmd_var->is_sel = 1; cmd_var->sel = perf_sel; }
                    }
                    g_return_pending = 0;
                    {
                        Value v = eval_source_range(0, g_methods[mi].source_len, g_methods[mi].source);
                        (void)v;
                    }
                    return_val = g_return_value;
                    g_var_count = saved_var_count;
                    g_return_pending = 0;
                    return return_val;
                }
            }
            return value_from_id(receiver);
        }

        /* NSString: [NSString stringWithFormat:@"..." args...] */
        if (IS_FOUNDATION_CLASS("NSString") && target.is_class && cstr_eq(sel_name, "stringWithFormat:") && arg_count >= 1) {
            return keyword_args[0];
        }

        /* NSString: [str length] → string length */
        if (cstr_eq(sel_name, "length") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            return value_from_int((int)cstr_len(s));
        }

        /* NSString: [str intValue] → parse as integer */
        if (cstr_eq(sel_name, "intValue") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            int val = 0;
            unsigned int i = 0;
            while (s[i] && (s[i] < '0' || s[i] > '9') && s[i] != '-') i++;
            if (s[i] == '-') { i++; while (s[i] >= '0' && s[i] <= '9') val = val * 10 - (s[i++] - '0'); }
            else { while (s[i] >= '0' && s[i] <= '9') val = val * 10 + (s[i++] - '0'); }
            return value_from_int(val);
        }

        /* NSString: [str UTF8String] → return self (already C string) */
        if (cstr_eq(sel_name, "UTF8String") && target.is_id && receiver != 0) {
            return value_from_id(receiver);
        }

        /* NSString: [str stringByAppendingString:other] → concatenate */
        if (cstr_eq(sel_name, "stringByAppendingString:") && target.is_id && receiver != 0 && arg_count >= 1) {
            const char *a = (const char *)receiver;
            const char *b = (const char *)args[0];
            unsigned int alen = cstr_len(a);
            unsigned int blen = cstr_len(b);
            char *result;
            unsigned int needed = alen + blen + 1;
            result = string_pool_alloc(needed);
            if (result == 0) return value_from_id(receiver);
            cstr_copy(result, a, needed);
            cstr_copy(result + alen, b, needed - alen);
            return value_from_id((id)result);
        }

        /* NSString: [str isEqualToString:other] → string compare */
        if (cstr_eq(sel_name, "isEqualToString:") && target.is_id && receiver != 0 && arg_count >= 1) {
            const char *a = (const char *)receiver;
            const char *b = (const char *)args[0];
            return value_from_int(cstr_eq(a, b) ? 1 : 0);
        }

        /* NSNumber: [NSNumber numberWithInt:n] → wrap int as id */
        if (IS_FOUNDATION_CLASS("NSNumber") && target.is_class && cstr_eq(sel_name, "numberWithInt:") && arg_count >= 1) {
            /* Store the int value in a string pool buffer.
             * Encoding: "NSNumber:<int_value>" */
            if (keyword_args[0].is_int) {
                char *buf;
                int v = keyword_args[0].int_val;
                int neg = v < 0;
                unsigned int pos = 9; /* after "NSNumber:" */
                buf = string_pool_alloc(30);
                if (buf == 0) return value_from_int(keyword_args[0].int_val);
                cstr_copy(buf, "NSNumber:", 30);
                if (neg) { v = -v; buf[pos++] = '-'; }
                if (v == 0) { buf[pos++] = '0'; }
                else {
                    char tmp[12];
                    int ti = 0;
                    while (v > 0) { tmp[ti++] = '0' + (v % 10); v /= 10; }
                    while (ti > 0) buf[pos++] = tmp[--ti];
                }
                buf[pos] = '\0';
                return value_from_id((id)buf);
            }
            return value_from_id(args[0]);
        }

        /* NSNumber: [num intValue] → unwrap int from NSNumber encoding */
        if (cstr_eq(sel_name, "intValue") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            if (cstr_eq_n(s, "NSNumber:", 9)) {
                int val = 0;
                unsigned int i = 9;
                int neg = 0;
                if (s[i] == '-') { neg = 1; i++; }
                while (s[i] >= '0' && s[i] <= '9') val = val * 10 + (s[i++] - '0');
                return value_from_int(neg ? -val : val);
            }
            return value_from_int(0);
        }

        /* NSNumber: [num boolValue] → 1 if non-zero */
        if (cstr_eq(sel_name, "boolValue") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            if (cstr_eq_n(s, "NSNumber:", 9)) {
                int val = 0;
                unsigned int i = 9;
                while (s[i] >= '0' && s[i] <= '9') val = val * 10 + (s[i++] - '0');
                return value_from_int(val ? 1 : 0);
            }
            return value_from_int(0);
        }

        /* NSNumber: [num description] → numeric string */
        if (cstr_eq(sel_name, "description") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            if (cstr_eq_n(s, "NSNumber:", 9)) {
                nslog_append(s + 9, cstr_len(s + 9));
            }
            return value_from_id(receiver);
        }

        /* ── Foundation collection dispatch ──────────────────────── */

        /* NSArray: [NSArray array] → empty immutable array */
        if (IS_FOUNDATION_CLASS("NSArray") && target.is_class && cstr_eq(sel_name, "array") && arg_count == 0) {
            unsigned int cid = g_next_coll_id++;
            return value_from_id(coll_make_marker("NSArr:", cid));
        }

        /* NSMutableArray: [NSMutableArray arrayWithCapacity:n] → empty mutable array */
        if (IS_FOUNDATION_CLASS("NSMutableArray") && target.is_class && cstr_eq(sel_name, "arrayWithCapacity:") && arg_count >= 1) {
            unsigned int cid = g_next_coll_id++;
            return value_from_id(coll_make_marker("NSMutArr:", cid));
        }

        /* NSMutableArray: [NSMutableArray array] → empty mutable array */
        if (IS_FOUNDATION_CLASS("NSMutableArray") && target.is_class && cstr_eq(sel_name, "array") && arg_count == 0) {
            unsigned int cid = g_next_coll_id++;
            return value_from_id(coll_make_marker("NSMutArr:", cid));
        }

        /* NSDictionary: [NSDictionary dictionary] → empty immutable dict */
        if (IS_FOUNDATION_CLASS("NSDictionary") && target.is_class && cstr_eq(sel_name, "dictionary") && arg_count == 0) {
            unsigned int cid = g_next_coll_id++;
            return value_from_id(coll_make_marker("NSDict:", cid));
        }

        /* NSMutableDictionary: [NSMutableDictionary dictionaryWithCapacity:n] → empty mutable dict */
        if (IS_FOUNDATION_CLASS("NSMutableDictionary") && target.is_class && cstr_eq(sel_name, "dictionaryWithCapacity:") && arg_count >= 1) {
            unsigned int cid = g_next_coll_id++;
            return value_from_id(coll_make_marker("NSMutDict:", cid));
        }

        /* NSMutableDictionary: [NSMutableDictionary dictionary] → empty mutable dict */
        if (IS_FOUNDATION_CLASS("NSMutableDictionary") && target.is_class && cstr_eq(sel_name, "dictionary") && arg_count == 0) {
            unsigned int cid = g_next_coll_id++;
            return value_from_id(coll_make_marker("NSMutDict:", cid));
        }

        /* NSSet: [NSSet setWithArray:arr] → set from array */
        if (IS_FOUNDATION_CLASS("NSSet") && target.is_class && cstr_eq(sel_name, "setWithArray:") && arg_count >= 1) {
            unsigned int cid = g_next_coll_id++;
            const char *arr_s = (const char *)keyword_args[0].obj_val;
            unsigned int arr_cid = coll_id_from_marker(arr_s, "NSArr:");
            if (arr_cid == 0) arr_cid = coll_id_from_marker(arr_s, "NSMutArr:");
            if (arr_cid > 0) {
                /* Copy unique elements from array to set */
                unsigned int i;
                for (i = 0; i < g_coll_entry_count; i++) {
                    if (g_coll_entries[i].coll_id == arr_cid) {
                        /* Check if already in set */
                        int existing = coll_find_by_key(cid, &g_coll_entries[i].key);
                        if (existing < 0) {
                            coll_add(cid, g_coll_entries[i].key, g_coll_entries[i].value);
                        }
                    }
                }
            }
            return value_from_id(coll_make_marker("NSSet:", cid));
        }

        /* ── Instance method dispatch on collection objects ────── */

        {
            unsigned int cid = 0;
            const char *s = (const char *)receiver;

            /* Try to identify the collection type and ID */
            if (target.is_id && receiver != 0) {
                cid = coll_id_from_marker(s, "NSArr:");
                if (cid == 0) cid = coll_id_from_marker(s, "NSMutArr:");
                if (cid == 0) cid = coll_id_from_marker(s, "NSDict:");
                if (cid == 0) cid = coll_id_from_marker(s, "NSMutDict:");
                if (cid == 0) cid = coll_id_from_marker(s, "NSSet:");
            }

            if (cid > 0) {
                /* [coll count] → number of entries */
                if (cstr_eq(sel_name, "count")) {
                    return value_from_int((int)coll_count(cid));
                }

                /* [arr objectAtIndex:i] → element at index */
                if (cstr_eq(sel_name, "objectAtIndex:") && arg_count >= 1 && keyword_args[0].is_int) {
                    int idx = coll_get_nth(cid, (unsigned int)keyword_args[0].int_val);
                    if (idx >= 0) {
                        return g_coll_entries[idx].key;
                    }
                    return value_from_id((id)"(nil)");
                }

                /* [mutArr addObject:obj] → append element */
                if (cstr_eq(sel_name, "addObject:") && arg_count >= 1) {
                    Value elem = keyword_args[0];
                    Value dummy = value_void();
                    if (coll_add(cid, elem, dummy) != 0) {
                        nslog_append("warning: collection entry table full\n", 38);
                    }
                    return value_from_id(receiver);
                }

                /* [mutArr removeLastObject] → remove last element */
                if (cstr_eq(sel_name, "removeLastObject")) {
                    unsigned int cnt = coll_count(cid);
                    if (cnt > 0) {
                        int idx = coll_get_nth(cid, cnt - 1);
                        if (idx >= 0) coll_remove_at((unsigned int)idx);
                    }
                    return value_from_id(receiver);
                }

                /* [dict objectForKey:key] → value for key */
                if (cstr_eq(sel_name, "objectForKey:") && arg_count >= 1) {
                    int idx = coll_find_by_key(cid, &keyword_args[0]);
                    if (idx >= 0) return g_coll_entries[idx].value;
                    return value_from_id((id)"(nil)");
                }

                /* [mutDict setObject:obj forKey:key] → set key-value */
                if (cstr_eq(sel_name, "setObject:forKey:") && arg_count >= 2) {
                    Value val = keyword_args[0];  /* first arg after setObject: */
                    Value key = keyword_args[1];   /* second arg after forKey: */
                    int idx = coll_find_by_key(cid, &key);
                    if (idx >= 0) {
                        g_coll_entries[idx].value = val;
                    } else {
                        if (coll_add(cid, key, val) != 0) {
                            nslog_append("warning: collection entry table full\n", 38);
                        }
                    }
                    return value_from_id(receiver);
                }

                /* [mutDict removeObjectForKey:key] → remove entry */
                if (cstr_eq(sel_name, "removeObjectForKey:") && arg_count >= 1) {
                    int idx = coll_find_by_key(cid, &keyword_args[0]);
                    if (idx >= 0) coll_remove_at((unsigned int)idx);
                    return value_from_id(receiver);
                }

                /* [dict allKeys] → array of keys */
                if (cstr_eq(sel_name, "allKeys")) {
                    unsigned int new_cid = g_next_coll_id++;
                    unsigned int i;
                    for (i = 0; i < g_coll_entry_count; i++) {
                        if (g_coll_entries[i].coll_id == cid) {
                            Value dummy = value_void();
                            coll_add(new_cid, g_coll_entries[i].key, dummy);
                        }
                    }
                    return value_from_id(coll_make_marker("NSArr:", new_cid));
                }

                /* [set containsObject:obj] → BOOL */
                if (cstr_eq(sel_name, "containsObject:") && arg_count >= 1) {
                    int idx = coll_find_by_key(cid, &keyword_args[0]);
                    return value_from_int(idx >= 0 ? 1 : 0);
                }

                /* [dict setObject:forKey: — alternate keyword arg parsing
                 * The selector "setObject:forKey:" has two keyword parts.
                 * keyword_args[0] is the object, keyword_args[1] is the key.
                 * This is already handled above. */

                /* [mutColl removeAllObjects] → remove all entries */
                if (cstr_eq(sel_name, "removeAllObjects")) {
                    coll_remove_all(cid);
                    return value_from_id(receiver);
                }

                /* [dict allValues] → array of values */
                if (cstr_eq(sel_name, "allValues")) {
                    unsigned int new_cid = g_next_coll_id++;
                    unsigned int i;
                    for (i = 0; i < g_coll_entry_count; i++) {
                        if (g_coll_entries[i].coll_id == cid) {
                            Value dummy = value_void();
                            coll_add(new_cid, g_coll_entries[i].value, dummy);
                        }
                    }
                    return value_from_id(coll_make_marker("NSArr:", new_cid));
                }

                /* [arr lastObject] → last element or nil */
                if (cstr_eq(sel_name, "lastObject")) {
                    unsigned int cnt = coll_count(cid);
                    if (cnt > 0) {
                        int idx = coll_get_nth(cid, cnt - 1);
                        if (idx >= 0) return g_coll_entries[idx].key;
                    }
                    return value_from_id((id)"(nil)");
                }

                /* [dict valueForKey:key] → same as objectForKey: */
                if (cstr_eq(sel_name, "valueForKey:") && arg_count >= 1) {
                    int idx = coll_find_by_key(cid, &keyword_args[0]);
                    if (idx >= 0) return g_coll_entries[idx].value;
                    return value_from_id((id)"(nil)");
                }

                /* [mutDict setValue:val forKey:key] → same as setObject:forKey: */
                if (cstr_eq(sel_name, "setValue:forKey:") && arg_count >= 2) {
                    Value val = keyword_args[0];
                    Value key = keyword_args[1];
                    int idx = coll_find_by_key(cid, &key);
                    if (idx >= 0) {
                        g_coll_entries[idx].value = val;
                    } else {
                        if (coll_add(cid, key, val) != 0) {
                            nslog_append("warning: collection entry table full\n", 38);
                        }
                    }
                    return value_from_id(receiver);
                }

                /* [arr enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) { ... }]
                 * The block argument is a block marker. We iterate the collection
                 * and invoke the block for each element. */
                if (cstr_eq(sel_name, "enumerateObjectsUsingBlock:") && arg_count >= 1) {
                    const char *blk_marker = (const char *)keyword_args[0].obj_val;
                    unsigned int bid = block_id_from_marker(blk_marker);
                    BlockImpl *blk = block_get(bid);
                    if (blk) {
                        unsigned int cnt = coll_count(cid);
                        unsigned int idx;
                        unsigned int saved_var_count = g_var_count;
                        for (idx = 0; idx < cnt; idx++) {
                            int entry_idx = coll_get_nth(cid, idx);
                            if (entry_idx < 0) break;

                            /* Restore captured variable values FIRST */
                            {
                                unsigned int ci;
                                for (ci = 0; ci < blk->capture_count; ci++) {
                                    InterpVar *cap_var = interp_get_or_create_var(blk->captures[ci].name);
                                    if (cap_var) {
                                        cap_var->is_id = blk->captures[ci].value.is_id;
                                        cap_var->value = blk->captures[ci].value.obj_val;
                                        cap_var->is_int = blk->captures[ci].value.is_int;
                                        cap_var->int_value = blk->captures[ci].value.int_val;
                                        cap_var->is_class = blk->captures[ci].value.is_class;
                                        cap_var->cls = blk->captures[ci].value.cls_val;
                                        cap_var->is_sel = blk->captures[ci].value.is_sel;
                                        cap_var->sel = blk->captures[ci].value.sel_val;
                                    }
                                }
                            }

                            /* Set up block argument variables (override captured) */
                            {
                                unsigned int ai;
                                for (ai = 0; ai < blk->arg_count; ai++) {
                                    InterpVar *arg_var = interp_get_or_create_var(blk->arg_names[ai]);
                                    if (arg_var) {
                                        if (ai == 0) {
                                            /* First arg: the object */
                                            arg_var->is_id = g_coll_entries[entry_idx].key.is_id;
                                            arg_var->value = g_coll_entries[entry_idx].key.obj_val;
                                            arg_var->is_int = g_coll_entries[entry_idx].key.is_int;
                                            arg_var->int_value = g_coll_entries[entry_idx].key.int_val;
                                            arg_var->is_class = g_coll_entries[entry_idx].key.is_class;
                                            arg_var->cls = g_coll_entries[entry_idx].key.cls_val;
                                            arg_var->is_sel = g_coll_entries[entry_idx].key.is_sel;
                                            arg_var->sel = g_coll_entries[entry_idx].key.sel_val;
                                        } else if (ai == 1) {
                                            /* Second arg: the index */
                                            arg_var->is_int = 1;
                                            arg_var->int_value = (int)idx;
                                            arg_var->is_id = 0;
                                        }
                                        /* Third arg (BOOL *stop) — we set up a 'stop' variable */
                                    }
                                }
                                /* Set up 'stop' variable for BOOL *stop */
                                {
                                    InterpVar *stop_var = interp_get_or_create_var("stop");
                                    if (stop_var) {
                                        stop_var->is_int = 1;
                                        stop_var->int_value = 0;
                                    }
                                }
                            }

                            /* Execute the block body */
                            g_return_pending = 0;
                            eval_source_range(0, blk->source_len, blk->source);

                            /* Check stop flag */
                            {
                                InterpVar *stop_var = interp_find_var("stop");
                                if (stop_var && stop_var->is_int && stop_var->int_value != 0) {
                                    break;
                                }
                            }

                            g_var_count = saved_var_count;
                        }
                    }
                    return value_from_id(receiver);
                }
            }
        }

        /* Check if this selector matches an interpreter-registered method.
         * Interpreter methods are executed directly in the interpreter to
         * avoid WASM calling convention issues with variadic IMP dispatch.
         * Match by: selector + class_ptr + is_class_method.
         * For class methods, target.is_class must be true and the method's
         * is_class_method must be 1. For instance methods, target.is_id
         * must be true (or target.is_class for alloc-init chain). */
        {
            unsigned int mi;
            int found = 0;
            for (mi = 0; mi < g_method_count; mi++) {
                if (g_methods[mi].selector != sel || g_methods[mi].source_len == 0) continue;

                /* Check class match */
                if (g_methods[mi].class_ptr != (Class)0) {
                    /* Method has a class restriction */
                    if (target.is_class && g_methods[mi].class_ptr == target.cls_val) {
                        /* OK — class method target matches */
                    } else if (target.is_id && receiver != 0 &&
                               cstr_starts((const char *)receiver, "FDObj:")) {
                        /* Receiver is an FDObj: marker — check class by name.
                         * Extract class name from FDObj:ClassName and look up
                         * the class pointer in the variable table. */
                        const char *recv_class_name = (const char *)receiver + 6;
                        Class recv_cls = 0;
                        {
                            unsigned int vi;
                            for (vi = 0; vi < g_var_count; vi++) {
                                if (g_vars[vi].is_class &&
                                    cstr_eq(g_vars[vi].name, recv_class_name)) {
                                    recv_cls = g_vars[vi].cls;
                                    break;
                                }
                            }
                        }
                        if (recv_cls != g_methods[mi].class_ptr) continue;
                    } else if (target.is_id && receiver != 0) {
                        /* Receiver might be a valid ObjC object — check class.
                         * If object_getClass returns 0 (e.g., WASM runtime
                         * doesn't track dynamically allocated classes), we
                         * still try the method — the selector match is
                         * usually sufficient for our interpreter. */
                        Class recv_cls = object_getClass(receiver);
                        if (recv_cls != 0 && g_methods[mi].class_ptr != recv_cls) continue;
                    } else {
                        continue; /* class mismatch */
                    }
                }

                /* Check class method vs instance method */
                if (g_methods[mi].is_class_method && target.is_class) {
                    found = 1; break; /* class method, called on class */
                }
                if (!g_methods[mi].is_class_method && (target.is_id || target.is_int)) {
                    found = 1; break; /* instance method, called on instance */
                }
            }

            if (found && mi < g_method_count) {
                /* Found an interpreter method — execute it directly */
                unsigned int saved_var_count = g_var_count;
                unsigned int saved_scope_base = g_var_scope_base;
                Value return_val;

                /* Set scope base to 0 so methods can access global variables
                 * (including ivars declared in @implementation bodies).
                 * Method-local variables are still isolated because we
                 * restore g_var_count after the method returns. */
                g_var_scope_base = 0;

                /* Set up self and _cmd as NEW variables in the method scope */
                {
                    InterpVar *var;
                    var = interp_get_or_create_var("self");
                    if (var) {
                        var->is_id = 1;
                        var->value = receiver;
                        var->is_int = 0;
                        var->is_class = 0;
                        var->is_sel = 0;
                    }
                    var = interp_get_or_create_var("_cmd");
                    if (var) {
                        var->is_sel = 1;
                        var->sel = sel;
                        var->is_int = 0;
                        var->is_class = 0;
                        var->is_id = 0;
                    }
                }

                /* Set up keyword argument variables from parsed args */
                {
                    unsigned int ai;
                    for (ai = 0; ai < g_methods[mi].arg_count && ai < 8 && ai < arg_count; ai++) {
                        InterpVar *var = interp_get_or_create_var(g_methods[mi].arg_names[ai]);
                        if (var) {
                            var->is_id = keyword_args[ai].is_id;
                            var->value = keyword_args[ai].obj_val;
                            var->is_int = keyword_args[ai].is_int;
                            var->int_value = keyword_args[ai].int_val;
                            var->is_class = keyword_args[ai].is_class;
                            var->cls = keyword_args[ai].cls_val;
                            var->is_sel = keyword_args[ai].is_sel;
                            var->sel = keyword_args[ai].sel_val;
                        }
                    }
                }

                /* Inject synthesized ivar values as variables so method
                 * bodies can access them (e.g., _count in increment). */
                {
                    unsigned int pi;
                    for (pi = 0; pi < g_property_count; pi++) {
                        if (g_properties[pi].synthesized &&
                            g_properties[pi].ivar_name[0] != '\0') {
                            InterpVar *ivar_var = interp_get_or_create_var(g_properties[pi].ivar_name);
                            if (ivar_var) {
                                Value *stored = instance_var_get(receiver, g_properties[pi].name);
                                if (stored) {
                                    ivar_var->is_id = stored->is_id;
                                    ivar_var->value = stored->obj_val;
                                    ivar_var->is_int = stored->is_int;
                                    ivar_var->int_value = stored->int_val;
                                    ivar_var->is_class = stored->is_class;
                                    ivar_var->cls = stored->cls_val;
                                    ivar_var->is_sel = stored->is_sel;
                                    ivar_var->sel = stored->sel_val;
                                } else {
                                    /* No value yet — default to 0 */
                                    ivar_var->is_int = g_properties[pi].is_int;
                                    ivar_var->int_value = 0;
                                    ivar_var->is_id = !g_properties[pi].is_int;
                                    ivar_var->value = 0;
                                    ivar_var->is_class = 0;
                                    ivar_var->is_sel = 0;
                                }
                            }
                        }
                    }
                }

                /* Execute the method body.
                 * Use eval_source_range instead of objc_interp to avoid
                 * destroying the caller's AST (objc_interp resets g_ast_count). */
                g_return_pending = 0;
                {
                    Value v = eval_source_range(0, g_methods[mi].source_len, g_methods[mi].source);
                    (void)v;
                }

                /* Write back synthesized ivar values to the side table */
                {
                    unsigned int pi;
                    for (pi = 0; pi < g_property_count; pi++) {
                        if (g_properties[pi].synthesized &&
                            g_properties[pi].ivar_name[0] != '\0') {
                            InterpVar *ivar_var = interp_find_var(g_properties[pi].ivar_name);
                            if (ivar_var) {
                                Value ivar_val;
                                ivar_val.obj_val = ivar_var->value;
                                ivar_val.cls_val = ivar_var->cls;
                                ivar_val.sel_val = ivar_var->sel;
                                ivar_val.int_val = ivar_var->int_value;
                                ivar_val.is_int = ivar_var->is_int;
                                ivar_val.is_class = ivar_var->is_class;
                                ivar_val.is_sel = ivar_var->is_sel;
                                ivar_val.is_id = ivar_var->is_id;
                                ivar_val.is_void = 0;
                                if (instance_var_set(receiver, g_properties[pi].name, ivar_val) != 0) {
                                    parser_error(p, "instance variable table full (max 256)");
                                }
                            }
                        }
                    }
                }

                /* Determine return value */
                if (g_return_pending) {
                    if (g_return_value.is_id) return_val = value_from_id(g_return_value.obj_val);
                    else if (g_return_value.is_class) return_val = value_from_class(g_return_value.cls_val);
                    else if (g_return_value.is_int) return_val = g_return_value;
                    else return_val = value_from_id(receiver);
                } else {
                    return_val = value_from_id(receiver);
                }

                /* Clean up method-local variables and restore scope */
                g_var_count = saved_var_count;
                g_var_scope_base = saved_scope_base;
                g_return_pending = 0;

                return return_val;
            }
        }

        /* ── Property dispatch (via instance variable side table) ──────
         * Synthesized properties are stored per-instance in g_instance_vars[].
         * This dispatch runs AFTER interpreter methods, so user-defined
         * methods override synthesized properties. */
        {
            /* Check if this selector matches a synthesized property getter.
             * A getter has the same selector name as the property. */
            unsigned int pi;
            for (pi = 0; pi < g_property_count; pi++) {
                if (g_properties[pi].synthesized &&
                    cstr_eq(sel_name, g_properties[pi].name)) {
                    /* It's a getter — look up in side table */
                    if (target.is_id && receiver != 0) {
                        Value *stored = instance_var_get(receiver, g_properties[pi].name);
                        if (stored) {
                            result = *stored;
                            return result;
                        }
                    }
                    /* No value stored yet — return default (0 for int, nil for id) */
                    if (g_properties[pi].is_int) {
                        result = value_from_int(0);
                    } else {
                        result = value_from_id(0);
                    }
                    return result;
                }
            }

            /* Check if this selector matches a synthesized property setter.
             * A setter has selector "set<PropName>:" — we check by building
             * the expected setter selector from each property name. */
            if (cstr_eq_n(sel_name, "set", 3) && sel_name[cstr_len(sel_name) - 1] == ':') {
                /* Extract property name from "setPropName:" → "propName"
                 * (lowercase first letter of PropName) */
                char prop_from_setter[64];
                unsigned int si = 3; /* skip "set" */
                unsigned int pi2 = 0;
                unsigned int sel_len = cstr_len(sel_name);
                /* The last char is ':', so the property name is from index 3 to sel_len-1 */
                if (si < sel_len - 1) {
                    /* Lowercase first letter */
                    if (sel_name[si] >= 'A' && sel_name[si] <= 'Z') {
                        prop_from_setter[pi2++] = sel_name[si] - 'A' + 'a';
                    } else {
                        prop_from_setter[pi2++] = sel_name[si];
                    }
                    si++;
                    while (si < sel_len - 1 && pi2 < 63) {
                        prop_from_setter[pi2++] = sel_name[si++];
                    }
                    prop_from_setter[pi2] = '\0';

                    /* Find matching property */
                    for (pi = 0; pi < g_property_count; pi++) {
                        if (g_properties[pi].synthesized &&
                            cstr_eq(prop_from_setter, g_properties[pi].name)) {
                            /* It's a setter — store in side table */
                            if (target.is_id && receiver != 0 && arg_count >= 1) {
                                Value val;
                                if (g_properties[pi].is_int) {
                                    val = value_from_int(keyword_args[0].is_int ? keyword_args[0].int_val : 0);
                                } else {
                                    val = keyword_args[0];
                                }
                                if (instance_var_set(receiver, g_properties[pi].name, val) != 0) {
                                    parser_error(p, "instance variable table full (max 256)");
                                }
                            }
                            result = value_from_id(receiver);
                            return result;
                        }
                    }
                }
            }
        }

        /* Fall through: no built-in, interpreter method, or property matched.
         * Runtime IMP dispatch is not used because WASM enforces exact
         * function signatures — variadic IMP calls cause signature
         * mismatch traps. All supported methods must be handled as
         * built-ins or interpreter-registered methods above. */
        {
            const char *cls_name = "unknown";
            if (target_class_name) {
                cls_name = target_class_name;
            }
            /* Don't call object_getClass on id targets — the pointer
             * might be a C string from the string pool, which would crash. */
            nslog_append("-", 1);
            nslog_append("[", 1);
            nslog_append(cls_name, cstr_len(cls_name));
            nslog_append(" ", 1);
            nslog_append(sel_name, cstr_len(sel_name));
            nslog_append("] does not respond to selector\n", 31);
            result = value_from_id(0);
            return result;
        }
    }
}

/* ── @interface / @implementation ────────────────────────────────── */

/* Parse @interface Name : SuperClass { ivars } methodDecls @end */
static Value parse_interface(Parser *p) {
    char class_name[64];
    char super_name[64];
    Class super_class;
    Class new_class;

    /* Expect class name */
    if (parser_current(p).type != TOK_IDENTIFIER) {
        parser_error(p, "Expected class name after @interface");
        return value_void();
    }
    cstr_copy(class_name, parser_current(p).text, 64);
    parser_advance(p);

    /* Parse : SuperClass */
    super_name[0] = '\0';
    super_class = 0;
    if (parser_current(p).type == TOK_COLON) {
        parser_advance(p);
        if (parser_current(p).type == TOK_IDENTIFIER) {
            cstr_copy(super_name, parser_current(p).text, 64);
            parser_advance(p);
            /* Look up the superclass in our variable table first,
             * then fall back to the runtime */
            {
                InterpVar *var = interp_find_var(super_name);
                if (var && var->is_class) {
                    super_class = var->cls;
                } else {
                    /* Only call objc_getClass if the runtime has been
                     * seeded with classes — calling it on an empty
                     * class table causes a division-by-zero */
                    super_class = 0; /* no superclass for now */
                }
            }
        }
    }

    /* Allocate the class pair.
     * In WASM, objc_allocateClassPair causes memory access out of bounds,
     * so we use sentinel class pointers (like Foundation classes).
     * Custom classes get pointers starting at 100 to avoid collisions
     * with Foundation sentinels (1-9). */
    {
        static unsigned int custom_class_id = 100;
        new_class = (Class)(unsigned long)custom_class_id++;
    }

    /* Parse instance variables { ... } */
    if (parser_current(p).type == TOK_OPEN_BRACE) {
        parser_advance(p);
        while (parser_current(p).type != TOK_CLOSE_BRACE &&
               parser_current(p).type != TOK_EOF) {
            /* Skip ivar declarations — we just consume tokens */
            parser_advance(p);
        }
        if (parser_current(p).type == TOK_CLOSE_BRACE) {
            parser_advance(p);
        }
    }

    /* Parse method declarations until @end */
    while (parser_current(p).type != TOK_AT_KEYWORD ||
           !cstr_eq(parser_current(p).text, "@end")) {
        if (parser_current(p).type == TOK_EOF) break;

        /* @property (attributes) type name; */
        if (parser_current(p).type == TOK_AT_KEYWORD &&
            cstr_eq(parser_current(p).text, "@property")) {
            parser_advance(p);

            /* Skip attributes in parens: (nonatomic, assign, strong, weak, copy, readonly, readwrite) */
            if (parser_current(p).type == TOK_OPEN_PAREN) {
                int depth = 1;
                parser_advance(p);
                while (depth > 0 && parser_current(p).type != TOK_EOF) {
                    if (parser_current(p).type == TOK_OPEN_PAREN) depth++;
                    else if (parser_current(p).type == TOK_CLOSE_PAREN) depth--;
                    parser_advance(p);
                }
            }

            /* Parse type and property name */
            if (parser_current(p).type == TOK_IDENTIFIER) {
                if (g_property_count >= 64) {
                    parser_error(p, "property table full (max 64 properties)");
                    /* skip until semicolon or close paren */
                    while (parser_current(p).type != TOK_SEMICOLON && parser_current(p).type != TOK_CLOSE_PAREN && parser_current(p).type != TOK_EOF) {
                        parser_advance(p);
                    }
                    continue;
                }
                PropertyDecl *prop = &g_properties[g_property_count];
                cstr_copy(prop->type_name, parser_current(p).text, 64);
                prop->is_int = cstr_eq(prop->type_name, "int") ||
                               cstr_eq(prop->type_name, "BOOL") ||
                               cstr_eq(prop->type_name, "long") ||
                               cstr_eq(prop->type_name, "char");
                cstr_copy(prop->class_name, class_name, 64);
                parser_advance(p);

                /* Skip pointer * */
                while (parser_current(p).type == TOK_STAR) {
                    parser_advance(p);
                }

                /* Property name */
                if (parser_current(p).type == TOK_IDENTIFIER) {
                    cstr_copy(prop->name, parser_current(p).text, 64);
                    parser_advance(p);
                    g_property_count++;
                }
            }

            if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
            continue;
        }

        /* Parse method declaration: - (returntype)selector:argtype argname ... */
        if (parser_current(p).type == TOK_MINUS || parser_current(p).type == TOK_PLUS) {
            parser_advance(p); /* skip - or + */

            /* Skip return type in parens */
            if (parser_current(p).type == TOK_OPEN_PAREN) {
                int depth = 1;
                parser_advance(p);
                while (depth > 0 && parser_current(p).type != TOK_EOF) {
                    if (parser_current(p).type == TOK_OPEN_PAREN) depth++;
                    else if (parser_current(p).type == TOK_CLOSE_PAREN) depth--;
                    parser_advance(p);
                }
            }

            /* Parse selector name */
            if (parser_current(p).type == TOK_IDENTIFIER) {
                parser_advance(p);
            }

            /* Skip remaining method declaration */
            while (parser_current(p).type != TOK_SEMICOLON &&
                   parser_current(p).type != TOK_AT_KEYWORD &&
                   parser_current(p).type != TOK_EOF) {
                parser_advance(p);
            }
            if (parser_current(p).type == TOK_SEMICOLON) {
                parser_advance(p);
            }
        } else {
            parser_advance(p);
        }
    }

    /* Expect @end */
    if (parser_current(p).type == TOK_AT_KEYWORD && cstr_eq(parser_current(p).text, "@end")) {
        parser_advance(p);
    }

    /* Register the class.
     * In WASM, objc_registerClassPair crashes on sentinel pointers,
     * so we skip it — our interpreter dispatches by name, not by
     * the runtime class table. */
    /* objc_registerClassPair(new_class); */

    /* Track the class in the variable table so it can be found by name */
    {
        InterpVar *var = interp_get_or_create_var(class_name);
        if (var) {
            var->is_class = 1;
            var->cls = new_class;
        }
    }

    return value_from_class(new_class);
}

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
        Value v = eval_source_range(0, g_methods[i].source_len, g_methods[i].source);
        (void)v; /* errors are captured in g_error_buffer */
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
static Value parse_implementation(Parser *p) {
    char class_name[64];
    Class cls;

    /* Expect class name */
    if (parser_current(p).type != TOK_IDENTIFIER) {
        parser_error(p, "Expected class name after @implementation");
        return value_void();
    }
    cstr_copy(class_name, parser_current(p).text, 64);
    parser_advance(p);

    cls = (Class)objc_getClass(class_name);
    if (cls == 0) {
        /* Check our variable table for the class */
        InterpVar *var = interp_find_var(class_name);
        if (var && var->is_class) {
            cls = var->cls;
        }
    }
    if (cls == 0) {
        parser_error(p, "Class not found for @implementation");
        return value_void();
    }

    /* Parse method definitions until @end */
    while (parser_current(p).type != TOK_AT_KEYWORD ||
           !cstr_eq(parser_current(p).text, "@end")) {
        if (parser_current(p).type == TOK_EOF) break;

        /* @synthesize prop = _ivar; or @synthesize prop; */
        if (parser_current(p).type == TOK_AT_KEYWORD &&
            cstr_eq(parser_current(p).text, "@synthesize")) {
            parser_advance(p);

            while (parser_current(p).type != TOK_SEMICOLON &&
                   parser_current(p).type != TOK_EOF) {
                if (parser_current(p).type == TOK_IDENTIFIER) {
                    char prop_name[64];
                    cstr_copy(prop_name, parser_current(p).text, 64);
                    parser_advance(p);

                    /* Parse = _ivar — store the ivar name for method body access */
                    if (parser_current(p).type == TOK_ASSIGN) {
                        parser_advance(p);
                        if (parser_current(p).type == TOK_IDENTIFIER) {
                            char ivar_name[64];
                            cstr_copy(ivar_name, parser_current(p).text, 64);
                            parser_advance(p);
                            /* Store ivar name in the property declaration */
                            {
                                unsigned int pi;
                                for (pi = 0; pi < g_property_count; pi++) {
                                    if (cstr_eq(g_properties[pi].name, prop_name) &&
                                        cstr_eq(g_properties[pi].class_name, class_name)) {
                                        cstr_copy(g_properties[pi].ivar_name, ivar_name, 64);
                                        break;
                                    }
                                }
                            }
                        }
                    }

                    /* Mark the property as synthesized — enables
                     * property dispatch via the instance variable
                     * side table in parse_message_send. */
                    {
                        unsigned int pi;
                        for (pi = 0; pi < g_property_count; pi++) {
                            if (cstr_eq(g_properties[pi].name, prop_name) &&
                                cstr_eq(g_properties[pi].class_name, class_name)) {
                                g_properties[pi].synthesized = 1;
                                break;
                            }
                        }
                    }

                    /* Skip comma between multiple synthesize declarations */
                    if (parser_current(p).type == TOK_COMMA) {
                        parser_advance(p);
                    }
                } else {
                    parser_advance(p);
                }
            }
            if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
            continue;
        }

        /* Variable declaration inside @implementation (e.g., int _ivar;) */
        if (parser_current(p).type == TOK_IDENTIFIER) {
            Token saved = p->lex.current;
            unsigned int saved_pos = p->lex.pos;
            Token next;

            /* Check if this looks like a type declaration */
            {
                int is_builtin = (
                    cstr_eq(parser_current(p).text, "int") ||
                    cstr_eq(parser_current(p).text, "void") ||
                    cstr_eq(parser_current(p).text, "id") ||
                    cstr_eq(parser_current(p).text, "Class") ||
                    cstr_eq(parser_current(p).text, "SEL") ||
                    cstr_eq(parser_current(p).text, "BOOL") ||
                    cstr_eq(parser_current(p).text, "long") ||
                    cstr_eq(parser_current(p).text, "char") ||
                    cstr_eq(parser_current(p).text, "float") ||
                    cstr_eq(parser_current(p).text, "double")
                );

                if (is_builtin) {
                    /* Parse as type+variable declaration */
                    Value v = parse_type_and_var_decl(p);
                    if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
                    continue;
                }
            }
        }

        /* Method definition: - (returntype)selector:argtype argname { body } */
        if (parser_current(p).type == TOK_MINUS || parser_current(p).type == TOK_PLUS) {
            int is_class_method = (parser_current(p).type == TOK_PLUS);
            char sel_name[256];
            unsigned int sel_len = 0;
            char type_encoding[64];
            char arg_names[8][64];
            unsigned int arg_count = 0;
            unsigned int body_start = 0;
            unsigned int body_len = 0;

            parser_advance(p); /* skip - or + */

            /* Skip return type in parens */
            type_encoding[0] = '@';
            type_encoding[1] = '\0';
            if (parser_current(p).type == TOK_OPEN_PAREN) {
                int depth = 1;
                parser_advance(p);
                while (depth > 0 && parser_current(p).type != TOK_EOF) {
                    if (parser_current(p).type == TOK_OPEN_PAREN) depth++;
                    else if (parser_current(p).type == TOK_CLOSE_PAREN) depth--;
                    parser_advance(p);
                }
            }

            /* Parse selector name */
            sel_name[0] = '\0';
            sel_len = 0;
            if (parser_current(p).type == TOK_IDENTIFIER) {
                cstr_copy(sel_name, parser_current(p).text, 256);
                sel_len = cstr_len(sel_name);
                parser_advance(p);
            }

            /* Parse keyword arguments — capture argument names.
             * Pattern: selectorPart: (type) argName selectorPart: (type) argName ...
             * The first selector part was already consumed above. */
            arg_count = 0;

            /* If the first part already has a colon (consumed above as part
             * of the initial identifier), handle the first keyword arg. */
            if (sel_len > 0 && sel_name[sel_len - 1] == ':') {
                /* Already have a trailing colon from the initial selector */
            } else if (parser_current(p).type == TOK_COLON) {
                parser_advance(p); /* skip : */
                sel_name[sel_len++] = ':';
                sel_name[sel_len] = '\0';
            }

            /* Now loop: parse (type) argName, then check for next keyword part */
            while (sel_len > 0 && sel_name[sel_len - 1] == ':') {
                /* Skip argument type in parens */
                if (parser_current(p).type == TOK_OPEN_PAREN) {
                    int depth = 1;
                    parser_advance(p);
                    while (depth > 0 && parser_current(p).type != TOK_EOF) {
                        if (parser_current(p).type == TOK_OPEN_PAREN) depth++;
                        else if (parser_current(p).type == TOK_CLOSE_PAREN) depth--;
                        parser_advance(p);
                    }
                }

                /* Capture argument name */
                if (parser_current(p).type == TOK_IDENTIFIER && arg_count < 8) {
                    cstr_copy(arg_names[arg_count], parser_current(p).text, 64);
                    arg_count++;
                    parser_advance(p);
                }

                /* Check for next keyword selector part: identifier followed by : */
                if (parser_current(p).type == TOK_IDENTIFIER) {
                    /* Look ahead: is the next token a colon? */
                    Token saved = p->lex.current;
                    unsigned int saved_pos = p->lex.pos;
                    unsigned int saved_token_start = p->lex.token_start;
                    parser_advance(p);

                    if (parser_current(p).type == TOK_COLON) {
                        /* This is a keyword selector part.
                         * We've already advanced past the identifier and
                         * loaded the colon as current. Now skip the colon
                         * and add both parts to the selector. */
                        cstr_copy(sel_name + sel_len, saved.text, 256 - sel_len);
                        sel_len += cstr_len(saved.text);
                        parser_advance(p); /* skip : (load next token) */
                        sel_name[sel_len++] = ':';
                        sel_name[sel_len] = '\0';
                        continue; /* loop to parse this arg's type and name */
                    }

                    /* Not a keyword part — restore */
                    p->lex.current = saved;
                    p->lex.pos = saved_pos;
                    p->lex.token_start = saved_token_start;
                }

                break; /* No more keyword parts */
            }

            /* Parse method body { ... } — capture the source */
            if (parser_current(p).type == TOK_OPEN_BRACE) {
                int brace_depth = 1;
                parser_advance(p); /* skip opening { */
                body_start = p->lex.token_start; /* start of first body token */

                while (brace_depth > 0 && parser_current(p).type != TOK_EOF) {
                    if (parser_current(p).type == TOK_OPEN_BRACE) brace_depth++;
                    else if (parser_current(p).type == TOK_CLOSE_BRACE) {
                        brace_depth--;
                        if (brace_depth == 0) break;
                    }
                    parser_advance(p);
                }

                /* body_len: from body_start to the start of the closing } */
                body_len = p->lex.token_start - body_start;

                if (parser_current(p).type == TOK_CLOSE_BRACE) {
                    parser_advance(p);
                }
            }

            /* Store the method — skip class_addMethod in WASM (crashes on
             * sentinel pointers). Our interpreter dispatches by selector
             * match in g_methods[], not through the runtime. */
            {
                SEL sel = sel_registerName(sel_name);
                /* class_addMethod(cls, sel, (void *)method_impl_trampoline, type_encoding); */

                /* Store method body and argument names for trampoline execution */
                if (g_method_count < MAX_METHODS && body_len > 0) {
                    MethodImpl *mi = &g_methods[g_method_count];
                    unsigned int copy_len = body_len;
                    if (copy_len >= 2048) copy_len = 2047;
                    /* Copy body source (content between the braces) */
                    cstr_copy(mi->source, p->lex.source + body_start, 2048);
                    mi->source_len = copy_len;
                    mi->class_ptr = cls;
                    mi->selector = sel;
                    mi->is_class_method = is_class_method;
                    mi->arg_count = arg_count;
                    {
                        unsigned int ai;
                        for (ai = 0; ai < arg_count && ai < 8; ai++) {
                            cstr_copy(mi->arg_names[ai], arg_names[ai], 64);
                        }
                    }
                    g_method_count++;
                } else if (g_method_count >= MAX_METHODS) {
                    parser_error(p, "method table full (max 64 methods)");
                }
            }
        } else {
            parser_advance(p);
        }
    }

    /* Expect @end */
    if (parser_current(p).type == TOK_AT_KEYWORD && cstr_eq(parser_current(p).text, "@end")) {
        parser_advance(p);
    }

    return value_from_class(cls);
}

/* ── Expression parser ──────────────────────────────────────────── */

static Value parse_primary(Parser *p) {
    Token tok = parser_current(p);

    /* String literal @"..." */
    if (tok.type == TOK_STRING_LITERAL) {
        /* Store the string in a global pool and return as id.
         * The token text includes the @ prefix for @"..." literals.
         * We skip it when storing in the pool. */
        parser_advance(p);
        {
            const char *text = tok.text;
            unsigned int skip_at = (text[0] == '@') ? 1 : 0;
            const char *content = text + skip_at;
            unsigned int len = cstr_len(content);
            char *str_ptr = string_pool_alloc(len + 1);
            if (str_ptr == 0) {
                parser_error(p, "string pool exhausted — restart kernel");
                return value_void();
            }
            cstr_copy(str_ptr, content, len + 1);
            return value_from_id((id)str_ptr);
        }
    }

    /* Integer literal */
    if (tok.type == TOK_INT_LITERAL) {
        int val = 0;
        unsigned int i = 0;
        while (tok.text[i] != '\0') {
            val = val * 10 + (tok.text[i] - '0');
            i++;
        }
        parser_advance(p);
        return value_from_int(val);
    }

    /* Message send [target selector:arg ...] */
    if (tok.type == TOK_OPEN_BRACKET) {
        parser_advance(p);
        /* Depth check: each nested [ ] message send counts as one level.
         * parse_message_send will also call parse_expression_safe for
         * the target, but we count here too so that [[...]] nesting
         * increments depth by 2 per level (primary + safe wrapper). */
        if (g_parse_depth >= MAX_PARSE_DEPTH) {
            parser_error(p, "expression too deeply nested (max 64 levels)");
            return value_void();
        }
        g_parse_depth++;
        {
            Value result = parse_message_send(p);
            g_parse_depth--;
            return result;
        }
    }

    /* Parenthesized expression */
    if (tok.type == TOK_OPEN_PAREN) {
        parser_advance(p);
        {
            Value v = parse_expression_safe(p);
            if (p->error) return v;
            parser_expect(p, TOK_CLOSE_PAREN);
            return v;
        }
    }

    /* Identifier — could be a variable, class name, or NSLog */
    if (tok.type == TOK_IDENTIFIER) {
        /* Check for NSLog */
        if (cstr_eq(tok.text, "NSLog")) {
            parser_advance(p);
            if (parser_current(p).type == TOK_OPEN_PAREN) {
                parser_advance(p);
                eval_nslog(p);
            }
            return value_void();
        }

        /* Check for sel_registerName */
        if (cstr_eq(tok.text, "sel_registerName")) {
            parser_advance(p);
            if (parser_current(p).type == TOK_OPEN_PAREN) {
                parser_advance(p);
                if (parser_current(p).type == TOK_STRING_LITERAL) {
                    SEL sel = sel_registerName(parser_current(p).text);
                    parser_advance(p);
                    parser_expect(p, TOK_CLOSE_PAREN);
                    return value_from_sel(sel);
                }
            }
            return value_void();
        }

        /* Check for objc_getClass */
        if (cstr_eq(tok.text, "objc_getClass")) {
            parser_advance(p);
            if (parser_current(p).type == TOK_OPEN_PAREN) {
                parser_advance(p);
                if (parser_current(p).type == TOK_STRING_LITERAL) {
                    Class cls = (Class)objc_getClass(parser_current(p).text);
                    parser_advance(p);
                    parser_expect(p, TOK_CLOSE_PAREN);
                    return value_from_class(cls);
                }
            }
            return value_void();
        }

        /* Look up variable */
        {
            InterpVar *var = interp_find_var(tok.text);
            if (var) {
                parser_advance(p);

                /* Post-increment/decrement: i++, i-- */
                if (parser_current(p).type == TOK_PLUS_PLUS && var->is_int) {
                    int old_val = var->int_value;
                    var->int_value++;
                    parser_advance(p);
                    return value_from_int(old_val);
                }
                if (parser_current(p).type == TOK_MINUS_MINUS && var->is_int) {
                    int old_val = var->int_value;
                    var->int_value--;
                    parser_advance(p);
                    return value_from_int(old_val);
                }

                /* Dot syntax: obj.property → [obj property]
                 *             obj.property = value → [obj setProperty:value] */
                if (parser_current(p).type == TOK_DOT && !var->is_int) {
                    char prop_name[64];
                    char setter_name[128];
                    parser_advance(p); /* consume . */

                    if (parser_current(p).type != TOK_IDENTIFIER) {
                        parser_error(p, "Expected property name after '.'");
                        return value_void();
                    }

                    cstr_copy(prop_name, parser_current(p).text, 64);
                    parser_advance(p);

                    /* Check for setter: obj.prop = value */
                    if (parser_current(p).type == TOK_ASSIGN) {
                        parser_advance(p);
                        {
                            Value val = parse_expression_safe(p);
                            if (p->error) return val;

                            /* Build setter selector: setProperty: */
                            setter_name[0] = 's';
                            setter_name[1] = 'e';
                            setter_name[2] = 't';
                            {
                                unsigned int pi = 0;
                                unsigned int si = 3;
                                /* Capitalize first letter of property */
                                if (prop_name[0] >= 'a' && prop_name[0] <= 'z') {
                                    setter_name[si++] = prop_name[0] - 'a' + 'A';
                                    pi = 1;
                                }
                                while (prop_name[pi] && si < 126) {
                                    setter_name[si++] = prop_name[pi++];
                                }
                                setter_name[si++] = ':';
                                setter_name[si] = '\0';
                            }

                            /* Dispatch setter as message send */
                            {
                                SEL setter_sel = sel_registerName(setter_name);
                                id receiver = var->is_id ? var->value : (id)var->cls;
                                unsigned int mi;
                                for (mi = 0; mi < g_method_count; mi++) {
                                    if (g_methods[mi].selector == setter_sel && g_methods[mi].source_len > 0 &&
                                        !g_methods[mi].is_class_method) {
                                        break;
                                    }
                                }
                                if (mi < g_method_count) {
                                    /* Execute setter method body */
                                    unsigned int saved_var_count = g_var_count;
                                    unsigned int saved_scope_base = g_var_scope_base;
                                    g_var_scope_base = 0; /* allow access to global vars */
                                    InterpVar *self_var = interp_get_or_create_var("self");
                                    if (self_var) {
                                        self_var->is_id = 1;
                                        self_var->value = receiver;
                                    }
                                    {
                                        InterpVar *cmd_var = interp_get_or_create_var("_cmd");
                                        if (cmd_var) {
                                            cmd_var->is_sel = 1;
                                            cmd_var->sel = setter_sel;
                                        }
                                    }
                                    /* Set first arg variable */
                                    if (g_methods[mi].arg_count > 0) {
                                        InterpVar *arg_var = interp_get_or_create_var(g_methods[mi].arg_names[0]);
                                        if (arg_var) {
                                            arg_var->is_id = val.is_id;
                                            arg_var->value = val.obj_val;
                                            arg_var->is_int = val.is_int;
                                            arg_var->int_value = val.int_val;
                                            arg_var->is_class = val.is_class;
                                            arg_var->cls = val.cls_val;
                                            arg_var->is_sel = val.is_sel;
                                            arg_var->sel = val.sel_val;
                                        }
                                    }
                                    /* Inject synthesized ivar values */
                                    {
                                        unsigned int pi;
                                        for (pi = 0; pi < g_property_count; pi++) {
                                            if (g_properties[pi].synthesized &&
                                                g_properties[pi].ivar_name[0] != '\0') {
                                                InterpVar *ivar_var = interp_get_or_create_var(g_properties[pi].ivar_name);
                                                if (ivar_var) {
                                                    Value *stored = instance_var_get(receiver, g_properties[pi].name);
                                                    if (stored) {
                                                        ivar_var->is_id = stored->is_id;
                                                        ivar_var->value = stored->obj_val;
                                                        ivar_var->is_int = stored->is_int;
                                                        ivar_var->int_value = stored->int_val;
                                                        ivar_var->is_class = stored->is_class;
                                                        ivar_var->cls = stored->cls_val;
                                                        ivar_var->is_sel = stored->is_sel;
                                                        ivar_var->sel = stored->sel_val;
                                                    } else {
                                                        ivar_var->is_int = g_properties[pi].is_int;
                                                        ivar_var->int_value = 0;
                                                        ivar_var->is_id = !g_properties[pi].is_int;
                                                        ivar_var->value = 0;
                                                        ivar_var->is_class = 0;
                                                        ivar_var->is_sel = 0;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    g_return_pending = 0;
                                    {
                                        Value v = eval_source_range(0, g_methods[mi].source_len, g_methods[mi].source);
                                        (void)v;
                                    }
                                    /* Write back synthesized ivar values */
                                    {
                                        unsigned int pi;
                                        for (pi = 0; pi < g_property_count; pi++) {
                                            if (g_properties[pi].synthesized &&
                                                g_properties[pi].ivar_name[0] != '\0') {
                                                InterpVar *ivar_var = interp_find_var(g_properties[pi].ivar_name);
                                                if (ivar_var) {
                                                    Value ivar_val;
                                                    ivar_val.obj_val = ivar_var->value;
                                                    ivar_val.cls_val = ivar_var->cls;
                                                    ivar_val.sel_val = ivar_var->sel;
                                                    ivar_val.int_val = ivar_var->int_value;
                                                    ivar_val.is_int = ivar_var->is_int;
                                                    ivar_val.is_class = ivar_var->is_class;
                                                    ivar_val.is_sel = ivar_var->is_sel;
                                                    ivar_val.is_id = ivar_var->is_id;
                                                    ivar_val.is_void = 0;
                                                    if (instance_var_set(receiver, g_properties[pi].name, ivar_val) != 0) {
                                    parser_error(p, "instance variable table full (max 256)");
                                }
                                                }
                                            }
                                        }
                                    }
                                    g_var_count = saved_var_count;
                                    g_var_scope_base = saved_scope_base;
                                    g_return_pending = 0;
                                } else {
                                    /* No method found — check for @synthesize property */
                                    unsigned int pi;
                                    for (pi = 0; pi < g_property_count; pi++) {
                                        if (g_properties[pi].synthesized &&
                                            cstr_eq(prop_name, g_properties[pi].name)) {
                                            /* Store in side table */
                                            if (instance_var_set(receiver, g_properties[pi].name, val) != 0) {
                                    parser_error(p, "instance variable table full (max 256)");
                                }
                                            break;
                                        }
                                    }
                                }
                                return val;
                            }
                        }
                    }

                    /* Getter: obj.property → [obj property] */
                    {
                        SEL prop_sel = sel_registerName(prop_name);
                        id receiver = var->is_id ? var->value : (id)var->cls;
                        unsigned int mi;
                        for (mi = 0; mi < g_method_count; mi++) {
                            if (g_methods[mi].selector == prop_sel && g_methods[mi].source_len > 0 &&
                                !g_methods[mi].is_class_method) {
                                break;
                            }
                        }
                        if (mi < g_method_count) {
                            /* Execute getter method body */
                            unsigned int saved_var_count = g_var_count;
                            unsigned int saved_scope_base = g_var_scope_base;
                            Value return_val;
                            g_var_scope_base = 0; /* allow access to global vars */
                            InterpVar *self_var = interp_get_or_create_var("self");
                            if (self_var) {
                                self_var->is_id = 1;
                                self_var->value = receiver;
                            }
                            {
                                InterpVar *cmd_var = interp_get_or_create_var("_cmd");
                                if (cmd_var) {
                                    cmd_var->is_sel = 1;
                                    cmd_var->sel = prop_sel;
                                }
                            }
                            /* Inject synthesized ivar values */
                            {
                                unsigned int pi;
                                for (pi = 0; pi < g_property_count; pi++) {
                                    if (g_properties[pi].synthesized &&
                                        g_properties[pi].ivar_name[0] != '\0') {
                                        InterpVar *ivar_var = interp_get_or_create_var(g_properties[pi].ivar_name);
                                        if (ivar_var) {
                                            Value *stored = instance_var_get(receiver, g_properties[pi].name);
                                            if (stored) {
                                                ivar_var->is_id = stored->is_id;
                                                ivar_var->value = stored->obj_val;
                                                ivar_var->is_int = stored->is_int;
                                                ivar_var->int_value = stored->int_val;
                                                ivar_var->is_class = stored->is_class;
                                                ivar_var->cls = stored->cls_val;
                                                ivar_var->is_sel = stored->is_sel;
                                                ivar_var->sel = stored->sel_val;
                                            } else {
                                                ivar_var->is_int = g_properties[pi].is_int;
                                                ivar_var->int_value = 0;
                                                ivar_var->is_id = !g_properties[pi].is_int;
                                                ivar_var->value = 0;
                                                ivar_var->is_class = 0;
                                                ivar_var->is_sel = 0;
                                            }
                                        }
                                    }
                                }
                            }
                            g_return_pending = 0;
                            {
                                Value v = eval_source_range(0, g_methods[mi].source_len, g_methods[mi].source);
                                (void)v;
                            }
                            /* Write back synthesized ivar values */
                            {
                                unsigned int pi;
                                for (pi = 0; pi < g_property_count; pi++) {
                                    if (g_properties[pi].synthesized &&
                                        g_properties[pi].ivar_name[0] != '\0') {
                                        InterpVar *ivar_var = interp_find_var(g_properties[pi].ivar_name);
                                        if (ivar_var) {
                                            Value ivar_val;
                                            ivar_val.obj_val = ivar_var->value;
                                            ivar_val.cls_val = ivar_var->cls;
                                            ivar_val.sel_val = ivar_var->sel;
                                            ivar_val.int_val = ivar_var->int_value;
                                            ivar_val.is_int = ivar_var->is_int;
                                            ivar_val.is_class = ivar_var->is_class;
                                            ivar_val.is_sel = ivar_var->is_sel;
                                            ivar_val.is_id = ivar_var->is_id;
                                            ivar_val.is_void = 0;
                                            if (instance_var_set(receiver, g_properties[pi].name, ivar_val) != 0) {
                                    parser_error(p, "instance variable table full (max 256)");
                                }
                                        }
                                    }
                                }
                            }
                            return_val = g_return_value;
                            g_var_count = saved_var_count;
                            g_var_scope_base = saved_scope_base;
                            g_return_pending = 0;
                            return return_val;
                        }
                        /* No interpreter method found — check @synthesize property */
                        {
                            unsigned int pi;
                            for (pi = 0; pi < g_property_count; pi++) {
                                if (g_properties[pi].synthesized &&
                                    cstr_eq(prop_name, g_properties[pi].name)) {
                                    /* Read from side table */
                                    Value *val = instance_var_get(receiver, g_properties[pi].name);
                                    if (val) return *val;
                                    return value_void();
                                }
                            }
                        }
                        /* No method or property found — return void */
                        return value_void();
                    }
                }

                /* Block invocation: blockName(args) or blockName()
                 * If the variable holds a block marker ("NSBlock:N"),
                 * and the next token is (, invoke the block. */
                if (parser_current(p).type == TOK_OPEN_PAREN && var->is_id && var->value != 0) {
                    const char *marker = (const char *)var->value;
                    unsigned int bid = block_id_from_marker(marker);
                    if (bid > 0) {
                        BlockImpl *blk = block_get(bid);
                        if (blk) {
                            Value args[8];
                            unsigned int arg_count = 0;
                            unsigned int saved_var_count = g_var_count;
                            unsigned int ai;
                            /* Save the block variable's current value so we
                             * can restore it after captured variable restoration.
                             * (Captured values may overwrite the block variable
                             * with a stale nil value from creation time.) */
                            id saved_block_value = var->value;
                            int saved_block_is_id = var->is_id;

                            parser_advance(p); /* consume ( */

                            /* Parse arguments */
                            while (parser_current(p).type != TOK_CLOSE_PAREN &&
                                   parser_current(p).type != TOK_EOF &&
                                   arg_count < 8) {
                                args[arg_count] = parse_expression(p);
                                arg_count++;
                                if (parser_current(p).type == TOK_COMMA) {
                                    parser_advance(p);
                                }
                            }
                            if (parser_current(p).type == TOK_CLOSE_PAREN) {
                                parser_advance(p);
                            }

                            /* Restore captured variable values FIRST,
                             * then set up argument variables (which
                             * take precedence over captured values). */
                            for (ai = 0; ai < blk->capture_count; ai++) {
                                InterpVar *cap_var = interp_get_or_create_var(blk->captures[ai].name);
                                if (cap_var) {
                                    cap_var->is_id = blk->captures[ai].value.is_id;
                                    cap_var->value = blk->captures[ai].value.obj_val;
                                    cap_var->is_int = blk->captures[ai].value.is_int;
                                    cap_var->int_value = blk->captures[ai].value.int_val;
                                    cap_var->is_class = blk->captures[ai].value.is_class;
                                    cap_var->cls = blk->captures[ai].value.cls_val;
                                    cap_var->is_sel = blk->captures[ai].value.is_sel;
                                    cap_var->sel = blk->captures[ai].value.sel_val;
                                }
                            }

                            /* Set up argument variables (override captured values) */
                            for (ai = 0; ai < blk->arg_count && ai < arg_count; ai++) {
                                InterpVar *arg_var = interp_get_or_create_var(blk->arg_names[ai]);
                                if (arg_var) {
                                    arg_var->is_id = args[ai].is_id;
                                    arg_var->value = args[ai].obj_val;
                                    arg_var->is_int = args[ai].is_int;
                                    arg_var->int_value = args[ai].int_val;
                                    arg_var->is_class = args[ai].is_class;
                                    arg_var->cls = args[ai].cls_val;
                                    arg_var->is_sel = args[ai].is_sel;
                                    arg_var->sel = args[ai].sel_val;
                                }
                            }

                            /* Execute the block body */
                            {
                                Value result;
                                g_return_pending = 0;
                                result = eval_source_range(0, blk->source_len, blk->source);
                                g_var_count = saved_var_count;
                                g_return_pending = 0;
                                /* Restore the block variable's value, which may
                                 * have been overwritten by captured variable
                                 * restoration (e.g., if the block was assigned
                                 * to a variable that was captured at creation
                                 * time with a nil value). */
                                var->value = saved_block_value;
                                var->is_id = saved_block_is_id;
                                return result;
                            }
                        }
                    }
                }

                if (var->is_int) return value_from_int(var->int_value);
                if (var->is_class) return value_from_class(var->cls);
                if (var->is_sel) return value_from_sel(var->sel);
                return value_from_id(var->value);
            }
        }

        /* Try as a class name — but only if the class table is populated.
         * We track registered classes ourselves to avoid crashing the
         * runtime's hash table when it's empty. */
        {
            unsigned int vi;
            for (vi = 0; vi < g_var_count; vi++) {
                if (cstr_eq(g_vars[vi].name, tok.text) && g_vars[vi].is_class) {
                    parser_advance(p);
                    return value_from_class(g_vars[vi].cls);
                }
            }
        }

        parser_advance(p);
        if (tok.type == TOK_AT_KEYWORD) {
            parser_error(p, "Unsupported @keyword");
        } else {
            parser_error(p, "Unknown identifier");
        }
        return value_void();
    }

    /* Pre-increment/decrement: ++i, --i */
    if (tok.type == TOK_PLUS_PLUS || tok.type == TOK_MINUS_MINUS) {
        int is_increment = (tok.type == TOK_PLUS_PLUS);
        parser_advance(p);
        {
            /* The next token must be an identifier (variable name) */
            if (parser_current(p).type == TOK_IDENTIFIER) {
                InterpVar *var = interp_find_var(parser_current(p).text);
                if (var && var->is_int) {
                    if (is_increment) var->int_value++;
                    else var->int_value--;
                    parser_advance(p);
                    return value_from_int(var->int_value);
                }
            }
            /* Fall back to parsing as primary expression */
            {
                Value v = parse_primary(p);
                if (v.is_int) {
                    if (is_increment) v.int_val++;
                    else v.int_val--;
                }
                return v;
            }
        }
    }

    /* Minus (unary) */
    if (tok.type == TOK_MINUS) {
        parser_advance(p);
        {
            Value v = parse_primary(p);
            if (v.is_int) return value_from_int(-v.int_val);
            return v;
        }
    }

    /* Logical NOT */
    if (tok.type == TOK_NOT) {
        parser_advance(p);
        {
            Value v = parse_primary(p);
            return value_from_int(is_truthy(v) ? 0 : 1);
        }
    }

    /* Unary minus */
    if (tok.type == TOK_MINUS) {
        parser_advance(p);
        {
            Value v = parse_primary(p);
            if (v.is_int) return value_from_int(-v.int_val);
            return v;
        }
    }

    /* Block literal: ^{ body } or ^(Type arg, ...) { body }
     * We capture the body source range (like method bodies) and
     * register it in g_blocks[]. Block invocation executes the
     * body via eval_source_range. */
    if (tok.type == TOK_CARET) {
        unsigned int block_id;
        BlockImpl *blk;
        unsigned int body_start, body_len;

        parser_advance(p); /* consume ^ */

        /* Allocate a block slot */
        if (g_block_count >= MAX_BLOCKS) {
            parser_error(p, "block table full (max 32)");
            return value_void();
        }
        block_id = g_next_block_id++;
        blk = &g_blocks[g_block_count];
        blk->block_id = block_id;
        blk->source[0] = '\0';
        blk->source_len = 0;
        blk->arg_count = 0;
        blk->capture_count = 0;

        /* Parse optional parameter list: (Type arg, Type arg, ...) */
        if (parser_current(p).type == TOK_OPEN_PAREN) {
            parser_advance(p); /* consume ( */
            while (parser_current(p).type != TOK_CLOSE_PAREN &&
                   parser_current(p).type != TOK_EOF) {
                /* Skip type name */
                if (parser_current(p).type == TOK_IDENTIFIER) {
                    parser_advance(p);
                }
                /* Skip pointer stars */
                while (parser_current(p).type == TOK_STAR) {
                    parser_advance(p);
                }
                /* Parameter name */
                if (parser_current(p).type == TOK_IDENTIFIER) {
                    if (blk->arg_count < 8) {
                        cstr_copy(blk->arg_names[blk->arg_count],
                                  parser_current(p).text, 64);
                        blk->arg_count++;
                    }
                    parser_advance(p);
                }
                /* Skip comma */
                if (parser_current(p).type == TOK_COMMA) {
                    parser_advance(p);
                }
            }
            if (parser_current(p).type == TOK_CLOSE_PAREN) {
                parser_advance(p); /* consume ) */
            }
        }

        /* Expect { and capture body source */
        if (parser_current(p).type != TOK_OPEN_BRACE) {
            parser_error(p, "expected { after block parameters");
            return value_void();
        }
        parser_advance(p); /* consume { */

        body_start = p->lex.token_start;

        /* Skip the body by matching braces */
        {
            unsigned int brace_depth = 1;
            while (brace_depth > 0 &&
                   parser_current(p).type != TOK_EOF) {
                if (parser_current(p).type == TOK_OPEN_BRACE) brace_depth++;
                else if (parser_current(p).type == TOK_CLOSE_BRACE) {
                    brace_depth--;
                    if (brace_depth == 0) break;
                }
                parser_advance(p);
            }
        }
        body_len = p->lex.token_start - body_start;

        if (parser_current(p).type == TOK_CLOSE_BRACE) {
            parser_advance(p); /* consume } */
        }

        /* Copy the body source into the block's source buffer */
        if (body_len > 0 && body_len < 2048) {
            unsigned int si;
            for (si = 0; si < body_len; si++) {
                blk->source[si] = p->lex.source[body_start + si];
            }
            blk->source[body_len] = '\0';
            blk->source_len = body_len;
        }
        g_block_count++;

        /* Capture current variable values (by-value snapshot).
         * We capture all non-class, non-sel variables that have
         * been defined before the block, EXCLUDING block parameters
         * (which will be set at invocation time). This is a
         * simplification — real ObjC blocks capture only referenced
         * variables, but for our interpreter, capturing everything
         * is simpler and correct for the notebook use case. */
        {
            unsigned int vi;
            for (vi = 0; vi < g_var_count && blk->capture_count < 16; vi++) {
                unsigned int ai;
                int is_arg = 0;
                /* Skip class variables, selector variables, and
                 * variables that are Foundation class names */
                if (g_vars[vi].is_class || g_vars[vi].is_sel) continue;
                if (g_vars[vi].name[0] == '\0') continue;
                /* Skip variables that shadow block parameters */
                for (ai = 0; ai < blk->arg_count; ai++) {
                    if (cstr_eq(g_vars[vi].name, blk->arg_names[ai])) {
                        is_arg = 1;
                        break;
                    }
                }
                if (is_arg) continue;
                cstr_copy(blk->captures[blk->capture_count].name,
                          g_vars[vi].name, 64);
                blk->captures[blk->capture_count].value.is_id = g_vars[vi].is_id;
                blk->captures[blk->capture_count].value.obj_val = g_vars[vi].value;
                blk->captures[blk->capture_count].value.is_int = g_vars[vi].is_int;
                blk->captures[blk->capture_count].value.int_val = g_vars[vi].int_value;
                blk->captures[blk->capture_count].value.is_class = g_vars[vi].is_class;
                blk->captures[blk->capture_count].value.cls_val = g_vars[vi].cls;
                blk->captures[blk->capture_count].value.is_sel = g_vars[vi].is_sel;
                blk->captures[blk->capture_count].value.sel_val = g_vars[vi].sel;
                blk->capture_count++;
            }
        }

        return value_from_id(block_make_marker(block_id));
    }

    /* @keyword */
    if (tok.type == TOK_AT_KEYWORD) {
        if (cstr_eq(tok.text, "@interface")) {
            parser_advance(p);
            return parse_interface(p);
        }
        if (cstr_eq(tok.text, "@implementation")) {
            parser_advance(p);
            return parse_implementation(p);
        }
        if (cstr_eq(tok.text, "@class")) {
            /* Forward declaration — skip until @end or ; */
            parser_advance(p);
            while (parser_current(p).type != TOK_SEMICOLON &&
                   parser_current(p).type != TOK_EOF) {
                parser_advance(p);
            }
            if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
            return value_void();
        }
        if (cstr_eq(tok.text, "@protocol")) {
            /* Skip protocol declarations */
            parser_advance(p);
            while (!(parser_current(p).type == TOK_AT_KEYWORD &&
                     cstr_eq(parser_current(p).text, "@end")) &&
                   parser_current(p).type != TOK_EOF) {
                parser_advance(p);
            }
            if (parser_current(p).type == TOK_AT_KEYWORD) parser_advance(p);
            return value_void();
        }
        parser_advance(p);
        return value_void();
    }

    parser_advance(p);
    parser_error(p, "Unexpected token");
    return value_void();
}

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
            }
        }
    }

    return left;
}

/* ── Truthiness helper ──────────────────────────────────────────── */

static int is_truthy(Value v) {
    if (v.is_int) return v.int_val != 0;
    if (v.is_id) return v.obj_val != 0;
    if (v.is_class) return v.cls_val != 0;
    if (v.is_void) return 0;
    return 0;
}

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
                cstr_copy(g_error_buffer, "expected ':' in ternary expression", OBJC_INTERP_ERROR_SIZE);
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

static Value parse_expression(Parser *p) {
    return parse_assignment(p);
}

/* ── Statement parser ───────────────────────────────────────────── */

static Value parse_type_and_var_decl(Parser *p) {
    /* Parse type: int, void, id, Class, SEL, Type* */
    char type_name[64];
    int is_pointer = 0;
    (void)is_pointer; /* may be used later for pointer type tracking */

    type_name[0] = '\0';

    if (parser_current(p).type == TOK_IDENTIFIER) {
        cstr_copy(type_name, parser_current(p).text, 64);
        parser_advance(p);
    }

    /* Block variable declaration: void (^blockName)(params) = ^{ ... };
     * After the return type, we see ( ^ name ) ( param_types ) = block_literal */
    if (parser_current(p).type == TOK_OPEN_PAREN) {
        /* Look ahead: is this ( ^ name )? */
        Token saved = parser_current(p);
        parser_advance(p); /* consume ( */

        if (parser_current(p).type == TOK_CARET) {
            /* Block variable declaration! */
            parser_advance(p); /* consume ^ */

            if (parser_current(p).type == TOK_IDENTIFIER) {
                char var_name_buf[64];
                InterpVar *var;
                Value init_val;

                cstr_copy(var_name_buf, parser_current(p).text, 64);
                parser_advance(p);

                if (parser_current(p).type == TOK_CLOSE_PAREN) {
                    parser_advance(p); /* consume ) */
                }

                /* Skip the parameter type list: (Type1, Type2, ...) */
                if (parser_current(p).type == TOK_OPEN_PAREN) {
                    parser_advance(p);
                    while (parser_current(p).type != TOK_CLOSE_PAREN &&
                           parser_current(p).type != TOK_EOF) {
                        parser_advance(p);
                    }
                    if (parser_current(p).type == TOK_CLOSE_PAREN) {
                        parser_advance(p);
                    }
                }

                var = interp_get_or_create_var(var_name_buf);
                if (var == 0) {
                    parser_error(p, "variable table full (max 1024)");
                    return value_void();
                }

                /* Parse initializer: = block_literal */
                if (parser_current(p).type == TOK_ASSIGN) {
                    parser_advance(p);
                    init_val = parse_expression(p);
                    if (p->error) return init_val;

                    if (var) {
                        var->value = init_val.obj_val;
                        var->cls = init_val.cls_val;
                        var->sel = init_val.sel_val;
                        var->is_int = init_val.is_int;
                        var->int_value = init_val.int_val;
                        var->is_class = init_val.is_class;
                        var->is_sel = init_val.is_sel;
                        var->is_id = init_val.is_id;
                    }
                    return init_val;
                }

                /* Default: uninitialized block */
                var->is_id = 1;
                var->value = 0;
                return value_void();
            }
        }

        /* Not a block declaration — restore and fall through.
         * This is tricky because we already consumed the (.
         * We can't un-read tokens, so we treat this as a
         * parenthesized expression of the type name (which is
         * unusual but not wrong in C). */
        /* Fall through — the ( was consumed but we can't put it back.
         * This path is unlikely in practice. */
    }

    /* Check for pointer * */
    while (parser_current(p).type == TOK_STAR) {
        is_pointer = 1;
        parser_advance(p);
    }

    /* Variable name */
    if (parser_current(p).type == TOK_IDENTIFIER) {
        char var_name_buf[64];
        InterpVar *var;
        Value init_val;
        cstr_copy(var_name_buf, parser_current(p).text, 64);
        parser_advance(p);

        var = interp_get_or_create_var(var_name_buf);
        if (var == 0) {
            parser_error(p, "variable table full (max 1024)");
            return value_void();
        }

        /* Parse initializer */
        if (parser_current(p).type == TOK_ASSIGN) {
            parser_advance(p);
            init_val = parse_expression(p);
            if (p->error) return init_val;

            if (var) {
                var->value = init_val.obj_val;
                var->cls = init_val.cls_val;
                var->sel = init_val.sel_val;
                var->is_int = init_val.is_int;
                var->int_value = init_val.int_val;
                var->is_class = init_val.is_class;
                var->is_sel = init_val.is_sel;
                var->is_id = init_val.is_id;
            }
            return init_val;
        }

        /* Default initialization */
        if (var) {
            if (cstr_eq(type_name, "int")) {
                var->is_int = 1;
                var->int_value = 0;
            } else if (cstr_eq(type_name, "Class") || cstr_eq(type_name, "Class")) {
                var->is_class = 1;
                var->cls = 0;
            } else if (cstr_eq(type_name, "SEL")) {
                var->is_sel = 1;
                var->sel = 0;
            } else {
                var->is_id = 1;
                var->value = 0;
            }
        }

        return value_void();
    }

    return value_void();
}

static Value parse_statement(Parser *p) {
    Token tok = parser_current(p);

    /* return statement: return [expr]; */
    if (tok.type == TOK_RETURN) {
        parser_advance(p);

        /* Parse optional return value */
        if (parser_current(p).type != TOK_SEMICOLON &&
            parser_current(p).type != TOK_CLOSE_BRACE &&
            parser_current(p).type != TOK_EOF) {
            g_return_value = parse_expression(p);
            if (p->error) return g_return_value;
        } else {
            g_return_value = value_void();
        }

        if (parser_current(p).type == TOK_SEMICOLON) {
            parser_advance(p);
        }

        g_return_pending = 1;
        return g_return_value;
    }

    /* @interface */
    if (tok.type == TOK_AT_KEYWORD && cstr_eq(tok.text, "@interface")) {
        parser_advance(p);
        return parse_interface(p);
    }

    /* @implementation */
    if (tok.type == TOK_AT_KEYWORD && cstr_eq(tok.text, "@implementation")) {
        parser_advance(p);
        return parse_implementation(p);
    }

    /* @class forward declaration */
    if (tok.type == TOK_AT_KEYWORD && cstr_eq(tok.text, "@class")) {
        parser_advance(p);
        while (parser_current(p).type != TOK_SEMICOLON &&
               parser_current(p).type != TOK_EOF) {
            parser_advance(p);
        }
        if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
        return value_void();
    }

    /* @protocol */
    if (tok.type == TOK_AT_KEYWORD && cstr_eq(tok.text, "@protocol")) {
        parser_advance(p);
        while (!(parser_current(p).type == TOK_AT_KEYWORD &&
                 cstr_eq(parser_current(p).text, "@end")) &&
               parser_current(p).type != TOK_EOF) {
            parser_advance(p);
        }
        if (parser_current(p).type == TOK_AT_KEYWORD) parser_advance(p);
        return value_void();
    }

    /* Type declaration: int, void, id, Class, SEL, or registered class name */
    if (tok.type == TOK_IDENTIFIER) {
        /* Check if this is a type name followed by a variable name.
         * Built-in types are always recognized. Registered class names
         * (from @implementation) are also recognized as types when
         * followed by * (pointer) or another identifier. */
        int is_builtin_type = (
            cstr_eq(tok.text, "int") || cstr_eq(tok.text, "void") ||
            cstr_eq(tok.text, "id") || cstr_eq(tok.text, "Class") ||
            cstr_eq(tok.text, "SEL") || cstr_eq(tok.text, "BOOL") ||
            cstr_eq(tok.text, "long") || cstr_eq(tok.text, "char") ||
            cstr_eq(tok.text, "float") || cstr_eq(tok.text, "double")
        );
        int is_class_type = (!is_builtin_type && objc_lookUpClass(tok.text) != 0);
        /* Also check variable table for Foundation class names (which are
         * registered as variables with is_class=1, not in the runtime). */
        if (!is_class_type && !is_builtin_type) {
            unsigned int vi;
            for (vi = 0; vi < g_var_count; vi++) {
                if (cstr_eq(g_vars[vi].name, tok.text) && g_vars[vi].is_class) {
                    is_class_type = 1;
                    break;
                }
            }
        }

        if (is_builtin_type || is_class_type) {
            /* Look ahead to see if next token is * or an identifier */
            Token saved = p->lex.current;
            unsigned int saved_pos = p->lex.pos;
            parser_advance(p);

            if (parser_current(p).type == TOK_STAR ||
                parser_current(p).type == TOK_IDENTIFIER ||
                parser_current(p).type == TOK_OPEN_PAREN) {
                /* Restore and parse as type+variable declaration */
                p->lex.current = saved;
                p->lex.pos = saved_pos;
                {
                    Value v = parse_type_and_var_decl(p);
                    if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
                    return v;
                }
            }

            /* Restore — this was just an expression starting with a type name */
            p->lex.current = saved;
            p->lex.pos = saved_pos;
        }

        /* Variable assignment: name = expr; */
        {
            InterpVar *var = interp_find_var(tok.text);
            if (var && parser_current(p).type != TOK_OPEN_PAREN &&
                parser_current(p).type != TOK_OPEN_BRACKET) {
                /* Check for assignment */
                Token saved = p->lex.current;
                unsigned int saved_pos = p->lex.pos;
                parser_advance(p);

                if (parser_current(p).type == TOK_ASSIGN) {
                    Value val;
                    parser_advance(p);
                    val = parse_expression(p);
                    if (p->error) return val;
                    var->value = val.obj_val;
                    var->cls = val.cls_val;
                    var->sel = val.sel_val;
                    var->is_int = val.is_int;
                    var->int_value = val.int_val;
                    var->is_class = val.is_class;
                    var->is_sel = val.is_sel;
                    if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
                    return val;
                }

                /* Compound assignment: +=, -=, *=, /=, %= */
                if (parser_current(p).type == TOK_PLUS_ASSIGN && var->is_int) {
                    Value val;
                    parser_advance(p);
                    val = parse_expression(p);
                    if (p->error) return val;
                    if (val.is_int) var->int_value += val.int_val;
                    if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
                    return value_from_int(var->int_value);
                }
                if (parser_current(p).type == TOK_MINUS_ASSIGN && var->is_int) {
                    Value val;
                    parser_advance(p);
                    val = parse_expression(p);
                    if (p->error) return val;
                    if (val.is_int) var->int_value -= val.int_val;
                    if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
                    return value_from_int(var->int_value);
                }
                if (parser_current(p).type == TOK_STAR_ASSIGN && var->is_int) {
                    Value val;
                    parser_advance(p);
                    val = parse_expression(p);
                    if (p->error) return val;
                    if (val.is_int) var->int_value *= val.int_val;
                    if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
                    return value_from_int(var->int_value);
                }
                if (parser_current(p).type == TOK_SLASH_ASSIGN && var->is_int) {
                    Value val;
                    parser_advance(p);
                    val = parse_expression(p);
                    if (p->error) return val;
                    if (val.is_int && val.int_val != 0) var->int_value /= val.int_val;
                    if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
                    return value_from_int(var->int_value);
                }
                if (parser_current(p).type == TOK_PERCENT_ASSIGN && var->is_int) {
                    Value val;
                    parser_advance(p);
                    val = parse_expression(p);
                    if (p->error) return val;
                    if (val.is_int && val.int_val != 0) var->int_value %= val.int_val;
                    if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
                    return value_from_int(var->int_value);
                }

                /* Not an assignment — restore and parse as expression */
                p->lex.current = saved;
                p->lex.pos = saved_pos;
            }
        }
    }

    /* Expression statement */
    {
        Value v = parse_expression(p);
        if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
        return v;
    }
}

/* ── Block parser ───────────────────────────────────────────────── */

static Value parse_block(Parser *p) {
    Value last = value_void();
    while (parser_current(p).type != TOK_EOF &&
           parser_current(p).type != TOK_CLOSE_BRACE) {
        if (interp_should_interrupt()) {
            parser_error(p, "Execution interrupted");
            return last;
        }
        last = parse_statement(p);
        if (p->error) return last;
        if (g_return_pending) return last;
    }
    return last;
}

/* ── AST-based statement parser (for control flow) ─────────────── */

/* Parse a block of statements into AST nodes.
 * Returns an AST_BLOCK node containing all children. */
static AstNode *parse_block_ast(Parser *p) {
    AstNode *block = ast_make_block();
    if (!block) {
        if (!p->error) {
            parser_error(p, "AST node limit reached (max 1024)");
        }
        return 0;
    }

    while (parser_current(p).type != TOK_EOF &&
           parser_current(p).type != TOK_CLOSE_BRACE) {
        AstNode *child = parse_statement_ast(p);
        if (!child) {
            if (!p->error) {
                parser_error(p, "AST node limit reached (max 1024)");
            }
            return 0;
        }
        if (p->error) return 0;
        if (ast_block_add(block, child) != 0) {
            parser_error(p, "block too large (max 128 statements)");
            return 0;
        }
        if (g_return_pending || g_break_pending || g_continue_pending) return block;
    }
    return block;
}

/* Parse a single statement into an AST node.
 * Control flow (if/while/for) → true AST nodes
 * Everything else → source range nodes (re-parsed on evaluation) */
static AstNode *parse_statement_ast(Parser *p) {
    Token tok = parser_current(p);

    /* if statement */
    if (tok.type == TOK_IF) {
        AstNode *condition, *then_branch, *else_branch;
        parser_advance(p);
        parser_expect(p, TOK_OPEN_PAREN);
        if (p->error) return 0;

        /* Parse condition as a source range — skip tokens, don't evaluate */
        {
            unsigned int cond_start = p->lex.token_start;
            int paren_depth = 1; /* we're inside the ( already */
            while (parser_current(p).type != TOK_EOF && paren_depth > 0) {
                if (parser_current(p).type == TOK_OPEN_PAREN) paren_depth++;
                else if (parser_current(p).type == TOK_CLOSE_PAREN) {
                    paren_depth--;
                    if (paren_depth == 0) break;
                }
                parser_advance(p);
            }
            condition = ast_make_source(AST_EXPR_STMT, cond_start,
                                       p->lex.token_start - cond_start);
            if (!condition && !p->error) {
                parser_error(p, "AST node limit reached (max 1024)");
                return 0;
            }
        }
        parser_expect(p, TOK_CLOSE_PAREN);
        if (p->error) return 0;

        /* Parse then-branch */
        if (parser_current(p).type == TOK_OPEN_BRACE) {
            parser_advance(p);
            then_branch = parse_block_ast(p);
            if (parser_current(p).type == TOK_CLOSE_BRACE) parser_advance(p);
        } else {
            then_branch = parse_statement_ast(p);
        }
        if (!then_branch) return 0;

        /* Parse optional else-branch */
        else_branch = 0;
        if (parser_current(p).type == TOK_ELSE) {
            parser_advance(p);
            if (parser_current(p).type == TOK_OPEN_BRACE) {
                parser_advance(p);
                else_branch = parse_block_ast(p);
                if (parser_current(p).type == TOK_CLOSE_BRACE) parser_advance(p);
            } else {
                else_branch = parse_statement_ast(p);
            }
            if (!else_branch) return 0;
        }

        {
            AstNode *node = ast_make_if(condition, then_branch, else_branch);
            if (!node && !p->error) {
                parser_error(p, "AST node limit reached (max 1024)");
                return 0;
            }
            return node;
        }
    }

    /* while statement */
    if (tok.type == TOK_WHILE) {
        AstNode *condition, *body;
        parser_advance(p);
        parser_expect(p, TOK_OPEN_PAREN);
        if (p->error) return 0;

        {
            unsigned int cond_start = p->lex.token_start;
            int paren_depth = 1;
            while (parser_current(p).type != TOK_EOF && paren_depth > 0) {
                if (parser_current(p).type == TOK_OPEN_PAREN) paren_depth++;
                else if (parser_current(p).type == TOK_CLOSE_PAREN) {
                    paren_depth--;
                    if (paren_depth == 0) break;
                }
                parser_advance(p);
            }
            condition = ast_make_source(AST_EXPR_STMT, cond_start,
                                        p->lex.token_start - cond_start);
        }
        parser_expect(p, TOK_CLOSE_PAREN);
        if (p->error) return 0;

        if (parser_current(p).type == TOK_OPEN_BRACE) {
            parser_advance(p);
            body = parse_block_ast(p);
            if (parser_current(p).type == TOK_CLOSE_BRACE) parser_advance(p);
        } else {
            body = parse_statement_ast(p);
        }
        if (!body) return 0;

        {
            AstNode *node = ast_make_while(condition, body);
            if (!node && !p->error) {
                parser_error(p, "AST node limit reached (max 1024)");
                return 0;
            }
            return node;
        }
    }

    /* for statement */
    if (tok.type == TOK_FOR) {
        parser_advance(p);
        parser_expect(p, TOK_OPEN_PAREN);
        if (p->error) return 0;

        /* Check for for-in: type var in collection
         * We look ahead: if we see IDENT IDENT TOK_IN, it's for-in.
         * Otherwise, it's a standard for loop. */
        {
            Token saved = p->lex.current;
            unsigned int saved_pos = p->lex.pos;
            unsigned int saved_token_start = p->lex.token_start;
            int is_for_in = 0;
            char for_in_var[64];
            for_in_var[0] = '\0';

            /* Try to match: type var in ... */
            if (parser_current(p).type == TOK_IDENTIFIER) {
                /* Could be a type name or just 'id' */
                parser_advance(p);
                if (parser_current(p).type == TOK_STAR) {
                    /* Skip pointer: id *var */
                    parser_advance(p);
                }
                if (parser_current(p).type == TOK_IDENTIFIER) {
                    cstr_copy(for_in_var, parser_current(p).text, 64);
                    parser_advance(p);
                    if (parser_current(p).type == TOK_IN) {
                        is_for_in = 1;
                    }
                }
            }

            if (is_for_in) {
                /* for-in loop: for (type var in collection) { body } */
                unsigned int coll_start_outer;
                unsigned int coll_len_outer = 0;
                AstNode *body;
                AstNode *node;

                parser_advance(p); /* skip 'in' */

                /* Parse collection expression (skip tokens up to close paren) */
                {
                    unsigned int coll_start = p->lex.token_start;
                    int pd = 0;
                    while (parser_current(p).type != TOK_EOF) {
                        if (parser_current(p).type == TOK_CLOSE_PAREN && pd == 0) break;
                        if (parser_current(p).type == TOK_OPEN_PAREN) pd++;
                        else if (parser_current(p).type == TOK_CLOSE_PAREN) pd--;
                        parser_advance(p);
                    }
                    coll_len_outer = p->lex.token_start - coll_start;
                    coll_start_outer = coll_start;
                }

                if (parser_current(p).type == TOK_CLOSE_PAREN) parser_advance(p);

                /* Body */
                if (parser_current(p).type == TOK_OPEN_BRACE) {
                    parser_advance(p);
                    body = parse_block_ast(p);
                    if (parser_current(p).type == TOK_CLOSE_BRACE) parser_advance(p);
                } else {
                    body = parse_statement_ast(p);
                }
                if (!body) return 0;

                /* Build AST_FOR_IN node */
                node = ast_alloc();
                if (!node) {
                    if (!p->error) {
                        parser_error(p, "AST node limit reached (max 1024)");
                    }
                    return 0;
                }
                node->type = AST_FOR_IN;
                cstr_copy(node->for_in.var_name, for_in_var, 64);
                node->for_in.collection_start = coll_start_outer;
                node->for_in.collection_len = coll_len_outer;
                node->for_in.body = body;
                return node;
            }

            /* Not for-in — restore and parse as standard for */
            p->lex.current = saved;
            p->lex.pos = saved_pos;
            p->lex.token_start = saved_token_start;
        }

        /* Standard for loop: for (init; cond; incr) { body } */
        {
            AstNode *init, *condition, *increment, *body;

        /* Init: capture as source range (skip tokens, don't evaluate) */
        {
            unsigned int init_start = p->lex.token_start;
            int pd = 0;
            while (parser_current(p).type != TOK_EOF) {
                if (parser_current(p).type == TOK_SEMICOLON && pd == 0) break;
                if (parser_current(p).type == TOK_OPEN_PAREN) pd++;
                else if (parser_current(p).type == TOK_CLOSE_PAREN) pd--;
                parser_advance(p);
            }
            init = ast_make_source(AST_EXPR_STMT, init_start,
                                   p->lex.token_start - init_start);
            if (!init && !p->error) {
                parser_error(p, "AST node limit reached (max 1024)");
                return 0;
            }
            if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
        }

        /* Condition: capture as source range (skip tokens, don't evaluate) */
        {
            unsigned int cond_start = p->lex.token_start;
            int pd = 0;
            while (parser_current(p).type != TOK_EOF) {
                if (parser_current(p).type == TOK_SEMICOLON && pd == 0) break;
                if (parser_current(p).type == TOK_OPEN_PAREN) pd++;
                else if (parser_current(p).type == TOK_CLOSE_PAREN) pd--;
                parser_advance(p);
            }
            condition = ast_make_source(AST_EXPR_STMT, cond_start,
                                       p->lex.token_start - cond_start);
            if (!condition && !p->error) {
                parser_error(p, "AST node limit reached (max 1024)");
                return 0;
            }
            if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
        }

        /* Increment: capture as source range (skip tokens, don't evaluate) */
        {
            unsigned int incr_start = p->lex.token_start;
            int pd = 0;
            while (parser_current(p).type != TOK_EOF) {
                if (parser_current(p).type == TOK_CLOSE_PAREN && pd == 0) break;
                if (parser_current(p).type == TOK_OPEN_PAREN) pd++;
                else if (parser_current(p).type == TOK_CLOSE_PAREN) pd--;
                parser_advance(p);
            }
            increment = ast_make_source(AST_EXPR_STMT, incr_start,
                                       p->lex.token_start - incr_start);
            if (!increment && !p->error) {
                parser_error(p, "AST node limit reached (max 1024)");
                return 0;
            }
            if (parser_current(p).type == TOK_CLOSE_PAREN) parser_advance(p);
        }

        /* Body */
        if (parser_current(p).type == TOK_OPEN_BRACE) {
            parser_advance(p);
            body = parse_block_ast(p);
            if (parser_current(p).type == TOK_CLOSE_BRACE) parser_advance(p);
        } else {
            body = parse_statement_ast(p);
        }
        if (!body) return 0;

        {
            AstNode *node = ast_make_for(init, condition, increment, body);
            if (!node && !p->error) {
                parser_error(p, "AST node limit reached (max 1024)");
                return 0;
            }
            return node;
        }
        }
    }

    /* break statement */
    if (tok.type == TOK_BREAK) {
        parser_advance(p);
        if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
        {
            AstNode *n = ast_alloc();
            if (!n) {
                if (!p->error) {
                    parser_error(p, "AST node limit reached (max 1024)");
                }
                return 0;
            }
            n->type = AST_BREAK;
            return n;
        }
    }

    /* continue statement */
    if (tok.type == TOK_CONTINUE) {
        parser_advance(p);
        if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
        {
            AstNode *n = ast_alloc();
            if (!n) {
                if (!p->error) {
                    parser_error(p, "AST node limit reached (max 1024)");
                }
                return 0;
            }
            n->type = AST_CONTINUE;
            return n;
        }
    }

    /* return statement → source range */
    if (tok.type == TOK_RETURN) {
        unsigned int start = p->lex.token_start;
        parser_advance(p);
        if (parser_current(p).type != TOK_SEMICOLON &&
            parser_current(p).type != TOK_CLOSE_BRACE &&
            parser_current(p).type != TOK_EOF) {
            parse_expression(p);
            if (p->error) return 0;
        }
        if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
        {
            AstNode *node = ast_make_source(AST_RETURN, start, p->lex.token_start - start);
            if (!node && !p->error) {
                parser_error(p, "AST node limit reached (max 1024)");
                return 0;
            }
            return node;
        }
    }

    /* @interface / @implementation — execute immediately (no AST) */
    if (tok.type == TOK_AT_KEYWORD &&
        (cstr_eq(tok.text, "@interface") || cstr_eq(tok.text, "@implementation") ||
         cstr_eq(tok.text, "@class") || cstr_eq(tok.text, "@protocol"))) {
        unsigned int start = p->lex.token_start;
        parse_statement(p); /* execute immediately */
        if (p->error) return 0;
        {
            AstNode *node = ast_make_source(AST_EXPR_STMT, start, p->lex.token_start - start);
            if (!node && !p->error) {
                parser_error(p, "AST node limit reached (max 1024)");
                return 0;
            }
            return node;
        }
    }

    /* Type declaration or expression statement → source range.
     * We only advance the parser to find the statement boundaries;
     * actual evaluation happens in eval_ast → eval_source_range.
     * This avoids the double-execution bug where parse_statement
     * evaluates the code during AST construction AND eval_source_range
     * evaluates it again during evaluation. */
    {
        unsigned int start = p->lex.token_start;
        int brace_depth = 0;
        /* Skip tokens until we find the statement-ending semicolon.
         * We need to track brace depth to handle nested blocks. */
        while (parser_current(p).type != TOK_EOF) {
            if (parser_current(p).type == TOK_OPEN_BRACE) brace_depth++;
            else if (parser_current(p).type == TOK_CLOSE_BRACE) {
                brace_depth--;
                if (brace_depth < 0) break; /* end of enclosing block */
            }
            else if (parser_current(p).type == TOK_SEMICOLON && brace_depth == 0) {
                parser_advance(p);
                break;
            }
            parser_advance(p);
        }
        {
            AstNode *node = ast_make_source(AST_EXPR_STMT, start, p->lex.token_start - start);
            if (!node && !p->error) {
                parser_error(p, "AST node limit reached (max 1024)");
                return 0;
            }
            return node;
        }
    }
}

/* ── AST evaluation ─────────────────────────────────────────────── */

/* Evaluate a source range by re-parsing it.
 * This creates a temporary parser over the source substring. */
static Value eval_source_range(unsigned int start, unsigned int len,
                               const char *source) {
    Parser p;
    Value last = value_void();
    g_parse_depth = 0;
    if (len == 0) return value_void();
    parser_init(&p, source + start, len);
    /* Parse all statements in the source range, not just the first one.
     * This is needed for method bodies with multiple statements.
     * For control flow (if/while/for), use the two-phase AST approach.
     * For other statements, evaluate directly. */
    while (p.lex.current.type != TOK_EOF && !p.error) {
        Token tok = parser_current(&p);
        if (tok.type == TOK_IF || tok.type == TOK_WHILE ||
            tok.type == TOK_FOR) {
            /* Control flow: use two-phase AST approach.
             * Save and restore AST count to avoid corrupting
             * the outer AST arena. */
            unsigned int saved_ast_count = g_ast_count;
            AstNode *root = parse_block_ast(&p);
            if (p.error) {
                g_error_code = p.error;
                cstr_copy(g_error_buffer, p.error_msg, OBJC_INTERP_ERROR_SIZE);
                g_ast_count = saved_ast_count;
                return last;
            }
            if (root) {
                last = eval_ast(root, source + start);
            }
            g_ast_count = saved_ast_count;
            if (p.error) {
                g_error_code = p.error;
                cstr_copy(g_error_buffer, p.error_msg, OBJC_INTERP_ERROR_SIZE);
                return last;
            }
        } else {
            last = parse_statement(&p);
            if (p.error) {
                g_error_code = p.error;
                cstr_copy(g_error_buffer, p.error_msg, OBJC_INTERP_ERROR_SIZE);
                return last;
            }
        }
    }
    return last;
}

/* Evaluate an AST node. source is the original full source string. */
static Value eval_ast(AstNode *node, const char *source) {
    Value last = value_void();
    if (!node) return last;

    switch (node->type) {
    case AST_IF: {
        Value cond = eval_ast(node->if_stmt.condition, source);
        if (is_truthy(cond)) {
            last = eval_ast(node->if_stmt.then_branch, source);
        } else if (node->if_stmt.else_branch) {
            last = eval_ast(node->if_stmt.else_branch, source);
        }
        break;
    }

    case AST_WHILE: {
        while (1) {
            Value cond = eval_ast(node->while_stmt.condition, source);
            if (!is_truthy(cond)) break;
            g_break_pending = 0;
            g_continue_pending = 0;
            eval_ast(node->while_stmt.body, source);
            if (g_break_pending) {
                g_break_pending = 0;
                break;
            }
            if (g_continue_pending) {
                g_continue_pending = 0;
                continue; /* re-evaluate condition */
            }
            if (g_return_pending) return last;
            if (interp_should_interrupt()) return last;
        }
        break;
    }

    case AST_FOR: {
        /* Init is already evaluated during parsing (for side effects).
         * But we need to re-evaluate it for loop correctness — actually,
         * the init only runs once, so we evaluate it here. */
        eval_ast(node->for_stmt.init, source);

        while (1) {
            /* Check condition (empty condition = always true) */
            if (node->for_stmt.condition->source_range.source_len > 0) {
                Value cond = eval_ast(node->for_stmt.condition, source);
                if (!is_truthy(cond)) break;
            }

            g_break_pending = 0;
            g_continue_pending = 0;
            eval_ast(node->for_stmt.body, source);

            if (g_break_pending) {
                g_break_pending = 0;
                break;
            }
            if (g_continue_pending) {
                g_continue_pending = 0;
                /* Skip to increment */
            }
            if (g_return_pending) return last;
            if (interp_should_interrupt()) return last;

            /* Increment */
            eval_ast(node->for_stmt.increment, source);
        }
        break;
    }

    case AST_FOR_IN: {
        /* for (type var in collection) { body }
         * Evaluate the collection expression, then iterate.
         * For NSArray/NSMutableArray: iterate by index, yield elements.
         * For NSDictionary/NSMutableDictionary: iterate by keys.
         * For NSSet: iterate by elements.
         * For NSString: iterate by character. */
        Value coll = eval_source_range(node->for_in.collection_start,
                                       node->for_in.collection_len, source);
        const char *coll_str = (const char *)coll.obj_val;
        unsigned int cid = 0;
        int is_nsstring = 0;

        if (coll.is_id && coll_str != 0) {
            cid = coll_id_from_marker(coll_str, "NSArr:");
            if (cid == 0) cid = coll_id_from_marker(coll_str, "NSMutArr:");
            if (cid == 0) cid = coll_id_from_marker(coll_str, "NSDict:");
            if (cid == 0) cid = coll_id_from_marker(coll_str, "NSMutDict:");
            if (cid == 0) cid = coll_id_from_marker(coll_str, "NSSet:");
            if (cid == 0) {
                /* Not a collection marker — check if it's a string */
                is_nsstring = (!cstr_eq_n(coll_str, "NSNumber:", 9) &&
                               !cstr_eq_n(coll_str, "FDObj:", 6));
            }
        }

        if (cid > 0) {
            /* Collection iteration using side table */
            unsigned int cnt = coll_count(cid);
            unsigned int idx;
            for (idx = 0; idx < cnt; idx++) {
                int entry_idx = coll_get_nth(cid, idx);
                if (entry_idx < 0) break;
                InterpVar *var = interp_get_or_create_var(node->for_in.var_name);
                if (var) {
                    /* For dicts, yield the key; for arrays/sets, yield the element */
                    var->is_id = g_coll_entries[entry_idx].key.is_id;
                    var->value = g_coll_entries[entry_idx].key.obj_val;
                    var->is_int = g_coll_entries[entry_idx].key.is_int;
                    var->int_value = g_coll_entries[entry_idx].key.int_val;
                    var->is_class = g_coll_entries[entry_idx].key.is_class;
                    var->cls = g_coll_entries[entry_idx].key.cls_val;
                    var->is_sel = g_coll_entries[entry_idx].key.is_sel;
                    var->sel = g_coll_entries[entry_idx].key.sel_val;
                }
                g_break_pending = 0;
                g_continue_pending = 0;
                eval_ast(node->for_in.body, source);
                if (g_break_pending) { g_break_pending = 0; break; }
                if (g_continue_pending) { g_continue_pending = 0; continue; }
                if (g_return_pending) return last;
                if (interp_should_interrupt()) return last;
            }
        } else if (is_nsstring) {
            /* NSString: iterate by character */
            unsigned int len = (unsigned int)cstr_len(coll_str);
            unsigned int ci;
            for (ci = 0; ci < len; ci++) {
                InterpVar *var = interp_get_or_create_var(node->for_in.var_name);
                if (var) {
                    /* Store single character as a string in the pool */
                    {
                        char *ch_ptr = string_pool_alloc(2);
                        if (ch_ptr == 0) {
                            g_error_code = OBJC_INTERP_RESOURCE_ERROR;
                            cstr_copy(g_error_buffer, "string pool exhausted — restart kernel", OBJC_INTERP_ERROR_SIZE);
                            interp_emit_stream("warning: string pool exhausted — restart kernel\n", cstr_len("warning: string pool exhausted — restart kernel\n"));
                            break;
                        }
                        ch_ptr[0] = coll_str[ci];
                        ch_ptr[1] = '\0';
                        var->is_id = 1;
                        var->value = (id)ch_ptr;
                        var->is_int = 0;
                    }
                }
                g_break_pending = 0;
                g_continue_pending = 0;
                eval_ast(node->for_in.body, source);
                if (g_break_pending) { g_break_pending = 0; break; }
                if (g_continue_pending) { g_continue_pending = 0; continue; }
                if (g_return_pending) return last;
                if (interp_should_interrupt()) return last;
            }
        } else {
            /* Unknown collection type — just skip */
        }
        break;
    }

    case AST_BLOCK: {
        unsigned int i;
        for (i = 0; i < node->block.count; i++) {
            last = eval_ast(node->block.children[i], source);
            if (g_return_pending || g_break_pending || g_continue_pending)
                return last;
        }
        break;
    }

    case AST_EXPR_STMT:
    case AST_VAR_DECL:
        last = eval_source_range(node->source_range.source_start,
                                 node->source_range.source_len, source);
        break;

    case AST_RETURN:
        last = eval_source_range(node->source_range.source_start,
                                 node->source_range.source_len, source);
        g_return_pending = 1;
        break;

    case AST_BREAK:
        g_break_pending = 1;
        break;

    case AST_CONTINUE:
        g_continue_pending = 1;
        break;
    }

    return last;
}

/* ── Value formatting for REPL display ─────────────────────────── */

static void fmt_append_char(char *buf, unsigned int capacity, unsigned int *offset, char ch) {
    if (*offset + 1u < capacity) {
        buf[*offset] = ch;
        *offset += 1u;
        buf[*offset] = '\0';
    }
}

static void fmt_append_str(char *buf, unsigned int capacity, unsigned int *offset, const char *str) {
    unsigned int i = 0u;
    if (str == 0) return;
    while (str[i] != '\0') {
        fmt_append_char(buf, capacity, offset, str[i]);
        i++;
    }
}

static void fmt_append_uint(char *buf, unsigned int capacity, unsigned int *offset, unsigned int val) {
    char digits[12];
    int di = 0;
    if (val == 0u) {
        fmt_append_char(buf, capacity, offset, '0');
        return;
    }
    while (val > 0u && di < 11) {
        digits[di++] = '0' + (char)(val % 10u);
        val /= 10u;
    }
    while (di > 0) {
        di--;
        fmt_append_char(buf, capacity, offset, digits[di]);
    }
}

static void fmt_append_hex(char *buf, unsigned int capacity, unsigned int *offset, unsigned long ptr) {
    char hex[17];
    int hi = 0;
    if (ptr == 0) {
        fmt_append_char(buf, capacity, offset, '0');
        return;
    }
    while (ptr > 0 && hi < 16) {
        hex[hi++] = "0123456789abcdef"[ptr % 16];
        ptr /= 16;
    }
    while (hi > 0) {
        hi--;
        fmt_append_char(buf, capacity, offset, hex[hi]);
    }
}

static void format_value(Value v, char *buf, unsigned int capacity) {
    unsigned int offset = 0;
    buf[0] = '\0';

    if (v.is_int) {
        int val = v.int_val;
        if (val < 0) {
            fmt_append_char(buf, capacity, &offset, '-');
            val = -val;
        }
        fmt_append_uint(buf, capacity, &offset, (unsigned int)val);
    } else if (v.is_class && v.cls_val != 0) {
        /* Look up class name from variable table (class_getName
         * crashes on sentinel pointers in WASM) */
        const char *name = 0;
        {
            unsigned int vi;
            for (vi = 0; vi < g_var_count; vi++) {
                if (g_vars[vi].is_class && g_vars[vi].cls == v.cls_val) {
                    name = g_vars[vi].name;
                    break;
                }
            }
        }
        if (name) fmt_append_str(buf, capacity, &offset, name);
        else fmt_append_str(buf, capacity, &offset, "Class");
    } else if (v.is_sel && v.sel_val != 0) {
        const char *name = sel_getName(v.sel_val);
        fmt_append_str(buf, capacity, &offset, "(SEL) ");
        fmt_append_str(buf, capacity, &offset, name);
    } else if (v.is_id && v.obj_val != 0) {
        /* Object — try to show class name and pointer.
         * But object_getClass can crash on non-ObjC pointers (C strings),
         * so we check if the pointer looks like a Foundation stub or C string first. */
        Class cls = (Class)0;
        const char *str_val = (const char *)v.obj_val;
        if (!cstr_starts(str_val, "FDObj:") &&
            str_val != 0 &&
            (str_val < g_string_pool || str_val >= g_string_pool + OBJC_INTERP_STRING_POOL_SIZE)) {
            cls = object_getClass(v.obj_val);
        }
        const char *name = "id";
        if (cstr_starts(str_val, "FDObj:")) {
            name = str_val + 6; /* Show class name from FDObj: marker */
        } else if (cls) {
            /* Look up class name from variable table (class_getName
             * crashes on sentinel pointers in WASM) */
            unsigned int vi;
            for (vi = 0; vi < g_var_count; vi++) {
                if (g_vars[vi].is_class && g_vars[vi].cls == cls) {
                    name = g_vars[vi].name;
                    break;
                }
            }
        }
        fmt_append_str(buf, capacity, &offset, "<");
        fmt_append_str(buf, capacity, &offset, name);
        fmt_append_str(buf, capacity, &offset, ": 0x");
        fmt_append_hex(buf, capacity, &offset, (unsigned long)v.obj_val);
        fmt_append_str(buf, capacity, &offset, ">");
    } else if (v.is_id && v.obj_val == 0) {
        fmt_append_str(buf, capacity, &offset, "nil");
    }
    /* void values produce an empty string — no display */
}

void objc_interp_gc_strings(void) {
    static RelocEntry relocs[MAX_STRING_POOL_MARKS];
    unsigned int reloc_count = 0;
    unsigned int new_offset = 0;
    unsigned int i;
    unsigned int pool_limit = g_string_pool_offset;
    unsigned long pool_start = (unsigned long)g_string_pool;
    unsigned long pool_end = pool_start + (unsigned long)pool_limit;

    /* Phase 1: Mark — collect live strings from persistent roots. */
    for (i = 0; i < g_var_count && reloc_count < MAX_STRING_POOL_MARKS; i++) {
        if (g_vars[i].is_id && g_vars[i].value != 0) {
            const char *ptr = (const char *)g_vars[i].value;
            if ((unsigned long)ptr >= pool_start && (unsigned long)ptr < pool_end) {
                relocs[reloc_count].old_off = (unsigned int)((unsigned long)ptr - pool_start);
                relocs[reloc_count].new_off = 0;
                reloc_count++;
            }
        }
    }
    for (i = 0; i < g_instance_var_count && reloc_count < MAX_STRING_POOL_MARKS; i++) {
        /* Mark the object key (FDObj: marker) if it's in the string pool */
        {
            const char *obj_ptr = (const char *)g_instance_vars[i].object;
            if ((unsigned long)obj_ptr >= pool_start && (unsigned long)obj_ptr < pool_end) {
                relocs[reloc_count].old_off = (unsigned int)((unsigned long)obj_ptr - pool_start);
                relocs[reloc_count].new_off = 0;
                reloc_count++;
            }
        }
        /* Mark the value if it's an id-typed string pool pointer */
        if (g_instance_vars[i].value.is_id && g_instance_vars[i].value.obj_val != 0) {
            const char *ptr = (const char *)g_instance_vars[i].value.obj_val;
            if ((unsigned long)ptr >= pool_start && (unsigned long)ptr < pool_end) {
                relocs[reloc_count].old_off = (unsigned int)((unsigned long)ptr - pool_start);
                relocs[reloc_count].new_off = 0;
                reloc_count++;
            }
        }
    }
    /* Mark collection entry keys and values that are string pool pointers */
    for (i = 0; i < g_coll_entry_count && reloc_count < MAX_STRING_POOL_MARKS; i++) {
        if (g_coll_entries[i].key.is_id && g_coll_entries[i].key.obj_val != 0) {
            const char *ptr = (const char *)g_coll_entries[i].key.obj_val;
            if ((unsigned long)ptr >= pool_start && (unsigned long)ptr < pool_end) {
                relocs[reloc_count].old_off = (unsigned int)((unsigned long)ptr - pool_start);
                relocs[reloc_count].new_off = 0;
                reloc_count++;
            }
        }
        if (g_coll_entries[i].value.is_id && g_coll_entries[i].value.obj_val != 0) {
            const char *ptr = (const char *)g_coll_entries[i].value.obj_val;
            if ((unsigned long)ptr >= pool_start && (unsigned long)ptr < pool_end) {
                relocs[reloc_count].old_off = (unsigned int)((unsigned long)ptr - pool_start);
                relocs[reloc_count].new_off = 0;
                reloc_count++;
            }
        }
    }

    /* Mark block captured values that are string pool pointers */
    for (i = 0; i < g_block_count && reloc_count < MAX_STRING_POOL_MARKS; i++) {
        unsigned int ci;
        for (ci = 0; ci < g_blocks[i].capture_count; ci++) {
            if (g_blocks[i].captures[ci].value.is_id && g_blocks[i].captures[ci].value.obj_val != 0) {
                const char *ptr = (const char *)g_blocks[i].captures[ci].value.obj_val;
                if ((unsigned long)ptr >= pool_start && (unsigned long)ptr < pool_end) {
                    relocs[reloc_count].old_off = (unsigned int)((unsigned long)ptr - pool_start);
                    relocs[reloc_count].new_off = 0;
                    reloc_count++;
                }
            }
        }
    }

    if (reloc_count == 0) {
        g_string_pool_offset = 0;
        return;
    }

    /* Sort by old offset so compaction runs in ascending order. */
    {
        unsigned int j;
        for (i = 1; i < reloc_count; i++) {
            RelocEntry tmp = relocs[i];
            j = i;
            while (j > 0 && relocs[j - 1].old_off > tmp.old_off) {
                relocs[j] = relocs[j - 1];
                j--;
            }
            relocs[j] = tmp;
        }
    }

    /* Phase 2: Compact — move only unique live strings. */
    for (i = 0; i < reloc_count; i++) {
        unsigned int old = relocs[i].old_off;
        if (i > 0 && relocs[i - 1].old_off == old) {
            relocs[i].new_off = relocs[i - 1].new_off;
            continue;
        }

        {
            unsigned int len = cstr_len(g_string_pool + old) + 1;
            if (old != new_offset) {
                memmove(g_string_pool + new_offset, g_string_pool + old, len);
            }
            relocs[i].new_off = new_offset;
            new_offset += len;
        }
    }
    g_string_pool_offset = new_offset;

    /* Phase 3: Update — rewrite all root pointers to their new offsets.
     * This includes variable values, instance var values, AND instance var
     * object keys (since FDObj: markers live in the string pool). */
    for (i = 0; i < g_var_count; i++) {
        if (g_vars[i].is_id && g_vars[i].value != 0) {
            const char *ptr = (const char *)g_vars[i].value;
            if ((unsigned long)ptr >= pool_start && (unsigned long)ptr < pool_end) {
                unsigned int off = (unsigned int)((unsigned long)ptr - pool_start);
                unsigned int r;
                for (r = 0; r < reloc_count; r++) {
                    if (relocs[r].old_off == off) {
                        g_vars[i].value = (id)(g_string_pool + relocs[r].new_off);
                        break;
                    }
                }
            }
        }
    }
    for (i = 0; i < g_instance_var_count; i++) {
        /* Update the object key if it's a string pool pointer (FDObj: marker) */
        {
            const char *obj_ptr = (const char *)g_instance_vars[i].object;
            if ((unsigned long)obj_ptr >= pool_start && (unsigned long)obj_ptr < pool_end) {
                unsigned int off = (unsigned int)((unsigned long)obj_ptr - pool_start);
                unsigned int r;
                for (r = 0; r < reloc_count; r++) {
                    if (relocs[r].old_off == off) {
                        g_instance_vars[i].object = (id)(g_string_pool + relocs[r].new_off);
                        break;
                    }
                }
            }
        }
        /* Update the value if it's an id-typed string pool pointer */
        if (g_instance_vars[i].value.is_id && g_instance_vars[i].value.obj_val != 0) {
            const char *ptr = (const char *)g_instance_vars[i].value.obj_val;
            if ((unsigned long)ptr >= pool_start && (unsigned long)ptr < pool_end) {
                unsigned int off = (unsigned int)((unsigned long)ptr - pool_start);
                unsigned int r;
                for (r = 0; r < reloc_count; r++) {
                    if (relocs[r].old_off == off) {
                        g_instance_vars[i].value.obj_val = (id)(g_string_pool + relocs[r].new_off);
                        break;
                    }
                }
            }
        }
    }
    /* Update collection entry keys and values that are string pool pointers */
    for (i = 0; i < g_coll_entry_count; i++) {
        if (g_coll_entries[i].key.is_id && g_coll_entries[i].key.obj_val != 0) {
            const char *ptr = (const char *)g_coll_entries[i].key.obj_val;
            if ((unsigned long)ptr >= pool_start && (unsigned long)ptr < pool_end) {
                unsigned int off = (unsigned int)((unsigned long)ptr - pool_start);
                unsigned int r;
                for (r = 0; r < reloc_count; r++) {
                    if (relocs[r].old_off == off) {
                        g_coll_entries[i].key.obj_val = (id)(g_string_pool + relocs[r].new_off);
                        break;
                    }
                }
            }
        }
        if (g_coll_entries[i].value.is_id && g_coll_entries[i].value.obj_val != 0) {
            const char *ptr = (const char *)g_coll_entries[i].value.obj_val;
            if ((unsigned long)ptr >= pool_start && (unsigned long)ptr < pool_end) {
                unsigned int off = (unsigned int)((unsigned long)ptr - pool_start);
                unsigned int r;
                for (r = 0; r < reloc_count; r++) {
                    if (relocs[r].old_off == off) {
                        g_coll_entries[i].value.obj_val = (id)(g_string_pool + relocs[r].new_off);
                        break;
                    }
                }
            }
        }
    }
    /* Update block captured values that are string pool pointers */
    for (i = 0; i < g_block_count; i++) {
        unsigned int ci;
        for (ci = 0; ci < g_blocks[i].capture_count; ci++) {
            if (g_blocks[i].captures[ci].value.is_id && g_blocks[i].captures[ci].value.obj_val != 0) {
                const char *ptr = (const char *)g_blocks[i].captures[ci].value.obj_val;
                if ((unsigned long)ptr >= pool_start && (unsigned long)ptr < pool_end) {
                    unsigned int off = (unsigned int)((unsigned long)ptr - pool_start);
                    unsigned int r;
                    for (r = 0; r < reloc_count; r++) {
                        if (relocs[r].old_off == off) {
                            g_blocks[i].captures[ci].value.obj_val = (id)(g_string_pool + relocs[r].new_off);
                            break;
                        }
                    }
                }
            }
        }
    }
}

void objc_interp_init(void) {
    g_nslog_offset = 0;
    g_nslog_buffer[0] = '\0';
    g_error_code = OBJC_INTERP_OK;
    g_error_buffer[0] = '\0';
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

    /* Reset per-execution state */
    g_nslog_offset = 0;
    g_nslog_buffer[0] = '\0';
    g_error_code = OBJC_INTERP_OK;
    g_error_buffer[0] = '\0';
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
    g_result_buffer[0] = '\0';
    /* Don't reset g_var_count — variables persist across cells */
    /* Don't reset g_method_count — methods persist across cells */
}
