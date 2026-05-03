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
typedef struct Parser {
    Lexer lex;
    int error;
    char error_msg[OBJC_INTERP_ERROR_SIZE];
} Parser;

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
                    /* Long or long long — check for %ld or %lld */
                    if (fmt[fi + 1] == 'l' && (fmt[fi + 2] == 'd' || fmt[fi + 2] == 'i')) {
                        /* %lld — long long */
                        fi += 2; /* skip 'll' */
                        if (arg_idx < arg_count) {
                            Value v = args[arg_idx++];
                            if (v.is_int) {
                                nslog_append_long((long)v.int_val);
                            }
                        }
                    } else if (fmt[fi + 1] == 'd' || fmt[fi + 1] == 'i') {
                        /* %ld */
                        fi++; /* skip 'l' */
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
                case 'x':
                    /* Hexadecimal */
                    if (arg_idx < arg_count) {
                        Value v = args[arg_idx++];
                        unsigned int val = (unsigned int)(v.is_int ? v.int_val : (v.is_id ? (long)v.obj_val : 0));
                        if (val == 0) {
                            nslog_append("0", 1);
                        } else {
                            char hex[17];
                            int hi = 0;
                            while (val > 0 && hi < 16) {
                                hex[hi++] = "0123456789abcdef"[val % 16];
                                val /= 16;
                            }
                            while (hi > 0) {
                                hi--;
                                nslog_append_char(hex[hi]);
                            }
                        }
                    }
                    break;
                case 'o':
                    /* Octal */
                    if (arg_idx < arg_count) {
                        Value v = args[arg_idx++];
                        unsigned int val = (unsigned int)(v.is_int ? v.int_val : (v.is_id ? (long)v.obj_val : 0));
                        if (val == 0) {
                            nslog_append("0", 1);
                        } else {
                            char oct[32];
                            int oi = 0;
                            while (val > 0 && oi < 31) {
                                oct[oi++] = '0' + (val % 8);
                                val /= 8;
                            }
                            while (oi > 0) {
                                oi--;
                                nslog_append_char(oct[oi]);
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
