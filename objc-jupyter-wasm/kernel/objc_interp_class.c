/*
 * objc_interp_class.c
 * Class declaration / implementation parsing extracted from the main interpreter.
 */

#include "objc_interp_types.h"
#include "objc_interp_globals.h"
#include "objc_interp_class.h"
#include "objc_interp_state.h"
#include "objc_interp_format.h"
#include "objc_interp_lexer.h"

/* Runtime bridge helpers. */
extern void interp_emit_stream(const char *data, unsigned int len);
extern const char *sel_getName(SEL);
extern id objc_lookUpClass(const char *name);
extern Class object_getClass(id);

/* Parser / interpreter helpers retained in objc_interpreter.c. */
extern Token parser_current(struct Parser *p);
extern void parser_advance(struct Parser *p);
extern int parser_expect(struct Parser *p, TokenType type);
extern void parser_error(struct Parser *p, const char *msg);
extern int copy_identifier_or_error(struct Parser *p, char *dst, const char *src, unsigned int capacity, const char *kind);
extern Value parse_expression(struct Parser *p);
extern Value parse_expression_safe(struct Parser *p);
extern Value parse_type_and_var_decl(struct Parser *p);
extern Value parse_statement(struct Parser *p);
extern Value parse_block(struct Parser *p);
extern Value eval_source_range(unsigned int start, unsigned int len, const char *source,
                               unsigned int line_offset);

extern InterpVar *interp_find_var(const char *name);
extern InterpVar *interp_get_or_create_var(const char *name);

/* Parser layout must match the definition in objc_interpreter.c. */

/* Parse @interface Name : SuperClass { ivars } methodDecls @end */
Value parse_interface(struct Parser *p) {
    char class_name[64];
    char super_name[64];
    Class super_class;
    Class new_class;

    if (parser_current(p).type != TOK_IDENTIFIER) {
        parser_error(p, "Expected class name after @interface");
        return value_void();
    }
    if (copy_identifier_or_error(p, class_name, parser_current(p).text, 64, "class")) {
        return value_void();
    }
    parser_advance(p);

    {
        InterpVar *existing = interp_find_var(class_name);
        if (existing && existing->is_class) {
            while (parser_current(p).type != TOK_AT_KEYWORD ||
                   !cstr_eq(parser_current(p).text, "@end")) {
                if (parser_current(p).type == TOK_EOF) break;
                parser_advance(p);
            }
            if (parser_current(p).type == TOK_AT_KEYWORD &&
                cstr_eq(parser_current(p).text, "@end")) {
                parser_advance(p);
            }
            return value_from_class(existing->cls);
        }
    }

    super_name[0] = '\0';
    super_class = 0;
    if (parser_current(p).type == TOK_COLON) {
        parser_advance(p);
        if (parser_current(p).type == TOK_IDENTIFIER) {
            if (copy_identifier_or_error(p, super_name, parser_current(p).text, 64, "superclass")) {
                return value_void();
            }
            parser_advance(p);
            {
                InterpVar *var = interp_find_var(super_name);
                if (var && var->is_class) {
                    super_class = var->cls;
                } else {
                    super_class = 0;
                }
            }
        }
    }

    {
        static unsigned int custom_class_id = 100;
        if (custom_class_id >= 100 + OBJC_INTERP_MAX_CLASSES) {
            parser_error(p, "class table full (max 128 classes)");
            return value_void();
        }
        new_class = (Class)(unsigned long)custom_class_id++;
    }

    if (parser_current(p).type == TOK_OPEN_BRACE) {
        parser_advance(p);
        while (parser_current(p).type != TOK_CLOSE_BRACE &&
               parser_current(p).type != TOK_EOF) {
            parser_advance(p);
        }
        if (parser_current(p).type == TOK_CLOSE_BRACE) {
            parser_advance(p);
        }
    }

    while (parser_current(p).type != TOK_AT_KEYWORD ||
           !cstr_eq(parser_current(p).text, "@end")) {
        if (parser_current(p).type == TOK_EOF) break;

        if (parser_current(p).type == TOK_AT_KEYWORD &&
            cstr_eq(parser_current(p).text, "@property")) {
            parser_advance(p);

            if (parser_current(p).type == TOK_OPEN_PAREN) {
                int depth = 1;
                parser_advance(p);
                while (depth > 0 && parser_current(p).type != TOK_EOF) {
                    if (parser_current(p).type == TOK_OPEN_PAREN) depth++;
                    else if (parser_current(p).type == TOK_CLOSE_PAREN) depth--;
                    parser_advance(p);
                }
            }

            if (parser_current(p).type == TOK_IDENTIFIER) {
                if (g_property_count >= 64) {
                    parser_error(p, "property table full (max 64 properties)");
                    while (parser_current(p).type != TOK_SEMICOLON && parser_current(p).type != TOK_CLOSE_PAREN && parser_current(p).type != TOK_EOF) {
                        parser_advance(p);
                    }
                    continue;
                }
                PropertyDecl *prop = &g_properties[g_property_count];
                if (copy_identifier_or_error(p, prop->type_name, parser_current(p).text, 64, "property type")) {
                    return value_void();
                }
                prop->is_int = cstr_eq(prop->type_name, "int") ||
                               cstr_eq(prop->type_name, "NSInteger") ||
                               cstr_eq(prop->type_name, "NSUInteger") ||
                               cstr_eq(prop->type_name, "BOOL") ||
                               cstr_eq(prop->type_name, "long") ||
                               cstr_eq(prop->type_name, "char");
                cstr_copy(prop->class_name, class_name, 64);
                parser_advance(p);

                while (parser_current(p).type == TOK_STAR) {
                    parser_advance(p);
                }

                if (parser_current(p).type == TOK_IDENTIFIER) {
                    if (copy_identifier_or_error(p, prop->name, parser_current(p).text, 64, "property")) {
                        return value_void();
                    }
                    parser_advance(p);
                    g_property_count++;
                }
            }

            if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
            continue;
        }

        if (parser_current(p).type == TOK_MINUS || parser_current(p).type == TOK_PLUS) {
            parser_advance(p);

            if (parser_current(p).type == TOK_OPEN_PAREN) {
                int depth = 1;
                parser_advance(p);
                while (depth > 0 && parser_current(p).type != TOK_EOF) {
                    if (parser_current(p).type == TOK_OPEN_PAREN) depth++;
                    else if (parser_current(p).type == TOK_CLOSE_PAREN) depth--;
                    parser_advance(p);
                }
            }

            if (parser_current(p).type == TOK_IDENTIFIER) {
                parser_advance(p);
            }

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

    if (parser_current(p).type == TOK_AT_KEYWORD && cstr_eq(parser_current(p).text, "@end")) {
        parser_advance(p);
    }

    {
        InterpVar *var = interp_get_or_create_var(class_name);
        if (var) {
            var->is_class = 1;
            var->cls = new_class;
        }
    }

    return value_from_class(new_class);
}

/* Method implementation function retained for runtime compatibility. */
static id method_impl_trampoline(id self, SEL _cmd, ...) {
    const char *sel_name = sel_getName(_cmd);
    unsigned int i;

    for (i = 0; i < g_method_count; i++) {
        if (g_methods[i].selector == _cmd && g_methods[i].source_len > 0) {
            break;
        }
    }

    if (i >= g_method_count || g_methods[i].source_len == 0) {
        return self;
    }

    unsigned int saved_var_count = g_var_count;

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

    {
        unsigned int sel_colons = 0;
        unsigned int si;
        for (si = 0; sel_name[si] != '\0'; si++) {
            if (sel_name[si] == ':') sel_colons++;
        }

        if (sel_colons > 0 && g_methods[i].arg_count > 0) {
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

    g_ctx.return_pending = 0;
    {
        Value v = eval_source_range(0, g_methods[i].source_len, g_methods[i].source, 0);
        (void)v;
    }

    {
        id return_val;

        if (g_ctx.return_pending) {
            if (g_ctx.return_value.is_id) return_val = g_ctx.return_value.obj_val;
            else if (g_ctx.return_value.is_class) return_val = (id)g_ctx.return_value.cls_val;
            else if (g_ctx.return_value.is_int) return_val = (id)(long)g_ctx.return_value.int_val;
            else return_val = self;
        } else {
            return_val = self;
        }

        g_var_count = saved_var_count;
        g_ctx.return_pending = 0;

        return return_val;
    }
}

/* Parse @implementation Name methodDefs @end */
Value parse_implementation(struct Parser *p) {
    char class_name[64];
    Class cls;

    if (parser_current(p).type != TOK_IDENTIFIER) {
        parser_error(p, "Expected class name after @implementation");
        return value_void();
    }
    if (copy_identifier_or_error(p, class_name, parser_current(p).text, 64, "class")) {
        return value_void();
    }
    parser_advance(p);

    cls = (Class)objc_getClass(class_name);
    if (cls == 0) {
        InterpVar *var = interp_find_var(class_name);
        if (var && var->is_class) {
            cls = var->cls;
        }
    }
    if (cls == 0) {
        parser_error(p, "Class not found for @implementation");
        return value_void();
    }

    {
        int class_has_methods = 0;
        unsigned int mi;
        for (mi = 0; mi < g_method_count; mi++) {
            if (g_methods[mi].class_ptr == cls) {
                class_has_methods = 1;
                break;
            }
        }
        if (class_has_methods) {
            while (parser_current(p).type != TOK_AT_KEYWORD ||
                   !cstr_eq(parser_current(p).text, "@end")) {
                if (parser_current(p).type == TOK_EOF) break;
                parser_advance(p);
            }
            if (parser_current(p).type == TOK_AT_KEYWORD &&
                cstr_eq(parser_current(p).text, "@end")) {
                parser_advance(p);
            }
            return value_from_class(cls);
        }
    }

    while (parser_current(p).type != TOK_AT_KEYWORD ||
           !cstr_eq(parser_current(p).text, "@end")) {
        if (parser_current(p).type == TOK_EOF) break;

        if (parser_current(p).type == TOK_AT_KEYWORD &&
            cstr_eq(parser_current(p).text, "@synthesize")) {
            parser_advance(p);

            while (parser_current(p).type != TOK_SEMICOLON &&
                   parser_current(p).type != TOK_EOF) {
                if (parser_current(p).type == TOK_IDENTIFIER) {
                    char prop_name[64];
                    if (copy_identifier_or_error(p, prop_name, parser_current(p).text, 64, "property")) {
                        return value_void();
                    }
                    parser_advance(p);

                    if (parser_current(p).type == TOK_ASSIGN) {
                        parser_advance(p);
                        if (parser_current(p).type == TOK_IDENTIFIER) {
                            char ivar_name[64];
                            if (copy_identifier_or_error(p, ivar_name, parser_current(p).text, 64, "ivar")) {
                                return value_void();
                            }
                            parser_advance(p);
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

        if (parser_current(p).type == TOK_IDENTIFIER) {
            Token saved = p->lex.current;
            unsigned int saved_pos = p->lex.pos;
            Token next;

            {
                int is_builtin = (
                    cstr_eq(parser_current(p).text, "int") ||
                    cstr_eq(parser_current(p).text, "NSInteger") ||
                    cstr_eq(parser_current(p).text, "NSUInteger") ||
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
                    Value v = parse_type_and_var_decl(p);
                    if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
                    continue;
                }
            }
        }

        if (parser_current(p).type == TOK_MINUS || parser_current(p).type == TOK_PLUS) {
            int is_class_method = (parser_current(p).type == TOK_PLUS);
            char sel_name[256];
            unsigned int sel_len = 0;
            char type_encoding[64];
            char arg_names[8][64];
            unsigned int arg_count = 0;
            unsigned int body_start = 0;
            unsigned int body_len = 0;

            parser_advance(p);

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

            sel_name[0] = '\0';
            sel_len = 0;
            if (parser_current(p).type == TOK_IDENTIFIER) {
                cstr_copy(sel_name, parser_current(p).text, 256);
                sel_len = cstr_len(sel_name);
                parser_advance(p);
            }

            arg_count = 0;

            if (sel_len > 0 && sel_name[sel_len - 1] == ':') {
            } else if (parser_current(p).type == TOK_COLON) {
                parser_advance(p);
                sel_name[sel_len++] = ':';
                sel_name[sel_len] = '\0';
            }

            while (sel_len > 0 && sel_name[sel_len - 1] == ':') {
                if (parser_current(p).type == TOK_OPEN_PAREN) {
                    int depth = 1;
                    parser_advance(p);
                    while (depth > 0 && parser_current(p).type != TOK_EOF) {
                        if (parser_current(p).type == TOK_OPEN_PAREN) depth++;
                        else if (parser_current(p).type == TOK_CLOSE_PAREN) depth--;
                        parser_advance(p);
                    }
                }

                if (parser_current(p).type == TOK_IDENTIFIER && arg_count < 8) {
                    if (copy_identifier_or_error(p, arg_names[arg_count], parser_current(p).text, 64, "argument")) {
                        return value_void();
                    }
                    arg_count++;
                    parser_advance(p);
                }

                if (parser_current(p).type == TOK_IDENTIFIER) {
                    Token saved = p->lex.current;
                    unsigned int saved_pos = p->lex.pos;
                    unsigned int saved_token_start = p->lex.token_start;
                    parser_advance(p);

                    if (parser_current(p).type == TOK_COLON) {
                        cstr_copy(sel_name + sel_len, saved.text, 256 - sel_len);
                        sel_len += cstr_len(saved.text);
                        parser_advance(p);
                        sel_name[sel_len++] = ':';
                        sel_name[sel_len] = '\0';
                        continue;
                    }

                    p->lex.current = saved;
                    p->lex.pos = saved_pos;
                    p->lex.token_start = saved_token_start;
                }

                break;
            }

            if (parser_current(p).type == TOK_OPEN_BRACE) {
                int brace_depth = 1;
                unsigned int after_brace = p->lex.token_start + 1;
                parser_advance(p);
                body_start = after_brace;

                while (brace_depth > 0 && parser_current(p).type != TOK_EOF) {
                    if (parser_current(p).type == TOK_OPEN_BRACE) brace_depth++;
                    else if (parser_current(p).type == TOK_CLOSE_BRACE) {
                        brace_depth--;
                        if (brace_depth == 0) break;
                    }
                    parser_advance(p);
                }

                body_len = p->lex.token_start - body_start;

                if (parser_current(p).type == TOK_CLOSE_BRACE) {
                    parser_advance(p);
                }
            }

            {
                SEL sel = sel_registerName(sel_name);
                if (sel == 0) {
                    parser_error(p, "selector table full (max 4096 selectors)");
                    return value_void();
                }

                if (g_method_count < MAX_METHODS && body_len > 0) {
                    if (body_len >= 2048) {
                        parser_error(p, "method body too long (max 2047 bytes)");
                        return value_void();
                    }
                    MethodImpl *mi = &g_methods[g_method_count];
                    unsigned int copy_len = body_len;
                    cstr_copy(mi->source, p->lex.source + body_start, copy_len + 1);
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

    if (parser_current(p).type == TOK_AT_KEYWORD && cstr_eq(parser_current(p).text, "@end")) {
        parser_advance(p);
    }

    return value_from_class(cls);
}
