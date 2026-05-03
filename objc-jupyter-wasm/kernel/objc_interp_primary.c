/*
 * objc_interp_primary.c
 * Primary expression parsing extracted from the main interpreter.
 */

#include "objc_interp_types.h"
#include "objc_interp_globals.h"
#include "objc_interp_primary.h"
#include "objc_interp_parser.h"
#include "objc_interp_state.h"
#include "objc_interp_dispatch.h"
#include "objc_interp_format.h"
#include "objc_interp_lexer.h"
#include "objc_interp_primary.h"
#include "objc_interp_ast.h"
#include "objc_interp_class.h"

/* Parser layout must match the definition in objc_interpreter.c. */
typedef struct Parser {
    Lexer lex;
    int error;
    char error_msg[OBJC_INTERP_ERROR_SIZE];
} Parser;

/* Externs for functions still in objc_interpreter.c or other modules. */
extern Token parser_current(struct Parser *p);
extern void parser_advance(struct Parser *p);
extern int parser_expect(struct Parser *p, TokenType type);
extern void parser_error(struct Parser *p, const char *msg);
extern int copy_identifier_or_error(struct Parser *p, char *dst, const char *src,
                                    unsigned int capacity, const char *kind);
extern Value parse_message_send(struct Parser *p);
extern id objc_lookUpClass(const char *name);
extern Class object_getClass(id);
extern int is_truthy(Value v);
extern InterpVar *interp_find_var(const char *name);
extern InterpVar *interp_get_or_create_var(const char *name);
extern void eval_nslog(struct Parser *p);

static int hex_digit_value(char ch) {
    if (ch >= '0' && ch <= '9') return ch - '0';
    if (ch >= 'a' && ch <= 'f') return ch - 'a' + 10;
    if (ch >= 'A' && ch <= 'F') return ch - 'A' + 10;
    return -1;
}

static int parse_integer_literal_magnitude(const char *text, unsigned long limit,
                                           unsigned long *out) {
    unsigned int i = 0;
    unsigned int base = 10;
    unsigned long val = 0;
    int saw_digit = 0;

    if (text == 0 || out == 0) return -1;
    if (text[0] == '0' && (text[1] == 'x' || text[1] == 'X')) {
        base = 16;
        i = 2;
    }

    while (text[i] != '\0') {
        int digit = (base == 16) ? hex_digit_value(text[i]) :
                    ((text[i] >= '0' && text[i] <= '9') ? text[i] - '0' : -1);
        if (digit < 0 || (unsigned int)digit >= base) return -1;
        saw_digit = 1;
        if (val > (limit - (unsigned long)digit) / base) return -2;
        val = val * base + (unsigned long)digit;
        i++;
    }

    if (!saw_digit) return -1;
    *out = val;
    return 0;
}

static Value parse_negated_integer_literal(Parser *p) {
    Token lit = parser_current(p);
    unsigned long mag = 0;
    int status;
    if (lit.truncated) {
        parser_error(p, "integer literal too long");
        return value_void();
    }
    status = parse_integer_literal_magnitude(lit.text, 2147483648ul, &mag);
    if (status == -2) {
        parser_error(p, "integer literal overflow");
        return value_void();
    }
    if (status != 0) {
        parser_error(p, "invalid integer literal");
        return value_void();
    }
    parser_advance(p);
    if (mag == 2147483648ul) return value_from_int(-2147483647 - 1);
    return value_from_int(-(int)mag);
}

Value parse_primary(Parser *p) {
    Token tok = parser_current(p);

    /* Unary minus — handle before other primaries */
    if (tok.type == TOK_MINUS) {
        parser_advance(p);
        if (parser_current(p).type == TOK_INT_LITERAL) {
            return parse_negated_integer_literal(p);
        }
        {
            Value v = parse_primary(p);
            if (v.is_int) return value_from_int(-v.int_val);
            if (v.is_float) return value_from_float(-v.float_val);
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

    /* Cast expression: (Type *)expr — just parse and ignore the type cast */
    if (tok.type == TOK_OPEN_PAREN) {
        Token saved = p->lex.current;
        unsigned int saved_pos = p->lex.pos;
        parser_advance(p); /* consume ( */
        /* Check if this looks like a type cast: (Type *) or (Type) */
        {
            int is_cast = 0;
            Token after_paren = parser_current(p);
            /* Check for type name followed by * or ) */
            if (after_paren.type == TOK_IDENTIFIER) {
                /* Skip type name */
                parser_advance(p);
                /* Check for * pointer or closing paren followed by expr */
                if (parser_current(p).type == TOK_STAR) {
                    parser_advance(p); /* consume * */
                    if (parser_current(p).type == TOK_CLOSE_PAREN) {
                        parser_advance(p); /* consume ) */
                        is_cast = 1;
                    }
                } else if (parser_current(p).type == TOK_CLOSE_PAREN) {
                    parser_advance(p); /* consume ) */
                    is_cast = 1;
                }
            }
            if (is_cast) {
                /* Just evaluate the expression inside, ignoring the cast type */
                return parse_primary(p);
            }
        }
        /* Not a cast — restore and let regular parsing handle it */
        p->lex.current = saved;
        p->lex.pos = saved_pos;
    }

    /* nil literal */
    if (tok.type == TOK_NIL) {
        parser_advance(p);
        return value_from_id(0);
    }

    /* String literal @"..." */
    if (tok.type == TOK_STRING_LITERAL) {
        /* Store the string in a global pool and return as id.
         * The token text includes the @ prefix for @"..." literals.
         * We skip it when storing in the pool. */
        if (tok.truncated) {
            parser_error(p, "string literal too long (max 255 bytes)");
            return value_void();
        }
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

    /* @-literal dispatch: @42, @3.14, @YES, @NO, @(expr), @[array], @{dict}
     * The lexer tokenizes '@' as TOK_AT_KEYWORD with text "@".
     * The next token after '@' determines the literal type.
     * IMPORTANT: We consume '@' exactly ONCE here, then dispatch
     * based on the following token. Previous code had a separate
     * numeric literal handler that consumed '@' and fell through
     * without restoring parser state, causing the @-literal
     * handler to skip a token.
     * NOTE: The lexer reads @YES/@NO/@TRUE/@FALSE as single
     * TOK_AT_KEYWORD tokens with text "@YES"/"@NO"/"@TRUE"/"@FALSE".
     * We handle those as special cases before the generic dispatch. */
    if (tok.type == TOK_AT_KEYWORD && (cstr_eq(tok.text, "@YES") || cstr_eq(tok.text, "@TRUE"))) {
        /* @YES / @TRUE → NSNumber numberWithBool:YES
         * Uses the same marker format as the built-in numberWithBool: handler. */
        parser_advance(p); /* consume @YES/@TRUE */
        {
            char *buf = string_pool_alloc(14);
            if (buf == 0) return value_from_int(1);
            cstr_copy(buf, "NSNumber:", 14);
            buf[9] = '1';
            buf[10] = '\0';
            return value_from_id((id)buf);
        }
    }
    if (tok.type == TOK_AT_KEYWORD && (cstr_eq(tok.text, "@NO") || cstr_eq(tok.text, "@FALSE"))) {
        /* @NO / @FALSE → NSNumber numberWithBool:NO
         * Uses the same marker format as the built-in numberWithBool: handler. */
        parser_advance(p); /* consume @NO/@FALSE */
        {
            char *buf = string_pool_alloc(14);
            if (buf == 0) return value_from_int(0);
            cstr_copy(buf, "NSNumber:", 14);
            buf[9] = '0';
            buf[10] = '\0';
            return value_from_id((id)buf);
        }
    }
    if (tok.type == TOK_AT_KEYWORD && cstr_eq(tok.text, "@")) {
        parser_advance(p); /* consume '@' */
        Token after_at = parser_current(p);

        if (after_at.type == TOK_INT_LITERAL) {
            /* @42 — numeric object literal → NSNumber marker */
            Value num_val = parse_primary(p); /* parse the integer */
            if (num_val.is_int) {
                /* Create NSNumber marker: "NSNumber:<int_value>"
                 * Same format as the built-in numberWithInt: handler. */
                char *buf = string_pool_alloc(64);
                if (buf != 0) {
                    int v = num_val.int_val;
                    cstr_copy(buf, "NSNumber:", 64);
                    {
                        /* Convert int to string and append */
                        char tmp[20];
                        int tpos = 0;
                        int neg = 0;
                        unsigned int blen;
                        if (v < 0) { neg = 1; v = -v; }
                        if (v == 0) tmp[tpos++] = '0';
                        else { while (v > 0) { tmp[tpos++] = '0' + (v % 10); v /= 10; } }
                        blen = (unsigned int)cstr_len(buf);
                        if (neg && blen < 63) buf[blen++] = '-';
                        while (tpos > 0 && blen < 63) buf[blen++] = tmp[--tpos];
                        buf[blen] = '\0';
                    }
                    return value_from_id((id)buf);
                }
            }
            return num_val;
        } else if (after_at.type == TOK_FLOAT_LITERAL) {
            /* @3.14 — numeric object literal → NSFloat marker */
            Value num_val = parse_primary(p); /* parse the float */
            if (num_val.is_float) {
                /* Create NSFloat marker: "NSFloat:<float_value>"
                 * Same format as the built-in numberWithDouble: handler. */
                char *buf = string_pool_alloc(64);
                if (buf != 0) {
                    cstr_copy(buf, "NSFloat:", 64);
                    {
                        /* Convert float to string and append */
                        char tmp[32];
                        int tpos = 0;
                        double v = num_val.float_val;
                        int neg = 0;
                        unsigned int blen;
                        unsigned int ipart;
                        double fpart;
                        if (v < 0) { neg = 1; v = -v; }
                        ipart = (unsigned int)v;
                        fpart = v - (double)ipart;
                        if (neg && cstr_len(buf) < 63) { blen = (unsigned int)cstr_len(buf); buf[blen++] = '-'; }
                        /* Integer part */
                        if (ipart == 0) tmp[tpos++] = '0';
                        else { unsigned int n = ipart; while (n > 0) { tmp[tpos++] = '0' + (n % 10); n /= 10; } }
                        blen = (unsigned int)cstr_len(buf);
                        while (tpos > 0 && blen < 63) buf[blen++] = tmp[--tpos];
                        /* Decimal part */
                        if (fpart > 0.0 && blen < 62) {
                            buf[blen++] = '.';
                            {
                                int digits = 0;
                                while (fpart > 0.0 && digits < 6 && blen < 63) {
                                    fpart *= 10.0;
                                    int d = (int)fpart;
                                    buf[blen++] = '0' + d;
                                    fpart -= (double)d;
                                    digits++;
                                }
                            }
                        }
                        buf[blen] = '\0';
                    }
                    return value_from_id((id)buf);
                }
            }
            return num_val;
        } else if (after_at.type == TOK_OPEN_PAREN) {
            /* @(expr) boxed expression */
            parser_advance(p); /* consume ( */
            {
                Value expr_val = parse_expression(p);
                parser_expect(p, TOK_CLOSE_PAREN);
                if (p->error) return value_void();
                if (expr_val.is_int) {
                    /* Create NSNumber marker: "NSNumber:<int_value>" */
                    char *buf = string_pool_alloc(64);
                    if (buf != 0) {
                        int v = expr_val.int_val;
                        cstr_copy(buf, "NSNumber:", 64);
                        {
                            char tmp[20];
                            int tpos = 0;
                            int neg = 0;
                            unsigned int blen;
                            if (v < 0) { neg = 1; v = -v; }
                            if (v == 0) tmp[tpos++] = '0';
                            else { while (v > 0) { tmp[tpos++] = '0' + (v % 10); v /= 10; } }
                            blen = (unsigned int)cstr_len(buf);
                            if (neg && blen < 63) buf[blen++] = '-';
                            while (tpos > 0 && blen < 63) buf[blen++] = tmp[--tpos];
                            buf[blen] = '\0';
                        }
                        return value_from_id((id)buf);
                    }
                    return expr_val;
                } else if (expr_val.is_float) {
                    /* Create NSFloat marker: "NSFloat:<float_value>" */
                    char *buf = string_pool_alloc(64);
                    if (buf != 0) {
                        cstr_copy(buf, "NSFloat:", 64);
                        {
                            char tmp[32];
                            int tpos = 0;
                            double v = expr_val.float_val;
                            int neg = 0;
                            unsigned int blen;
                            unsigned int ipart;
                            double fpart;
                            if (v < 0) { neg = 1; v = -v; }
                            ipart = (unsigned int)v;
                            fpart = v - (double)ipart;
                            if (neg && cstr_len(buf) < 63) { blen = (unsigned int)cstr_len(buf); buf[blen++] = '-'; }
                            if (ipart == 0) tmp[tpos++] = '0';
                            else { unsigned int n = ipart; while (n > 0) { tmp[tpos++] = '0' + (n % 10); n /= 10; } }
                            blen = (unsigned int)cstr_len(buf);
                            while (tpos > 0 && blen < 63) buf[blen++] = tmp[--tpos];
                            if (fpart > 0.0 && blen < 62) {
                                buf[blen++] = '.';
                                {
                                    int digits = 0;
                                    while (fpart > 0.0 && digits < 6 && blen < 63) {
                                        fpart *= 10.0;
                                        int d = (int)fpart;
                                        buf[blen++] = '0' + d;
                                        fpart -= (double)d;
                                        digits++;
                                    }
                                }
                            }
                            buf[blen] = '\0';
                        }
                        return value_from_id((id)buf);
                    }
                    return expr_val;
                } else if (expr_val.is_id || expr_val.is_class) {
                    return expr_val;
                }
                return expr_val;
            }
        } else if (after_at.type == TOK_OPEN_BRACKET) {
            /* @[ ... ] array literal */
            parser_advance(p); /* consume [ */
            {
                Value objects[64];
                unsigned int obj_count = 0;
                InterpVar *arr_var = 0;
                unsigned int i;
                if (parser_current(p).type != TOK_CLOSE_BRACKET) {
                    objects[obj_count++] = parse_expression_safe(p);
                    while (parser_current(p).type == TOK_COMMA && obj_count < 64) {
                        parser_advance(p);
                        objects[obj_count++] = parse_expression_safe(p);
                    }
                }
                if (parser_current(p).type == TOK_CLOSE_BRACKET) {
                    parser_advance(p);
                }
                for (i = 0; i < g_var_count; i++) {
                    if (cstr_eq(g_vars[i].name, "NSMutableArray") && g_vars[i].is_class) {
                        arr_var = &g_vars[i];
                        break;
                    }
                }
                if (!arr_var) {
                    arr_var = interp_get_or_create_var("NSMutableArray");
                    if (arr_var) {
                        arr_var->is_class = 1;
                        arr_var->cls = (Class)objc_lookUpClass("NSMutableArray");
                    }
                }
                if (arr_var && arr_var->cls) {
                    /* Create array directly using collection side table,
                     * not via interpreter method dispatch (which won't find
                     * the built-in "array" class method). */
                    unsigned int arr_cid = g_next_coll_id++;
                    Value arr = value_from_id(coll_make_marker("NSMutArr:", arr_cid));
                    for (i = 0; i < obj_count; i++) {
                        coll_add(arr_cid, objects[i], value_from_int(0));
                    }
                    return arr;
                }
            }
            return value_void();
        } else if (after_at.type == TOK_OPEN_BRACE) {
            /* @{ ... } dictionary literal */
            parser_advance(p); /* consume { */
            {
                InterpVar *dict_var = 0;
                unsigned int i;
                for (i = 0; i < g_var_count; i++) {
                    if (cstr_eq(g_vars[i].name, "NSMutableDictionary") && g_vars[i].is_class) {
                        dict_var = &g_vars[i];
                        break;
                    }
                }
                if (!dict_var) {
                    dict_var = interp_get_or_create_var("NSMutableDictionary");
                    if (dict_var) {
                        dict_var->is_class = 1;
                        dict_var->cls = (Class)objc_lookUpClass("NSMutableDictionary");
                    }
                }
                if (dict_var && dict_var->cls) {
                    /* Create dictionary directly using collection side table,
                     * not via interpreter method dispatch (which won't find
                     * the built-in "dictionary" class method). */
                    unsigned int cid = g_next_coll_id++;
                    Value dict = value_from_id(coll_make_marker("NSMutDict:", cid));
                    while (parser_current(p).type != TOK_CLOSE_BRACE && parser_current(p).type != TOK_EOF) {
                        Value key, value;
                        key = parse_expression_safe(p);
                        if (parser_current(p).type == TOK_COLON) {
                            parser_advance(p);
                            value = parse_expression_safe(p);
                            /* Add key-value pair directly to collection
                             * side table (bypass interpreter method dispatch). */
                            coll_add(cid, key, value);
                        }
                        if (parser_current(p).type == TOK_COMMA) {
                            parser_advance(p);
                        }
                    }
                    parser_expect(p, TOK_CLOSE_BRACE);
                    return dict;
                }
            }
            return value_void();
        }
        /* @ not followed by int, float, (, [, or { — fall through to error */
        parser_error(p, "Unexpected '@' (expected @number, @(...), @[...], or @{...})");
        return value_void();
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
                    if (sel == 0) {
                        parser_error(p, "selector table full (max 4096 selectors)");
                        return value_void();
                    }
                    return value_from_sel(sel);
                }
            }
        }
        return value_void();
    }

    /* Integer literal */
    if (tok.type == TOK_INT_LITERAL) {
        unsigned long val = 0;
        int status;
        if (tok.truncated) {
            parser_error(p, "integer literal too long");
            return value_void();
        }
        status = parse_integer_literal_magnitude(tok.text, 2147483647ul, &val);
        if (status == -2) {
            parser_error(p, "integer literal overflow");
            return value_void();
        }
        if (status != 0) {
            parser_error(p, "invalid integer literal");
            return value_void();
        }
        parser_advance(p);
        return value_from_int((int)val);
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
                    if (sel == 0) {
                        parser_error(p, "selector table full (max 4096 selectors)");
                        return value_void();
                    }
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

                    if (copy_identifier_or_error(p, prop_name, parser_current(p).text, 64, "property")) {
                        return value_void();
                    }
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
                                Value method_target = value_from_id(receiver);
                                unsigned int mi;
                                if (setter_sel == 0) {
                                    parser_error(p, "selector table full (max 4096 selectors)");
                                    return value_void();
                                }
                                mi = find_interpreter_method(setter_sel, method_target, receiver, 1);
                                if (mi < g_method_count) {
                                    Value setter_args[1];
                                    setter_args[0] = val;
                                    (void)execute_interpreter_method(p, &g_methods[mi], setter_sel,
                                                                     receiver, setter_args, 1, 0);
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
                                                    interp_set_var_from_value(ivar_var, val);
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
                                                interp_set_var_from_value(ivar_var, new_val);
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
                        Value method_target = value_from_id(receiver);
                        unsigned int mi;
                        if (prop_sel == 0) {
                            parser_error(p, "selector table full (max 4096 selectors)");
                            return value_void();
                        }
                        mi = find_interpreter_method(prop_sel, method_target, receiver, 1);
                        if (mi < g_method_count) {
                            return execute_interpreter_method(p, &g_methods[mi], prop_sel,
                                                              receiver, 0, 0, 0);
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
                                result = eval_source_range(0, blk->source_len, blk->source, 0);

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
        if (parser_current(p).type == TOK_INT_LITERAL) {
            return parse_negated_integer_literal(p);
        }
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
                        if (copy_identifier_or_error(p, blk->arg_names[blk->arg_count],
                                                     parser_current(p).text, 64,
                                                     "block argument")) {
                            return value_void();
                        }
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
        } else if (body_len >= 2048) {
            parser_error(p, "block body too large (max 2047 bytes)");
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