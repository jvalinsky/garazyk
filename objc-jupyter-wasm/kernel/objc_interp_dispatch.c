/*
 * Extracted method dispatch and NSLog evaluation helpers from the
 * Objective-C interpreter.
 */

#include "objc_interp_types.h"
#include "objc_interp_context.h"
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
extern InterpVar *interp_find_var(const char *name);

/* string pool and FDObj helpers */
extern int is_string_pool_pointer(id ptr);
extern Class class_for_fdobj_marker(id receiver);

/* Forward declarations for this file */
const char *class_get_superclass_name(const char *class_name);
Class class_ptr_for_name(const char *name);
const char *class_name_for_ptr(Class cls);

/* Parser layout must match the definition in objc_interpreter.c. */

static InterpVar *dispatch_find_var(const char *name) {
    unsigned int i;
    if (g_ctx.var_count == 0) return 0;
    for (i = g_ctx.var_count; i > g_ctx.var_scope_base; i--) {
        if (cstr_eq(g_ctx.vars[i - 1].name, name)) {
            return &g_ctx.vars[i - 1];
        }
    }
    return 0;
}

static InterpVar *dispatch_get_or_create_var(const char *name) {
    InterpVar *v = dispatch_find_var(name);
    if (v) return v;
    if (g_ctx.var_count >= OBJC_INTERP_MAX_VARS) return 0;
    cstr_copy(g_ctx.vars[g_ctx.var_count].name, name, 64);
    g_ctx.vars[g_ctx.var_count].value = 0;
    g_ctx.vars[g_ctx.var_count].cls = 0;
    g_ctx.vars[g_ctx.var_count].sel = 0;
    g_ctx.vars[g_ctx.var_count].is_int = 0;
    g_ctx.vars[g_ctx.var_count].int_value = 0;
    g_ctx.vars[g_ctx.var_count].is_float = 0;
    g_ctx.vars[g_ctx.var_count].float_value = 0.0;
    g_ctx.vars[g_ctx.var_count].is_class = 0;
    g_ctx.vars[g_ctx.var_count].is_sel = 0;
    g_ctx.vars[g_ctx.var_count].is_id = 0;
    g_ctx.vars[g_ctx.var_count].is_block_captured = 0;
    g_ctx.vars[g_ctx.var_count].is_static = 0;
    g_ctx.var_count++;
    return &g_ctx.vars[g_ctx.var_count - 1];
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
            if (ptr >= g_ctx.string_pool && ptr < g_ctx.string_pool + OBJC_INTERP_STRING_POOL_SIZE) {
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
    const char *target_class_name = 0;
    Class recv_cls = (Class)0;

    /* Get target class information */
    if (target.is_class) {
        recv_cls = (Class)target.cls_val;
        target_class_name = class_name_for_ptr(recv_cls);
    } else if (target.is_id && receiver != 0) {
        if (is_string_pool_pointer(receiver)) {
            recv_cls = class_for_fdobj_marker(receiver);
        } else {
            recv_cls = object_getClass(receiver);
        }
        if (recv_cls) {
            target_class_name = class_name_for_ptr(recv_cls);
        }
    }

    /* First pass: search for exact class match (most specific) */
    for (mi = 0; mi < g_ctx.method_count; mi++) {
        MethodImpl *method = &g_ctx.methods[mi];
        if (method->selector != sel) continue;

        if (target.is_class && method->is_class_method) {
            if (method->class_ptr == target.cls_val) return mi;
            if (target_class_name) {
                const char *method_class_name = class_name_for_ptr(method->class_ptr);
                if (method_class_name && cstr_eq(method_class_name, target_class_name)) return mi;
            }
        } else if ((target.is_id || target.is_int) && !method->is_class_method) {
            if (recv_cls && method->class_ptr == recv_cls) return mi;
            if (target_class_name) {
                const char *method_class_name = class_name_for_ptr(method->class_ptr);
                if (method_class_name && cstr_eq(method_class_name, target_class_name)) return mi;
            }
        }
    }

    /* Second pass: walk superclass chain for inherited methods */
    if (target_class_name && (target.is_id || target.is_int)) {
        const char *current = target_class_name;
        unsigned int depth;
        for (depth = 0; depth < 16; depth++) {
            const char *super_name = class_get_superclass_name(current);
            if (!super_name || super_name[0] == '\0') break;
            for (mi = 0; mi < g_ctx.method_count; mi++) {
                MethodImpl *method = &g_ctx.methods[mi];
                if (method->selector != sel) continue;
                if (method->is_class_method) continue;
                {
                    const char *method_class_name = class_name_for_ptr(method->class_ptr);
                    if (method_class_name && cstr_eq(method_class_name, super_name)) return mi;
                }
            }
            current = super_name;
        }
    }

    /* Third pass: class method superclass walk */
    if (target_class_name && target.is_class) {
        const char *current = target_class_name;
        unsigned int depth;
        for (depth = 0; depth < 16; depth++) {
            const char *super_name = class_get_superclass_name(current);
            if (!super_name || super_name[0] == '\0') break;
            for (mi = 0; mi < g_ctx.method_count; mi++) {
                MethodImpl *method = &g_ctx.methods[mi];
                if (method->selector != sel) continue;
                if (!method->is_class_method) continue;
                {
                    const char *method_class_name = class_name_for_ptr(method->class_ptr);
                    if (method_class_name && cstr_eq(method_class_name, super_name)) return mi;
                }
            }
            current = super_name;
        }
    }
    return g_ctx.method_count;
}

/* Look up the superclass name for a given class name from the hierarchy table. */
const char *class_get_superclass_name(const char *class_name) {
    unsigned int hi;
    for (hi = 0; hi < g_ctx.class_hierarchy_count; hi++) {
        if (cstr_eq(g_ctx.class_hierarchy_class[hi], class_name)) {
            return g_ctx.class_hierarchy_super[hi];
        }
    }
    return 0;
}

/* Look up the class_ptr (sentinel) for a class name from the variable table. */
Class class_ptr_for_name(const char *name) {
    unsigned int vi;
    for (vi = 0; vi < g_ctx.var_count; vi++) {
        if (g_ctx.vars[vi].is_class && cstr_eq(g_ctx.vars[vi].name, name)) {
            return g_ctx.vars[vi].cls;
        }
    }
    return (Class)0;
}

/* Look up the class name for a given class_ptr from the variable table. */
const char *class_name_for_ptr(Class cls) {
    unsigned int vi;
    for (vi = 0; vi < g_ctx.var_count; vi++) {
        if (g_ctx.vars[vi].is_class && g_ctx.vars[vi].cls == cls) {
            return g_ctx.vars[vi].name;
        }
    }
    return 0;
}

/* Find method for super dispatch: walk the superclass chain from skip_class
 * and search for methods matching the selector in any superclass.
 * This implements [super selector:] by looking up the method in the
 * superclass chain rather than the current class. */
unsigned int find_interpreter_method_super(SEL sel, Value target, id receiver,
                                           Class skip_class) {
    unsigned int mi;
    /* Collect the set of superclass class_ptrs by walking the hierarchy */
    Class super_classes[16]; /* max 16 levels of inheritance */
    unsigned int super_count = 0;
    const char *current_name = class_name_for_ptr(skip_class);

    /* Walk up the hierarchy from skip_class */
    while (current_name && super_count < 16) {
        const char *parent_name = class_get_superclass_name(current_name);
        if (!parent_name || parent_name[0] == '\0') break;
        Class parent_cls = class_ptr_for_name(parent_name);
        if (parent_cls == (Class)0) break;
        super_classes[super_count++] = parent_cls;
        current_name = parent_name;
    }

    /* Search for methods matching the selector in superclass order
     * (most specific first: B before A) to respect overriding. */
    {
        unsigned int si;
        for (si = 0; si < super_count; si++) {
            for (mi = 0; mi < g_ctx.method_count; mi++) {
                MethodImpl *method = &g_ctx.methods[mi];
                if (method->selector != sel || method->source_len == 0) continue;
                if (method->class_ptr == skip_class) continue;
                if (method->class_ptr == super_classes[si]) {
                    if (!method->is_class_method && (target.is_id || target.is_int)) {
                        return mi;
                    }
                    if (method->is_class_method && target.is_class) {
                        return mi;
                    }
                }
            }
        }
    }
    return g_ctx.method_count;
}

int bind_method_var(const char *name, Value value) {
    InterpVar *var = dispatch_get_or_create_var(name);
    if (var == 0) return -1;
    interp_set_var_from_value(var, value);
    return 0;
}

void inject_synthesized_ivars(id receiver) {
    unsigned int pi;
    for (pi = 0; pi < g_ctx.property_count; pi++) {
        if (g_ctx.properties[pi].synthesized &&
            g_ctx.properties[pi].ivar_name[0] != '\0' &&
            property_matches_class(receiver, pi)) {
            InterpVar *ivar_var = dispatch_get_or_create_var(g_ctx.properties[pi].ivar_name);
            if (ivar_var) {
                Value *stored = instance_var_get(receiver, g_ctx.properties[pi].name);
                if (stored) {
                    interp_set_var_from_value(ivar_var, *stored);
                } else {
                    interp_set_var_from_value(ivar_var,
                        g_ctx.properties[pi].is_int ? value_from_int(0) : value_from_id(0));
                }
            }
        }
    }
    /* Also inject explicit class ivars (from @interface { } blocks).
     * These are ivars declared directly in the class, not via @property. */
    {
        /* Find the class name for the receiver */
        const char *recv_class = 0;
        const char *recv_marker = (const char *)receiver;
        if (cstr_starts(recv_marker, "FDObj:")) {
            recv_class = recv_marker + 6;
        }
        if (recv_class) {
            unsigned int ci;
            for (ci = 0; ci < g_ctx.class_ivar_count; ci++) {
                if (cstr_eq(g_ctx.class_ivars[ci].class_name, recv_class)) {
                    /* Check if this ivar is already handled by a synthesized property */
                    int handled_by_property = 0;
                    for (pi = 0; pi < g_ctx.property_count; pi++) {
                        if (g_ctx.properties[pi].synthesized &&
                            cstr_eq(g_ctx.properties[pi].ivar_name, g_ctx.class_ivars[ci].ivar_name) &&
                            cstr_eq(g_ctx.properties[pi].class_name, recv_class)) {
                            handled_by_property = 1;
                            break;
                        }
                    }
                    if (!handled_by_property) {
                        InterpVar *ivar_var = dispatch_get_or_create_var(g_ctx.class_ivars[ci].ivar_name);
                        if (ivar_var) {
                            Value *stored = instance_var_get(receiver, g_ctx.class_ivars[ci].ivar_name);
                            if (stored) {
                                interp_set_var_from_value(ivar_var, *stored);
                            } else {
                                interp_set_var_from_value(ivar_var,
                                    g_ctx.class_ivars[ci].is_int ? value_from_int(0) : value_from_id(0));
                            }
                        }
                    }
                }
            }
        }
    }
}

void write_back_synthesized_ivars(struct Parser *p, id receiver) {
    unsigned int pi;
    for (pi = 0; pi < g_ctx.property_count; pi++) {
        if (g_ctx.properties[pi].synthesized &&
            g_ctx.properties[pi].ivar_name[0] != '\0' &&
            property_matches_class(receiver, pi)) {
            InterpVar *ivar_var = dispatch_find_var(g_ctx.properties[pi].ivar_name);
            if (ivar_var) {
                Value ivar_val = value_from_interp_var(ivar_var);
                if (instance_var_set(receiver, g_ctx.properties[pi].name, ivar_val) != 0) {
                    parser_error(p, "instance variable table full (max 256)");
                    return;
                }
            }
        }
    }
    /* Also write back explicit class ivars (from @interface { } blocks) */
    {
        const char *recv_class = 0;
        const char *recv_marker = (const char *)receiver;
        if (cstr_starts(recv_marker, "FDObj:")) {
            recv_class = recv_marker + 6;
        }
        if (recv_class) {
            unsigned int ci;
            for (ci = 0; ci < g_ctx.class_ivar_count; ci++) {
                if (cstr_eq(g_ctx.class_ivars[ci].class_name, recv_class)) {
                    /* Skip if already handled by a synthesized property */
                    int handled_by_property = 0;
                    for (pi = 0; pi < g_ctx.property_count; pi++) {
                        if (g_ctx.properties[pi].synthesized &&
                            cstr_eq(g_ctx.properties[pi].ivar_name, g_ctx.class_ivars[ci].ivar_name) &&
                            cstr_eq(g_ctx.properties[pi].class_name, recv_class)) {
                            handled_by_property = 1;
                            break;
                        }
                    }
                    if (!handled_by_property) {
                        InterpVar *ivar_var = dispatch_find_var(g_ctx.class_ivars[ci].ivar_name);
                        if (ivar_var) {
                            Value ivar_val = value_from_interp_var(ivar_var);
                            if (instance_var_set(receiver, g_ctx.class_ivars[ci].ivar_name, ivar_val) != 0) {
                                parser_error(p, "instance variable table full (max 256)");
                                return;
                            }
                        }
                    }
                }
            }
        }
    }
}

Value execute_interpreter_method(struct Parser *p, MethodImpl *method, SEL sel,
                                 id receiver, const Value *args,
                                 unsigned int arg_count,
                                 int return_receiver_on_void) {
    unsigned int saved_var_count = g_ctx.var_count;
    unsigned int saved_scope_base = g_ctx.var_scope_base;
    Value return_val = return_receiver_on_void ? value_from_id(receiver) : value_void();
    unsigned int ai;

    g_ctx.var_scope_base = g_ctx.var_count;
    g_ctx.return_pending = 0;
    g_ctx.return_value = value_void();

    /* Save and set current class for super dispatch */
    {
        Class saved_class_ptr = g_ctx.current_class_ptr;
        g_ctx.current_class_ptr = method->class_ptr;

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

    if (!p->error && g_ctx.return_pending) {
        return_val = g_ctx.return_value;
    }

done:
    g_ctx.var_count = saved_var_count;
    g_ctx.var_scope_base = saved_scope_base;
    g_ctx.return_pending = 0;
    g_ctx.current_class_ptr = saved_class_ptr;
    }
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

/* Check if a class conforms to a given protocol.
 * 1. Checks the class_conformances table (populated in parse_interface).
 * 2. If the protocol declares required methods, verifies the class
 *    (or its @implementation) actually implements them.
 * Returns 1 if the class conforms (name + method-level), 0 otherwise. */
int class_conforms_to_protocol(const char *class_name, const char *protocol_name) {
    int found_protocol = 0;
    int found_class = 0;
    unsigned int pi = 0; /* protocol index */
    unsigned int ci = 0; /* class variable index */

    /* Find the protocol in the protocol table */
    for (pi = 0; pi < g_ctx.protocol_count; pi++) {
        if (cstr_eq(g_ctx.protocols[pi].name, protocol_name)) {
            found_protocol = 1;
            break;
        }
    }
    if (!found_protocol) return 0; /* protocol not even registered */

    /* Find the class in the variable table */
    for (ci = 0; ci < g_ctx.var_count; ci++) {
        if (g_ctx.vars[ci].is_class && cstr_eq(g_ctx.vars[ci].name, class_name)) {
            found_class = 1;
            break;
        }
    }
    if (!found_class) return 0; /* class not found */

    /* Check class_conformances table (was <Protocol> declared?) */
    {
        unsigned int cc;
        int name_conforms = 0;
        for (cc = 0; cc < g_ctx.class_conforms_count[ci]; cc++) {
            if (cstr_eq(g_ctx.class_conformances[ci][cc], protocol_name)) {
                name_conforms = 1;
                break;
            }
        }
        if (!name_conforms) return 0; /* class was not declared as conforming */
    }

    /* Method-level check: verify required methods are implemented.
     * We check both: (a) methods registered via @implementation, and
     * (b) methods dynamically added via class_addMethod. */
    {
        unsigned int ri;
        unsigned int mi;
        Class target_cls = g_ctx.vars[ci].cls;

        for (ri = 0; ri < g_ctx.protocols[pi].required_count; ri++) {
            const char *req_sel = g_ctx.protocols[pi].required_methods[ri];
            int method_found = 0;

            /* Check interpreter-registered methods (from @implementation) */
            for (mi = 0; mi < g_ctx.method_count; mi++) {
                if (g_ctx.methods[mi].class_ptr == target_cls &&
                    cstr_eq(sel_getName(g_ctx.methods[mi].selector), req_sel)) {
                    method_found = 1;
                    break;
                }
            }
            if (!method_found) return 0; /* required method not implemented */
        }
    }

    return 1; /* all required methods found */
}
