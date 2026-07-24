/*
 * objc_interp_parser.c
 * Expression and statement parsing extracted from the main interpreter.
 */

#include "objc_interp_types.h"
#include "objc_interp_context.h"
#include "objc_interp_parser.h"
#include "objc_interp_ast.h"
#include "objc_interp_state.h"
#include "objc_interp_lexer.h"
#include "objc_interp_class.h"

/* Parser layout must match the definition in objc_interpreter.c. */

/* Externs for functions still in objc_interpreter.c or other modules. */
extern Token parser_current(struct Parser *p);
extern void parser_advance(struct Parser *p);
extern int parser_expect(struct Parser *p, TokenType type);
extern void parser_error(struct Parser *p, const char *msg);
extern int copy_identifier_or_error(struct Parser *p, char *dst, const char *src,
                                    unsigned int capacity, const char *kind);
extern Value parse_primary(struct Parser *p);
extern Value parse_message_send(struct Parser *p);
extern id objc_lookUpClass(const char *name);
extern const char *typedef_resolve(const char *name);
extern int interp_should_interrupt(void);
extern InterpVar *interp_find_var(const char *name);
extern InterpVar *interp_get_or_create_var(const char *name);
extern StructDef *struct_def_find(const char *name);

/* Forward declarations for static precedence functions. */
static Value parse_multiplicative(Parser *p);
static Value parse_shift(Parser *p);
static Value parse_additive(Parser *p);
static Value parse_comparison(Parser *p);
static Value parse_bitwise_xor(Parser *p);
static Value parse_bitwise_or(Parser *p);
static Value parse_logical_and(Parser *p);
static Value parse_logical_or(Parser *p);
static Value parse_ternary(Parser *p);
static Value parse_assignment(Parser *p);

Value parse_expression_safe(Parser *p) {
    Value result;
    if (g_ctx.parse_depth >= MAX_PARSE_DEPTH) {
        parser_error(p, "maximum expression depth exceeded");
        return value_void();
    }
    g_ctx.parse_depth++;
    result = parse_expression(p);
    g_ctx.parse_depth--;
    return result;
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

static Value parse_shift(Parser *p) {
    Value left = parse_multiplicative(p);
    if (p->error) return left;

    while (parser_current(p).type == TOK_LEFT_SHIFT ||
           parser_current(p).type == TOK_RIGHT_SHIFT) {
        TokenType op = parser_current(p).type;
        parser_advance(p);
        {
            Value right = parse_multiplicative(p);
            if (p->error) return right;
            if (left.is_int && right.is_int) {
                if (op == TOK_LEFT_SHIFT) left.int_val = left.int_val << right.int_val;
                else if (op == TOK_RIGHT_SHIFT) left.int_val = left.int_val >> right.int_val;
            }
        }
    }

    return left;
}

static Value parse_additive(Parser *p) {
    Value left = parse_shift(p);
    if (p->error) return left;

    while (parser_current(p).type == TOK_PLUS ||
           parser_current(p).type == TOK_MINUS) {
        TokenType op = parser_current(p).type;
        parser_advance(p);
        {
            Value right = parse_shift(p);
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
            } else if (op == TOK_EQ || op == TOK_NEQ) {
                /* id/class comparison: obj == nil, obj != nil, nil == obj, etc.
                 * Also handles id == id (pointer equality) and Class != nil */
                int result = 0;
                long lv = 0, rv = 0;
                if (left.is_id) lv = (long)left.obj_val;
                else if (left.is_class) lv = (long)left.cls_val;
                else if (left.is_int) lv = left.int_val;
                if (right.is_id) rv = (long)right.obj_val;
                else if (right.is_class) rv = (long)right.cls_val;
                else if (right.is_int) rv = right.int_val;
                if (op == TOK_EQ) result = (lv == rv);
                else result = (lv != rv);
                left = value_from_int(result);
            }
        }
    }

    return left;
}

Value parse_bitwise_and(Parser *p) {
    Value left = parse_comparison(p);
    if (p->error) return left;

    while (parser_current(p).type == TOK_AMPERSAND) {
        parser_advance(p);
        {
            Value right = parse_comparison(p);
            if (p->error) return right;
            if (left.is_int && right.is_int) {
                left = value_from_int(left.int_val & right.int_val);
            }
        }
    }

    return left;
}

static Value parse_bitwise_xor(Parser *p) {
    Value left = parse_bitwise_and(p);
    if (p->error) return left;

    while (parser_current(p).type == TOK_CARET) {
        parser_advance(p);
        {
            Value right = parse_bitwise_and(p);
            if (p->error) return right;
            if (left.is_int && right.is_int) {
                left = value_from_int(left.int_val ^ right.int_val);
            }
        }
    }

    return left;
}

static Value parse_bitwise_or(Parser *p) {
    Value left = parse_bitwise_xor(p);
    if (p->error) return left;

    while (parser_current(p).type == TOK_BITWISE_OR) {
        parser_advance(p);
        {
            Value right = parse_bitwise_xor(p);
            if (p->error) return right;
            if (left.is_int && right.is_int) {
                left = value_from_int(left.int_val | right.int_val);
            }
        }
    }

    return left;
}

static Value parse_logical_and(Parser *p) {
    Value left = parse_bitwise_or(p);
    if (p->error) return left;

    while (parser_current(p).type == TOK_AND) {
        parser_advance(p);
        if (!is_truthy(left)) {
            /* Short-circuit: left is falsy, so && yields 0.
             * We must still parse the right side to consume tokens,
             * but suppress side effects (message sends, variable mutations). */
            int saved_suppress = g_ctx.suppress_side_effects;
            g_ctx.suppress_side_effects = 1;
            {
                Value right = parse_bitwise_or(p);
                (void)right; /* discard — result is always 0 */
            }
            g_ctx.suppress_side_effects = saved_suppress;
            if (p->error) return left;
            left = value_from_int(0);
        } else {
            Value right = parse_bitwise_or(p);
            if (p->error) return right;
            left = value_from_int(is_truthy(right) ? 1 : 0);
        }
    }

    return left;
}

static Value parse_logical_or(Parser *p) {
    Value left = parse_logical_and(p);
    if (p->error) return left;

    while (parser_current(p).type == TOK_OR) {
        parser_advance(p);
        if (is_truthy(left)) {
            /* Short-circuit: left is truthy, so || yields 1.
             * Parse right side to consume tokens but suppress side effects. */
            int saved_suppress = g_ctx.suppress_side_effects;
            g_ctx.suppress_side_effects = 1;
            {
                Value right = parse_logical_and(p);
                (void)right; /* discard — result is always 1 */
            }
            g_ctx.suppress_side_effects = saved_suppress;
            if (p->error) return left;
            left = value_from_int(1);
        } else {
            Value right = parse_logical_and(p);
            if (p->error) return right;
            left = value_from_int(is_truthy(right) ? 1 : 0);
        }
    }

    return left;
}

static Value parse_ternary(Parser *p) {
    Value cond = parse_logical_or(p);
    if (p->error) return cond;

    if (parser_current(p).type == TOK_QUESTION) {
        parser_advance(p);
        {
            int cond_truthy = is_truthy(cond);
            if (cond_truthy) {
                /* Evaluate true branch, skip false branch */
                Value true_val = parse_ternary(p); /* right-associative */
                if (p->error) return true_val;
                if (parser_current(p).type != TOK_COLON) {
                    p->error = 1;
                    cstr_copy(g_ctx.error_buffer, "expected ':' in ternary expression", OBJC_INTERP_ERROR_SIZE);
                    return cond;
                }
                parser_advance(p); /* skip : */
                {
                    /* Suppress side effects for the false branch */
                    int saved_suppress = g_ctx.suppress_side_effects;
                    g_ctx.suppress_side_effects = 1;
                    {
                        Value false_val = parse_ternary(p);
                        (void)false_val;
                    }
                    g_ctx.suppress_side_effects = saved_suppress;
                }
                if (p->error) return true_val;
                return true_val;
            } else {
                /* Skip true branch, evaluate false branch */
                int saved_suppress = g_ctx.suppress_side_effects;
                g_ctx.suppress_side_effects = 1;
                {
                    Value true_val = parse_ternary(p);
                    (void)true_val;
                }
                g_ctx.suppress_side_effects = saved_suppress;
                if (p->error) return cond;
                if (parser_current(p).type != TOK_COLON) {
                    p->error = 1;
                    cstr_copy(g_ctx.error_buffer, "expected ':' in ternary expression", OBJC_INTERP_ERROR_SIZE);
                    return cond;
                }
                parser_advance(p); /* skip : */
                {
                    Value false_val = parse_ternary(p); /* right-associative */
                    if (p->error) return false_val;
                    return false_val;
                }
            }
        }
    }

    return cond;
}

static Value parse_assignment(Parser *p) {
    /* Pointer dereference assignment: *identifier = value
     * In the interpreter, pointer variables are stored as regular variables,
     * so *stop = 1 is equivalent to stop = 1. */
    if (parser_current(p).type == TOK_STAR) {
        Token star_tok = parser_current(p);
        unsigned int saved_pos = p->lex.pos;
        Token saved_tok = p->lex.current;
        parser_advance(p); /* consume * */
        if (parser_current(p).type == TOK_IDENTIFIER) {
            Token ident = parser_current(p);
            parser_advance(p);
            if (parser_current(p).type == TOK_ASSIGN) {
                InterpVar *var = interp_find_var(ident.text);
                Value val;
                parser_advance(p);
                val = parse_assignment(p);
                if (p->error) return val;
                if (var == 0) {
                    parser_error(p, "assignment target is not a variable");
                    return value_void();
                }
                if (!g_ctx.suppress_side_effects) {
                    interp_set_var_from_value(var, val);
                }
                return val;
            }
        }
        /* Not a dereference assignment — rewind and fall through */
        p->lex.pos = saved_pos;
        p->lex.current = saved_tok;
    }

    if (parser_current(p).type == TOK_IDENTIFIER) {
        Token ident = parser_current(p);
        Token saved = p->lex.current;
        unsigned int saved_pos = p->lex.pos;
        parser_advance(p);
        if (parser_current(p).type == TOK_ASSIGN) {
            InterpVar *var = interp_find_var(ident.text);
            Value val;
            parser_advance(p);
            val = parse_assignment(p);
            if (p->error) return val;
            if (var == 0) {
                parser_error(p, "assignment target is not a variable");
                return value_void();
            }
            if (!g_ctx.suppress_side_effects) {
                interp_set_var_from_value(var, val);
            }
            return val;
        }
        p->lex.current = saved;
        p->lex.pos = saved_pos;
    }

    Value target = parse_ternary(p);
    if (p->error) return target;
    if (parser_current(p).type == TOK_ASSIGN) {
        parser_error(p, "unsupported assignment target");
        return value_void();
    }
    return target;
}

Value parse_expression(Parser *p) {
    return parse_assignment(p);
}

Value parse_type_and_var_decl(Parser *p) {
    /* Parse type: int, void, id, Class, SEL, Type* */
    char type_name[64];
    int is_pointer = 0;
    int is_block_var = 0;  /* 1 if __block qualifier */
    int is_static_var = 0;  /* 1 if static variable — persists across cells */
    (void)is_pointer; /* may be used later for pointer type tracking */

    /* Check for __block qualifier */
    if (parser_current(p).type == TOK_IDENTIFIER && cstr_eq(parser_current(p).text, "__block")) {
        is_block_var = 1;
        parser_advance(p);
    }

    /* Check for static qualifier */
    if (parser_current(p).type == TOK_IDENTIFIER && cstr_eq(parser_current(p).text, "static")) {
        is_static_var = 1;
        parser_advance(p);
    }

    /* Skip type qualifiers: const, volatile, restrict — not semantically
     * meaningful in the interpreter, but must be consumed to avoid
     * "Unknown identifier" errors on declarations like
     *   const char *bytes = [data bytes]; */
    while (parser_current(p).type == TOK_IDENTIFIER &&
           (cstr_eq(parser_current(p).text, "const") ||
            cstr_eq(parser_current(p).text, "volatile") ||
            cstr_eq(parser_current(p).text, "restrict"))) {
        parser_advance(p);
    }

    type_name[0] = '\0';

    if (parser_current(p).type == TOK_IDENTIFIER) {
        cstr_copy(type_name, parser_current(p).text, 64);
        parser_advance(p);
    }

    /* Multi-token type parsing: unsigned int, long long, signed char, etc.
     * Consume subsequent type tokens that extend the type, then map
     * the combined type to one of the interpreter's internal types. */
    if (cstr_eq(type_name, "unsigned") || cstr_eq(type_name, "signed")) {
        /* unsigned/signed alone → int; followed by int/char/long/short → combine */
        if (parser_current(p).type == TOK_IDENTIFIER) {
            if (cstr_eq(parser_current(p).text, "int") ||
                cstr_eq(parser_current(p).text, "char") ||
                cstr_eq(parser_current(p).text, "short") ||
                cstr_eq(parser_current(p).text, "long")) {
                /* unsigned int → int, unsigned char → char, etc.
                 * In the interpreter, all are mapped to the base type. */
                cstr_copy(type_name, parser_current(p).text, 64);
                parser_advance(p);
            }
            /* else: standalone "unsigned" → treat as "int" */
        }
        if (cstr_eq(type_name, "unsigned") || cstr_eq(type_name, "signed")) {
            cstr_copy(type_name, "int", 64);
        }
    }
    if (cstr_eq(type_name, "long")) {
        /* long alone → int; long long → int; long double → double */
        if (parser_current(p).type == TOK_IDENTIFIER) {
            if (cstr_eq(parser_current(p).text, "long")) {
                cstr_copy(type_name, "int", 64); /* long long → int */
                parser_advance(p);
            } else if (cstr_eq(parser_current(p).text, "int")) {
                cstr_copy(type_name, "int", 64); /* long int → int */
                parser_advance(p);
            } else if (cstr_eq(parser_current(p).text, "double")) {
                cstr_copy(type_name, "double", 64); /* long double → double */
                parser_advance(p);
            }
        }
        /* standalone "long" → int */
        if (cstr_eq(type_name, "long")) {
            cstr_copy(type_name, "int", 64);
        }
    }
    if (cstr_eq(type_name, "short")) {
        /* short alone → int; short int → int */
        if (parser_current(p).type == TOK_IDENTIFIER &&
            cstr_eq(parser_current(p).text, "int")) {
            parser_advance(p);
        }
        cstr_copy(type_name, "int", 64);
    }
    /* Also handle: unsigned long, unsigned long long, etc.
     * These come from the unsigned branch above mapping to "long" or "int",
     * then we need to handle "long" after "unsigned" was consumed.
     * The unsigned branch already consumed the base type, but if it saw
     * "unsigned long" it mapped type_name to "long" — handle that here. */
    if (cstr_eq(type_name, "long")) {
        if (parser_current(p).type == TOK_IDENTIFIER) {
            if (cstr_eq(parser_current(p).text, "long")) {
                cstr_copy(type_name, "int", 64); /* long long → int */
                parser_advance(p);
            } else if (cstr_eq(parser_current(p).text, "int")) {
                cstr_copy(type_name, "int", 64); /* long int → int */
                parser_advance(p);
            }
        }
        if (cstr_eq(type_name, "long")) {
            cstr_copy(type_name, "int", 64);
        }
    }

    /* Resolve typedef aliases: if type_name is a typedef, replace with base type.
     * This allows "MyInt x = 5;" to work when "typedef int MyInt;" was declared. */
    {
        const char *resolved = typedef_resolve(type_name);
        if (resolved && !cstr_eq(resolved, type_name)) {
            cstr_copy(type_name, resolved, 64);
        }
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

                if (copy_identifier_or_error(p, var_name_buf, parser_current(p).text, 64, "variable")) {
                    return value_void();
                }
                parser_advance(p);

                if (parser_current(p).type == TOK_CLOSE_PAREN) {
                    parser_advance(p); /* consume ) */
                }

                /* Skip the parameter type list: (Type1, Type2, ...)
                 * We need to track parenthesis depth to handle nested types. */
                if (parser_current(p).type == TOK_OPEN_PAREN) {
                    unsigned int paren_depth = 0;
                    do {
                        if (parser_current(p).type == TOK_OPEN_PAREN) paren_depth++;
                        else if (parser_current(p).type == TOK_CLOSE_PAREN) paren_depth--;
                        parser_advance(p);
                    } while (paren_depth > 0 && parser_current(p).type != TOK_EOF);
                }

                /* For static block variables, check if one already exists */
                if (is_static_var) {
                    InterpVar *existing = interp_find_var(var_name_buf);
                    if (existing && existing->is_static) {
                        /* Static variable already initialized - skip reinitialization */
                        if (parser_current(p).type == TOK_ASSIGN) {
                            parser_advance(p);
                            parse_expression(p);
                            if (p->error) return value_void();
                        }
                        return value_void();
                    }
                }

                var = interp_get_or_create_var(var_name_buf);
                if (var == 0) {
                    parser_error(p, "variable table full (max 1024)");
                    return value_void();
                }
                var->is_block_captured = is_block_var;
                var->is_static = is_static_var; /* mark as static if needed */

                /* When side effects are suppressed, parse initializer but
                 * don't store the value (variable still exists but is
                 * zero-initialized). */
                /* Parse initializer: = block_literal */
                if (parser_current(p).type == TOK_ASSIGN) {
                    parser_advance(p);
                    init_val = parse_expression(p);
                    if (p->error) return init_val;

                    if (var && !g_ctx.suppress_side_effects) {
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
                if (!g_ctx.suppress_side_effects) {
                    var->is_id = 1;
                    var->value = 0;
                }
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
        if (copy_identifier_or_error(p, var_name_buf, parser_current(p).text, 64, "variable")) {
            return value_void();
        }
        parser_advance(p);

        /* Check for C array declarator: name[N]
         * Only valid for char/unsigned char types — desugars to NSData.
         * We track the array size for brace initializer validation. */
        {
            int is_char_array = 0;
            int array_size = 0;
            if (parser_current(p).type == TOK_OPEN_BRACKET &&
                cstr_eq(type_name, "char")) {
                /* Save position to backtrack if this isn't an array declarator */
                unsigned int saved_pos = p->lex.pos;
                unsigned int saved_token_start = p->lex.token_start;
                unsigned int saved_line = p->lex.line;
                unsigned int saved_column = p->lex.column;
                Token saved_tok = parser_current(p);
                parser_advance(p); /* consume [ */

                /* Parse constant integer expression for array size */
                if (parser_current(p).type == TOK_INT_LITERAL) {
                    /* Parse integer from token text */
                    int sz = 0;
                    const char *s = parser_current(p).text;
                    while (*s >= '0' && *s <= '9') sz = sz * 10 + (*s++ - '0');
                    array_size = sz;
                    parser_advance(p);
                    if (parser_current(p).type == TOK_CLOSE_BRACKET) {
                        parser_advance(p); /* consume ] */
                        is_char_array = 1;
                    } else {
                        /* Not an array declarator — backtrack */
                        p->lex.pos = saved_pos;
                        p->lex.token_start = saved_token_start;
                        p->lex.line = saved_line;
                        p->lex.column = saved_column;
                        p->lex.current = saved_tok;
                    }
                } else if (parser_current(p).type == TOK_CLOSE_BRACKET) {
                    /* name[] — unsized array, size determined by initializer */
                    parser_advance(p); /* consume ] */
                    is_char_array = 1;
                    array_size = 0; /* will be set from initializer */
                } else {
                    /* Not an array declarator — backtrack */
                    p->lex.pos = saved_pos;
                    p->lex.token_start = saved_token_start;
                    p->lex.line = saved_line;
                    p->lex.column = saved_column;
                    p->lex.current = saved_tok;
                }
            }

            if (is_char_array) {
                /* Char array declaration — create variable and handle brace initializer */
                var = interp_get_or_create_var(var_name_buf);
                if (var == 0) {
                    parser_error(p, "variable table full (max 1024)");
                    return value_void();
                }
                var->is_int = 0;
                var->is_float = 0;
                var->is_class = 0;
                var->is_sel = 0;
                if (parser_current(p).type == TOK_ASSIGN) {
                    parser_advance(p); /* consume = */
                }

                if (parser_current(p).type == TOK_OPEN_BRACE) {
                    /* Parse {expr, expr, ...} brace initializer */
                    parser_advance(p); /* consume { */
                    {
                        /* Build hex-encoded NSData from byte values */
                        char hex_buf[512]; /* max 256 bytes */
                        int hex_idx = 0;

                        while (parser_current(p).type != TOK_CLOSE_BRACE &&
                               parser_current(p).type != TOK_EOF &&
                               !p->error) {
                            Value bv = parse_expression(p);
                            if (p->error) break;
                            {
                                int val = bv.is_int ? bv.int_val : 0;
                                static const char hex_chars[] = "0123456789abcdef";
                                if (hex_idx + 2 < (int)sizeof(hex_buf)) {
                                    hex_buf[hex_idx++] = hex_chars[(val >> 4) & 0x0f];
                                    hex_buf[hex_idx++] = hex_chars[val & 0x0f];
                                }
                            }
                            if (parser_current(p).type == TOK_COMMA) {
                                parser_advance(p);
                            } else {
                                break;
                            }
                        }
                        hex_buf[hex_idx] = '\0';

                        if (parser_current(p).type == TOK_CLOSE_BRACE) {
                            parser_advance(p); /* consume } */
                        }

                        /* Create NSData: marker from hex */
                        {
                            unsigned int needed = 7 + (unsigned int)hex_idx + 1;
                            ObjId h = obj_alloc(needed);
                            if (h != OBJ_NULL) {
                                char *buf = obj_deref_mut(h);
                                cstr_copy(buf, "NSData:", needed);
                                cstr_copy(buf + 7, hex_buf, (unsigned int)hex_idx + 1);
                            }
                            if (var && !g_ctx.suppress_side_effects) {
                                var->is_id = 1;
                                var->value = h;
                                var->is_int = 0;
                                var->is_float = 0;
                                var->is_class = 0;
                                var->is_sel = 0;
                            }
                        }
                    }
                    goto after_initializer;
                }

                /* No brace initializer — default to empty NSData */
                if (var && !g_ctx.suppress_side_effects) {
                    ObjId h = obj_alloc(8);
                    if (h != OBJ_NULL) {
                        char *buf = obj_deref_mut(h);
                        cstr_copy(buf, "NSData:", 8);
                    }
                    var->is_id = 1;
                    var->value = h;
                    var->is_int = 0;
                    var->is_float = 0;
                    var->is_class = 0;
                    var->is_sel = 0;
                }
                goto after_initializer;
            }
        }

        /* For static variables, check if one already exists (persistent across cells) */
        if (is_static_var) {
            var = interp_find_var(var_name_buf);
            if (var && var->is_static) {
                /* Static variable already exists - skip reinitialization */
                var->is_block_captured = is_block_var; /* update block capture flag */
                /* Skip initializer if present */
                if (parser_current(p).type == TOK_ASSIGN) {
                    parser_advance(p);
                    /* Parse but discard the value */
                    parse_expression(p);
                    if (p->error) return value_void();
                }
                return value_void();
            }
        }

        var = interp_get_or_create_var(var_name_buf);
        if (var == 0) {
            parser_error(p, "variable table full (max 1024)");
            return value_void();
        }
        /* Clear all type flags before re-setting — prevents stale flags
         * when a variable is redeclared (e.g., 'int i = 1' after 'int i = 0'
         * in a prior cell, where the old variable had is_int=1 but also
         * potentially stale is_id/is_float from state pollution). */
        if (!g_ctx.suppress_side_effects) {
            var->is_int = 0;
            var->is_float = 0;
            var->is_class = 0;
            var->is_sel = 0;
            var->is_id = 0;
            var->is_struct = 0;
            var->is_block_captured = is_block_var;
            var->is_static = is_static_var; /* mark as static if needed */
        }

        /* Parse initializer */
        if (parser_current(p).type == TOK_ASSIGN) {
            parser_advance(p);

            /* Struct brace initializer: NSRange r = {5, 3}; */
            {
                StructDef *sd = struct_def_find(type_name);
                if (sd && parser_current(p).type == TOK_OPEN_BRACE) {
                    unsigned int inst_id = g_ctx.struct_instance_count;
                    if (inst_id >= MAX_STRUCT_INSTANCES) {
                        parser_error(p, "struct instance table full");
                        return value_void();
                    }
                    {
                        StructInstance *si = &g_ctx.struct_instances[inst_id];
                        cstr_copy(si->type_name, type_name, 64);
                        si->field_count = sd->field_count;
                        si->active = 1;
                        {
                            unsigned int fi;
                            for (fi = 0; fi < sd->field_count && fi < MAX_STRUCT_FIELDS; fi++) {
                                si->int_fields[fi] = 0;
                                si->float_fields[fi] = 0.0;
                                si->id_fields[fi] = 0;
                            }
                        }
                        g_ctx.struct_instance_count++;
                    }

                    /* Parse { field1, field2, ... } */
                    parser_advance(p); /* consume { */
                    {
                        unsigned int fi;
                        for (fi = 0; fi < sd->field_count && fi < MAX_STRUCT_FIELDS; fi++) {
                            if (fi > 0 && parser_current(p).type == TOK_COMMA) {
                                parser_advance(p);
                            }
                            if (parser_current(p).type == TOK_CLOSE_BRACE) break;
                            {
                                Value fv = parse_expression(p);
                                if (p->error) return fv;
                                StructInstance *si = &g_ctx.struct_instances[inst_id];
                                if (sd->field_types[fi] == 0) {
                                    si->int_fields[fi] = fv.is_int ? fv.int_val : (fv.is_float ? (int)fv.float_val : 0);
                                } else if (sd->field_types[fi] == 1) {
                                    si->float_fields[fi] = fv.is_float ? fv.float_val : (fv.is_int ? (double)fv.int_val : 0.0);
                                } else {
                                    si->id_fields[fi] = fv.obj_val;
                                }
                            }
                        }
                    }
                    if (parser_current(p).type == TOK_CLOSE_BRACE) {
                        parser_advance(p);
                    }

                    if (var && !g_ctx.suppress_side_effects) {
                        var->is_struct = 1;
                        var->struct_instance_id = inst_id;
                    }
                    /* Don't return — fall through to handle comma-separated decls */
                    goto after_initializer;
                }
            }

            init_val = parse_expression(p);
            if (p->error) return init_val;

            if (var && !g_ctx.suppress_side_effects) {
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
            /* Don't return here — fall through to handle comma-separated
             * declarations like int a = 0, b = 1, c = 2; */
        } else {
            /* Default initialization (no initializer provided) */
        if (var && !g_ctx.suppress_side_effects) {
            if (cstr_eq(type_name, "int") || cstr_eq(type_name, "NSInteger") || cstr_eq(type_name, "NSUInteger")) {
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
        } /* end else (no initializer) */

after_initializer:

        /* Handle comma-separated declarations: int a = 0, b = 0, c = 0; */
        while (parser_current(p).type == TOK_COMMA) {
            parser_advance(p); /* consume , */

            /* Skip pointer stars */
            while (parser_current(p).type == TOK_STAR) {
                parser_advance(p);
            }

            /* Next variable name */
            if (parser_current(p).type == TOK_IDENTIFIER) {
                char var_name2[64];
                if (copy_identifier_or_error(p, var_name2, parser_current(p).text, 64, "variable")) {
                    return value_void();
                }
                parser_advance(p);

                var = interp_get_or_create_var(var_name2);
                if (var == 0) {
                    parser_error(p, "variable table full (max 1024)");
                    return value_void();
                }
                var->is_int = 0;
                var->is_float = 0;
                var->is_class = 0;
                var->is_sel = 0;
                var->is_id = 0;
                var->is_block_captured = is_block_var;
                var->is_static = is_static_var;

                /* Parse optional initializer */
                if (parser_current(p).type == TOK_ASSIGN) {
                    Value init_val2;
                    parser_advance(p);
                    init_val2 = parse_expression(p);
                    if (p->error) return init_val2;

                    var->value = init_val2.obj_val;
                    var->cls = init_val2.cls_val;
                    var->sel = init_val2.sel_val;
                    var->is_int = init_val2.is_int;
                    var->int_value = init_val2.int_val;
                    var->is_float = init_val2.is_float;
                    var->float_value = init_val2.float_val;
                    var->is_class = init_val2.is_class;
                    var->is_sel = init_val2.is_sel;
                    var->is_id = init_val2.is_id;
                } else {
                    /* Set default value based on type */
                    if (cstr_eq(type_name, "int") || cstr_eq(type_name, "NSInteger") || cstr_eq(type_name, "NSUInteger")) {
                        var->is_int = 1;
                        var->int_value = 0;
                    } else if (cstr_eq(type_name, "float") || cstr_eq(type_name, "double")) {
                        var->is_float = 1;
                        var->float_value = 0.0;
                    } else if (cstr_eq(type_name, "Class")) {
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
            }
        }

        return value_void();
    }

    return value_void();
}

Value parse_statement(Parser *p) {
    Token tok = parser_current(p);

    /* return statement: return [expr]; */
    if (tok.type == TOK_RETURN) {
        parser_advance(p);

        /* Parse optional return value */
        if (parser_current(p).type != TOK_SEMICOLON &&
            parser_current(p).type != TOK_CLOSE_BRACE &&
            parser_current(p).type != TOK_EOF) {
            g_ctx.return_value = parse_expression(p);
            if (p->error) return g_ctx.return_value;
        } else {
            g_ctx.return_value = value_void();
        }

        if (parser_current(p).type == TOK_SEMICOLON) {
            parser_advance(p);
        }

        g_ctx.return_pending = 1;
        return g_ctx.return_value;
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
        return parse_protocol(p);
    }

    /* @try ... @catch ... @finally ... (no-op semantics for now) */
    if (tok.type == TOK_AT_KEYWORD && cstr_eq(tok.text, "@try")) {
        parser_advance(p);
        /* Parse the try body { ... } */
        if (parser_current(p).type == TOK_OPEN_BRACE) {
            int brace_depth = 1;
            parser_advance(p);
            while (brace_depth > 0 && parser_current(p).type != TOK_EOF) {
                if (parser_current(p).type == TOK_OPEN_BRACE) brace_depth++;
                else if (parser_current(p).type == TOK_CLOSE_BRACE) brace_depth--;
                if (brace_depth > 0) parser_advance(p);
            }
            if (parser_current(p).type == TOK_CLOSE_BRACE) parser_advance(p);
        }
        /* Parse @catch blocks */
        while (parser_current(p).type == TOK_AT_KEYWORD &&
               cstr_eq(parser_current(p).text, "@catch")) {
            parser_advance(p);
            /* Skip (Exception *e) or similar */
            if (parser_current(p).type == TOK_OPEN_PAREN) {
                int paren_depth = 1;
                parser_advance(p);
                while (paren_depth > 0 && parser_current(p).type != TOK_EOF) {
                    if (parser_current(p).type == TOK_OPEN_PAREN) paren_depth++;
                    else if (parser_current(p).type == TOK_CLOSE_PAREN) paren_depth--;
                    if (paren_depth > 0) parser_advance(p);
                }
                if (parser_current(p).type == TOK_CLOSE_PAREN) parser_advance(p);
            }
            /* Parse the catch body { ... } */
            if (parser_current(p).type == TOK_OPEN_BRACE) {
                int brace_depth = 1;
                parser_advance(p);
                while (brace_depth > 0 && parser_current(p).type != TOK_EOF) {
                    if (parser_current(p).type == TOK_OPEN_BRACE) brace_depth++;
                    else if (parser_current(p).type == TOK_CLOSE_BRACE) brace_depth--;
                    if (brace_depth > 0) parser_advance(p);
                }
                if (parser_current(p).type == TOK_CLOSE_BRACE) parser_advance(p);
            }
        }
        /* Parse optional @finally block */
        if (parser_current(p).type == TOK_AT_KEYWORD &&
            cstr_eq(parser_current(p).text, "@finally")) {
            parser_advance(p);
            /* Parse the finally body { ... } */
            if (parser_current(p).type == TOK_OPEN_BRACE) {
                int brace_depth = 1;
                parser_advance(p);
                while (brace_depth > 0 && parser_current(p).type != TOK_EOF) {
                    if (parser_current(p).type == TOK_OPEN_BRACE) brace_depth++;
                    else if (parser_current(p).type == TOK_CLOSE_BRACE) brace_depth--;
                    if (brace_depth > 0) parser_advance(p);
                }
                if (parser_current(p).type == TOK_CLOSE_BRACE) parser_advance(p);
            }
        }
        return value_void();
    }
    /* @synchronized — intentionally unsupported in the WASM kernel (ADR 0010).
     * Produces a clean diagnostic and skips the mutex expression + body. */
    if (tok.type == TOK_AT_KEYWORD && cstr_eq(tok.text, "@synchronized")) {
        parser_error(p, "the @synchronized directive is not supported in the WASM kernel");
        /* Skip past the mutex expression and body so subsequent code parses. */
        parser_advance(p);
        if (parser_current(p).type == TOK_OPEN_PAREN) {
            int paren_depth = 1;
            parser_advance(p);
            while (paren_depth > 0 && parser_current(p).type != TOK_EOF) {
                if (parser_current(p).type == TOK_OPEN_PAREN) paren_depth++;
                else if (parser_current(p).type == TOK_CLOSE_PAREN) paren_depth--;
                if (paren_depth > 0) parser_advance(p);
            }
            if (parser_current(p).type == TOK_CLOSE_PAREN) parser_advance(p);
        }
        if (parser_current(p).type == TOK_OPEN_BRACE) {
            int brace_depth = 1;
            parser_advance(p);
            while (brace_depth > 0 && parser_current(p).type != TOK_EOF) {
                if (parser_current(p).type == TOK_OPEN_BRACE) brace_depth++;
                else if (parser_current(p).type == TOK_CLOSE_BRACE) brace_depth--;
                if (brace_depth > 0) parser_advance(p);
            }
            if (parser_current(p).type == TOK_CLOSE_BRACE) parser_advance(p);
        }
        return value_void();
    }
    /* C function definition — reuses BlockImpl for the tutorial-shape subset.
     * Stores the function body as a block-backed InterpVar so that calls
     * like func_name(args) resolve through the existing block-invocation path. */
    if (tok.type == TOK_IDENTIFIER) {
        Token saved = p->lex.current;
        unsigned int saved_pos = p->lex.pos;
        int is_func = 0;
        char func_name[64];
        func_name[0] = '\0';

        /* Consume return type tokens; the last identifier before '(' is the
         * function name. Track it as we go. */
        while (parser_current(p).type == TOK_IDENTIFIER || parser_current(p).type == TOK_STAR) {
            if (parser_current(p).type == TOK_IDENTIFIER) {
                cstr_copy(func_name, parser_current(p).text, 64);
            }
            parser_advance(p);
        }

        if (parser_current(p).type == TOK_OPEN_PAREN) {
            /* Parse parameter list: skip types, record param names */
            char param_names[8][64];
            unsigned int param_count = 0;
            int paren_depth = 0;
            parser_advance(p); /* consume ( */
            paren_depth++;

            while (paren_depth > 0 && parser_current(p).type != TOK_EOF && param_count < 8) {
                /* Skip type tokens for this parameter (int, char, *, etc.),
                 * but use look-ahead to avoid consuming the parameter name
                 * itself. The last identifier before ',' or ')' is the
                 * parameter name, not a type token. */
                while (parser_current(p).type == TOK_IDENTIFIER ||
                       parser_current(p).type == TOK_STAR) {
                    if (parser_current(p).type == TOK_IDENTIFIER) {
                        Token saved = p->lex.current;
                        unsigned int saved_pos = p->lex.pos;
                        parser_advance(p);
                        if (parser_current(p).type == TOK_COMMA ||
                            parser_current(p).type == TOK_CLOSE_PAREN) {
                            /* Identifier was the parameter name — rewind so
                             * the name-recording block below captures it. */
                            p->lex.current = saved;
                            p->lex.pos = saved_pos;
                            break;
                        }
                        /* This was a type token (e.g., "int", "const").
                         * Keep going to consume stars and further tokens. */
                    } else {
                        parser_advance(p); /* consume * */
                    }
                }
                /* Record parameter name if present */
                if (parser_current(p).type == TOK_IDENTIFIER) {
                    cstr_copy(param_names[param_count], parser_current(p).text, 64);
                    param_count++;
                    parser_advance(p);
                }
                /* Skip commas between params, close-paren ends the list */
                if (parser_current(p).type == TOK_COMMA) {
                    parser_advance(p);
                } else if (parser_current(p).type == TOK_CLOSE_PAREN) {
                    parser_advance(p);
                    paren_depth--;
                } else {
                    /* Unrecognized token inside parameter list — skip it
                     * (e.g., @ in NSLog argument position, string literals).
                     * This prevents infinite loops on unexpected content. */
                    parser_advance(p);
                }
            }

            /* Drain remaining close-parens if we hit the param limit */
            while (paren_depth > 0 && parser_current(p).type != TOK_EOF) {
                if (parser_current(p).type == TOK_CLOSE_PAREN) paren_depth--;
                if (paren_depth > 0) parser_advance(p);
            }
            if (parser_current(p).type == TOK_CLOSE_PAREN) parser_advance(p);

            if (parser_current(p).type == TOK_OPEN_BRACE) {
                is_func = 1;

                /* Register the function as a block-backed variable */
                if (func_name[0] != '\0' && g_ctx.block_count < MAX_BLOCKS) {
                    BlockImpl *blk = &g_ctx.blocks[g_ctx.block_count];
                    unsigned int body_start;
                    unsigned int ai;

                    blk->block_id = g_ctx.next_block_id++;
                    blk->arg_count = param_count;
                    blk->capture_count = 0;
                    for (ai = 0; ai < param_count && ai < 8; ai++) {
                        cstr_copy(blk->arg_names[ai], param_names[ai], 64);
                    }

                    /* Capture body source (without outer braces).
                     * Capture body_start before consuming '{' so the
                     * pointer is right after the opening brace, not
                     * after whatever token follows it. */
                    body_start = p->lex.token_start + 1; /* right after { */
                    parser_advance(p); /* consume { */

                    /* Count braces to find the end of the body */
                    {
                        int brace_depth = 1;
                        while (brace_depth > 0 && parser_current(p).type != TOK_EOF) {
                            if (parser_current(p).type == TOK_OPEN_BRACE) brace_depth++;
                            else if (parser_current(p).type == TOK_CLOSE_BRACE) brace_depth--;
                            if (brace_depth > 0) parser_advance(p);
                        }
                        /* parser_advance consumed the closing } */
                    }
                    /* body_end is pos-1 (position of the closing '}').
                     * pos is now at the closing '}' (the loop stops without
                     * advancing past it). Advance past '}' so the caller
                     * doesn't see a stray brace. */
                    {
                        unsigned int body_end = p->lex.pos - 1;
                        if (body_start < body_end) {
                            unsigned int body_len = body_end - body_start;
                            if (body_len < 2048) {
                                unsigned int ci;
                                for (ci = 0; ci < body_len; ci++) {
                                    blk->source[ci] = p->lex.source[body_start + ci];
                                }
                                blk->source[body_len] = '\0';
                                blk->source_len = body_len;
                            }
                        }
                    }
                    parser_advance(p); /* consume } */
                    g_ctx.block_count++;

                    /* Create the variable pointing to the block */
                    {
                        ObjId marker = block_make_marker(blk->block_id);
                        InterpVar *var = interp_get_or_create_var(func_name);
                        if (var && !g_ctx.suppress_side_effects) {
                            var->is_id = 1;
                            var->value = marker;
                            var->is_int = 0;
                            var->is_float = 0;
                            var->is_class = 0;
                            var->is_sel = 0;
                        }
                    }
                    return value_void();
                }
            }
        }

        if (is_func) {
            /* Function registration failed (table full). Skip the body
             * gracefully so surrounding code still runs. */
            int brace_depth = 0;
            do {
                if (parser_current(p).type == TOK_OPEN_BRACE) brace_depth++;
                else if (parser_current(p).type == TOK_CLOSE_BRACE) brace_depth--;
                parser_advance(p);
            } while (brace_depth > 0 && parser_current(p).type != TOK_EOF);
            return value_void();
        } else {
            /* Not a function definition, restore lexer state */
            p->lex.current = saved;
            p->lex.pos = saved_pos;
        }
    }

    /* typedef statement: typedef <type> <name>; or typedef NS_ENUM(...) */
    if (tok.type == TOK_IDENTIFIER && cstr_eq(tok.text, "typedef")) {
        parser_advance(p); /* consume 'typedef' */

        /* Handle NS_ENUM macro: typedef NS_ENUM(NSInteger, Direction) { ... } */
        if (parser_current(p).type == TOK_IDENTIFIER &&
            cstr_eq(parser_current(p).text, "NS_ENUM")) {
            parser_advance(p); /* consume NS_ENUM */
            if (parser_current(p).type == TOK_OPEN_PAREN) {
                parser_advance(p); /* consume ( */
                /* Read the base type (e.g., NSInteger) */
                char base_type[64];
                base_type[0] = '\0';
                if (parser_current(p).type == TOK_IDENTIFIER) {
                    cstr_copy(base_type, parser_current(p).text, 64);
                    parser_advance(p);
                }
                /* Comma */
                if (parser_current(p).type == TOK_COMMA) {
                    parser_advance(p);
                }
                /* Read the enum name */
                char enum_name[64];
                enum_name[0] = '\0';
                if (parser_current(p).type == TOK_IDENTIFIER) {
                    cstr_copy(enum_name, parser_current(p).text, 64);
                    parser_advance(p);
                }
                /* Close paren */
                if (parser_current(p).type == TOK_CLOSE_PAREN) {
                    parser_advance(p);
                }
                /* Record the typedef */
                if (enum_name[0] != '\0' && g_ctx.typedef_count < OBJC_INTERP_MAX_TYPEDEFS) {
                    cstr_copy(g_ctx.typedefs[g_ctx.typedef_count].alias, enum_name, 64);
                    cstr_copy(g_ctx.typedefs[g_ctx.typedef_count].base_type,
                              base_type[0] ? base_type : "int", 64);
                    g_ctx.typedef_count++;
                }
                /* Parse optional { A, B, C } enum body */
                if (parser_current(p).type == TOK_OPEN_BRACE) {
                    parser_advance(p); /* consume { */
                    while (parser_current(p).type != TOK_CLOSE_BRACE &&
                           parser_current(p).type != TOK_EOF) {
                        /* Read enum constant name */
                        if (parser_current(p).type == TOK_IDENTIFIER) {
                            char const_name[64];
                            cstr_copy(const_name, parser_current(p).text, 64);
                            parser_advance(p);
                            /* Optional = value */
                            if (parser_current(p).type == TOK_ASSIGN) {
                                parser_advance(p);
                                /* Parse the value expression (simple: just an integer) */
                                Value val = parse_expression(p);
                                /* Register as a variable */
                                InterpVar *var = interp_get_or_create_var(const_name);
                                if (var) {
                                    var->is_int = 1;
                                    var->int_value = val.is_int ? val.int_val : 0;
                                    var->is_id = 0;
                                    var->is_class = 0;
                                    var->is_sel = 0;
                                }
                            } else {
                                /* Auto-increment: register with value 0 */
                                InterpVar *var = interp_get_or_create_var(const_name);
                                if (var) {
                                    var->is_int = 1;
                                    var->int_value = 0;
                                    var->is_id = 0;
                                    var->is_class = 0;
                                    var->is_sel = 0;
                                }
                            }
                        }
                        if (parser_current(p).type == TOK_COMMA) {
                            parser_advance(p);
                        }
                    }
                    if (parser_current(p).type == TOK_CLOSE_BRACE) {
                        parser_advance(p);
                    }
                }
                if (parser_current(p).type == TOK_SEMICOLON) {
                    parser_advance(p);
                }
                return value_void();
            }
        }

        /* Regular typedef: typedef <type> <name>; */
        {
            char base_type[64];
            char alias_name[64];
            base_type[0] = '\0';
            alias_name[0] = '\0';

            /* Read the base type (possibly multi-token) */
            if (parser_current(p).type == TOK_IDENTIFIER) {
                cstr_copy(base_type, parser_current(p).text, 64);
                parser_advance(p);

                /* Multi-token type: unsigned int, long long, etc. */
                if (cstr_eq(base_type, "unsigned") || cstr_eq(base_type, "signed")) {
                    if (parser_current(p).type == TOK_IDENTIFIER &&
                        (cstr_eq(parser_current(p).text, "int") ||
                         cstr_eq(parser_current(p).text, "char") ||
                         cstr_eq(parser_current(p).text, "long") ||
                         cstr_eq(parser_current(p).text, "short"))) {
                        parser_advance(p);
                    }
                    cstr_copy(base_type, "int", 64);
                }
                if (cstr_eq(base_type, "long")) {
                    if (parser_current(p).type == TOK_IDENTIFIER &&
                        (cstr_eq(parser_current(p).text, "long") ||
                         cstr_eq(parser_current(p).text, "int"))) {
                        parser_advance(p);
                    }
                    cstr_copy(base_type, "int", 64);
                }
            }

            /* Skip pointer * */
            while (parser_current(p).type == TOK_STAR) {
                parser_advance(p);
                cstr_copy(base_type, "id", 64);
            }

            /* Read the alias name */
            if (parser_current(p).type == TOK_IDENTIFIER) {
                cstr_copy(alias_name, parser_current(p).text, 64);
                parser_advance(p);
            }

            /* Record the typedef */
            if (alias_name[0] != '\0' && g_ctx.typedef_count < OBJC_INTERP_MAX_TYPEDEFS) {
                cstr_copy(g_ctx.typedefs[g_ctx.typedef_count].alias, alias_name, 64);
                cstr_copy(g_ctx.typedefs[g_ctx.typedef_count].base_type,
                          base_type[0] ? base_type : "int", 64);
                g_ctx.typedef_count++;
            }

            if (parser_current(p).type == TOK_SEMICOLON) {
                parser_advance(p);
            }
            return value_void();
        }
    }

    /* Type declaration: int, void, id, Class, SEL, or registered class name */
    /* Also __block qualifier before type */
    if (tok.type == TOK_IDENTIFIER) {
        /* Check for __block qualifier */
        int is_block_qualifier = cstr_eq(tok.text, "__block");
        /* Storage qualifiers — route to parse_type_and_var_decl
         * for proper handling (static/extern). */
        int is_storage_qualifier = (
            cstr_eq(tok.text, "static") ||
            cstr_eq(tok.text, "extern")
        );
        /* Type qualifiers: const, volatile, restrict — always followed by
         * a type name, so route to parse_type_and_var_decl like storage
         * qualifiers. */
        int is_type_qualifier = (
            cstr_eq(tok.text, "const") ||
            cstr_eq(tok.text, "volatile") ||
            cstr_eq(tok.text, "restrict")
        );
        /* Type modifiers: unsigned, signed, short — always followed by
         * a type name (or standalone as int). Route to parse_type_and_var_decl
         * which now handles multi-token type parsing. */
        int is_type_modifier = (
            cstr_eq(tok.text, "unsigned") ||
            cstr_eq(tok.text, "signed") ||
            cstr_eq(tok.text, "short")
        );
        /* Check if this is a type name followed by a variable name.
         * Built-in types are always recognized. Registered class names
         * (from @implementation) are also recognized as types when
         * followed by * (pointer) or another identifier.
         * Also check if this is a typedef alias. */
        /* Note: unsigned, short omitted — they're type modifiers that need
         * multi-token type parsing. Will be addressed in a separate fix. */
        int is_builtin_type = (
            cstr_eq(tok.text, "int") || cstr_eq(tok.text, "NSInteger") ||
            cstr_eq(tok.text, "NSUInteger") || cstr_eq(tok.text, "void") ||
            cstr_eq(tok.text, "id") || cstr_eq(tok.text, "Class") ||
            cstr_eq(tok.text, "SEL") || cstr_eq(tok.text, "BOOL") ||
            cstr_eq(tok.text, "long") || cstr_eq(tok.text, "char") ||
            cstr_eq(tok.text, "float") || cstr_eq(tok.text, "double") ||
            /* Foundation framework types */
            cstr_eq(tok.text, "NSString") || cstr_eq(tok.text, "NSArray") ||
            cstr_eq(tok.text, "NSMutableArray") || cstr_eq(tok.text, "NSDictionary") ||
            cstr_eq(tok.text, "NSMutableDictionary") || cstr_eq(tok.text, "NSNumber") ||
            cstr_eq(tok.text, "NSData") || cstr_eq(tok.text, "NSSet") ||
            cstr_eq(tok.text, "NSCharacterSet") ||
            /* C99 integer types */
            cstr_eq(tok.text, "uint8_t") || cstr_eq(tok.text, "uint16_t") ||
            cstr_eq(tok.text, "uint32_t") || cstr_eq(tok.text, "uint64_t") ||
            cstr_eq(tok.text, "int8_t") || cstr_eq(tok.text, "int16_t") ||
            cstr_eq(tok.text, "int32_t") || cstr_eq(tok.text, "int64_t") ||
            cstr_eq(tok.text, "size_t")
        );
        /* Check if it's a typedef alias */
        const char *resolved_type = typedef_resolve(tok.text);
        int is_typedef = (resolved_type != tok.text);
        int is_class_type = (!is_builtin_type && !is_typedef && objc_lookUpClass(tok.text) != 0);
        /* Check if it's a known struct type (NSRange, CGPoint, etc.) */
        int is_struct_type = (struct_def_find(tok.text) != 0);
        /* Also check variable table for Foundation class names (which are
         * registered as variables with is_class=1, not in the runtime). */
        if (!is_class_type && !is_builtin_type && !is_struct_type) {
            unsigned int vi;
            for (vi = 0; vi < g_ctx.var_count; vi++) {
                if (cstr_eq(g_ctx.vars[vi].name, tok.text) && g_ctx.vars[vi].is_class) {
                    is_class_type = 1;
                    break;
                }
            }
        }

        if (is_builtin_type || is_class_type || is_typedef || is_struct_type || is_block_qualifier || is_storage_qualifier || is_type_qualifier || is_type_modifier) {
            if (is_block_qualifier || is_storage_qualifier || is_type_qualifier || is_type_modifier) {
                /* __block and storage qualifiers (static, extern)
                 * are always followed by a type — call directly */
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
                    interp_set_var_from_value(var, val);
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

Value parse_block(Parser *p) {
    Value last = value_void();
    while (parser_current(p).type != TOK_EOF &&
           parser_current(p).type != TOK_CLOSE_BRACE) {
        if (interp_should_interrupt()) {
            parser_error(p, "Execution interrupted");
            return last;
        }
        last = parse_statement(p);
        if (p->error) return last;
        if (g_ctx.return_pending) return last;
    }
    return last;
}
