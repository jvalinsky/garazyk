/*
 * Extracted method dispatch and NSLog evaluation helpers from the
 * Objective-C interpreter.
 */

#include "objc_interp_types.h"
#include "objc_interp_globals.h"
#include "objc_interp_dispatch.h"
#include "objc_interp_state.h"
#include "objc_interp_format.h"
#include "objc_interp_lexer.h"

/* Runtime bridge function used by NSLog streaming. */
extern void interp_emit_stream(const char *data, unsigned int len);
extern const char *sel_getName(SEL);
extern Class object_getClass(id);

/* Parser helpers still implemented in objc_interpreter.c. */
extern Token parser_current(struct Parser *p);
extern void parser_advance(struct Parser *p);
extern int parser_expect(struct Parser *p, TokenType type);
extern void parser_error(struct Parser *p, const char *msg);
extern Value parse_expression_safe(struct Parser *p);
extern Value eval_source_range(unsigned int start, unsigned int len, const char *source,
                               unsigned int line_offset);

/* Parser layout must match the definition in objc_interpreter.c. */

static InterpVar *dispatch_find_var(const char *name) {
    unsigned int i;
    if (g_var_count == 0) return 0;
    for (i = g_var_count; i > g_var_scope_base; i--) {
        if (cstr_eq(g_vars[i - 1].name, name)) {
            return &g_vars[i - 1];
        }
    }
    return 0;
}

static InterpVar *dispatch_get_or_create_var(const char *name) {
    InterpVar *v = dispatch_find_var(name);
    if (v) return v;
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
    g_vars[g_var_count].is_block_captured = 0;
    g_vars[g_var_count].is_static = 0;
    g_var_count++;
    return &g_vars[g_var_count - 1];
}

int interpreter_method_matches(MethodImpl *method, SEL sel, Value target,
                               id receiver, int instance_only) {
    if (method == 0 || method->selector != sel || method->source_len == 0) return 0;

    if (method->class_ptr != (Class)0) {
        if (target.is_class && method->class_ptr == target.cls_val) {
            /* class target matches */
        } else if (target.is_id && is_string_pool_pointer(receiver) &&
                   cstr_starts((const char *)receiver, "FDObj:")) {
            if (class_for_fdobj_marker(receiver) != method->class_ptr) return 0;
        } else if (target.is_id && receiver != 0) {
            const char *ptr = (const char *)receiver;
            Class recv_cls;
            if (ptr >= g_string_pool && ptr < g_string_pool + OBJC_INTERP_STRING_POOL_SIZE) {
                return 0;
            }
            recv_cls = object_getClass(receiver);
            if (recv_cls != 0 && method->class_ptr != recv_cls) return 0;
        } else {
            return 0;
        }
    }

    if (instance_only) {
        return !method->is_class_method && (target.is_id || target.is_int);
    }
    if (method->is_class_method && target.is_class) return 1;
    if (!method->is_class_method && (target.is_id || target.is_int)) return 1;
    return 0;
}

unsigned int find_interpreter_method(SEL sel, Value target, id receiver,
                                     int instance_only) {
    unsigned int mi;
    for (mi = 0; mi < g_method_count; mi++) {
        if (interpreter_method_matches(&g_methods[mi], sel, target, receiver, instance_only)) {
            return mi;
        }
    }
    return g_method_count;
}

int bind_method_var(const char *name, Value value) {
    InterpVar *var = dispatch_get_or_create_var(name);
    if (var == 0) return -1;
    interp_set_var_from_value(var, value);
    return 0;
}

void inject_synthesized_ivars(id receiver) {
    unsigned int pi;
    for (pi = 0; pi < g_property_count; pi++) {
        if (g_properties[pi].synthesized &&
            g_properties[pi].ivar_name[0] != '\0' &&
            property_matches_class(receiver, pi)) {
            InterpVar *ivar_var = dispatch_get_or_create_var(g_properties[pi].ivar_name);
            if (ivar_var) {
                Value *stored = instance_var_get(receiver, g_properties[pi].name);
                if (stored) {
                    interp_set_var_from_value(ivar_var, *stored);
                } else {
                    interp_set_var_from_value(ivar_var,
                        g_properties[pi].is_int ? value_from_int(0) : value_from_id(0));
                }
            }
        }
    }
}

void write_back_synthesized_ivars(struct Parser *p, id receiver) {
    unsigned int pi;
    for (pi = 0; pi < g_property_count; pi++) {
        if (g_properties[pi].synthesized &&
            g_properties[pi].ivar_name[0] != '\0' &&
            property_matches_class(receiver, pi)) {
            InterpVar *ivar_var = dispatch_find_var(g_properties[pi].ivar_name);
            if (ivar_var) {
                Value ivar_val = value_from_interp_var(ivar_var);
                if (instance_var_set(receiver, g_properties[pi].name, ivar_val) != 0) {
                    parser_error(p, "instance variable table full (max 256)");
                    return;
                }
            }
        }
    }
}

Value execute_interpreter_method(struct Parser *p, MethodImpl *method, SEL sel,
                                 id receiver, const Value *args,
                                 unsigned int arg_count,
                                 int return_receiver_on_void) {
    unsigned int saved_var_count = g_var_count;
    unsigned int saved_scope_base = g_var_scope_base;
    Value return_val = return_receiver_on_void ? value_from_id(receiver) : value_void();
    unsigned int ai;

    g_var_scope_base = g_var_count;
    g_return_pending = 0;
    g_return_value = value_void();

    if (bind_method_var("self", value_from_id(receiver)) != 0 ||
        bind_method_var("_cmd", value_from_sel(sel)) != 0) {
        parser_error(p, "variable table full (max 1024)");
        goto done;
    }

    for (ai = 0; ai < method->arg_count && ai < 8 && ai < arg_count; ai++) {
        if (bind_method_var(method->arg_names[ai], args[ai]) != 0) {
            parser_error(p, "variable table full (max 1024)");
            goto done;
        }
    }

    inject_synthesized_ivars(receiver);

    {
        Value ignored = eval_source_range(0, method->source_len, method->source, 0);
        (void)ignored;
    }

    if (!p->error) {
        write_back_synthesized_ivars(p, receiver);
    }

    if (!p->error && g_return_pending) {
        return_val = g_return_value;
    }

done:
    g_var_count = saved_var_count;
    g_var_scope_base = saved_scope_base;
    g_return_pending = 0;
    return return_val;
}

void eval_nslog(struct Parser *p) {
    Value fmt_val;
    const char *fmt;
    Value args[16];
    int arg_count = 0;

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

    /* Process format string using the shared formatter */
    if (fmt == 0) {
        nslog_append("(null)", 6);
        return;
    }

    {
        Value result = format_values_to_pool(fmt, args, arg_count);
        if (result.is_id && result.obj_val != 0) {
            const char *s = (const char *)result.obj_val;
            nslog_append(s, cstr_len(s));
        }
    }

    /* NSLog always appends a newline */
    nslog_append_char('\n');
}
