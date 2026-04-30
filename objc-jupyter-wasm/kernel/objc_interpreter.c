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

/* Runtime functions exported from the WASM module but not declared
 * in the headers we include (they're in NSObject.h normally). */
extern Class object_getClass(id);

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
    TOK_RETURN,        /* return keyword */
    TOK_IF,            /* if keyword */
    TOK_ELSE,          /* else keyword */
    TOK_WHILE,         /* while keyword */
    TOK_FOR,           /* for keyword */
    TOK_DO,            /* do keyword */
    TOK_BREAK,         /* break keyword */
    TOK_CONTINUE,      /* continue keyword */
    TOK_AND,           /* && */
    TOK_OR,            /* || */
    TOK_NOT,           /* ! (logical not) */
    TOK_PLUS_PLUS,     /* ++ */
    TOK_MINUS_MINUS,   /* -- */
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
    unsigned int i;
    for (i = 0; i < g_var_count; i++) {
        if (cstr_eq(g_vars[i].name, name)) {
            return &g_vars[i];
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

/* ── Forward declarations ───────────────────────────────────────── */

static Value parse_expression(Parser *p);
static Value parse_statement(Parser *p);
static Value parse_block(Parser *p);

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
    fmt_val = parse_expression(p);
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
            args[arg_count] = parse_expression(p);
            if (p->error) return;
            arg_count++;
        } else {
            /* Skip excess arguments */
            parse_expression(p);
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
                            const char *name = class_getName(v.cls_val);
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
    target = parse_expression(p);
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
                    Value arg = parse_expression(p);
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

        if (target.is_id) receiver = target.obj_val;
        else if (target.is_class) receiver = (id)target.cls_val;
        else if (target.is_int) receiver = (id)(long)target.int_val;

        /* Built-in: [ClassName alloc] → class_createInstance */
        if (target.is_class && cstr_eq(sel_name, "alloc")) {
            id instance = (id)0;
            instance = class_createInstance(target.cls_val, 0);
            if (instance == 0) {
                nslog_append("[alloc] failed for class ", 27);
                nslog_append(class_getName(target.cls_val),
                             cstr_len(class_getName(target.cls_val)));
                nslog_append("\n", 1);
            }
            return value_from_id(instance);
        }

        /* Built-in: [obj init] → return self (standard NSObject pattern) */
        if (cstr_eq(sel_name, "init") && target.is_id && receiver != 0) {
            return value_from_id(receiver);
        }

        /* Built-in: [obj class] → return the object's class */
        if (cstr_eq(sel_name, "class") && target.is_id && receiver != 0) {
            Class cls = (Class)0;
            cls = object_getClass(receiver);
            return value_from_class(cls);
        }

        /* Check if this selector matches an interpreter-registered method.
         * Interpreter methods are executed directly in the interpreter to
         * avoid WASM calling convention issues with variadic IMP dispatch. */
        {
            unsigned int mi;
            for (mi = 0; mi < g_method_count; mi++) {
                if (g_methods[mi].selector == sel && g_methods[mi].source_len > 0) {
                    break;
                }
            }

            if (mi < g_method_count) {
                /* Found an interpreter method — execute it directly */
                unsigned int saved_var_count = g_var_count;
                Value return_val;

                /* Set up self and _cmd */
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

                /* Execute the method body */
                g_return_pending = 0;
                {
                    int interp_result = objc_interp(g_methods[mi].source, g_methods[mi].source_len);
                    (void)interp_result;
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

                /* Clean up method-local variables */
                g_var_count = saved_var_count;
                g_return_pending = 0;

                return return_val;
            }
        }

        /* Fall through: no built-in or interpreter method matched.
         * Runtime IMP dispatch is not used because WASM enforces exact
         * function signatures — variadic IMP calls cause signature
         * mismatch traps. All supported methods must be handled as
         * built-ins or interpreter-registered methods above. */
        {
            const char *cls_name = "unknown";
            if (target.is_id && receiver != 0) {
                Class cls = object_getClass(receiver);
                if (cls) cls_name = class_getName(cls);
            } else if (target.is_class && target.cls_val) {
                cls_name = class_getName(target.cls_val);
            }
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

    /* Allocate the class pair */
    new_class = objc_allocateClassPair(super_class, class_name, 0);
    if (new_class == 0) {
        parser_error(p, "Failed to allocate class pair");
        return value_void();
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

    /* Register the class */
    objc_registerClassPair(new_class);

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
        int result = objc_interp(g_methods[i].source, g_methods[i].source_len);
        (void)result; /* errors are captured in g_error_buffer */
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

            /* Store the method and register it with the class */
            {
                SEL sel = sel_registerName(sel_name);
                class_addMethod(cls, sel, (void *)method_impl_trampoline, type_encoding);

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
        /* Store the string in a global pool and return as id */
        /* For now, we just return the string text as a value */
        parser_advance(p);
        /* We'll store @"..." strings in a simple pool */
        {
            static char string_pool[4096];
            static unsigned int string_pool_offset = 0;
            unsigned int len = cstr_len(tok.text);
            char *str_ptr;
            if (string_pool_offset + len + 2 > 4096) {
                string_pool_offset = 0;
            }
            str_ptr = string_pool + string_pool_offset;
            cstr_copy(str_ptr, tok.text, 4096 - string_pool_offset);
            string_pool_offset += len + 1;
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
        return parse_message_send(p);
    }

    /* Parenthesized expression */
    if (tok.type == TOK_OPEN_PAREN) {
        parser_advance(p);
        {
            Value v = parse_expression(p);
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
        parser_error(p, "Unsupported @keyword");
        return value_void();
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

static Value parse_assignment(Parser *p) {
    Value target = parse_comparison(p);
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

        if (is_builtin_type || is_class_type) {
            /* Look ahead to see if next token is * or an identifier */
            Token saved = p->lex.current;
            unsigned int saved_pos = p->lex.pos;
            parser_advance(p);

            if (parser_current(p).type == TOK_STAR ||
                parser_current(p).type == TOK_IDENTIFIER) {
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
        const char *name = class_getName(v.cls_val);
        fmt_append_str(buf, capacity, &offset, name);
    } else if (v.is_sel && v.sel_val != 0) {
        const char *name = sel_getName(v.sel_val);
        fmt_append_str(buf, capacity, &offset, "(SEL) ");
        fmt_append_str(buf, capacity, &offset, name);
    } else if (v.is_id && v.obj_val != 0) {
        /* Object — show class name and pointer */
        Class cls = object_getClass(v.obj_val);
        const char *name = cls ? class_getName(cls) : "unknown";
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

/* ── Public API ─────────────────────────────────────────────────── */

void objc_interp_init(void) {
    g_nslog_offset = 0;
    g_nslog_buffer[0] = '\0';
    g_error_code = OBJC_INTERP_OK;
    g_error_buffer[0] = '\0';
    g_result_buffer[0] = '\0';
    g_var_count = 0;
    g_method_count = 0;
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

    /* Don't reset variable table — it persists across cells */

    parser_init(&p, source, length);

    /* Parse and evaluate all statements */
    {
        Value last = parse_block(&p);

        if (p.error) {
            if (cstr_eq(p.error_msg, "Execution interrupted")) {
                g_error_code = OBJC_INTERP_INTERRUPTED;
            } else {
                g_error_code = p.error;
            }
            cstr_copy(g_error_buffer, p.error_msg, OBJC_INTERP_ERROR_SIZE);
            return p.error;
        }

        /* Format the last expression result for REPL display */
        format_value(last, g_result_buffer, 512);
    }

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
