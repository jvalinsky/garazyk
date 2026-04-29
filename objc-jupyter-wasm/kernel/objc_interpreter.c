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
    TOK_AT_KEYWORD,     /* @interface, @implementation, @end, @"string" */
    TOK_STRING_LITERAL, /* @"..." or "..." */
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
    unsigned int pos;
    unsigned int line;
    unsigned int column;
    Token current;
} Lexer;

static void lexer_init(Lexer *lex, const char *source, unsigned int length) {
    lex->source = source;
    lex->source_len = length;
    lex->pos = 0;
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
    for (i = 0; i < len && g_nslog_offset + 1 < OBJC_INTERP_NSLOG_BUFFER_SIZE; i++) {
        g_nslog_buffer[g_nslog_offset++] = text[i];
    }
    g_nslog_buffer[g_nslog_offset] = '\0';
}

static void nslog_append_char(char ch) {
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
    int arg_idx = 0;

    /* Parse format string */
    fmt_val = parse_expression(p);
    if (p->error) return;

    fmt = 0;
    if (fmt_val.is_id) {
        /* For @"..." string literals, the value is stored as a pointer
         * to the string data in the token. We use the token text directly. */
        /* Actually, we need to handle this differently. The @"..." literal
         * produces an id, but for NSLog we need the C string representation.
         * For now, let's use a simpler approach: store the string literal
         * text in a side buffer. */
    }

    /* Simplified approach: NSLog(@"format", args...)
     * We parse the format string token directly and then process arguments.
     * This requires that we track the format string text from the lexer.
     */

    /* For now, let's just capture the format string from the current token
     * if it was a @"..." string literal. We'll need to restructure this. */

    /* Actually, let's take a step back. The way this interpreter works:
     * 1. We parse NSLog as an identifier
     * 2. We see the opening paren
     * 3. The first argument is @"format" which is a TOK_STRING_LITERAL
     * 4. We parse it as an expression, getting a Value
     * 5. We need to extract the C string from the Value
     *
     * The problem: @"..." creates an id, but we don't have NSString yet.
     * Solution: For @"..." literals, we store the string data in a
     * global string pool and the id points to it. The string pool
     * entries are null-terminated C strings.
     */

    /* For the initial implementation, let's use a simpler approach:
     * We parse NSLog specially — we look at the raw token for the
     * format string, then parse the remaining arguments.
     */

    /* This is getting complex. Let me simplify: parse NSLog as a
     * special form directly, consuming tokens from the parser. */
    (void)fmt;
    (void)fi;
    (void)arg_idx;

    /* Skip remaining arguments for now */
    while (parser_current(p).type != TOK_CLOSE_PAREN && parser_current(p).type != TOK_EOF) {
        parser_advance(p);
    }
    if (parser_current(p).type == TOK_CLOSE_PAREN) {
        parser_advance(p);
    }

    nslog_append("NSLog called\n", 13);
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
    int arg_count;
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

            /* Append selector component */
            if (sel_len > 0) {
                if (sel_len + 1 < 256) sel_name[sel_len++] = ':';
            }
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
        struct objc_slot *slot;

        if (target.is_id) receiver = target.obj_val;
        else if (target.is_class) receiver = (id)target.cls_val;
        else if (target.is_int) receiver = (id)(long)target.int_val;

        /* Use objc_msg_lookup_sender for portability (objc_msgSend is
         * not available on WASM — message.h guards it with arch checks).
         * The slot contains the IMP (method implementation pointer). */
        slot = objc_msg_lookup_sender(&receiver, sel, 0);
        if (slot && slot->method) {
            typedef id (*MsgSendIMP)(id, SEL, ...);
            MsgSendIMP imp = (MsgSendIMP)slot->method;
            result = value_from_id(imp(receiver, sel));
        } else {
            result = value_from_id(0);
        }
        return result;
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

/* Method implementation context — stored for method callbacks */
typedef struct {
    char source[2048]; /* method body source */
    unsigned int source_len;
    Class class_ptr;
    SEL selector;
    int is_class_method;
} MethodImpl;

#define MAX_METHODS 64
static MethodImpl g_methods[MAX_METHODS];
static unsigned int g_method_count = 0;

/* Method implementation function — called by objc_msgSend */
static id method_impl_trampoline(id self, SEL _cmd) {
    /* For now, NSLog the call and return self */
    const char *sel_name = sel_getName(_cmd);
    nslog_append("-[", 2);
    nslog_append(class_getName(object_getClass(self)), cstr_len(class_getName(object_getClass(self))));
    nslog_append(" ", 1);
    nslog_append(sel_name, cstr_len(sel_name));
    nslog_append("] called\n", 9);
    return self;
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

            /* Parse keyword arguments */
            while (parser_current(p).type == TOK_COLON) {
                parser_advance(p); /* skip : */
                sel_name[sel_len++] = ':';
                sel_name[sel_len] = '\0';

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

                /* Skip argument name */
                if (parser_current(p).type == TOK_IDENTIFIER) {
                    parser_advance(p);
                }
            }

            /* Parse method body { ... } */
            if (parser_current(p).type == TOK_OPEN_BRACE) {
                int brace_depth = 1;
                unsigned int body_start = p->lex.pos;
                parser_advance(p);

                while (brace_depth > 0 && parser_current(p).type != TOK_EOF) {
                    if (parser_current(p).type == TOK_OPEN_BRACE) brace_depth++;
                    else if (parser_current(p).type == TOK_CLOSE_BRACE) {
                        brace_depth--;
                        if (brace_depth == 0) break;
                    }
                    parser_advance(p);
                }

                if (parser_current(p).type == TOK_CLOSE_BRACE) {
                    parser_advance(p);
                }
            }

            /* Add the method to the class */
            {
                SEL sel = sel_registerName(sel_name);
                class_addMethod(cls, sel, (void *)method_impl_trampoline, type_encoding);
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

    /* Type declaration: int, void, id, Class, SEL, or class name */
    if (tok.type == TOK_IDENTIFIER) {
        /* Check if this is a type name followed by a variable name.
         * We only check built-in types here — not runtime classes,
         * because objc_getClass may crash if the class table is empty. */
        if (cstr_eq(tok.text, "int") || cstr_eq(tok.text, "void") ||
            cstr_eq(tok.text, "id") || cstr_eq(tok.text, "Class") ||
            cstr_eq(tok.text, "SEL") || cstr_eq(tok.text, "BOOL") ||
            cstr_eq(tok.text, "long") || cstr_eq(tok.text, "char") ||
            cstr_eq(tok.text, "float") || cstr_eq(tok.text, "double")) {
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
        last = parse_statement(p);
        if (p->error) return last;
    }
    return last;
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

    /* Don't reset variable table — it persists across cells */

    parser_init(&p, source, length);

    /* Parse and evaluate all statements */
    parse_block(&p);

    if (p.error) {
        g_error_code = p.error;
        cstr_copy(g_error_buffer, p.error_msg, OBJC_INTERP_ERROR_SIZE);
        return p.error;
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
