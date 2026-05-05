/*
 * objc_interp_class.c
 * Class declaration / implementation parsing extracted from the main interpreter.
 */

#include "objc_interp_types.h"
#include "objc_interp_context.h"
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

/* Class-to-protocol conformance table (simplified storage).
 * For each class, stores up to 8 protocol names it conforms to. */
static char class_conformances[OBJC_INTERP_MAX_CLASSES][8][64];
static unsigned int class_conforms_count[OBJC_INTERP_MAX_CLASSES];

/* Record that a class conforms to a protocol (by name). */
static void add_class_conformance(const char *class_name, const char *protocol_name) {
    unsigned int ci;
    /* Find class index by name */
    for (ci = 0; ci < OBJC_INTERP_MAX_CLASSES; ci++) {
        InterpVar *var = &g_ctx.vars[ci];
        if (var->is_class && cstr_eq(var->name, class_name)) {
            unsigned int cc = class_conforms_count[ci];
            if (cc < 8) {
                cstr_copy(class_conformances[ci][cc], protocol_name, 64);
                class_conforms_count[ci]++;
            }
            return;
        }
    }
}

/* Check if a class (by name) conforms to a protocol (by name). */
static int check_class_conformance(const char *class_name, const char *protocol_name) {
    unsigned int ci;
    for (ci = 0; ci < OBJC_INTERP_MAX_CLASSES; ci++) {
        InterpVar *var = &g_ctx.vars[ci];
        if (var->is_class && cstr_eq(var->name, class_name)) {
            unsigned int cc;
            for (cc = 0; cc < class_conforms_count[ci]; cc++) {
                if (cstr_eq(class_conformances[ci][cc], protocol_name)) return 1;
            }
            return 0;
        }
    }
    return 0;
}

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

    /* Parse <Protocol1, Protocol2, ...> conformance list */
    if (parser_current(p).type == TOK_LT) {
        parser_advance(p);
        while (parser_current(p).type != TOK_GT &&
               parser_current(p).type != TOK_EOF) {
            if (parser_current(p).type == TOK_IDENTIFIER) {
                /* Record that this class conforms to the named protocol */
                add_class_conformance(class_name, parser_current(p).text);
                parser_advance(p);
            } else {
                parser_advance(p);
            }
            if (parser_current(p).type == TOK_COMMA) {
                parser_advance(p);
            }
        }
        if (parser_current(p).type == TOK_GT) {
            parser_advance(p);
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

    /* Register the class-superclass relationship in the hierarchy table */
    if (g_ctx.class_hierarchy_count < MAX_CLASS_HIERARCHY) {
        cstr_copy(g_ctx.class_hierarchy_class[g_ctx.class_hierarchy_count], class_name, 64);
        cstr_copy(g_ctx.class_hierarchy_super[g_ctx.class_hierarchy_count], super_name, 64);
        g_ctx.class_hierarchy_count++;
    }

    if (parser_current(p).type == TOK_OPEN_BRACE) {
        parser_advance(p); /* consume { */
        /* Parse ivar declarations: type name; type name; ... */
        while (parser_current(p).type != TOK_CLOSE_BRACE &&
               parser_current(p).type != TOK_EOF) {
            /* Read the type name(s) */
            char ivar_type[64];
            ivar_type[0] = '\0';

            /* Skip type qualifiers (const, volatile, __weak, __strong, __unsafe_unretained) */
            while (parser_current(p).type == TOK_IDENTIFIER &&
                   (cstr_eq(parser_current(p).text, "const") ||
                    cstr_eq(parser_current(p).text, "volatile") ||
                    cstr_eq(parser_current(p).text, "__weak") ||
                    cstr_eq(parser_current(p).text, "__strong") ||
                    cstr_eq(parser_current(p).text, "__unsafe_unretained"))) {
                parser_advance(p);
            }

            /* Read the type name */
            if (parser_current(p).type == TOK_IDENTIFIER) {
                cstr_copy(ivar_type, parser_current(p).text, 64);
                parser_advance(p);

                /* Multi-token types: unsigned int, long long, etc. */
                if (cstr_eq(ivar_type, "unsigned") || cstr_eq(ivar_type, "signed")) {
                    if (parser_current(p).type == TOK_IDENTIFIER &&
                        (cstr_eq(parser_current(p).text, "int") ||
                         cstr_eq(parser_current(p).text, "char") ||
                         cstr_eq(parser_current(p).text, "long") ||
                         cstr_eq(parser_current(p).text, "short"))) {
                        parser_advance(p);
                    }
                    cstr_copy(ivar_type, "int", 64);
                }
                if (cstr_eq(ivar_type, "long")) {
                    if (parser_current(p).type == TOK_IDENTIFIER &&
                        (cstr_eq(parser_current(p).text, "long") ||
                         cstr_eq(parser_current(p).text, "int"))) {
                        parser_advance(p);
                    }
                    cstr_copy(ivar_type, "int", 64);
                }
                if (cstr_eq(ivar_type, "short")) {
                    if (parser_current(p).type == TOK_IDENTIFIER &&
                        cstr_eq(parser_current(p).text, "int")) {
                        parser_advance(p);
                    }
                    cstr_copy(ivar_type, "int", 64);
                }
            }

            /* Check for pointer * after type */
            while (parser_current(p).type == TOK_STAR) {
                parser_advance(p);
                /* If type was a class name, mark as id */
                if (ivar_type[0] != '\0' && !cstr_eq(ivar_type, "int") &&
                    !cstr_eq(ivar_type, "char") && !cstr_eq(ivar_type, "float") &&
                    !cstr_eq(ivar_type, "double") && !cstr_eq(ivar_type, "void")) {
                    cstr_copy(ivar_type, "id", 64);
                }
            }

            /* Read one or more ivar names separated by commas */
            while (parser_current(p).type == TOK_IDENTIFIER ||
                   (parser_current(p).type == TOK_IDENTIFIER &&
                    parser_current(p).text[0] == '_')) {
                char ivar_name[64];
                cstr_copy(ivar_name, parser_current(p).text, 64);
                parser_advance(p);

                /* Handle pointer after ivar name (e.g., int *_ptr) */
                while (parser_current(p).type == TOK_STAR) {
                    parser_advance(p);
                }

                /* Record this ivar */
                if (g_ctx.class_ivar_count < MAX_CLASS_IVARS) {
                    ClassIvar *ci = &g_ctx.class_ivars[g_ctx.class_ivar_count];
                    cstr_copy(ci->class_name, class_name, 64);
                    cstr_copy(ci->ivar_name, ivar_name, 64);
                    cstr_copy(ci->type_name, ivar_type, 64);
                    ci->is_int = (cstr_eq(ivar_type, "int") || cstr_eq(ivar_type, "NSInteger") ||
                                  cstr_eq(ivar_type, "NSUInteger") || cstr_eq(ivar_type, "long") ||
                                  cstr_eq(ivar_type, "char") || cstr_eq(ivar_type, "BOOL") ||
                                  cstr_eq(ivar_type, "short"));
                    ci->is_id = (cstr_eq(ivar_type, "id") || cstr_eq(ivar_type, "NSString") ||
                                 cstr_eq(ivar_type, "NSArray") || cstr_eq(ivar_type, "NSMutableArray") ||
                                 cstr_eq(ivar_type, "NSDictionary") || cstr_eq(ivar_type, "NSMutableDictionary") ||
                                 cstr_eq(ivar_type, "NSNumber") || cstr_eq(ivar_type, "NSData") ||
                                 cstr_eq(ivar_type, "NSSet") || cstr_eq(ivar_type, "NSObject"));
                    g_ctx.class_ivar_count++;
                }

                /* Comma-separated ivars: int x, y; */
                if (parser_current(p).type == TOK_COMMA) {
                    parser_advance(p);
                    continue;
                }
                break;
            }

            /* Consume the semicolon */
            if (parser_current(p).type == TOK_SEMICOLON) {
                parser_advance(p);
            }
        }
        if (parser_current(p).type == TOK_CLOSE_BRACE) {
            parser_advance(p); /* consume } */
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
                if (g_ctx.property_count >= 64) {
                    parser_error(p, "property table full (max 64 properties)");
                    while (parser_current(p).type != TOK_SEMICOLON && parser_current(p).type != TOK_CLOSE_PAREN && parser_current(p).type != TOK_EOF) {
                        parser_advance(p);
                    }
                    continue;
                }
                PropertyDecl *prop = &g_ctx.properties[g_ctx.property_count];
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
                    g_ctx.property_count++;
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

/* Parse @protocol Name <ConformsTo> { @required/@optional method_decls } @end */
Value parse_protocol(struct Parser *p) {
    char proto_name[64];

    if (parser_current(p).type != TOK_IDENTIFIER) {
        parser_error(p, "Expected protocol name after @protocol");
        return value_void();
    }
    if (copy_identifier_or_error(p, proto_name, parser_current(p).text, 64, "protocol")) {
        return value_void();
    }
    parser_advance(p);

    /* Check if protocol already declared — skip body if so */
    {
        unsigned int pi;
        for (pi = 0; pi < g_ctx.protocol_count; pi++) {
            if (cstr_eq(g_ctx.protocols[pi].name, proto_name)) {
                /* Skip to @end */
                while (!(parser_current(p).type == TOK_AT_KEYWORD &&
                         cstr_eq(parser_current(p).text, "@end")) &&
                       parser_current(p).type != TOK_EOF) {
                    parser_advance(p);
                }
                if (parser_current(p).type == TOK_AT_KEYWORD &&
                    cstr_eq(parser_current(p).text, "@end")) {
                    parser_advance(p);
                }
                return value_void();
            }
        }
    }

    if (g_ctx.protocol_count >= MAX_PROTOCOLS) {
        parser_error(p, "protocol table full (max 32 protocols)");
        return value_void();
    }

    ProtocolDecl *proto = &g_ctx.protocols[g_ctx.protocol_count];
    cstr_copy(proto->name, proto_name, MAX_PROTOCOL_NAME);
    proto->conforms_count = 0;
    proto->required_count = 0;
    proto->optional_count = 0;

    /* Parse <ConformsTo1, ConformsTo2> conformance list */
    if (parser_current(p).type == TOK_LT) {
        parser_advance(p);
        while (parser_current(p).type != TOK_GT &&
               parser_current(p).type != TOK_EOF) {
            if (parser_current(p).type == TOK_IDENTIFIER &&
                proto->conforms_count < 8) {
                if (copy_identifier_or_error(p, proto->conforms_to[proto->conforms_count],
                                          parser_current(p).text, MAX_PROTOCOL_NAME,
                                          "conforms-to protocol")) {
                    return value_void();
                }
                proto->conforms_count++;
                parser_advance(p);
            } else {
                parser_advance(p);
            }
            if (parser_current(p).type == TOK_COMMA) {
                parser_advance(p);
            }
        }
        if (parser_current(p).type == TOK_GT) {
            parser_advance(p);
        }
    }

    /* Parse protocol body: @required/@optional method decls, @end */
    {
        int current_section_required = 1; /* default is @required */

        while (!(parser_current(p).type == TOK_AT_KEYWORD &&
                 cstr_eq(parser_current(p).text, "@end")) &&
               parser_current(p).type != TOK_EOF) {

            if (parser_current(p).type == TOK_AT_KEYWORD) {
                if (cstr_eq(parser_current(p).text, "@required")) {
                    current_section_required = 1;
                    parser_advance(p);
                    continue;
                }
                if (cstr_eq(parser_current(p).text, "@optional")) {
                    current_section_required = 0;
                    parser_advance(p);
                    continue;
                }
                /* Unknown @keyword in protocol — skip it */
                parser_advance(p);
                continue;
            }

            /* Method declaration: + or - followed by selector */
            if (parser_current(p).type == TOK_PLUS || parser_current(p).type == TOK_MINUS) {
                char sel_name[256];
                unsigned int sel_len = 0;

                parser_advance(p); /* consume + or - */

                /* Skip return type in parens: (void), (id), etc. */
                if (parser_current(p).type == TOK_OPEN_PAREN) {
                    int depth = 1;
                    parser_advance(p);
                    while (depth > 0 && parser_current(p).type != TOK_EOF) {
                        if (parser_current(p).type == TOK_OPEN_PAREN) depth++;
                        else if (parser_current(p).type == TOK_CLOSE_PAREN) depth--;
                        parser_advance(p);
                    }
                }

                /* Build selector name from keyword parts */
                while (parser_current(p).type != TOK_SEMICOLON &&
                       parser_current(p).type != TOK_EOF &&
                       parser_current(p).type != TOK_OPEN_BRACE &&
                       !(parser_current(p).type == TOK_AT_KEYWORD &&
                         (cstr_eq(parser_current(p).text, "@required") ||
                          cstr_eq(parser_current(p).text, "@optional") ||
                          cstr_eq(parser_current(p).text, "@end")))) {

                    if (parser_current(p).type == TOK_IDENTIFIER) {
                        unsigned int len = cstr_len(parser_current(p).text);
                        if (sel_len + len + 1 < 256) {
                            cstr_copy(sel_name + sel_len, parser_current(p).text, 256 - sel_len);
                            sel_len += len;
                        }
                        parser_advance(p);
                    } else if (parser_current(p).type == TOK_COLON) {
                        if (sel_len + 1 < 256) {
                            sel_name[sel_len++] = ':';
                            sel_name[sel_len] = '\0';
                        }
                        parser_advance(p);
                        /* Skip argument type (int), (id), etc. */
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
                    } else {
                        parser_advance(p);
                    }
                }

                sel_name[sel_len] = '\0';

                /* Store method in appropriate list */
                if (sel_len > 0) {
                    if (current_section_required && proto->required_count < MAX_PROTOCOL_METHODS) {
                        cstr_copy(proto->required_methods[proto->required_count], sel_name, 256);
                        proto->required_count++;
                    } else if (!current_section_required && proto->optional_count < MAX_PROTOCOL_METHODS) {
                        cstr_copy(proto->optional_methods[proto->optional_count], sel_name, 256);
                        proto->optional_count++;
                    }
                }

                if (parser_current(p).type == TOK_SEMICOLON) {
                    parser_advance(p);
                }
                continue;
            }

            /* Skip unknown tokens */
            parser_advance(p);
        }
    }

    if (parser_current(p).type == TOK_AT_KEYWORD &&
        cstr_eq(parser_current(p).text, "@end")) {
        parser_advance(p);
    }

    g_ctx.protocol_count++;
    return value_void();
}

/* Method implementation function retained for runtime compatibility. */
static id method_impl_trampoline(id self, SEL _cmd, ...) {
    const char *sel_name = sel_getName(_cmd);
    unsigned int i;

    for (i = 0; i < g_ctx.method_count; i++) {
        if (g_ctx.methods[i].selector == _cmd && g_ctx.methods[i].source_len > 0) {
            break;
        }
    }

    if (i >= g_ctx.method_count || g_ctx.methods[i].source_len == 0) {
        return self;
    }

    unsigned int saved_var_count = g_ctx.var_count;

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

        if (sel_colons > 0 && g_ctx.methods[i].arg_count > 0) {
            __builtin_va_list ap;
            __builtin_va_start(ap, _cmd);

            unsigned int ai;
            for (ai = 0; ai < sel_colons && ai < g_ctx.methods[i].arg_count && ai < 8; ai++) {
                id arg_val = __builtin_va_arg(ap, id);
                InterpVar *var = interp_get_or_create_var(g_ctx.methods[i].arg_names[ai]);
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
        Value v = eval_source_range(0, g_ctx.methods[i].source_len, g_ctx.methods[i].source, 0);
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

        g_ctx.var_count = saved_var_count;
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
        for (mi = 0; mi < g_ctx.method_count; mi++) {
            if (g_ctx.methods[mi].class_ptr == cls) {
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
                                for (pi = 0; pi < g_ctx.property_count; pi++) {
                                    if (cstr_eq(g_ctx.properties[pi].name, prop_name) &&
                                        cstr_eq(g_ctx.properties[pi].class_name, class_name)) {
                                        cstr_copy(g_ctx.properties[pi].ivar_name, ivar_name, 64);
                                        break;
                                    }
                                }
                            }
                        }
                    }

                    {
                        unsigned int pi;
                        for (pi = 0; pi < g_ctx.property_count; pi++) {
                            if (cstr_eq(g_ctx.properties[pi].name, prop_name) &&
                                cstr_eq(g_ctx.properties[pi].class_name, class_name)) {
                                g_ctx.properties[pi].synthesized = 1;
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

                if (g_ctx.method_count < MAX_METHODS && body_len > 0) {
                    if (body_len >= 2048) {
                        parser_error(p, "method body too long (max 2047 bytes)");
                        return value_void();
                    }
                    MethodImpl *mi = &g_ctx.methods[g_ctx.method_count];
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
                    g_ctx.method_count++;
                } else if (g_ctx.method_count >= MAX_METHODS) {
                    parser_error(p, "method table full (max 64 methods)");
                }
            }
        } else {
            parser_advance(p);
        }
    }

    {
        unsigned int pi;
        for (pi = 0; pi < g_ctx.property_count; pi++) {
            if (cstr_eq(g_ctx.properties[pi].class_name, class_name) &&
                !g_ctx.properties[pi].synthesized) {
                g_ctx.properties[pi].synthesized = 1;
                if (g_ctx.properties[pi].ivar_name[0] == '\0') {
                    const char *pname = g_ctx.properties[pi].name;
                    unsigned int ppos = 0;
                    g_ctx.properties[pi].ivar_name[ppos++] = '_';
                    while (*pname && ppos < 62) {
                        g_ctx.properties[pi].ivar_name[ppos++] = *pname++;
                    }
                    g_ctx.properties[pi].ivar_name[ppos] = '\0';
                }
            }
        }
    }

    if (parser_current(p).type == TOK_AT_KEYWORD && cstr_eq(parser_current(p).text, "@end")) {
        parser_advance(p);
    }

    return value_from_class(cls);
}
