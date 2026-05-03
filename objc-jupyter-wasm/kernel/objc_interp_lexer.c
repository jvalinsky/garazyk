/* objc_interp_lexer.c — Lexer for the ObjC interpreter
 *
 * Tokenizes Objective-C source into Token objects for the parser.
 * Handles: identifiers, keywords, @-keywords, string literals (@"..." and "..."),
 * integer literals (decimal and hex 0x...), float literals, operators
 * (single and two-character), and comments (// and /* *​/).
 *
 * Dependencies: objc_interp_types.h (Lexer, Token, TokenType, cstr_* helpers)
 */

#include "objc_interp_types.h"
#include "objc_interp_lexer.h"

/* ── Helper predicates ─────────────────────────────────────────── */

static int is_alpha(char ch) {
    return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_';
}

static int is_digit(char ch) {
    return ch >= '0' && ch <= '9';
}

static int is_alnum(char ch) {
    return is_alpha(ch) || is_digit(ch);
}

/* ── Lexer core ───────────────────────────────────────────────── */

void lexer_init(Lexer *lex, const char *source, unsigned int length,
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
    lex->current.truncated = 0;
}

char lexer_peek(Lexer *lex) {
    if (lex->pos >= lex->source_len) return '\0';
    return lex->source[lex->pos];
}

char lexer_next(Lexer *lex) {
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

void lexer_skip_whitespace_and_comments(Lexer *lex) {
    while (lex->pos < lex->source_len) {
        char ch = lexer_peek(lex);
        if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') {
            lexer_next(lex);
        } else if (ch == '/' && lex->pos + 1 < lex->source_len &&
                   lex->source[lex->pos + 1] == '/') {
            /* Single-line comment: consume everything until \n or EOF */
            while (lex->pos < lex->source_len && lexer_peek(lex) != '\n' && lexer_peek(lex) != '\0') {
                lexer_next(lex);
            }
            /* Consume the \n if present */
            if (lex->pos < lex->source_len && lexer_peek(lex) == '\n') {
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
            /* If we hit EOF without finding star-slash, just return - the outer loop will handle it */
        } else {
            break;
        }
    }
}

Token lexer_next_token(Lexer *lex) {
    Token tok;
    unsigned int i = 0;

    lexer_skip_whitespace_and_comments(lex);
    lex->token_start = lex->pos; /* remember where this token begins */
    tok.line = lex->line;
    tok.column = lex->column;
    tok.truncated = 0;
    tok.text[0] = '\0';
    tok.type = TOK_EOF;

    if (lex->pos >= lex->source_len) {
        tok.type = TOK_EOF;
        return tok;
    }

    char ch = lexer_peek(lex);

    /* Preprocessor directives: #import, #define, #pragma, #if, #ifdef, etc.
     * Skip the entire line — these have no meaning in the interpreter. */
    if (ch == '#') {
        while (lex->pos < lex->source_len && lexer_peek(lex) != '\n' && lexer_peek(lex) != '\0') {
            lexer_next(lex);
        }
        if (lex->pos < lex->source_len && lexer_peek(lex) == '\n') {
            lexer_next(lex);
        }
        /* Recurse to get the next real token */
        return lexer_next_token(lex);
    }

    /* @-keywords and @\"string\" */
    if (ch == '@') {
        lexer_next(lex);
        tok.text[0] = '@';
        tok.text[1] = '\0';
        i = 1;

        if (lexer_peek(lex) == '"') {
            /* @"string literal" */
            lexer_next(lex); /* skip opening " */
            int was_truncated = 0;
            while (lex->pos < lex->source_len && lexer_peek(lex) != '"') {
                char c = lexer_next(lex);
                if (c == '\\' && lex->pos < lex->source_len) {
                    c = lexer_next(lex);
                    if (c == 'n') c = '\n';
                    else if (c == 't') c = '\t';
                    else if (c == 'r') c = '\r';
                    else if (c == '0') c = '\0';
                    else if (c == 'a') c = '\a';
                    else if (c == 'b') c = '\b';
                    else if (c == 'f') c = '\f';
                    else if (c == 'v') c = '\v';
                    else if (c == '\\') c = '\\';
                    else if (c == '"') c = '"';
                    else if (c == '\'') c = '\'';
                    /* else: unknown escape, keep the character after backslash as-is */
                }
                if (i + 1 < OBJC_INTERP_MAX_TOKEN) {
                    tok.text[i++] = c;
                } else {
                    was_truncated = 1;
                }
            }
            if (lex->pos < lex->source_len) lexer_next(lex); /* skip closing " */
            tok.text[i] = '\0';
            tok.truncated = was_truncated;
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
        int was_truncated = 0;
        while (lex->pos < lex->source_len && lexer_peek(lex) != '"') {
            char c = lexer_next(lex);
            if (c == '\\' && lex->pos < lex->source_len) {
                c = lexer_next(lex);
                if (c == 'n') c = '\n';
                else if (c == 't') c = '\t';
                else if (c == 'r') c = '\r';
                else if (c == '0') c = '\0';
                else if (c == 'a') c = '\a';
                else if (c == 'b') c = '\b';
                else if (c == 'f') c = '\f';
                else if (c == 'v') c = '\v';
                else if (c == '\\') c = '\\';
                else if (c == '"') c = '"';
                else if (c == '\'') c = '\'';
                /* else: unknown escape, keep the character after backslash as-is */
            }
            if (i + 1 < OBJC_INTERP_MAX_TOKEN) {
                tok.text[i++] = c;
            } else {
                was_truncated = 1;
            }
        }
        if (lex->pos < lex->source_len) lexer_next(lex); /* skip closing " */
        tok.text[i] = '\0';
        tok.truncated = was_truncated;
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
        } else if (cstr_eq(tok.text, "nil")) {
            tok.type = TOK_NIL;
        } else if (cstr_eq(tok.text, "NULL")) {
            tok.type = TOK_NIL;
        } else if (cstr_eq(tok.text, "instancetype")) {
            /* Treat instancetype as id — same semantics in interpreter */
            cstr_copy(tok.text, "id", 64);
            tok.type = TOK_IDENTIFIER;
        } else if (cstr_eq(tok.text, "CGFloat")) {
            /* Treat CGFloat as double */
            cstr_copy(tok.text, "double", 64);
            tok.type = TOK_IDENTIFIER;
        } else if (cstr_eq(tok.text, "static")) {
            tok.type = TOK_IDENTIFIER; /* treat as ordinary identifier, handle in var decl */
        } else if (cstr_eq(tok.text, "super")) {
            tok.type = TOK_SUPER;
        } else if (cstr_eq(tok.text, "typedef")) {
            tok.type = TOK_IDENTIFIER; /* handle in parse_statement */
        }
        return tok;
    }

    /* Integer / float literal */
    if (is_digit(ch)) {
        if (ch == '0' && lex->pos + 1 < lex->source_len &&
            (lex->source[lex->pos + 1] == 'x' || lex->source[lex->pos + 1] == 'X')) {
            tok.text[i++] = lexer_next(lex); /* 0 */
            tok.text[i++] = lexer_next(lex); /* x/X */
            while (lex->pos < lex->source_len) {
                char hc = lexer_peek(lex);
                int is_hex = (hc >= '0' && hc <= '9') ||
                             (hc >= 'a' && hc <= 'f') ||
                             (hc >= 'A' && hc <= 'F');
                if (!is_hex) break;
                if (i + 1 < OBJC_INTERP_MAX_TOKEN) {
                    tok.text[i++] = lexer_next(lex);
                } else {
                    lexer_next(lex);
                    tok.truncated = 1;
                }
            }
            tok.text[i] = '\0';
            tok.type = TOK_INT_LITERAL;
            return tok;
        }
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
        if (ch == '<' && next == '<') {
            lexer_next(lex);
            tok.text[0] = '<'; tok.text[1] = '<'; tok.text[2] = '\0';
            tok.type = TOK_LEFT_SHIFT;
            return tok;
        }
        if (ch == '<' && next == '=') {
            lexer_next(lex);
            tok.text[0] = '<'; tok.text[1] = '='; tok.text[2] = '\0';
            tok.type = TOK_LE;
            return tok;
        }
        if (ch == '>' && next == '>') {
            lexer_next(lex);
            tok.text[0] = '>'; tok.text[1] = '>'; tok.text[2] = '\0';
            tok.type = TOK_RIGHT_SHIFT;
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
        case '|': tok.type = TOK_BITWISE_OR; break;
        default: tok.type = TOK_UNKNOWN; break;
    }

    return tok;
}
