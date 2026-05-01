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
static unsigned int g_error_line = 0;
static unsigned int g_error_column = 0;

/* Forward declaration — Parser struct defined below */
struct Parser;
static void set_error_from_parser(struct Parser *p);

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
    int is_float;
    double float_value;
    int is_class;   /* 1 if this holds a Class */
    int is_sel;     /* 1 if this holds a SEL */
    int is_id;      /* 1 if this holds an id */
    int is_block_captured; /* 1 if __block variable — capture by reference */
} InterpVar;

#define OBJC_INTERP_MAX_BLOCKS_CAPTURED 32

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
    TOK_FLOAT_LITERAL,
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
    TOK_SWITCH,        /* switch keyword */
    TOK_CASE,          /* case keyword */
    TOK_DEFAULT,       /* default keyword */
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

/* ── Parser ─────────────────────────────────────────────────────── */

typedef struct Parser {
    Lexer lex;
    int error;
    char error_msg[OBJC_INTERP_ERROR_SIZE];
} Parser;

static void set_error_from_parser(Parser *p) {
    g_error_code = p->error;
    cstr_copy(g_error_buffer, p->error_msg, OBJC_INTERP_ERROR_SIZE);
    g_error_line = p->lex.line;
    g_error_column = p->lex.column;
}

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
    double float_val;
    int is_int;
    int is_float;
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
    v.float_val = 0.0;
    v.is_int = 0;
    v.is_float = 0;
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
    v.float_val = 0.0;
    v.is_int = 0;
    v.is_float = 0;
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
    v.float_val = 0.0;
    v.is_int = 1;
    v.is_float = 0;
    v.is_class = 0;
    v.is_sel = 0;
    v.is_id = 0;
    v.is_void = 0;
    return v;
}

static Value value_from_float(double f) {
    Value v;
    v.obj_val = 0;
    v.cls_val = 0;
    v.sel_val = 0;
    v.int_val = 0;
    v.float_val = f;
    v.is_int = 0;
    v.is_float = 1;
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
    v.float_val = 0.0;
    v.is_int = 0;
    v.is_float = 0;
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
    v.float_val = 0.0;
    v.is_int = 0;
    v.is_float = 0;
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

/* Insert an entry at a logical position within a collection.
 * Shifts existing entries at that position and later to make room.
 * Returns 0 on success, -1 if table full or position invalid. */
static int coll_insert_at(unsigned int coll_id, unsigned int pos, Value key, Value value);

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

static int coll_insert_at(unsigned int coll_id, unsigned int pos, Value key, Value value) {
    int nth = coll_get_nth(coll_id, pos);
    if (nth < 0) return -1;
    if (g_coll_entry_count >= MAX_COLL_ENTRIES) return -1;
    /* Shift entries from nth onward to make room */
    {
        unsigned int i;
        for (i = g_coll_entry_count; i > (unsigned int)nth; i--) {
            g_coll_entries[i] = g_coll_entries[i - 1];
        }
    }
    g_coll_entries[(unsigned int)nth].coll_id = coll_id;
    g_coll_entries[(unsigned int)nth].key = key;
    g_coll_entries[(unsigned int)nth].value = value;
    g_coll_entry_count++;
    return 0;
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
    int is_by_ref;   /* 1 if __block — capture by reference */
    unsigned int var_index; /* index into g_vars[] for by-reference access */
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

/* Check if a property belongs to the receiver's class.
 * For FDObj: markers, extracts the class name and compares against
 * g_properties[pi].class_name. For non-FDObj: receivers (Foundation
 * objects), returns 1 (always match) since Foundation classes don't
 * have user-defined properties. */
static int property_matches_class(id receiver, unsigned int pi) {
    const char *s = (const char *)receiver;
    if (receiver != 0 && cstr_starts(s, "FDObj:")) {
        const char *recv_class = s + 6;
        if (g_properties[pi].class_name[0] != '\0' &&
            !cstr_eq(recv_class, g_properties[pi].class_name)) {
            return 0;
        }
    }
    return 1;
}

/* Check if a variable name is a synthesized ivar name.
 * Returns the property index if found, or -1 if not.
 * This is used to redirect ivar access in method bodies to the side table. */
static int find_synthesized_ivar(const char *var_name, id receiver) {
    unsigned int pi;
    for (pi = 0; pi < g_property_count; pi++) {
        if (g_properties[pi].synthesized &&
            g_properties[pi].ivar_name[0] != '\0' &&
            cstr_eq(var_name, g_properties[pi].ivar_name) &&
            property_matches_class(receiver, pi)) {
            return (int)pi;
        }
    }
    return -1;
}

/* Read a synthesized ivar value from the side table.
 * Returns the value, or value_void() if not found. */
static Value synthesized_ivar_get(id self, const char *var_name) {
    int pi = find_synthesized_ivar(var_name, self);
    if (pi >= 0) {
        Value *val = instance_var_get(self, g_properties[pi].name);
        if (val) return *val;
    }
    return value_void();
}

/* Write a synthesized ivar value to the side table. */
static int synthesized_ivar_set(id self, const char *var_name, Value val) {
    int pi = find_synthesized_ivar(var_name, self);
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
    AST_CONTINUE,
    AST_SWITCH,
    AST_DO_WHILE
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
        struct { /* AST_SWITCH */
            unsigned int expr_start;  /* source range for switch expression */
            unsigned int expr_len;
            int case_values[32];      /* integer values for each case */
            AstNode *case_bodies[32]; /* body block for each case */
            unsigned int case_count;
            int has_default;
            AstNode *default_body;
        } switch_stmt;
        struct { /* AST_DO_WHILE */
            AstNode *condition;
            AstNode *body;
        } do_while_stmt;
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

static AstNode *ast_make_do_while(AstNode *body, AstNode *condition) {
    AstNode *n = ast_alloc();
    if (!n) return 0;
    n->type = AST_DO_WHILE;
    n->do_while_stmt.body = body;
    n->do_while_stmt.condition = condition;
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
                    /* Object — print description or string */
                    if (arg_idx < arg_count) {
                        Value v = args[arg_idx++];
                        if (v.is_id && v.obj_val != 0) {
                            const char *s = (const char *)v.obj_val;
                            /* NSData: display as <hex bytes> */
                            if (cstr_eq_n(s, "NSData:", 7)) {
                                const char *hex = s + 7;
                                int hex_len = (int)cstr_len(hex);
                                nslog_append("<", 1);
                                {
                                    int i;
                                    for (i = 0; i < hex_len; i++) {
                                        if (i > 0 && i % 8 == 0) nslog_append(" ", 1);
                                        nslog_append(&hex[i], 1);
                                    }
                                }
                                nslog_append(">", 1);
                            }
                            /* NSNumber: display numeric value */
                            else if (cstr_eq_n(s, "NSNumber:", 9)) {
                                nslog_append(s + 9, cstr_len(s + 9));
                            }
                            /* NSFloat: display float value */
                            else if (cstr_eq_n(s, "NSFloat:", 8)) {
                                nslog_append(s + 8, cstr_len(s + 8));
                            }
                            /* FDObj: display as <ClassName> */
                            else if (cstr_eq_n(s, "FDObj:", 6)) {
                                nslog_append("<", 1);
                                nslog_append(s + 6, cstr_len(s + 6));
                                nslog_append(">", 1);
                            }
                            /* Collection markers: display summary */
                            else if (cstr_eq_n(s, "NSArr:", 6) || cstr_eq_n(s, "NSMutArr:", 9) ||
                                     cstr_eq_n(s, "NSDict:", 7) || cstr_eq_n(s, "NSMutDict:", 10) ||
                                     cstr_eq_n(s, "NSSet:", 6) || cstr_eq_n(s, "NSBlock:", 8)) {
                                nslog_append(s, cstr_len(s));
                            }
                            /* Regular string */
                            else {
                                nslog_append(s, cstr_len(s));
                            }
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
                        } else if (v.is_sel && v.sel_val != 0) {
                            const char *sel_name = sel_getName(v.sel_val);
                            if (sel_name) nslog_append(sel_name, cstr_len(sel_name));
                            else nslog_append("(SEL)null", 9);
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
                    /* Float/double */
                    if (arg_idx < arg_count) {
                        Value v = args[arg_idx++];
                        if (v.is_float) {
                            /* Simple %f: 6 decimal places */
                            char fbuf[64];
                            int fi = 0;
                            double fv = v.float_val;
                            int negative = 0;
                            if (fv < 0.0) { negative = 1; fv = -fv; }
                            /* Integer part */
                            unsigned long ipart = (unsigned long)fv;
                            double fpart = fv - (double)ipart;
                            if (negative) fbuf[fi++] = '-';
                            /* Convert integer part */
                            if (ipart == 0) {
                                fbuf[fi++] = '0';
                            } else {
                                char ibuf[20];
                                int ii = 0;
                                while (ipart > 0) { ibuf[ii++] = '0' + (ipart % 10); ipart /= 10; }
                                while (ii > 0) fbuf[fi++] = ibuf[--ii];
                            }
                            fbuf[fi++] = '.';
                            /* 6 decimal places */
                            for (int d = 0; d < 6; d++) {
                                fpart *= 10.0;
                                int digit = (int)fpart;
                                fbuf[fi++] = '0' + digit;
                                fpart -= digit;
                            }
                            /* Trim trailing zeros */
                            while (fi > 1 && fbuf[fi-1] == '0') fi--;
                            if (fbuf[fi-1] == '.') fi++; /* keep one decimal place */
                            fbuf[fi] = '\0';
                            nslog_append(fbuf, fi);
                        } else if (v.is_int) {
                            /* %f with int argument: promote to double */
                            char fbuf[32];
                            int fi = 0;
                            int iv = v.int_val;
                            if (iv < 0) { fbuf[fi++] = '-'; iv = -iv; }
                            if (iv == 0) { fbuf[fi++] = '0'; }
                            else {
                                char ibuf[20];
                                int ii = 0;
                                while (iv > 0) { ibuf[ii++] = '0' + (iv % 10); iv /= 10; }
                                while (ii > 0) fbuf[fi++] = ibuf[--ii];
                            }
                            fbuf[fi++] = '.'; fbuf[fi++] = '0'; fbuf[fi++] = '0';
                            fbuf[fi++] = '0'; fbuf[fi++] = '0'; fbuf[fi++] = '0';
                            fbuf[fi++] = '0'; fbuf[fi] = '\0';
                            nslog_append(fbuf, fi);
                        }
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

/* Format values into a string pool entry, similar to NSLog but without
 * the trailing newline and host stream output. Returns the string pool
 * pointer as an id value. */
static Value format_values_to_pool(const char *fmt, Value *args, int arg_count) {
    char buf[1024];
    unsigned int pos = 0;
    unsigned int fi = 0;
    int arg_idx = 0;

    if (fmt == 0) {
        char *r = string_pool_alloc(7);
        if (r == 0) return value_from_id(0);
        cstr_copy(r, "(null)", 7);
        return value_from_id((id)r);
    }

    while (fmt[fi] != '\0' && pos < sizeof(buf) - 1) {
        if (fmt[fi] == '%' && fmt[fi + 1] != '\0') {
            fi++;
            switch (fmt[fi]) {
                case '%':
                    if (pos < sizeof(buf)-1) buf[pos++] = '%';
                    break;
                case '@':
                    if (arg_idx < arg_count) {
                        Value v = args[arg_idx++];
                        if (v.is_id && v.obj_val != 0) {
                            const char *s = (const char *)v.obj_val;
                            if (cstr_eq_n(s, "NSData:", 7)) {
                                const char *hex = s + 7;
                                int hex_len = (int)cstr_len(hex);
                                if (pos < sizeof(buf)-1) buf[pos++] = '<';
                                { int i; for (i = 0; i < hex_len && pos < sizeof(buf)-2; i++) buf[pos++] = hex[i]; }
                                if (pos < sizeof(buf)-1) buf[pos++] = '>';
                            } else if (cstr_eq_n(s, "NSNumber:", 9)) {
                                const char *val = s + 9;
                                while (*val && pos < sizeof(buf)-1) buf[pos++] = *val++;
                            } else if (cstr_eq_n(s, "NSFloat:", 8)) {
                                const char *val = s + 8;
                                while (*val && pos < sizeof(buf)-1) buf[pos++] = *val++;
                            } else if (cstr_eq_n(s, "FDObj:", 6)) {
                                if (pos < sizeof(buf)-1) buf[pos++] = '<';
                                { const char *cn = s + 6; while (*cn && pos < sizeof(buf)-2) buf[pos++] = *cn++; }
                                if (pos < sizeof(buf)-1) buf[pos++] = '>';
                            } else {
                                while (*s && pos < sizeof(buf)-1) buf[pos++] = *s++;
                            }
                        } else if (v.is_class && v.cls_val != 0) {
                            const char *name = 0;
                            unsigned int vi;
                            for (vi = 0; vi < g_var_count; vi++) {
                                if (g_vars[vi].is_class && g_vars[vi].cls == v.cls_val) {
                                    name = g_vars[vi].name; break;
                                }
                            }
                            if (name == 0) name = "Class";
                            while (*name && pos < sizeof(buf)-1) buf[pos++] = *name++;
                        } else if (v.is_sel && v.sel_val != 0) {
                            const char *sel_name = sel_getName(v.sel_val);
                            if (sel_name) { while (*sel_name && pos < sizeof(buf)-1) buf[pos++] = *sel_name++; }
                        } else if (v.is_int) {
                            /* Format int as decimal */
                            int val = v.int_val;
                            int neg = val < 0;
                            if (neg) val = -val;
                            char tmp[12]; int ti = 0;
                            if (val == 0) tmp[ti++] = '0';
                            else { while (val > 0) { tmp[ti++] = '0' + (val % 10); val /= 10; } }
                            if (neg && pos < sizeof(buf)-1) buf[pos++] = '-';
                            while (ti > 0 && pos < sizeof(buf)-1) buf[pos++] = tmp[--ti];
                        } else {
                            const char *nil_s = "(nil)";
                            while (*nil_s && pos < sizeof(buf)-1) buf[pos++] = *nil_s++;
                        }
                    }
                    break;
                case 'd': case 'i':
                    if (arg_idx < arg_count) {
                        Value v = args[arg_idx++];
                        if (v.is_int) {
                            int val = v.int_val;
                            int neg = val < 0;
                            if (neg) val = -val;
                            char tmp[12]; int ti = 0;
                            if (val == 0) tmp[ti++] = '0';
                            else { while (val > 0) { tmp[ti++] = '0' + (val % 10); val /= 10; } }
                            if (neg && pos < sizeof(buf)-1) buf[pos++] = '-';
                            while (ti > 0 && pos < sizeof(buf)-1) buf[pos++] = tmp[--ti];
                        } else if (v.is_id) {
                            int val = (int)(long)v.obj_val;
                            int neg = val < 0;
                            if (neg) val = -val;
                            char tmp[12]; int ti = 0;
                            if (val == 0) tmp[ti++] = '0';
                            else { while (val > 0) { tmp[ti++] = '0' + (val % 10); val /= 10; } }
                            if (neg && pos < sizeof(buf)-1) buf[pos++] = '-';
                            while (ti > 0 && pos < sizeof(buf)-1) buf[pos++] = tmp[--ti];
                        }
                    }
                    break;
                case 'l':
                    if (fmt[fi + 1] == 'd' || fmt[fi + 1] == 'i') {
                        fi++;
                        if (arg_idx < arg_count) {
                            Value v = args[arg_idx++];
                            if (v.is_int) {
                                long val = (long)v.int_val;
                                int neg = val < 0;
                                if (neg) val = -val;
                                char tmp[20]; int ti = 0;
                                if (val == 0) tmp[ti++] = '0';
                                else { while (val > 0) { tmp[ti++] = '0' + (int)(val % 10); val /= 10; } }
                                if (neg && pos < sizeof(buf)-1) buf[pos++] = '-';
                                while (ti > 0 && pos < sizeof(buf)-1) buf[pos++] = tmp[--ti];
                            }
                        }
                    }
                    break;
                case 'u':
                    if (arg_idx < arg_count) {
                        Value v = args[arg_idx++];
                        if (v.is_int) {
                            int val = v.int_val;
                            if (val < 0) val = 0;
                            char tmp[12]; int ti = 0;
                            if (val == 0) tmp[ti++] = '0';
                            else { while (val > 0) { tmp[ti++] = '0' + (val % 10); val /= 10; } }
                            while (ti > 0 && pos < sizeof(buf)-1) buf[pos++] = tmp[--ti];
                        }
                    }
                    break;
                case 'f': {
                    if (arg_idx < arg_count && pos < sizeof(buf) - 10) {
                        Value v = args[arg_idx++];
                        double fv = v.is_float ? v.float_val : (v.is_int ? (double)v.int_val : 0.0);
                        int neg = fv < 0.0;
                        if (neg) fv = -fv;
                        unsigned long ipart = (unsigned long)fv;
                        double fpart = fv - (double)ipart;
                        if (neg && pos < sizeof(buf)-1) buf[pos++] = '-';
                        if (ipart == 0 && pos < sizeof(buf)-1) buf[pos++] = '0';
                        else {
                            char ibuf[20]; int ii = 0;
                            while (ipart > 0) { ibuf[ii++] = '0' + (int)(ipart % 10); ipart /= 10; }
                            while (ii > 0 && pos < sizeof(buf)-1) buf[pos++] = ibuf[--ii];
                        }
                        if (pos < sizeof(buf)-1) buf[pos++] = '.';
                        { int d; for (d = 0; d < 6 && pos < sizeof(buf)-2; d++) {
                            fpart *= 10.0;
                            int digit = (int)fpart;
                            buf[pos++] = '0' + digit;
                            fpart -= digit;
                        }}
                        while (pos > 1 && buf[pos-1] == '0') pos--;
                        if (pos > 0 && buf[pos-1] == '.' && pos < sizeof(buf)-1) buf[pos++] = '0';
                    }
                    break;
                }
                case 's':
                    if (arg_idx < arg_count) {
                        Value v = args[arg_idx++];
                        if (v.is_id && v.obj_val != 0) {
                            const char *s = (const char *)v.obj_val;
                            while (*s && pos < sizeof(buf)-1) buf[pos++] = *s++;
                        }
                    }
                    break;
                case 'p':
                    if (arg_idx < arg_count && pos < sizeof(buf) - 3) {
                        Value v = args[arg_idx++];
                        if (pos < sizeof(buf)-1) buf[pos++] = '0';
                        if (pos < sizeof(buf)-1) buf[pos++] = 'x';
                        if (v.is_id) {
                            unsigned long ptr = (unsigned long)v.obj_val;
                            char hex[17]; int hi = 0;
                            if (ptr == 0 && pos < sizeof(buf)-1) buf[pos++] = '0';
                            else {
                                while (ptr > 0 && hi < 16) { hex[hi++] = "0123456789abcdef"[ptr % 16]; ptr /= 16; }
                                while (hi > 0 && pos < sizeof(buf)-1) buf[pos++] = hex[--hi];
                            }
                        }
                    }
                    break;
                default:
                    if (pos < sizeof(buf)-2) { buf[pos++] = '%'; buf[pos++] = fmt[fi]; }
                    break;
            }
            fi++;
        } else {
            buf[pos++] = fmt[fi++];
        }
    }
    buf[pos] = '\0';

    {
        unsigned int needed = pos + 1;
        char *result = string_pool_alloc(needed);
        if (result == 0) return value_from_id(0);
        cstr_copy(result, buf, needed);
        return value_from_id((id)result);
    }
}

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
            const char *s = (const char *)receiver;
            /* FDObj: markers — return class pointer from variable table */
            if (cstr_starts(s, "FDObj:")) {
                const char *recv_class_name = s + 6;
                unsigned int vi;
                for (vi = 0; vi < g_var_count; vi++) {
                    if (g_vars[vi].is_class && cstr_eq(g_vars[vi].name, recv_class_name)) {
                        return value_from_class(g_vars[vi].cls);
                    }
                }
                return value_from_class((Class)0);
            }
            /* Tagged Foundation string pool objects — return their sentinel class */
            if (cstr_starts(s, "NSNumber:")) return value_from_class((Class)3);
            if (cstr_starts(s, "NSFloat:")) return value_from_class((Class)3);
            if (cstr_starts(s, "NSArr:")) return value_from_class((Class)4);
            if (cstr_starts(s, "NSMutArr:")) return value_from_class((Class)4);
            if (cstr_starts(s, "NSDict:")) return value_from_class((Class)5);
            if (cstr_starts(s, "NSMutDict:")) return value_from_class((Class)5);
            if (cstr_starts(s, "NSSet:")) return value_from_class((Class)6);
            if (cstr_starts(s, "NSData:")) return value_from_class((Class)7);
            if (cstr_starts(s, "NSBlock:")) return value_from_class((Class)8);
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
                /* For real ObjC objects, try object_getClass.
                 * Guard against string pool pointers. */
                const char *ptr = (const char *)receiver;
                if (ptr >= g_string_pool && ptr < g_string_pool + OBJC_INTERP_STRING_POOL_SIZE) {
                    nslog_append("<unknown>", 9);
                } else {
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
            }
            return value_from_id(receiver);
        }

        /* NSObject: [obj isEqual:other] → 1 if same pointer */
        if (cstr_eq(sel_name, "isEqual:") && target.is_id && arg_count >= 1) {
            /* NSData: compare by content (not pointer) */
            if (receiver != 0 && cstr_eq_n((const char *)receiver, "NSData:", 7)) {
                const char *other = (const char *)args[0];
                if (other && cstr_eq_n(other, "NSData:", 7)) {
                    return value_from_int(cstr_eq((const char *)receiver, other) ? 1 : 0);
                }
                return value_from_int(0);
            }
            /* NSNumber: compare by value (not pointer) */
            if (receiver != 0 && (cstr_eq_n((const char *)receiver, "NSNumber:", 9) ||
                                  cstr_eq_n((const char *)receiver, "NSFloat:", 8))) {
                const char *other = (const char *)args[0];
                if (other && (cstr_eq_n(other, "NSNumber:", 9) || cstr_eq_n(other, "NSFloat:", 8))) {
                    return value_from_int(cstr_eq((const char *)receiver, other) ? 1 : 0);
                }
                return value_from_int(0);
            }
            /* Default: pointer comparison */
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
            const char *fmt = 0;
            if (keyword_args[0].is_id && keyword_args[0].obj_val != 0) {
                fmt = (const char *)keyword_args[0].obj_val;
            }
            return format_values_to_pool(fmt, keyword_args + 1, arg_count - 1);
        }

        /* NSString: [str length] → string length */
        if (cstr_eq(sel_name, "length") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            /* NSData: length = hex_len / 2 */
            if (cstr_eq_n(s, "NSData:", 7)) {
                int hex_len = (int)cstr_len(s + 7);
                return value_from_int(hex_len / 2);
            }
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

        /* NSString: [str substringFromIndex:n] → extract from index to end */
        if (cstr_eq(sel_name, "substringFromIndex:") && target.is_id && receiver != 0 && arg_count >= 1) {
            const char *s = (const char *)receiver;
            int from = keyword_args[0].is_int ? keyword_args[0].int_val : 0;
            int slen = (int)cstr_len(s);
            if (from < 0) from = 0;
            if (from > slen) from = slen;
            {
                unsigned int needed = (unsigned int)(slen - from) + 1;
                char *result = string_pool_alloc(needed);
                if (result == 0) return value_from_id(receiver);
                cstr_copy(result, s + from, needed);
                return value_from_id((id)result);
            }
        }

        /* NSString: [str substringToIndex:n] → extract from start to index */
        if (cstr_eq(sel_name, "substringToIndex:") && target.is_id && receiver != 0 && arg_count >= 1) {
            const char *s = (const char *)receiver;
            int to = keyword_args[0].is_int ? keyword_args[0].int_val : 0;
            int slen = (int)cstr_len(s);
            if (to < 0) to = 0;
            if (to > slen) to = slen;
            {
                unsigned int needed = (unsigned int)to + 1;
                char *result = string_pool_alloc(needed);
                if (result == 0) return value_from_id(receiver);
                cstr_copy(result, s, needed);
                result[to] = '\0';
                return value_from_id((id)result);
            }
        }

        /* NSString: [str characterAtIndex:n] → return character as int */
        if (cstr_eq(sel_name, "characterAtIndex:") && target.is_id && receiver != 0 && arg_count >= 1) {
            const char *s = (const char *)receiver;
            int idx = keyword_args[0].is_int ? keyword_args[0].int_val : 0;
            int slen = (int)cstr_len(s);
            if (idx < 0 || idx >= slen) return value_from_int(0);
            return value_from_int((int)(unsigned char)s[idx]);
        }

        /* NSString: [str hasPrefix:prefix] → check if string starts with prefix */
        if (cstr_eq(sel_name, "hasPrefix:") && target.is_id && receiver != 0 && arg_count >= 1) {
            const char *s = (const char *)receiver;
            const char *prefix = (const char *)keyword_args[0].obj_val;
            int slen = (int)cstr_len(s);
            int plen = (int)cstr_len(prefix);
            if (plen > slen || plen == 0) return value_from_int(plen == 0 ? 1 : 0);
            return value_from_int(cstr_starts(s, prefix) ? 1 : 0);
        }

        /* NSString: [str hasSuffix:suffix] → check if string ends with suffix */
        if (cstr_eq(sel_name, "hasSuffix:") && target.is_id && receiver != 0 && arg_count >= 1) {
            const char *s = (const char *)receiver;
            const char *suffix = (const char *)keyword_args[0].obj_val;
            int slen = (int)cstr_len(s);
            int sfxlen = (int)cstr_len(suffix);
            if (sfxlen > slen || sfxlen == 0) return value_from_int(sfxlen == 0 ? 1 : 0);
            return value_from_int(cstr_eq(s + slen - sfxlen, suffix) ? 1 : 0);
        }

        /* NSString: [str uppercaseString] → ASCII uppercase */
        if (cstr_eq(sel_name, "uppercaseString") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            int slen = (int)cstr_len(s);
            char *result = string_pool_alloc((unsigned int)slen + 1);
            if (result == 0) return value_from_id(receiver);
            {
                int i;
                for (i = 0; i < slen; i++) {
                    char c = s[i];
                    if (c >= 'a' && c <= 'z') c = (char)(c - 32);
                    result[i] = c;
                }
                result[slen] = '\0';
            }
            return value_from_id((id)result);
        }

        /* NSString: [str lowercaseString] → ASCII lowercase */
        if (cstr_eq(sel_name, "lowercaseString") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            int slen = (int)cstr_len(s);
            char *result = string_pool_alloc((unsigned int)slen + 1);
            if (result == 0) return value_from_id(receiver);
            {
                int i;
                for (i = 0; i < slen; i++) {
                    char c = s[i];
                    if (c >= 'A' && c <= 'Z') c = (char)(c + 32);
                    result[i] = c;
                }
                result[slen] = '\0';
            }
            return value_from_id((id)result);
        }

        /* NSString: [str stringByReplacingOccurrencesOfString:find withString:replace]
         * Replace all occurrences of find with replace. */
        if (cstr_eq(sel_name, "stringByReplacingOccurrencesOfString:withString:") && target.is_id && receiver != 0 && arg_count >= 2) {
            const char *src = (const char *)receiver;
            const char *find = (const char *)keyword_args[0].obj_val;
            const char *repl = (const char *)keyword_args[1].obj_val;
            int src_len = (int)cstr_len(src);
            int find_len = (int)cstr_len(find);
            int repl_len = (int)cstr_len(repl);
            if (find_len == 0) return value_from_id(receiver);
            {
                /* Two passes: count matches to size the buffer, then build */
                int match_count = 0;
                int si;
                for (si = 0; si <= src_len - find_len; ) {
                    if (cstr_starts(src + si, find)) {
                        match_count++;
                        si += find_len;
                    } else {
                        si++;
                    }
                }
                unsigned int needed = (unsigned int)(src_len + match_count * (repl_len - find_len)) + 1;
                char *result = string_pool_alloc(needed);
                if (result == 0) return value_from_id(receiver);
                {
                    int ri = 0;
                    si = 0;
                    while (si < src_len) {
                        if (si <= src_len - find_len && cstr_starts(src + si, find)) {
                            int j;
                            for (j = 0; j < repl_len && ri < (int)needed - 1; j++)
                                result[ri++] = repl[j];
                            si += find_len;
                        } else {
                            result[ri++] = src[si++];
                        }
                    }
                    result[ri] = '\0';
                }
                return value_from_id((id)result);
            }
        }

        /* NSString: [str componentsSeparatedByString:sep] → NSArray of components */
        if (cstr_eq(sel_name, "componentsSeparatedByString:") && target.is_id && receiver != 0 && arg_count >= 1) {
            const char *src = (const char *)receiver;
            const char *sep = (const char *)keyword_args[0].obj_val;
            int src_len = (int)cstr_len(src);
            int sep_len = (int)cstr_len(sep);
            unsigned int new_cid = g_next_coll_id++;
            Value dummy = value_void();
            if (sep_len == 0) {
                /* Empty separator: each char is a component */
                int i;
                for (i = 0; i < src_len; i++) {
                    char *comp = string_pool_alloc(2);
                    if (comp) { comp[0] = src[i]; comp[1] = '\0'; }
                    if (comp) coll_add(new_cid, value_from_id((id)comp), dummy);
                }
            } else {
                int start = 0;
                int si;
                for (si = 0; si <= src_len; ) {
                    if (si <= src_len - sep_len && cstr_starts(src + si, sep)) {
                        /* Component from start to si */
                        int comp_len = si - start;
                        char *comp = string_pool_alloc((unsigned int)comp_len + 1);
                        if (comp) {
                            int j;
                            for (j = 0; j < comp_len; j++) comp[j] = src[start + j];
                            comp[comp_len] = '\0';
                            coll_add(new_cid, value_from_id((id)comp), dummy);
                        }
                        si += sep_len;
                        start = si;
                    } else {
                        si++;
                    }
                }
                /* Last component */
                {
                    int comp_len = src_len - start;
                    char *comp = string_pool_alloc((unsigned int)comp_len + 1);
                    if (comp) {
                        int j;
                        for (j = 0; j < comp_len; j++) comp[j] = src[start + j];
                        comp[comp_len] = '\0';
                        coll_add(new_cid, value_from_id((id)comp), dummy);
                    }
                }
            }
            return value_from_id(coll_make_marker("NSArr:", new_cid));
        }

        /* NSString: [str stringByTrimmingWhitespace] → trim leading/trailing whitespace
         * Convenience method (not a real ObjC API — that uses
         * stringByTrimmingCharactersInSet: which needs NSCharacterSet). */
        if (cstr_eq(sel_name, "stringByTrimmingWhitespace") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            int slen = (int)cstr_len(s);
            int start = 0, end = slen;
            while (start < end && (s[start] == ' ' || s[start] == '\t' || s[start] == '\n' || s[start] == '\r'))
                start++;
            while (end > start && (s[end-1] == ' ' || s[end-1] == '\t' || s[end-1] == '\n' || s[end-1] == '\r'))
                end--;
            {
                int comp_len = end - start;
                unsigned int needed = (unsigned int)comp_len + 1;
                char *result = string_pool_alloc(needed);
                if (result == 0) return value_from_id(receiver);
                {
                    int i;
                    for (i = 0; i < comp_len; i++) result[i] = s[start + i];
                    result[comp_len] = '\0';
                }
                return value_from_id((id)result);
            }
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
            /* NSData: display as <hex bytes> */
            if (cstr_eq_n(s, "NSData:", 7)) {
                const char *hex = s + 7;
                int hex_len = (int)cstr_len(hex);
                unsigned int needed = 2 + (unsigned int)hex_len + (unsigned int)(hex_len / 8) + 1;
                char *result = string_pool_alloc(needed);
                if (result) {
                    int ri = 0, i;
                    result[ri++] = '<';
                    for (i = 0; i < hex_len; i++) {
                        if (i > 0 && i % 8 == 0) result[ri++] = ' ';
                        result[ri++] = hex[i];
                    }
                    result[ri++] = '>';
                    result[ri] = '\0';
                    return value_from_id((id)result);
                }
            }
            /* NSNumber: display numeric value */
            if (cstr_eq_n(s, "NSNumber:", 9)) {
                nslog_append(s + 9, cstr_len(s + 9));
            }
            /* NSFloat: display float value */
            if (cstr_eq_n(s, "NSFloat:", 8)) {
                nslog_append(s + 8, cstr_len(s + 8));
            }
            return value_from_id(receiver);
        }

        /* NSNumber: [NSNumber numberWithFloat:f] → wrap float as id */
        if (IS_FOUNDATION_CLASS("NSNumber") && target.is_class && cstr_eq(sel_name, "numberWithFloat:") && arg_count >= 1) {
            if (keyword_args[0].is_float) {
                char *buf = string_pool_alloc(64);
                if (buf == 0) return value_from_float(keyword_args[0].float_val);
                cstr_copy(buf, "NSFloat:", 64);
                {
                    double fv = keyword_args[0].float_val;
                    int neg = fv < 0.0;
                    unsigned int pos = 8;
                    if (neg) { fv = -fv; buf[pos++] = '-'; }
                    unsigned long ipart = (unsigned long)fv;
                    double fpart = fv - (double)ipart;
                    if (ipart == 0) { buf[pos++] = '0'; }
                    else {
                        char tmp[20]; int ti = 0;
                        while (ipart > 0) { tmp[ti++] = '0' + (ipart % 10); ipart /= 10; }
                        while (ti > 0) buf[pos++] = tmp[--ti];
                    }
                    buf[pos++] = '.';
                    for (int d = 0; d < 6 && pos < 60; d++) {
                        fpart *= 10.0; int digit = (int)fpart;
                        buf[pos++] = '0' + digit; fpart -= digit;
                    }
                    /* Trim trailing zeros */
                    while (pos > 0 && buf[pos-1] == '0') pos--;
                    if (buf[pos-1] == '.') pos++; /* keep at least one decimal */
                    buf[pos] = '\0';
                }
                return value_from_id((id)buf);
            }
            return value_from_id(args[0]);
        }

        /* NSNumber: [NSNumber numberWithDouble:d] → wrap double as id */
        if (IS_FOUNDATION_CLASS("NSNumber") && target.is_class && cstr_eq(sel_name, "numberWithDouble:") && arg_count >= 1) {
            /* Same encoding as numberWithFloat */
            if (keyword_args[0].is_float) {
                char *buf = string_pool_alloc(64);
                if (buf == 0) return value_from_float(keyword_args[0].float_val);
                cstr_copy(buf, "NSFloat:", 64);
                {
                    double fv = keyword_args[0].float_val;
                    int neg = fv < 0.0;
                    unsigned int pos = 8;
                    if (neg) { fv = -fv; buf[pos++] = '-'; }
                    unsigned long ipart = (unsigned long)fv;
                    double fpart = fv - (double)ipart;
                    if (ipart == 0) { buf[pos++] = '0'; }
                    else {
                        char tmp[20]; int ti = 0;
                        while (ipart > 0) { tmp[ti++] = '0' + (ipart % 10); ipart /= 10; }
                        while (ti > 0) buf[pos++] = tmp[--ti];
                    }
                    buf[pos++] = '.';
                    for (int d = 0; d < 6 && pos < 60; d++) {
                        fpart *= 10.0; int digit = (int)fpart;
                        buf[pos++] = '0' + digit; fpart -= digit;
                    }
                    while (pos > 0 && buf[pos-1] == '0') pos--;
                    if (buf[pos-1] == '.') pos++;
                    buf[pos] = '\0';
                }
                return value_from_id((id)buf);
            }
            return value_from_id(args[0]);
        }

        /* NSNumber: [num floatValue] → unwrap float from NSFloat encoding */
        if (cstr_eq(sel_name, "floatValue") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            if (cstr_eq_n(s, "NSFloat:", 8)) {
                double val = 0.0;
                unsigned int i = 8;
                int neg = 0;
                if (s[i] == '-') { neg = 1; i++; }
                while (s[i] >= '0' && s[i] <= '9') val = val * 10.0 + (s[i++] - '0');
                if (s[i] == '.') {
                    double frac = 0.1;
                    i++;
                    while (s[i] >= '0' && s[i] <= '9') {
                        val += (s[i] - '0') * frac;
                        frac *= 0.1;
                        i++;
                    }
                }
                return value_from_float(neg ? -val : val);
            }
            return value_from_float(0.0);
        }

        /* NSNumber: [num doubleValue] → unwrap double from NSFloat encoding */
        if (cstr_eq(sel_name, "doubleValue") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            if (cstr_eq_n(s, "NSFloat:", 8)) {
                double val = 0.0;
                unsigned int i = 8;
                int neg = 0;
                if (s[i] == '-') { neg = 1; i++; }
                while (s[i] >= '0' && s[i] <= '9') val = val * 10.0 + (s[i++] - '0');
                if (s[i] == '.') {
                    double frac = 0.1;
                    i++;
                    while (s[i] >= '0' && s[i] <= '9') {
                        val += (s[i] - '0') * frac;
                        frac *= 0.1;
                        i++;
                    }
                }
                return value_from_float(neg ? -val : val);
            }
            return value_from_float(0.0);
        }

        /* NSNumber: [NSNumber numberWithBool:b] → wrap bool as NSNumber */
        if (IS_FOUNDATION_CLASS("NSNumber") && target.is_class && cstr_eq(sel_name, "numberWithBool:") && arg_count >= 1) {
            int v = keyword_args[0].is_int ? (keyword_args[0].int_val ? 1 : 0) : 0;
            char *buf = string_pool_alloc(14);
            if (buf == 0) return value_from_int(v);
            cstr_copy(buf, "NSNumber:", 14);
            buf[9] = '0' + v;
            buf[10] = '\0';
            return value_from_id((id)buf);
        }

        /* NSNumber: [num stringValue] → numeric string representation */
        if (cstr_eq(sel_name, "stringValue") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            if (cstr_eq_n(s, "NSNumber:", 9)) {
                unsigned int vlen = (unsigned int)cstr_len(s + 9);
                char *result = string_pool_alloc(vlen + 1);
                if (result == 0) return value_from_id(receiver);
                cstr_copy(result, s + 9, vlen + 1);
                return value_from_id((id)result);
            }
            if (cstr_eq_n(s, "NSFloat:", 8)) {
                unsigned int vlen = (unsigned int)cstr_len(s + 8);
                char *result = string_pool_alloc(vlen + 1);
                if (result == 0) return value_from_id(receiver);
                cstr_copy(result, s + 8, vlen + 1);
                return value_from_id((id)result);
            }
            return value_from_id(receiver);
        }

        /* NSNumber: [num longValue] → alias for intValue */
        if (cstr_eq(sel_name, "longValue") && target.is_id && receiver != 0) {
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

        /* ── NSData dispatch ──────────────────────────────────────── */

        /* NSData: [NSData data] → empty data */
        if (IS_FOUNDATION_CLASS("NSData") && target.is_class && cstr_eq(sel_name, "data") && arg_count == 0) {
            char *buf = string_pool_alloc(8);
            if (buf == 0) return value_from_id((id)"NSData:");
            cstr_copy(buf, "NSData:", 8);
            return value_from_id((id)buf);
        }

        /* NSData: [NSData dataWithBytes:ptr length:len] → create from string bytes
         * Since we don't have real byte pointers, we accept a string (treating
         * each char as a byte) and encode as "NSData:<hex>". */
        if (IS_FOUNDATION_CLASS("NSData") && target.is_class && cstr_eq(sel_name, "dataWithBytes:length:") && arg_count >= 2) {
            const char *bytes = (const char *)keyword_args[0].obj_val;
            int len = keyword_args[1].is_int ? keyword_args[1].int_val : 0;
            if (len < 0) len = 0;
            {
                int blen = (int)cstr_len(bytes);
                if (len > blen) len = blen;
                /* Hex encoding: 2 chars per byte + "NSData:" prefix */
                unsigned int needed = 7 + (unsigned int)len * 2 + 1;
                char *buf = string_pool_alloc(needed);
                if (buf == 0) return value_from_id((id)"NSData:");
                cstr_copy(buf, "NSData:", needed);
                {
                    static const char hex_chars[] = "0123456789abcdef";
                    int i;
                    for (i = 0; i < len; i++) {
                        unsigned char c = (unsigned char)bytes[i];
                        buf[7 + i * 2] = hex_chars[(c >> 4) & 0x0f];
                        buf[7 + i * 2 + 1] = hex_chars[c & 0x0f];
                    }
                    buf[7 + len * 2] = '\0';
                }
                return value_from_id((id)buf);
            }
        }

        /* NSData instance methods — check for NSData: prefix on receiver */
        if (target.is_id && receiver != 0 && cstr_eq_n((const char *)receiver, "NSData:", 7)) {
            const char *s = (const char *)receiver;

            /* [data bytes] → decode hex back to raw bytes (as string) */
            if (cstr_eq(sel_name, "bytes")) {
                const char *hex = s + 7;
                int hex_len = (int)cstr_len(hex);
                int byte_len = hex_len / 2;
                char *result = string_pool_alloc((unsigned int)byte_len + 1);
                if (result == 0) return value_from_id(receiver);
                {
                    static const char hex_vals[] = "0123456789abcdef";
                    int i;
                    for (i = 0; i < byte_len; i++) {
                        char hi = hex[i * 2];
                        char lo = hex[i * 2 + 1];
                        int hi_val = 0, lo_val = 0, j;
                        for (j = 0; j < 16; j++) {
                            if (hi == hex_vals[j] || hi == hex_vals[j] - 32) hi_val = j;
                            if (lo == hex_vals[j] || lo == hex_vals[j] - 32) lo_val = j;
                        }
                        result[i] = (char)((hi_val << 4) | lo_val);
                    }
                    result[byte_len] = '\0';
                }
                return value_from_id((id)result);
            }

            /* [data description] → display as <hex bytes> */
            if (cstr_eq(sel_name, "description")) {
                const char *hex = s + 7;
                int hex_len = (int)cstr_len(hex);
                /* Format: <xxxx xxxx ...> with spaces every 8 hex chars */
                unsigned int needed = 2 + (unsigned int)hex_len + (unsigned int)(hex_len / 8) + 1;
                char *result = string_pool_alloc(needed);
                if (result == 0) return value_from_id(receiver);
                {
                    int ri = 0;
                    int i;
                    result[ri++] = '<';
                    for (i = 0; i < hex_len; i++) {
                        if (i > 0 && i % 8 == 0) result[ri++] = ' ';
                        result[ri++] = hex[i];
                    }
                    result[ri++] = '>';
                    result[ri] = '\0';
                }
                return value_from_id((id)result);
            }

            /* [data isEqual:other] → compare data */
            if (cstr_eq(sel_name, "isEqual:") && arg_count >= 1) {
                const char *other = (const char *)keyword_args[0].obj_val;
                if (other && cstr_eq_n(other, "NSData:", 7)) {
                    return value_from_int(cstr_eq(s, other) ? 1 : 0);
                }
                return value_from_int(0);
            }

            /* [data isEqualToData:other] → compare data */
            if (cstr_eq(sel_name, "isEqualToData:") && arg_count >= 1) {
                const char *other = (const char *)keyword_args[0].obj_val;
                if (other && cstr_eq_n(other, "NSData:", 7)) {
                    return value_from_int(cstr_eq(s, other) ? 1 : 0);
                }
                return value_from_int(0);
            }

            /* [data subdataWithRange:] — needs NSRange, deferred */
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

        /* NSDictionary: [NSDictionary dictionaryWithObject:obj forKey:key] → dict with one entry */
        if (IS_FOUNDATION_CLASS("NSDictionary") && target.is_class && cstr_eq(sel_name, "dictionaryWithObject:forKey:") && arg_count >= 2) {
            unsigned int cid = g_next_coll_id++;
            coll_add(cid, keyword_args[1], keyword_args[0]); /* key, value */
            return value_from_id(coll_make_marker("NSDict:", cid));
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

                /* [mutArr replaceObjectAtIndex:n withObject:obj] → replace element */
                if (cstr_eq(sel_name, "replaceObjectAtIndex:withObject:") && arg_count >= 2) {
                    int idx = coll_get_nth(cid, (unsigned int)keyword_args[0].int_val);
                    if (idx >= 0) {
                        g_coll_entries[(unsigned int)idx].key = keyword_args[1];
                    }
                    return value_from_id(receiver);
                }

                /* [mutArr insertObject:obj atIndex:n] → insert element at index */
                if (cstr_eq(sel_name, "insertObject:atIndex:") && arg_count >= 2) {
                    Value dummy = value_void();
                    coll_insert_at(cid, (unsigned int)keyword_args[1].int_val, keyword_args[0], dummy);
                    return value_from_id(receiver);
                }

                /* [mutArr removeObjectAtIndex:n] → remove element at index */
                if (cstr_eq(sel_name, "removeObjectAtIndex:") && arg_count >= 1) {
                    int idx = coll_get_nth(cid, (unsigned int)keyword_args[0].int_val);
                    if (idx >= 0) coll_remove_at((unsigned int)idx);
                    return value_from_id(receiver);
                }

                /* [arr indexOfObject:obj] → find index of object */
                if (cstr_eq(sel_name, "indexOfObject:") && arg_count >= 1) {
                    unsigned int i, pos = 0;
                    for (i = 0; i < g_coll_entry_count; i++) {
                        if (g_coll_entries[i].coll_id != cid) continue;
                        if (g_coll_entries[i].key.is_int && keyword_args[0].is_int &&
                            g_coll_entries[i].key.int_val == keyword_args[0].int_val) {
                            return value_from_int((int)pos);
                        }
                        if (g_coll_entries[i].key.is_id && keyword_args[0].is_id &&
                            g_coll_entries[i].key.obj_val != 0 && keyword_args[0].obj_val != 0 &&
                            cstr_eq((const char *)g_coll_entries[i].key.obj_val,
                                    (const char *)keyword_args[0].obj_val)) {
                            return value_from_int((int)pos);
                        }
                        pos++;
                    }
                    return value_from_int(-1); /* NSNotFound */
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

                /* [dict isEqualToDictionary:other] → compare dicts */
                if (cstr_eq(sel_name, "isEqualToDictionary:") && arg_count >= 1) {
                    const char *other_s = (const char *)keyword_args[0].obj_val;
                    unsigned int other_cid = coll_id_from_marker(other_s, "NSDict:");
                    if (other_cid == 0) other_cid = coll_id_from_marker(other_s, "NSMutDict:");
                    if (other_cid == 0) return value_from_int(0);
                    {
                        unsigned int my_count = coll_count(cid);
                        unsigned int other_count = coll_count(other_cid);
                        if (my_count != other_count) return value_from_int(0);
                        /* Check all keys in self exist in other with same value */
                        unsigned int i;
                        for (i = 0; i < g_coll_entry_count; i++) {
                            if (g_coll_entries[i].coll_id == cid) {
                                int other_idx = coll_find_by_key(other_cid, &g_coll_entries[i].key);
                                if (other_idx < 0) return value_from_int(0);
                                /* Compare values — both are Values, check fields */
                                if (g_coll_entries[i].value.is_int != g_coll_entries[other_idx].value.is_int ||
                                    g_coll_entries[i].value.is_id != g_coll_entries[other_idx].value.is_id ||
                                    g_coll_entries[i].value.is_float != g_coll_entries[other_idx].value.is_float)
                                    return value_from_int(0);
                                if (g_coll_entries[i].value.is_int && g_coll_entries[i].value.int_val != g_coll_entries[other_idx].value.int_val)
                                    return value_from_int(0);
                                if (g_coll_entries[i].value.is_float && g_coll_entries[i].value.float_val != g_coll_entries[other_idx].value.float_val)
                                    return value_from_int(0);
                                if (g_coll_entries[i].value.is_id) {
                                    const char *a = (const char *)g_coll_entries[i].value.obj_val;
                                    const char *b = (const char *)g_coll_entries[other_idx].value.obj_val;
                                    if (a == 0 || b == 0) { if (a != b) return value_from_int(0); }
                                    else if (!cstr_eq(a, b)) return value_from_int(0);
                                }
                            }
                        }
                        return value_from_int(1);
                    }
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
                                        if (blk->captures[ci].is_by_ref) {
                                            /* __block: read from original variable slot */
                                            unsigned int vi = blk->captures[ci].var_index;
                                            if (vi < g_var_count) {
                                                cap_var->is_id = g_vars[vi].is_id;
                                                cap_var->value = g_vars[vi].value;
                                                cap_var->is_int = g_vars[vi].is_int;
                                                cap_var->int_value = g_vars[vi].int_value;
                                                cap_var->is_float = g_vars[vi].is_float;
                                                cap_var->float_value = g_vars[vi].float_value;
                                                cap_var->is_class = g_vars[vi].is_class;
                                                cap_var->cls = g_vars[vi].cls;
                                                cap_var->is_sel = g_vars[vi].is_sel;
                                                cap_var->sel = g_vars[vi].sel;
                                                cap_var->is_block_captured = g_vars[vi].is_block_captured;
                                            }
                                        } else {
                                            /* by-value: restore snapshot */
                                            cap_var->is_id = blk->captures[ci].value.is_id;
                                            cap_var->value = blk->captures[ci].value.obj_val;
                                            cap_var->is_int = blk->captures[ci].value.is_int;
                                            cap_var->int_value = blk->captures[ci].value.int_val;
                                            cap_var->is_float = blk->captures[ci].value.is_float;
                                            cap_var->float_value = blk->captures[ci].value.float_val;
                                            cap_var->is_class = blk->captures[ci].value.is_class;
                                            cap_var->cls = blk->captures[ci].value.cls_val;
                                            cap_var->is_sel = blk->captures[ci].value.is_sel;
                                            cap_var->sel = blk->captures[ci].value.sel_val;
                                        }
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

                            /* Write back __block variables to original slots */
                            {
                                unsigned int ci;
                                for (ci = 0; ci < blk->capture_count; ci++) {
                                    if (blk->captures[ci].is_by_ref) {
                                        unsigned int vi = blk->captures[ci].var_index;
                                        InterpVar *cap_var = interp_find_var(blk->captures[ci].name);
                                        if (cap_var && vi < g_var_count) {
                                            g_vars[vi].is_id = cap_var->is_id;
                                            g_vars[vi].value = cap_var->value;
                                            g_vars[vi].is_int = cap_var->is_int;
                                            g_vars[vi].int_value = cap_var->int_value;
                                            g_vars[vi].is_float = cap_var->is_float;
                                            g_vars[vi].float_value = cap_var->float_value;
                                            g_vars[vi].is_class = cap_var->is_class;
                                            g_vars[vi].cls = cap_var->cls;
                                            g_vars[vi].is_sel = cap_var->is_sel;
                                            g_vars[vi].sel = cap_var->sel;
                                        }
                                    }
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
                         * Guard against non-ObjC pointers (string pool, etc.)
                         * by checking if the pointer is in the string pool range. */
                        const char *ptr = (const char *)receiver;
                        if (ptr >= g_string_pool && ptr < g_string_pool + OBJC_INTERP_STRING_POOL_SIZE) {
                            /* String pool pointer — not a valid ObjC object.
                             * Skip this method (class mismatch). */
                            continue;
                        }
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

                /* Limit scope to method-local variables only (self, _cmd, args, synthesized ivars).
                 * This prevents cross-call and cross-class variable contamination.
                 * Previously set to 0, allowing methods to see any variable in g_vars[],
                 * which caused stale variables from prior calls to be found instead of
                 * creating fresh ones. For example, on the second call to a method,
                 * interp_get_or_create_var would find the stale variable from the first call. */
                g_var_scope_base = g_var_count;

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
                            g_properties[pi].ivar_name[0] != '\0' &&
                            property_matches_class(receiver, pi)) {
                            InterpVar *ivar_var = interp_get_or_create_var(g_properties[pi].ivar_name);
                            if (ivar_var) {
                                Value *stored = instance_var_get(receiver, g_properties[pi].name);
                                if (stored) {
                                    ivar_var->is_id = stored->is_id;
                                    ivar_var->value = stored->obj_val;
                                    ivar_var->is_int = stored->is_int;
                                    ivar_var->int_value = stored->int_val;
                                    ivar_var->is_float = stored->is_float;
                                    ivar_var->float_value = stored->float_val;
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
                            g_properties[pi].ivar_name[0] != '\0' &&
                            property_matches_class(receiver, pi)) {
                            InterpVar *ivar_var = interp_find_var(g_properties[pi].ivar_name);
                            if (ivar_var) {
                                Value ivar_val;
                                ivar_val.obj_val = ivar_var->value;
                                ivar_val.cls_val = ivar_var->cls;
                                ivar_val.sel_val = ivar_var->sel;
                                ivar_val.int_val = ivar_var->int_value;
                                ivar_val.is_int = ivar_var->is_int;
                                ivar_val.float_val = ivar_var->float_value;
                                ivar_val.is_float = ivar_var->is_float;
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
                    cstr_eq(sel_name, g_properties[pi].name) &&
                    property_matches_class(receiver, pi)) {
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
                            cstr_eq(prop_from_setter, g_properties[pi].name) &&
                            property_matches_class(receiver, pi)) {
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
                                /* Also update the ivar variable if we're inside
                                 * a method body, so the write-back doesn't
                                 * overwrite with a stale value. */
                                if (g_properties[pi].ivar_name[0] != '\0') {
                                    InterpVar *ivar_var = interp_find_var(g_properties[pi].ivar_name);
                                    if (ivar_var) {
                                        ivar_var->int_value = val.is_int ? val.int_val : 0;
                                        ivar_var->is_int = val.is_int;
                                        ivar_var->value = val.obj_val;
                                        ivar_var->is_id = val.is_id;
                                        ivar_var->is_float = val.is_float;
                                        ivar_var->float_value = val.float_val;
                                        ivar_var->cls = val.cls_val;
                                        ivar_var->is_class = val.is_class;
                                        ivar_var->sel = val.sel_val;
                                        ivar_var->is_sel = val.is_sel;
                                    }
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

    /* Auto-synthesize: mark any unsynthesized properties for this class
     * as synthesized, matching Objective-C's default behavior.
     * Also auto-generate ivar name (_propertyName) if not set. */
    {
        unsigned int pi;
        for (pi = 0; pi < g_property_count; pi++) {
            if (cstr_eq(g_properties[pi].class_name, class_name) &&
                !g_properties[pi].synthesized) {
                g_properties[pi].synthesized = 1;
                if (g_properties[pi].ivar_name[0] == '\0') {
                    const char *pname = g_properties[pi].name;
                    unsigned int ppos = 0;
                    g_properties[pi].ivar_name[ppos++] = '_';
                    while (*pname && ppos < 62) {
                        g_properties[pi].ivar_name[ppos++] = *pname++;
                    }
                    g_properties[pi].ivar_name[ppos] = '\0';
                }
            }
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

    /* Unary minus — handle before other primaries */
    if (tok.type == TOK_MINUS) {
        parser_advance(p);
        {
            Value v = parse_primary(p);
            if (v.is_int) return value_from_int(-v.int_val);
            if (v.is_float) return value_from_float(-v.float_val);
            return v;
        }
    }

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

    /* @selector() expression */
    if (tok.type == TOK_AT_KEYWORD && cstr_eq(tok.text, "@selector")) {
        parser_advance(p); /* consume @selector */
        if (parser_current(p).type == TOK_OPEN_PAREN) {
            parser_advance(p); /* consume ( */
            {
                char sel_name[256];
                unsigned int sel_len = 0;
                sel_name[0] = '\0';
                while (parser_current(p).type != TOK_CLOSE_PAREN &&
                       parser_current(p).type != TOK_EOF) {
                    Token ct = parser_current(p);
                    if (ct.type == TOK_IDENTIFIER || ct.type == TOK_AT_KEYWORD) {
                        unsigned int tl = cstr_len(ct.text);
                        if (sel_len + tl + 1 < 256) {
                            cstr_copy(sel_name + sel_len, ct.text, tl + 1);
                            sel_len += tl;
                        }
                    } else if (ct.type == TOK_COLON) {
                        if (sel_len + 1 < 256) {
                            sel_name[sel_len++] = ':';
                            sel_name[sel_len] = '\0';
                        }
                    } else {
                        break;
                    }
                    parser_advance(p);
                }
                parser_expect(p, TOK_CLOSE_PAREN);
                if (!p->error) {
                    SEL sel = sel_registerName(sel_name);
                    return value_from_sel(sel);
                }
            }
        }
        return value_void();
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

    /* Float literal */
    if (tok.type == TOK_FLOAT_LITERAL) {
        double val = 0.0;
        double frac = 0.1;
        unsigned int i = 0;
        /* Parse integer part */
        while (tok.text[i] != '\0' && tok.text[i] != '.') {
            val = val * 10.0 + (tok.text[i] - '0');
            i++;
        }
        /* Skip decimal point */
        if (tok.text[i] == '.') i++;
        /* Parse fractional part */
        while (tok.text[i] != '\0') {
            val += (tok.text[i] - '0') * frac;
            frac *= 0.1;
            i++;
        }
        parser_advance(p);
        return value_from_float(val);
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
                                            arg_var->is_float = val.is_float;
                                            arg_var->float_value = val.float_val;
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
                                                g_properties[pi].ivar_name[0] != '\0' &&
                                                property_matches_class(receiver, pi)) {
                                                InterpVar *ivar_var = interp_get_or_create_var(g_properties[pi].ivar_name);
                                                if (ivar_var) {
                                                    Value *stored = instance_var_get(receiver, g_properties[pi].name);
                                                    if (stored) {
                                                        ivar_var->is_id = stored->is_id;
                                                        ivar_var->value = stored->obj_val;
                                                        ivar_var->is_int = stored->is_int;
                                                        ivar_var->int_value = stored->int_val;
                                                        ivar_var->is_float = stored->is_float;
                                                        ivar_var->float_value = stored->float_val;
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
                                                g_properties[pi].ivar_name[0] != '\0' &&
                                                property_matches_class(receiver, pi)) {
                                                InterpVar *ivar_var = interp_find_var(g_properties[pi].ivar_name);
                                                if (ivar_var) {
                                                    Value ivar_val;
                                                    ivar_val.obj_val = ivar_var->value;
                                                    ivar_val.cls_val = ivar_var->cls;
                                                    ivar_val.sel_val = ivar_var->sel;
                                                    ivar_val.int_val = ivar_var->int_value;
                                                    ivar_val.is_int = ivar_var->is_int;
                                                    ivar_val.float_val = ivar_var->float_value;
                                                    ivar_val.is_float = ivar_var->is_float;
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
                                            cstr_eq(prop_name, g_properties[pi].name) &&
                                            property_matches_class(receiver, pi)) {
                                            /* Store in side table */
                                            if (instance_var_set(receiver, g_properties[pi].name, val) != 0) {
                                    parser_error(p, "instance variable table full (max 256)");
                                }
                                            /* Also update the ivar variable if inside a method body */
                                            if (g_properties[pi].ivar_name[0] != '\0') {
                                                InterpVar *ivar_var = interp_find_var(g_properties[pi].ivar_name);
                                                if (ivar_var) {
                                                    ivar_var->int_value = val.is_int ? val.int_val : 0;
                                                    ivar_var->is_int = val.is_int;
                                                    ivar_var->value = val.obj_val;
                                                    ivar_var->is_id = val.is_id;
                                                    ivar_var->is_float = val.is_float;
                                                    ivar_var->float_value = val.float_val;
                                                    ivar_var->cls = val.cls_val;
                                                    ivar_var->is_class = val.is_class;
                                                    ivar_var->sel = val.sel_val;
                                                    ivar_var->is_sel = val.is_sel;
                                                }
                                            }
                                            break;
                                        }
                                    }
                                }
                                return val;
                            }
                        }
                    }

                    /* Compound assignment on dot syntax: obj.prop += expr, etc. */
                    if (parser_current(p).type == TOK_PLUS_ASSIGN ||
                        parser_current(p).type == TOK_MINUS_ASSIGN ||
                        parser_current(p).type == TOK_STAR_ASSIGN ||
                        parser_current(p).type == TOK_SLASH_ASSIGN ||
                        parser_current(p).type == TOK_PERCENT_ASSIGN) {
                        TokenType compound_op = parser_current(p).type;
                        parser_advance(p);
                        {
                            Value rhs = parse_expression_safe(p);
                            if (p->error) return rhs;

                            /* Read current value via getter */
                            id receiver = var->is_id ? var->value : (id)var->cls;
                            Value current = value_void();
                            {
                                unsigned int pi;
                                for (pi = 0; pi < g_property_count; pi++) {
                                    if (g_properties[pi].synthesized &&
                                        cstr_eq(prop_name, g_properties[pi].name) &&
                                        property_matches_class(receiver, pi)) {
                                        Value *stored = instance_var_get(receiver, g_properties[pi].name);
                                        if (stored) current = *stored;
                                        else if (g_properties[pi].is_int) current = value_from_int(0);
                                        break;
                                    }
                                }
                            }

                            /* Compute new value */
                            Value new_val;
                            if (current.is_int && rhs.is_int) {
                                switch (compound_op) {
                                    case TOK_PLUS_ASSIGN: new_val = value_from_int(current.int_val + rhs.int_val); break;
                                    case TOK_MINUS_ASSIGN: new_val = value_from_int(current.int_val - rhs.int_val); break;
                                    case TOK_STAR_ASSIGN: new_val = value_from_int(current.int_val * rhs.int_val); break;
                                    case TOK_SLASH_ASSIGN: new_val = value_from_int(rhs.int_val != 0 ? current.int_val / rhs.int_val : 0); break;
                                    case TOK_PERCENT_ASSIGN: new_val = value_from_int(rhs.int_val != 0 ? current.int_val % rhs.int_val : 0); break;
                                    default: new_val = current; break;
                                }
                            } else {
                                new_val = current;
                            }

                            /* Write back via setter */
                            {
                                unsigned int pi;
                                for (pi = 0; pi < g_property_count; pi++) {
                                    if (g_properties[pi].synthesized &&
                                        cstr_eq(prop_name, g_properties[pi].name) &&
                                        property_matches_class(receiver, pi)) {
                                        if (instance_var_set(receiver, g_properties[pi].name, new_val) != 0) {
                                            parser_error(p, "instance variable table full (max 256)");
                                        }
                                        /* Also update ivar variable if inside method body */
                                        if (g_properties[pi].ivar_name[0] != '\0') {
                                            InterpVar *ivar_var = interp_find_var(g_properties[pi].ivar_name);
                                            if (ivar_var) {
                                                ivar_var->int_value = new_val.is_int ? new_val.int_val : 0;
                                                ivar_var->is_int = new_val.is_int;
                                                ivar_var->float_value = new_val.is_float ? new_val.float_val : 0.0;
                                                ivar_var->is_float = new_val.is_float;
                                                ivar_var->value = new_val.obj_val;
                                                ivar_var->is_id = new_val.is_id;
                                                ivar_var->cls = new_val.cls_val;
                                                ivar_var->is_class = new_val.is_class;
                                                ivar_var->sel = new_val.sel_val;
                                                ivar_var->is_sel = new_val.is_sel;
                                            }
                                        }
                                        break;
                                    }
                                }
                            }
                            if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
                            return new_val;
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
                                        g_properties[pi].ivar_name[0] != '\0' &&
                                        property_matches_class(receiver, pi)) {
                                        InterpVar *ivar_var = interp_get_or_create_var(g_properties[pi].ivar_name);
                                        if (ivar_var) {
                                            Value *stored = instance_var_get(receiver, g_properties[pi].name);
                                            if (stored) {
                                                ivar_var->is_id = stored->is_id;
                                                ivar_var->value = stored->obj_val;
                                                ivar_var->is_int = stored->is_int;
                                                ivar_var->int_value = stored->int_val;
                                                ivar_var->is_float = stored->is_float;
                                                ivar_var->float_value = stored->float_val;
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
                                        g_properties[pi].ivar_name[0] != '\0' &&
                                        property_matches_class(receiver, pi)) {
                                        InterpVar *ivar_var = interp_find_var(g_properties[pi].ivar_name);
                                        if (ivar_var) {
                                            Value ivar_val;
                                            ivar_val.obj_val = ivar_var->value;
                                            ivar_val.cls_val = ivar_var->cls;
                                            ivar_val.sel_val = ivar_var->sel;
                                            ivar_val.int_val = ivar_var->int_value;
                                            ivar_val.is_int = ivar_var->is_int;
                                            ivar_val.float_val = ivar_var->float_value;
                                            ivar_val.is_float = ivar_var->is_float;
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
                                    cstr_eq(prop_name, g_properties[pi].name) &&
                                    property_matches_class(receiver, pi)) {
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

                /* Subscript syntax: arr[index] → objectAtIndex:
                 *                    dict[key] → objectForKey:
                 *                    arr[index] = obj → replaceObjectAtIndex:withObject:
                 *                    dict[key] = obj → setObject:forKey: */
                if (parser_current(p).type == TOK_OPEN_BRACKET && var->is_id && var->value != 0) {
                    const char *marker = (const char *)var->value;
                    unsigned int cid = coll_id_from_marker(marker, "NSArr:");
                    unsigned int cid2 = coll_id_from_marker(marker, "NSMutArr:");
                    unsigned int cid3 = coll_id_from_marker(marker, "NSDict:");
                    unsigned int cid4 = coll_id_from_marker(marker, "NSMutDict:");

                    if (cid > 0 || cid2 > 0 || cid3 > 0 || cid4 > 0) {
                        unsigned int actual_cid = cid > 0 ? cid : cid2 > 0 ? cid2 : cid3 > 0 ? cid3 : cid4;
                        int is_array = (cid > 0 || cid2 > 0);

                        parser_advance(p); /* consume [ */

                        {
                            Value index = parse_expression(p);
                            if (p->error) return index;

                            if (parser_current(p).type != TOK_CLOSE_BRACKET) {
                                parser_error(p, "Expected ']' after subscript index");
                                return value_void();
                            }
                            parser_advance(p); /* consume ] */

                            /* Check for assignment: arr[index] = value */
                            if (parser_current(p).type == TOK_ASSIGN) {
                                parser_advance(p);
                                {
                                    Value val = parse_expression_safe(p);
                                    if (p->error) return val;

                                    if (is_array) {
                                        /* replaceObjectAtIndex:withObject: */
                                        int idx = coll_get_nth(actual_cid, (unsigned int)index.int_val);
                                        if (idx >= 0) {
                                            g_coll_entries[(unsigned int)idx].key = val;
                                        }
                                    } else {
                                        /* setObject:forKey: */
                                        int idx = coll_find_by_key(actual_cid, &index);
                                        if (idx >= 0) {
                                            g_coll_entries[(unsigned int)idx].value = val;
                                        } else {
                                            coll_add(actual_cid, index, val);
                                        }
                                    }
                                    return value_from_id(var->value);
                                }
                            }

                            /* Read: objectAtIndex: or objectForKey: */
                            if (is_array) {
                                int idx = coll_get_nth(actual_cid, (unsigned int)index.int_val);
                                if (idx >= 0) return g_coll_entries[(unsigned int)idx].key;
                                return value_from_id((id)"(nil)");
                            } else {
                                int idx = coll_find_by_key(actual_cid, &index);
                                if (idx >= 0) return g_coll_entries[(unsigned int)idx].value;
                                return value_from_id((id)"(nil)");
                            }
                        }
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
                                    if (blk->captures[ai].is_by_ref) {
                                        /* __block: read from original variable slot */
                                        unsigned int vi = blk->captures[ai].var_index;
                                        if (vi < g_var_count) {
                                            cap_var->is_id = g_vars[vi].is_id;
                                            cap_var->value = g_vars[vi].value;
                                            cap_var->is_int = g_vars[vi].is_int;
                                            cap_var->int_value = g_vars[vi].int_value;
                                            cap_var->is_float = g_vars[vi].is_float;
                                            cap_var->float_value = g_vars[vi].float_value;
                                            cap_var->is_class = g_vars[vi].is_class;
                                            cap_var->cls = g_vars[vi].cls;
                                            cap_var->is_sel = g_vars[vi].is_sel;
                                            cap_var->sel = g_vars[vi].sel;
                                            cap_var->is_block_captured = g_vars[vi].is_block_captured;
                                        }
                                    } else {
                                        /* by-value: restore snapshot */
                                        cap_var->is_id = blk->captures[ai].value.is_id;
                                        cap_var->value = blk->captures[ai].value.obj_val;
                                        cap_var->is_int = blk->captures[ai].value.is_int;
                                        cap_var->int_value = blk->captures[ai].value.int_val;
                                        cap_var->is_float = blk->captures[ai].value.is_float;
                                        cap_var->float_value = blk->captures[ai].value.float_val;
                                        cap_var->is_class = blk->captures[ai].value.is_class;
                                        cap_var->cls = blk->captures[ai].value.cls_val;
                                        cap_var->is_sel = blk->captures[ai].value.is_sel;
                                        cap_var->sel = blk->captures[ai].value.sel_val;
                                    }
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

                                /* Write back __block variables to original slots */
                                {
                                    unsigned int ci;
                                    for (ci = 0; ci < blk->capture_count; ci++) {
                                        if (blk->captures[ci].is_by_ref) {
                                            unsigned int vi = blk->captures[ci].var_index;
                                            InterpVar *cap_var = interp_find_var(blk->captures[ci].name);
                                            if (cap_var && vi < g_var_count) {
                                                g_vars[vi].is_id = cap_var->is_id;
                                                g_vars[vi].value = cap_var->value;
                                                g_vars[vi].is_int = cap_var->is_int;
                                                g_vars[vi].int_value = cap_var->int_value;
                                                g_vars[vi].is_float = cap_var->is_float;
                                                g_vars[vi].float_value = cap_var->float_value;
                                                g_vars[vi].is_class = cap_var->is_class;
                                                g_vars[vi].cls = cap_var->cls;
                                                g_vars[vi].is_sel = cap_var->is_sel;
                                                g_vars[vi].sel = cap_var->sel;
                                            }
                                        }
                                    }
                                }

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

                if (var->is_float) return value_from_float(var->float_value);
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
                if (g_vars[vi].is_block_captured) {
                    /* __block variable: capture by reference (store index) */
                    blk->captures[blk->capture_count].is_by_ref = 1;
                    blk->captures[blk->capture_count].var_index = vi;
                    /* Still snapshot value for fallback / GC marking */
                    blk->captures[blk->capture_count].value.is_id = g_vars[vi].is_id;
                    blk->captures[blk->capture_count].value.obj_val = g_vars[vi].value;
                    blk->captures[blk->capture_count].value.is_int = g_vars[vi].is_int;
                    blk->captures[blk->capture_count].value.int_val = g_vars[vi].int_value;
                    blk->captures[blk->capture_count].value.is_float = g_vars[vi].is_float;
                    blk->captures[blk->capture_count].value.float_val = g_vars[vi].float_value;
                    blk->captures[blk->capture_count].value.is_class = g_vars[vi].is_class;
                    blk->captures[blk->capture_count].value.cls_val = g_vars[vi].cls;
                    blk->captures[blk->capture_count].value.is_sel = g_vars[vi].is_sel;
                    blk->captures[blk->capture_count].value.sel_val = g_vars[vi].sel;
                } else {
                    /* Normal variable: capture by value (snapshot) */
                    blk->captures[blk->capture_count].is_by_ref = 0;
                    blk->captures[blk->capture_count].var_index = 0;
                    blk->captures[blk->capture_count].value.is_id = g_vars[vi].is_id;
                    blk->captures[blk->capture_count].value.obj_val = g_vars[vi].value;
                    blk->captures[blk->capture_count].value.is_int = g_vars[vi].is_int;
                    blk->captures[blk->capture_count].value.int_val = g_vars[vi].int_value;
                    blk->captures[blk->capture_count].value.is_float = g_vars[vi].is_float;
                    blk->captures[blk->capture_count].value.float_val = g_vars[vi].float_value;
                    blk->captures[blk->capture_count].value.is_class = g_vars[vi].is_class;
                    blk->captures[blk->capture_count].value.cls_val = g_vars[vi].cls;
                    blk->captures[blk->capture_count].value.is_sel = g_vars[vi].is_sel;
                    blk->captures[blk->capture_count].value.sel_val = g_vars[vi].sel;
                }
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
    int is_block_var = 0;  /* 1 if __block qualifier */
    (void)is_pointer; /* may be used later for pointer type tracking */

    /* Check for __block qualifier */
    if (parser_current(p).type == TOK_IDENTIFIER && cstr_eq(parser_current(p).text, "__block")) {
        is_block_var = 1;
        parser_advance(p);
    }

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
                        var->is_float = init_val.is_float;
                        var->float_value = init_val.float_val;
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
        var->is_block_captured = is_block_var;

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
                var->is_float = init_val.is_float;
                var->float_value = init_val.float_val;
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
            } else if (cstr_eq(type_name, "float") || cstr_eq(type_name, "double")) {
                var->is_float = 1;
                var->float_value = 0.0;
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
    /* Also __block qualifier before type */
    if (tok.type == TOK_IDENTIFIER) {
        /* Check for __block qualifier */
        int is_block_qualifier = cstr_eq(tok.text, "__block");
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

        if (is_builtin_type || is_class_type || is_block_qualifier) {
            if (is_block_qualifier) {
                /* __block is always followed by a type — call directly */
                Value v = parse_type_and_var_decl(p);
                if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
                return v;
            }
            /* Look ahead to see if next token is * or an identifier */
            {
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
                    var->is_float = val.is_float;
                    var->float_value = val.float_val;
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

                /* Float compound assignment: +=, -=, *=, /= */
                if (parser_current(p).type == TOK_PLUS_ASSIGN && var->is_float) {
                    Value val;
                    parser_advance(p);
                    val = parse_expression(p);
                    if (p->error) return val;
                    if (val.is_float) var->float_value += val.float_val;
                    else if (val.is_int) var->float_value += val.int_val;
                    if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
                    return value_from_float(var->float_value);
                }
                if (parser_current(p).type == TOK_MINUS_ASSIGN && var->is_float) {
                    Value val;
                    parser_advance(p);
                    val = parse_expression(p);
                    if (p->error) return val;
                    if (val.is_float) var->float_value -= val.float_val;
                    else if (val.is_int) var->float_value -= val.int_val;
                    if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
                    return value_from_float(var->float_value);
                }
                if (parser_current(p).type == TOK_STAR_ASSIGN && var->is_float) {
                    Value val;
                    parser_advance(p);
                    val = parse_expression(p);
                    if (p->error) return val;
                    if (val.is_float) var->float_value *= val.float_val;
                    else if (val.is_int) var->float_value *= val.int_val;
                    if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
                    return value_from_float(var->float_value);
                }
                if (parser_current(p).type == TOK_SLASH_ASSIGN && var->is_float) {
                    Value val;
                    parser_advance(p);
                    val = parse_expression(p);
                    if (p->error) return val;
                    if (val.is_float && val.float_val != 0.0) var->float_value /= val.float_val;
                    else if (val.is_int && val.int_val != 0) var->float_value /= val.int_val;
                    if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
                    return value_from_float(var->float_value);
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

    /* do-while statement */
    if (tok.type == TOK_DO) {
        AstNode *body, *condition;
        parser_advance(p); /* consume 'do' */

        if (parser_current(p).type == TOK_OPEN_BRACE) {
            parser_advance(p);
            body = parse_block_ast(p);
            if (parser_current(p).type == TOK_CLOSE_BRACE) parser_advance(p);
        } else {
            body = parse_statement_ast(p);
        }
        if (!body) return 0;

        parser_expect(p, TOK_WHILE);
        if (p->error) return 0;
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
        parser_expect(p, TOK_SEMICOLON);
        if (p->error) return 0;

        {
            AstNode *node = ast_make_do_while(body, condition);
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

    /* switch statement */
    if (tok.type == TOK_SWITCH) {
        AstNode *node = ast_alloc();
        if (!node) {
            parser_error(p, "AST node limit reached (max 1024)");
            return 0;
        }
        node->type = AST_SWITCH;
        node->switch_stmt.case_count = 0;
        node->switch_stmt.has_default = 0;
        node->switch_stmt.default_body = 0;

        parser_advance(p); /* consume 'switch' */

        /* Expect (expr) */
        if (parser_current(p).type != TOK_OPEN_PAREN) {
            parser_error(p, "Expected '(' after 'switch'");
            return 0;
        }
        parser_advance(p); /* consume ( */

        /* Capture switch expression as source range */
        node->switch_stmt.expr_start = p->lex.token_start;
        {
            int depth = 1;
            while (depth > 0 && parser_current(p).type != TOK_EOF) {
                if (parser_current(p).type == TOK_OPEN_PAREN) depth++;
                else if (parser_current(p).type == TOK_CLOSE_PAREN) {
                    depth--;
                    if (depth == 0) break; /* don't advance past the closing ) */
                }
                parser_advance(p);
            }
        }
        node->switch_stmt.expr_len = p->lex.token_start - node->switch_stmt.expr_start;

        if (parser_current(p).type == TOK_CLOSE_PAREN) parser_advance(p);

        /* Expect { */
        if (parser_current(p).type != TOK_OPEN_BRACE) {
            parser_error(p, "Expected '{' after switch expression");
            return 0;
        }
        parser_advance(p); /* consume { */

        /* Parse case/default clauses */
        while (parser_current(p).type != TOK_CLOSE_BRACE &&
               parser_current(p).type != TOK_EOF &&
               !p->error) {
            if (parser_current(p).type == TOK_CASE) {
                unsigned int ci = node->switch_stmt.case_count;
                if (ci >= 32) {
                    parser_error(p, "Too many case labels (max 32)");
                    return 0;
                }
                parser_advance(p); /* consume 'case' */

                /* Parse case value (integer constant) */
                {
                    Value case_val = parse_expression(p);
                    if (p->error) return 0;
                    node->switch_stmt.case_values[ci] = case_val.int_val;
                }

                if (parser_current(p).type == TOK_COLON) parser_advance(p);

                /* Parse case body (statements until next case/default/}) */
                {
                    AstNode *body = ast_alloc();
                    if (!body) {
                        parser_error(p, "AST node limit reached");
                        return 0;
                    }
                    body->type = AST_BLOCK;
                    body->block.count = 0;

                    while (parser_current(p).type != TOK_CASE &&
                           parser_current(p).type != TOK_DEFAULT &&
                           parser_current(p).type != TOK_CLOSE_BRACE &&
                           parser_current(p).type != TOK_EOF &&
                           !p->error) {
                        AstNode *stmt = parse_statement_ast(p);
                        if (!stmt) break;
                        if (body->block.count < 128) {
                            body->block.children[body->block.count++] = stmt;
                        }
                    }
                    node->switch_stmt.case_bodies[ci] = body;
                }
                node->switch_stmt.case_count++;
            } else if (parser_current(p).type == TOK_DEFAULT) {
                parser_advance(p); /* consume 'default' */
                if (parser_current(p).type == TOK_COLON) parser_advance(p);

                node->switch_stmt.has_default = 1;
                {
                    AstNode *body = ast_alloc();
                    if (!body) {
                        parser_error(p, "AST node limit reached");
                        return 0;
                    }
                    body->type = AST_BLOCK;
                    body->block.count = 0;

                    while (parser_current(p).type != TOK_CASE &&
                           parser_current(p).type != TOK_DEFAULT &&
                           parser_current(p).type != TOK_CLOSE_BRACE &&
                           parser_current(p).type != TOK_EOF &&
                           !p->error) {
                        AstNode *stmt = parse_statement_ast(p);
                        if (!stmt) break;
                        if (body->block.count < 128) {
                            body->block.children[body->block.count++] = stmt;
                        }
                    }
                    node->switch_stmt.default_body = body;
                }
            } else {
                /* Unexpected token inside switch body */
                parser_advance(p);
            }
        }

        if (parser_current(p).type == TOK_CLOSE_BRACE) parser_advance(p);

        return node;
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
            tok.type == TOK_FOR || tok.type == TOK_SWITCH ||
            tok.type == TOK_DO) {
            /* Control flow: use two-phase AST approach.
             * Save and restore AST count to avoid corrupting
             * the outer AST arena. */
            unsigned int saved_ast_count = g_ast_count;
            AstNode *root = parse_block_ast(&p);
            if (p.error) {
                set_error_from_parser(&p);
                g_ast_count = saved_ast_count;
                return last;
            }
            if (root) {
                last = eval_ast(root, source + start);
            }
            g_ast_count = saved_ast_count;
            if (p.error) {
                set_error_from_parser(&p);
                return last;
            }
        } else {
            last = parse_statement(&p);
            if (p.error) {
                set_error_from_parser(&p);
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

    case AST_DO_WHILE: {
        do {
            g_break_pending = 0;
            g_continue_pending = 0;
            eval_ast(node->do_while_stmt.body, source);
            if (g_break_pending) {
                g_break_pending = 0;
                break;
            }
            if (g_continue_pending) {
                g_continue_pending = 0;
                /* skip to condition check */
            }
            if (g_return_pending) return last;
            if (interp_should_interrupt()) return last;
            {
                Value cond = eval_ast(node->do_while_stmt.condition, source);
                if (!is_truthy(cond)) break;
            }
        } while (1);
        break;
    }

    case AST_FOR: {
        /* Init is already evaluated during parsing (for side effects).
         * But we need to re-evaluate it for loop correctness — actually,
         * the init only runs once, so we evaluate it here. */
        eval_ast(node->for_stmt.init, source);

        while (1) {
            /* Check condition (empty condition = always true) */
            if (node->for_stmt.condition != 0 && node->for_stmt.condition->source_range.source_len > 0) {
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

    case AST_SWITCH: {
        /* Evaluate the switch expression */
        Value switch_val = eval_source_range(
            node->switch_stmt.expr_start,
            node->switch_stmt.expr_len, source);
        if (g_error_code != OBJC_INTERP_OK) return switch_val;

        /* Find matching case */
        int matched_case = -1;
        {
            unsigned int ci;
            for (ci = 0; ci < node->switch_stmt.case_count; ci++) {
                if (switch_val.is_int && node->switch_stmt.case_values[ci] == switch_val.int_val) {
                    matched_case = (int)ci;
                    break;
                }
            }
        }

        /* Execute from matched case (fall-through) or from default.
         * A break inside a switch exits the switch (not the enclosing loop).
         * We use a local flag to track switch-break separately from
         * g_break_pending (which would exit the enclosing for/while). */
        {
            int switch_break = 0;
            if (matched_case >= 0) {
                unsigned int ci;
                for (ci = (unsigned int)matched_case; ci < node->switch_stmt.case_count; ci++) {
                    g_break_pending = 0;
                    eval_ast(node->switch_stmt.case_bodies[ci], source);
                    if (g_break_pending) {
                        switch_break = 1;
                        g_break_pending = 0; /* consume the break — it exits switch, not loop */
                        break;
                    }
                    if (g_return_pending) return last;
                }
                /* Fall through to default if no break */
                if (!switch_break && !g_return_pending &&
                    node->switch_stmt.has_default && node->switch_stmt.default_body) {
                    g_break_pending = 0;
                    eval_ast(node->switch_stmt.default_body, source);
                    if (g_break_pending) {
                        switch_break = 1;
                        g_break_pending = 0; /* consume break */
                    }
                }
            } else if (node->switch_stmt.has_default && node->switch_stmt.default_body) {
                g_break_pending = 0;
                eval_ast(node->switch_stmt.default_body, source);
                if (g_break_pending) {
                    switch_break = 1;
                    g_break_pending = 0; /* consume break */
                }
            }
            (void)switch_break; /* break was consumed — enclosing loop continues */
        }
        break;
    }
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
    } else if (v.is_float) {
        /* Format float with up to 6 decimal places, trimming trailing zeros */
        double fv = v.float_val;
        int negative = 0;
        if (fv < 0.0) { negative = 1; fv = -fv; }
        if (negative) fmt_append_char(buf, capacity, &offset, '-');
        unsigned long ipart = (unsigned long)fv;
        double fpart = fv - (double)ipart;
        /* Integer part */
        if (ipart == 0) {
            fmt_append_char(buf, capacity, &offset, '0');
        } else {
            char ibuf[20];
            int ii = 0;
            while (ipart > 0) { ibuf[ii++] = '0' + (ipart % 10); ipart /= 10; }
            while (ii > 0) fmt_append_char(buf, capacity, &offset, ibuf[--ii]);
        }
        fmt_append_char(buf, capacity, &offset, '.');
        /* Fractional part: up to 6 digits, trim trailing zeros */
        char fbuf[7];
        int fi = 0;
        int last_nonzero = 0;
        for (int d = 0; d < 6; d++) {
            fpart *= 10.0;
            int digit = (int)fpart;
            fbuf[fi++] = '0' + digit;
            if (digit != 0) last_nonzero = fi;
            fpart -= digit;
        }
        /* If all zeros, show at least one */
        if (last_nonzero == 0) last_nonzero = 1;
        for (int d = 0; d < last_nonzero; d++) {
            fmt_append_char(buf, capacity, &offset, fbuf[d]);
        }
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
    /* Mark the static g_return_value if it holds a string pool pointer */
    if (g_return_value.is_id && g_return_value.obj_val != 0 && reloc_count < MAX_STRING_POOL_MARKS) {
        const char *ptr = (const char *)g_return_value.obj_val;
        if ((unsigned long)ptr >= pool_start && (unsigned long)ptr < pool_end) {
            relocs[reloc_count].old_off = (unsigned int)((unsigned long)ptr - pool_start);
            relocs[reloc_count].new_off = 0;
            reloc_count++;
        }
    }
    for (i = 0; i < g_instance_var_count && reloc_count < MAX_STRING_POOL_MARKS; i++) {
        /* Mark the object key (FDObj: marker) if it's in the string pool */
        {
            const char *obj_ptr = (const char *)g_instance_vars[i].object;
            if ((unsigned long)obj_ptr >= pool_start && (unsigned long)obj_ptr < pool_end) {
                if (reloc_count >= MAX_STRING_POOL_MARKS) break;
                relocs[reloc_count].old_off = (unsigned int)((unsigned long)obj_ptr - pool_start);
                relocs[reloc_count].new_off = 0;
                reloc_count++;
            }
        }
        /* Mark the value if it's an id-typed string pool pointer */
        if (g_instance_vars[i].value.is_id && g_instance_vars[i].value.obj_val != 0) {
            const char *ptr = (const char *)g_instance_vars[i].value.obj_val;
            if ((unsigned long)ptr >= pool_start && (unsigned long)ptr < pool_end) {
                if (reloc_count >= MAX_STRING_POOL_MARKS) break;
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
                if (reloc_count >= MAX_STRING_POOL_MARKS) break;
                relocs[reloc_count].old_off = (unsigned int)((unsigned long)ptr - pool_start);
                relocs[reloc_count].new_off = 0;
                reloc_count++;
            }
        }
        if (g_coll_entries[i].value.is_id && g_coll_entries[i].value.obj_val != 0) {
            const char *ptr = (const char *)g_coll_entries[i].value.obj_val;
            if ((unsigned long)ptr >= pool_start && (unsigned long)ptr < pool_end) {
                if (reloc_count >= MAX_STRING_POOL_MARKS) break;
                relocs[reloc_count].old_off = (unsigned int)((unsigned long)ptr - pool_start);
                relocs[reloc_count].new_off = 0;
                reloc_count++;
            }
        }
    }

    /* Mark block captured values that are string pool pointers */
    for (i = 0; i < g_block_count && reloc_count < MAX_STRING_POOL_MARKS; i++) {
        unsigned int ci;
        for (ci = 0; ci < g_blocks[i].capture_count && reloc_count < MAX_STRING_POOL_MARKS; ci++) {
            if (g_blocks[i].captures[ci].value.is_id && g_blocks[i].captures[ci].value.obj_val != 0) {
                const char *ptr = (const char *)g_blocks[i].captures[ci].value.obj_val;
                if ((unsigned long)ptr >= pool_start && (unsigned long)ptr < pool_end) {
                    if (reloc_count >= MAX_STRING_POOL_MARKS) break;
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
    /* Update g_return_value if it holds a string pool pointer */
    if (g_return_value.is_id && g_return_value.obj_val != 0) {
        const char *ptr = (const char *)g_return_value.obj_val;
        if ((unsigned long)ptr >= pool_start && (unsigned long)ptr < pool_end) {
            unsigned int off = (unsigned int)((unsigned long)ptr - pool_start);
            unsigned int r;
            for (r = 0; r < reloc_count; r++) {
                if (relocs[r].old_off == off) {
                    g_return_value.obj_val = (id)(g_string_pool + relocs[r].new_off);
                    break;
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
