/*
 * objc_interp_messages.c
 * Message send parsing and Foundation dispatch extracted from the main interpreter.
 */

#include "objc_interp_types.h"
#include "objc_interp_globals.h"
#include "objc_interp_parser.h"
#include "objc_interp_state.h"
#include "objc_interp_dispatch.h"
#include "objc_interp_format.h"
#include "objc_interp_lexer.h"
#include "objc_interp_primary.h"
#include "objc_interp_ast.h"

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
extern id objc_lookUpClass(const char *name);
extern Class object_getClass(id);
extern InterpVar *interp_find_var(const char *name);
extern InterpVar *interp_get_or_create_var(const char *name);

Value parse_message_send(Parser *p) {
    Value target;
    char sel_name[256];
    unsigned int sel_len;
    id args[16];
    Value keyword_args[16]; /* preserve Value types for interpreter method dispatch */
    unsigned int arg_count;
    Value result;
    int target_is_super = 0;
    id receiver = 0;
    const char *target_class_name = 0; /* for Foundation name-based dispatch */
    SEL sel = 0;

    /* Parse target — check for super keyword */
    if (parser_current(p).type == TOK_SUPER) {
        target_is_super = 1;
        parser_advance(p);
        /* super in an @implementation — treat as self for now */
        /* In a real runtime, super calls the superclass method */
        target = value_from_id(0); /* placeholder */
        {
            InterpVar *self_var = interp_find_var("self");
            if (self_var && self_var->is_id) {
                target = value_from_id(self_var->value);
            }
        }
    } else {
        target = parse_expression_safe(p);
    }
    if (p->error) return value_void();

    /* Build selector name from the message pattern */
    sel_name[0] = '\0';
    sel_len = 0;
    arg_count = 0;

    /* Parse selector parts and arguments */
    while (parser_current(p).type != TOK_CLOSE_BRACKET &&
           parser_current(p).type != TOK_EOF) {

        /* Comma-separated variadic arguments (e.g., stringWithFormat:@"%d", n).
         * In ObjC, commas inside [ ] brackets separate variadic arguments
         * after the last keyword argument. Parse each as an additional
         * positional argument. */
        if (parser_current(p).type == TOK_COMMA) {
            parser_advance(p); /* skip , */
            if (arg_count < 16) {
                Value arg = parse_expression_safe(p);
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
            continue;
        }

        if (parser_current(p).type == TOK_IDENTIFIER) {
            /* Selector component */
            char part_buf[OBJC_INTERP_MAX_TOKEN];
            unsigned int part_len;
            cstr_copy(part_buf, parser_current(p).text, OBJC_INTERP_MAX_TOKEN);
            part_len = cstr_len(part_buf);

            /* Reserve room for this part plus a possible ':' and the null
             * terminator. Without this guard, a long selector silently
             * overflows sel_name[256]: the cstr_copy below bounds the byte
             * write, but `sel_len += part_len` advances by the untruncated
             * length, and the next `sel_name[sel_len] = ':'` then indexes
             * past the buffer. */
            if (sel_len + part_len + 2 > sizeof(sel_name)) {
                sel_name[sel_len] = '\0';
                parser_error(p, "selector name too long (max 254 chars)");
                return value_void();
            }

            /* Append selector component (no extra colon — the colon
             * after each keyword part is added below) */
            cstr_copy(sel_name + sel_len, part_buf, sizeof(sel_name) - sel_len);
            sel_len += part_len;

            parser_advance(p);

            /* If next token is colon, this is a keyword argument */
            if (parser_current(p).type == TOK_COLON) {
                parser_advance(p); /* consume : */

                /* Append ':' to the selector. Bounded: the guard above
                 * already reserved room for the colon and null. */
                sel_name[sel_len] = ':';
                sel_len++;
                sel_name[sel_len] = '\0';

                /* Parse argument */
                if (arg_count < 16) {
                    Value arg = parse_expression_safe(p);
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
                /* Handle comma-separated variadic arguments (for stringWithFormat:, etc.) */
                while (parser_current(p).type == TOK_COMMA && arg_count < 16) {
                    parser_advance(p); /* consume ',' */
                    if (arg_count < 16) {
                        Value arg = parse_expression_safe(p);
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
        sel = sel_registerName(sel_name);
        if (sel == 0) {
            parser_error(p, "selector table full (max 4096 selectors)");
            return value_void();
        }

        if (target.is_id) receiver = target.obj_val;
        else if (target.is_class) receiver = (id)target.cls_val;
        else if (target.is_int) receiver = (id)(long)target.int_val;

        /* Nil messaging: in ObjC, [nil anyMethod] returns nil/0/NO.
         * This is a fundamental language feature — without it, any
         * property access on an uninitialized ivar crashes. */
        if (target.is_id && receiver == 0) {
            result = value_from_id(0);
            return result;
        }

        /* Determine target class name for Foundation dispatch.
         * Foundation classes are not registered in the runtime (to avoid
         * WASM traps from objc_allocateClassPair), so we dispatch by name.
         * We look up the variable name from g_vars[].
         * IMPORTANT: We can't call object_getClass on non-ObjC pointers
         * (like C strings from the string pool) — it causes WASM traps.
         * So we only call it for class targets, not id targets. */
        if (target.is_class && target.cls_val) {
            /* Look up class name from variable table.
             * We can't call class_getName on sentinel pointers (crashes in WASM).
             * Sentinel pointers: Foundation classes (1-9), custom classes (100+). */
            {
                unsigned int vi;
                for (vi = 0; vi < g_var_count; vi++) {
                    if (g_vars[vi].is_class && g_vars[vi].cls == target.cls_val) {
                        target_class_name = g_vars[vi].name;
                        break;
                    }
                }
            }
        }
        /* For id targets, we don't call object_getClass because the
         * pointer might not be a valid ObjC object. Instead, we
         * dispatch by selector name alone for Foundation methods. */

        /* Helper: check if target is a Foundation class */
        #define IS_FOUNDATION_CLASS(name) \
            (target_class_name && cstr_eq(target_class_name, name))

        /* Built-in: [ClassName alloc] → return FDObj: marker for all classes.
         * In WASM, class_createInstance crashes on sentinel pointers,
         * so we use the FDObj: marker approach for ALL classes (not just
         * Foundation). Custom classes get sentinel pointers >= 100. */
        if (target.is_class && cstr_eq(sel_name, "alloc")) {
            if (target_class_name) {
                unsigned int name_len = cstr_len(target_class_name);
                unsigned int needed = 6 + name_len + 1;
                char *buf = string_pool_alloc(needed);
                if (buf == 0) {
                    /* String pool exhausted. Returning a literal sentinel
                     * here would be misinterpreted by downstream FDObj:
                     * checks as a Foundation object of class "overflow". */
                    parser_error(p, "string pool exhausted ([alloc])");
                    return value_void();
                }
                cstr_copy(buf, "FDObj:", needed);
                cstr_copy(buf + 6, target_class_name, needed - 6);
                return value_from_id((id)buf);
            }
            return value_from_id((id)0);
        }

        /* Built-in: [ClassName new] → same as alloc (returns FDObj: marker) */
        if (target.is_class && cstr_eq(sel_name, "new")) {
            if (target_class_name) {
                unsigned int name_len = cstr_len(target_class_name);
                unsigned int needed = 6 + name_len + 1;
                char *buf = string_pool_alloc(needed);
                if (buf == 0) {
                    parser_error(p, "string pool exhausted ([new])");
                    return value_void();
                }
                cstr_copy(buf, "FDObj:", needed);
                cstr_copy(buf + 6, target_class_name, needed - 6);
                return value_from_id((id)buf);
            }
            return value_from_id((id)0);
        }

        /* ── Interpreter method dispatch for custom classes ─────────
         * For FDObj: markers of custom (non-Foundation) classes, check
         * interpreter-registered methods BEFORE built-in dispatch.
         * Foundation classes (NSString, NSNumber, NSArray, NSDictionary,
         * NSSet, NSData, NSObject) use built-in dispatch exclusively.
         * Custom classes may override built-in selectors (e.g., init,
         * count, description) with @implementation methods.
         * When target_is_super is set, skip this dispatch to avoid
         * infinite recursion (super calls should fall through to
         * built-in NSObject dispatch). */
        if (!target_is_super &&
            target.is_id && receiver != 0 &&
            is_string_pool_pointer(receiver) &&
            cstr_starts((const char *)receiver, "FDObj:")) {
            const char *recv_cls = ((const char *)receiver) + 6;
            int is_foundation = (cstr_eq(recv_cls, "NSString") ||
                                 cstr_eq(recv_cls, "NSNumber") ||
                                 cstr_eq(recv_cls, "NSArray") ||
                                 cstr_eq(recv_cls, "NSMutableArray") ||
                                 cstr_eq(recv_cls, "NSDictionary") ||
                                 cstr_eq(recv_cls, "NSMutableDictionary") ||
                                 cstr_eq(recv_cls, "NSSet") ||
                                 cstr_eq(recv_cls, "NSData") ||
                                 cstr_eq(recv_cls, "NSObject"));
            if (!is_foundation) {
                unsigned int mi = find_interpreter_method(sel, target, receiver, 0);
                if (mi < g_method_count) {
                    return execute_interpreter_method(p, &g_methods[mi], sel, receiver,
                                                      keyword_args, arg_count, 1);
                }
            }
        }

        /* Built-in: [obj init] → return self (standard NSObject pattern) */
        if (cstr_eq(sel_name, "init") && target.is_id && receiver != 0) {
            /* Check if receiver is an FDObj: marker for a collection class.
             * If so, create a proper collection marker instead of returning
             * the FDObj: marker. */
            const char *s = (const char *)receiver;
            if (cstr_eq_n(s, "FDObj:", 6)) {
                const char *cls_name = s + 6;
                unsigned int cid = g_next_coll_id++;
                if (cstr_eq(cls_name, "NSMutableArray")) {
                    return value_from_id(coll_make_marker("NSMutArr:", cid));
                }
                if (cstr_eq(cls_name, "NSMutableDictionary")) {
                    return value_from_id(coll_make_marker("NSMutDict:", cid));
                }
                if (cstr_eq(cls_name, "NSArray")) {
                    return value_from_id(coll_make_marker("NSArr:", cid));
                }
                if (cstr_eq(cls_name, "NSDictionary")) {
                    return value_from_id(coll_make_marker("NSDict:", cid));
                }
                if (cstr_eq(cls_name, "NSSet")) {
                    return value_from_id(coll_make_marker("NSSet:", cid));
                }
            }
            return value_from_id(receiver);
        }

        /* Built-in: [obj class] → return the object's class */
        if (cstr_eq(sel_name, "class") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            /* FDObj: markers — return class pointer from variable table */
            if (cstr_starts(s, "FDObj:")) {
                const char *recv_class_name = s + 6;
                unsigned int vi;
                for (vi = 0; vi < g_var_count; vi++) {
                    if (g_vars[vi].is_class && cstr_eq(g_vars[vi].name, recv_class_name)) {
                        return value_from_class(g_vars[vi].cls);
                    }
                }
                return value_from_class((Class)0);
            }
            /* Tagged Foundation string pool objects — return their sentinel class */
            if (cstr_starts(s, "NSNumber:")) return value_from_class((Class)3);
            if (cstr_starts(s, "NSFloat:")) return value_from_class((Class)3);
            if (cstr_starts(s, "NSArr:")) return value_from_class((Class)4);
            if (cstr_starts(s, "NSMutArr:")) return value_from_class((Class)4);
            if (cstr_starts(s, "NSDict:")) return value_from_class((Class)5);
            if (cstr_starts(s, "NSMutDict:")) return value_from_class((Class)5);
            if (cstr_starts(s, "NSSet:")) return value_from_class((Class)6);
            if (cstr_starts(s, "NSData:")) return value_from_class((Class)7);
            if (cstr_starts(s, "NSBlock:")) return value_from_class((Class)8);
            Class cls = (Class)0;
            cls = object_getClass(receiver);
            return value_from_class(cls);
        }

        /* ── Foundation built-in dispatch ────────────────────────────── */

        /* NSObject: [obj description] → class name */
        if (cstr_eq(sel_name, "description") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            /* Check if it's a Foundation class object (FDObj:ClassName) */
            if (cstr_eq_n(s, "FDObj:", 6)) {
                nslog_append("<", 1);
                nslog_append(s + 6, cstr_len(s + 6));
                nslog_append(">", 1);
            } else if (target_class_name) {
                nslog_append("<", 1);
                nslog_append(target_class_name, cstr_len(target_class_name));
                nslog_append(">", 1);
            } else {
                /* For real ObjC objects, try object_getClass.
                 * Guard against string pool pointers. */
                const char *ptr = (const char *)receiver;
                if (ptr >= g_string_pool && ptr < g_string_pool + OBJC_INTERP_STRING_POOL_SIZE) {
                    nslog_append("<unknown>", 9);
                } else {
                    Class cls = object_getClass(receiver);
                    if (cls) {
                        const char *name = class_getName(cls);
                        if (name) {
                            nslog_append("<", 1);
                            nslog_append(name, cstr_len(name));
                            nslog_append(">", 1);
                        }
                    }
                }
            }
            return value_from_id(receiver);
        }

        /* NSObject: [obj isEqual:other] → 1 if same pointer */
        if (cstr_eq(sel_name, "isEqual:") && target.is_id && arg_count >= 1) {
            /* NSData: compare by content (not pointer) */
            if (receiver != 0 && cstr_eq_n((const char *)receiver, "NSData:", 7)) {
                const char *other = (const char *)args[0];
                if (other && cstr_eq_n(other, "NSData:", 7)) {
                    return value_from_int(cstr_eq((const char *)receiver, other) ? 1 : 0);
                }
                return value_from_int(0);
            }
            /* NSNumber: compare by value (not pointer) */
            if (receiver != 0 && (cstr_eq_n((const char *)receiver, "NSNumber:", 9) ||
                                  cstr_eq_n((const char *)receiver, "NSFloat:", 8))) {
                const char *other = (const char *)args[0];
                if (other && (cstr_eq_n(other, "NSNumber:", 9) || cstr_eq_n(other, "NSFloat:", 8))) {
                    return value_from_int(cstr_eq((const char *)receiver, other) ? 1 : 0);
                }
                return value_from_int(0);
            }
            /* Default: pointer comparison */
            int equal = (receiver == args[0]) ? 1 : 0;
            return value_from_int(equal);
        }

        /* NSObject: [obj hash] → pointer as int */
        if (cstr_eq(sel_name, "hash") && target.is_id && receiver != 0) {
            return value_from_int((int)(long)receiver);
        }

        /* NSObject: [obj respondsToSelector:sel] → check if method exists */
        if (cstr_eq(sel_name, "respondsToSelector:") && target.is_id && arg_count >= 1) {
            if (keyword_args[0].is_sel) {
                unsigned int mi;
                for (mi = 0; mi < g_method_count; mi++) {
                    if (g_methods[mi].selector == keyword_args[0].sel_val) {
                        return value_from_int(1);
                    }
                }
            }
            return value_from_int(0);
        }

        /* NSObject: [obj performSelector:sel] → dispatch selector */
        if (cstr_eq(sel_name, "performSelector:") && target.is_id && arg_count >= 1) {
            if (keyword_args[0].is_sel) {
                SEL perf_sel = keyword_args[0].sel_val;
                unsigned int mi;
                int found = 0;
                for (mi = 0; mi < g_method_count; mi++) {
                    if (g_methods[mi].selector == perf_sel && g_methods[mi].source_len > 0 &&
                        !g_methods[mi].is_class_method) {
                        found = 1;
                        break;
                    }
                }
                if (found) {
                    unsigned int saved_var_count = g_var_count;
                    Value return_val;
                    InterpVar *self_var = interp_get_or_create_var("self");
                    if (self_var) { self_var->is_id = 1; self_var->value = receiver; }
                    {
                        InterpVar *cmd_var = interp_get_or_create_var("_cmd");
                        if (cmd_var) { cmd_var->is_sel = 1; cmd_var->sel = perf_sel; }
                    }
                    g_return_pending = 0;
                    {
                        Value v = eval_source_range(0, g_methods[mi].source_len, g_methods[mi].source, 0);
                        (void)v;
                    }
                    return_val = g_return_value;
                    g_var_count = saved_var_count;
                    g_return_pending = 0;
                    return return_val;
                }
            }
            return value_from_id(receiver);
        }

        /* NSString: [NSString stringWithFormat:@"..." args...] */
        if (IS_FOUNDATION_CLASS("NSString") && target.is_class && cstr_eq(sel_name, "stringWithFormat:") && arg_count >= 1) {
            const char *fmt = 0;
            if (keyword_args[0].is_id && keyword_args[0].obj_val != 0) {
                fmt = (const char *)keyword_args[0].obj_val;
            }
            /* Validate format string argument count */
            if (fmt) {
                int format_count = 0, i = 0;
                while (fmt[i] != '\0') {
                    if (fmt[i] == '%' && fmt[i+1] != '\0' && fmt[i+1] != '%') {
                        format_count++;
                        i += 2;
                    } else {
                        i++;
                    }
                }
                int args_available = (int)arg_count - 1;
                if (format_count > args_available) {
                    nslog_append("Warning: stringWithFormat has ", 30);
                    { char buf[12]; int len = 0; int fc = format_count;
                      while (fc > 0 || len == 0) { buf[len++] = '0' + (fc % 10); fc /= 10; }
                      while (len > 0) nslog_append(buf + --len, 1);
                    }
                    nslog_append(" format specifiers but only ", 28);
                    { char buf[12]; int len = 0; int aa = args_available;
                      while (aa > 0 || len == 0) { buf[len++] = '0' + (aa % 10); aa /= 10; }
                      while (len > 0) nslog_append(buf + --len, 1);
                    }
                    nslog_append(" arguments\n", 11);
                }
            }
            return format_values_to_pool(fmt, keyword_args + 1, arg_count - 1);
        }

        /* NSString: [str length] → string length */
        if (cstr_eq(sel_name, "length") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            /* NSData: length = hex_len / 2 */
            if (cstr_eq_n(s, "NSData:", 7)) {
                int hex_len = (int)cstr_len(s + 7);
                return value_from_int(hex_len / 2);
            }
            return value_from_int((int)cstr_len(s));
        }

        /* NSString: [str intValue] → parse as integer */
        if (cstr_eq(sel_name, "intValue") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            int val = 0;
            unsigned int i = 0;
            while (s[i] && (s[i] < '0' || s[i] > '9') && s[i] != '-') i++;
            if (s[i] == '-') { i++; while (s[i] >= '0' && s[i] <= '9') val = val * 10 - (s[i++] - '0'); }
            else { while (s[i] >= '0' && s[i] <= '9') val = val * 10 + (s[i++] - '0'); }
            return value_from_int(val);
        }

        /* NSString: [NSString stringWithString:str] → copy string */
        if (IS_FOUNDATION_CLASS("NSString") && target.is_class && cstr_eq(sel_name, "stringWithString:") && arg_count >= 1) {
            if (keyword_args[0].is_id && keyword_args[0].obj_val != 0) {
                const char *s = (const char *)keyword_args[0].obj_val;
                unsigned int slen = cstr_len(s);
                char *result = string_pool_alloc(slen + 1);
                if (result == 0) return value_from_id(0);
                cstr_copy(result, s, slen + 1);
                return value_from_id((id)result);
            }
            return value_from_id(0);
        }

        /* NSString: [str stringWithString:other] → copy string */
        if (cstr_eq(sel_name, "stringWithString:") && target.is_id && receiver != 0 && arg_count >= 1) {
            if (keyword_args[0].is_id && keyword_args[0].obj_val != 0) {
                const char *s = (const char *)keyword_args[0].obj_val;
                unsigned int slen = cstr_len(s);
                char *result = string_pool_alloc(slen + 1);
                if (result == 0) return value_from_id(receiver);
                cstr_copy(result, s, slen + 1);
                return value_from_id((id)result);
            }
            return value_from_id(receiver);
        }

        /* NSNumber: [num longLongValue] → return long as int */
        if (cstr_eq(sel_name, "longLongValue") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            if (cstr_eq_n(s, "NSNumber:", 9)) {
                int val = 0;
                unsigned int i = 9;
                while (s[i] >= '0' && s[i] <= '9') val = val * 10 + (s[i++] - '0');
                return value_from_int(val);
            }
            return value_from_int(0);
        }

        /* NSString: [str UTF8String] → return self (already C string) */
        if (cstr_eq(sel_name, "UTF8String") && target.is_id && receiver != 0) {
            return value_from_id(receiver);
        }

        /* NSNumber: [num unsignedIntValue] → return unsigned int as int */
        if (cstr_eq(sel_name, "unsignedIntValue") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            if (cstr_eq_n(s, "NSNumber:", 9)) {
                int val = 0;
                unsigned int i = 9;
                while (s[i] >= '0' && s[i] <= '9') val = val * 10 + (s[i++] - '0');
                return value_from_int(val);
            }
            return value_from_int(0);
        }

        /* NSString: [str stringByAppendingString:other] → concatenate */
        if (cstr_eq(sel_name, "stringByAppendingString:") && target.is_id && receiver != 0 && arg_count >= 1) {
            const char *a = (const char *)receiver;
            const char *b = (const char *)args[0];
            unsigned int alen = cstr_len(a);
            unsigned int blen = cstr_len(b);
            char *result;
            unsigned int needed = alen + blen + 1;
            result = string_pool_alloc(needed);
            if (result == 0) return value_from_id(receiver);
            cstr_copy(result, a, needed);
            cstr_copy(result + alen, b, needed - alen);
            return value_from_id((id)result);
        }

        /* NSString: [str stringByAppendingPathComponent:other] → concatenate with / */
        if (cstr_eq(sel_name, "stringByAppendingPathComponent:") && target.is_id && receiver != 0 && arg_count >= 1) {
            const char *a = (const char *)receiver;
            const char *b = (const char *)args[0];
            unsigned int alen = cstr_len(a);
            unsigned int blen = cstr_len(b);
            char *result;
            unsigned int needed = alen + 1 + blen + 1; /* +1 for / separator */
            result = string_pool_alloc(needed);
            if (result == 0) return value_from_id(receiver);
            cstr_copy(result, a, needed);
            result[alen] = '/';
            cstr_copy(result + alen + 1, b, needed - alen - 1);
            return value_from_id((id)result);
        }

        /* NSString: [str capitalizedString] → capitalize first letter of each word */
        if (cstr_eq(sel_name, "capitalizedString") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            int slen = (int)cstr_len(s);
            char *result = string_pool_alloc((unsigned int)slen + 1);
            if (result == 0) return value_from_id(receiver);
            {
                int i = 0;
                int capitalize_next = 1;
                while (i < slen) {
                    char c = s[i];
                    if (capitalize_next && c >= 'a' && c <= 'z') {
                        result[i] = (char)(c - 32);
                    } else {
                        result[i] = c;
                    }
                    capitalize_next = (c == ' ' || c == '\t' || c == '\n' || c == '-');
                    i++;
                }
                result[slen] = '\0';
            }
            return value_from_id((id)result);
        }

        /* NSString: [str isEqualToString:other] → string compare */
        if (cstr_eq(sel_name, "isEqualToString:") && target.is_id && receiver != 0 && arg_count >= 1) {
            const char *a = (const char *)receiver;
            const char *b = (const char *)args[0];
            return value_from_int(cstr_eq(a, b) ? 1 : 0);
        }

        /* NSString: [str substringFromIndex:n] → extract from index to end */
        if (cstr_eq(sel_name, "substringFromIndex:") && target.is_id && receiver != 0 && arg_count >= 1) {
            const char *s = (const char *)receiver;
            int from = keyword_args[0].is_int ? keyword_args[0].int_val : 0;
            int slen = (int)cstr_len(s);
            if (from < 0) from = 0;
            if (from > slen) from = slen;
            {
                unsigned int needed = (unsigned int)(slen - from) + 1;
                char *result = string_pool_alloc(needed);
                if (result == 0) return value_from_id(receiver);
                cstr_copy(result, s + from, needed);
                return value_from_id((id)result);
            }
        }

        /* NSString: [str substringToIndex:n] → extract from start to index */
        if (cstr_eq(sel_name, "substringToIndex:") && target.is_id && receiver != 0 && arg_count >= 1) {
            const char *s = (const char *)receiver;
            int to = keyword_args[0].is_int ? keyword_args[0].int_val : 0;
            int slen = (int)cstr_len(s);
            if (to < 0) to = 0;
            if (to > slen) to = slen;
            {
                unsigned int needed = (unsigned int)to + 1;
                char *result = string_pool_alloc(needed);
                if (result == 0) return value_from_id(receiver);
                cstr_copy(result, s, needed);
                result[to] = '\0';
                return value_from_id((id)result);
            }
        }

        /* NSString: [str characterAtIndex:n] → return character as int */
        if (cstr_eq(sel_name, "characterAtIndex:") && target.is_id && receiver != 0 && arg_count >= 1) {
            const char *s = (const char *)receiver;
            int idx = keyword_args[0].is_int ? keyword_args[0].int_val : 0;
            int slen = (int)cstr_len(s);
            if (idx < 0 || idx >= slen) return value_from_int(0);
            return value_from_int((int)(unsigned char)s[idx]);
        }

        /* NSString: [str hasPrefix:prefix] → check if string starts with prefix */
        if (cstr_eq(sel_name, "hasPrefix:") && target.is_id && receiver != 0 && arg_count >= 1) {
            const char *s = (const char *)receiver;
            const char *prefix = (const char *)keyword_args[0].obj_val;
            int slen = (int)cstr_len(s);
            int plen = (int)cstr_len(prefix);
            if (plen > slen || plen == 0) return value_from_int(plen == 0 ? 1 : 0);
            return value_from_int(cstr_starts(s, prefix) ? 1 : 0);
        }

        /* NSString: [str hasSuffix:suffix] → check if string ends with suffix */
        if (cstr_eq(sel_name, "hasSuffix:") && target.is_id && receiver != 0 && arg_count >= 1) {
            const char *s = (const char *)receiver;
            const char *suffix = (const char *)keyword_args[0].obj_val;
            int slen = (int)cstr_len(s);
            int sfxlen = (int)cstr_len(suffix);
            if (sfxlen > slen || sfxlen == 0) return value_from_int(sfxlen == 0 ? 1 : 0);
            return value_from_int(cstr_eq(s + slen - sfxlen, suffix) ? 1 : 0);
        }

        /* NSString: [str uppercaseString] → ASCII uppercase */
        if (cstr_eq(sel_name, "uppercaseString") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            int slen = (int)cstr_len(s);
            char *result = string_pool_alloc((unsigned int)slen + 1);
            if (result == 0) return value_from_id(receiver);
            {
                int i;
                for (i = 0; i < slen; i++) {
                    char c = s[i];
                    if (c >= 'a' && c <= 'z') c = (char)(c - 32);
                    result[i] = c;
                }
                result[slen] = '\0';
            }
            return value_from_id((id)result);
        }

        /* NSString: [str lowercaseString] → ASCII lowercase */
        if (cstr_eq(sel_name, "lowercaseString") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            int slen = (int)cstr_len(s);
            char *result = string_pool_alloc((unsigned int)slen + 1);
            if (result == 0) return value_from_id(receiver);
            {
                int i;
                for (i = 0; i < slen; i++) {
                    char c = s[i];
                    if (c >= 'A' && c <= 'Z') c = (char)(c + 32);
                    result[i] = c;
                }
                result[slen] = '\0';
            }
            return value_from_id((id)result);
        }

        /* NSString: [str stringByReplacingOccurrencesOfString:find withString:replace]
         * Replace all occurrences of find with replace. */
        if (cstr_eq(sel_name, "stringByReplacingOccurrencesOfString:withString:") && target.is_id && receiver != 0 && arg_count >= 2) {
            const char *src = (const char *)receiver;
            const char *find = (const char *)keyword_args[0].obj_val;
            const char *repl = (const char *)keyword_args[1].obj_val;
            int src_len = (int)cstr_len(src);
            int find_len = (int)cstr_len(find);
            int repl_len = (int)cstr_len(repl);
            if (find_len == 0) return value_from_id(receiver);
            {
                /* Two passes: count matches to size the buffer, then build */
                int match_count = 0;
                int si;
                for (si = 0; si <= src_len - find_len; ) {
                    if (cstr_starts(src + si, find)) {
                        match_count++;
                        si += find_len;
                    } else {
                        si++;
                    }
                }
                /* Calculate needed size carefully to avoid underflow on shrinking replacements */
                int size_delta = match_count * (repl_len - find_len);
                int final_size = src_len + size_delta;
                if (final_size < 0) final_size = 0;
                unsigned int needed = (unsigned int)final_size + 1;
                char *result = string_pool_alloc(needed);
                if (result == 0) return value_from_id(receiver);
                {
                    int ri = 0;
                    si = 0;
                    while (si < src_len) {
                        if (si <= src_len - find_len && cstr_starts(src + si, find)) {
                            int j;
                            for (j = 0; j < repl_len && ri < (int)needed - 1; j++)
                                result[ri++] = repl[j];
                            si += find_len;
                        } else {
                            result[ri++] = src[si++];
                        }
                    }
                    result[ri] = '\0';
                }
                return value_from_id((id)result);
            }
        }

        /* NSString: [str componentsSeparatedByString:sep] → NSArray of components */
        if (cstr_eq(sel_name, "componentsSeparatedByString:") && target.is_id && receiver != 0 && arg_count >= 1) {
            const char *src = (const char *)receiver;
            const char *sep = (const char *)keyword_args[0].obj_val;
            int src_len = (int)cstr_len(src);
            int sep_len = (int)cstr_len(sep);
            unsigned int new_cid = g_next_coll_id++;
            Value dummy = value_void();
            if (sep_len == 0) {
                /* Empty separator: each char is a component */
                int i;
                for (i = 0; i < src_len; i++) {
                    char *comp = string_pool_alloc(2);
                    if (comp == 0) {
                        coll_remove_all(new_cid);
                        interp_set_resource_error("string pool exhausted while splitting string");
                        return value_void();
                    }
                    comp[0] = src[i];
                    comp[1] = '\0';
                    if (coll_add(new_cid, value_from_id((id)comp), dummy) != 0) {
                        coll_remove_all(new_cid);
                        interp_set_resource_error("collection entry table full while splitting string");
                        return value_void();
                    }
                }
            } else {
                int start = 0;
                int si;
                for (si = 0; si <= src_len; ) {
                    if (si <= src_len - sep_len && cstr_starts(src + si, sep)) {
                        /* Component from start to si */
                        int comp_len = si - start;
                        char *comp = string_pool_alloc((unsigned int)comp_len + 1);
                        if (comp == 0) {
                            coll_remove_all(new_cid);
                            interp_set_resource_error("string pool exhausted while splitting string");
                            return value_void();
                        }
                        {
                            int j;
                            for (j = 0; j < comp_len; j++) comp[j] = src[start + j];
                            comp[comp_len] = '\0';
                        }
                        if (coll_add(new_cid, value_from_id((id)comp), dummy) != 0) {
                            coll_remove_all(new_cid);
                            interp_set_resource_error("collection entry table full while splitting string");
                            return value_void();
                        }
                        si += sep_len;
                        start = si;
                    } else {
                        si++;
                    }
                }
                /* Last component */
                {
                    int comp_len = src_len - start;
                    char *comp = string_pool_alloc((unsigned int)comp_len + 1);
                    if (comp == 0) {
                        coll_remove_all(new_cid);
                        interp_set_resource_error("string pool exhausted while splitting string");
                        return value_void();
                    }
                    {
                        int j;
                        for (j = 0; j < comp_len; j++) comp[j] = src[start + j];
                        comp[comp_len] = '\0';
                    }
                    if (coll_add(new_cid, value_from_id((id)comp), dummy) != 0) {
                        coll_remove_all(new_cid);
                        interp_set_resource_error("collection entry table full while splitting string");
                        return value_void();
                    }
                }
            }
            return value_from_id(coll_make_marker("NSArr:", new_cid));
        }

        /* NSString: [str stringByTrimmingWhitespace] → trim leading/trailing whitespace
         * Convenience method (not a real ObjC API — that uses
         * stringByTrimmingCharactersInSet: which needs NSCharacterSet). */
        if (cstr_eq(sel_name, "stringByTrimmingWhitespace") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            int slen = (int)cstr_len(s);
            int start = 0, end = slen;
            while (start < end && (s[start] == ' ' || s[start] == '\t' || s[start] == '\n' || s[start] == '\r'))
                start++;
            while (end > start && (s[end-1] == ' ' || s[end-1] == '\t' || s[end-1] == '\n' || s[end-1] == '\r'))
                end--;
            {
                int comp_len = end - start;
                unsigned int needed = (unsigned int)comp_len + 1;
                char *result = string_pool_alloc(needed);
                if (result == 0) return value_from_id(receiver);
                {
                    int i;
                    for (i = 0; i < comp_len; i++) result[i] = s[start + i];
                    result[comp_len] = '\0';
                }
                return value_from_id((id)result);
            }
        }

        /* NSNumber: [NSNumber numberWithInt:n] → wrap int as id */
        if (IS_FOUNDATION_CLASS("NSNumber") && target.is_class && cstr_eq(sel_name, "numberWithInt:") && arg_count >= 1) {
            /* Store the int value in a string pool buffer.
             * Encoding: "NSNumber:<int_value>" */
            if (keyword_args[0].is_int) {
                char *buf;
                int v = keyword_args[0].int_val;
                int neg = v < 0;
                unsigned int pos = 9; /* after "NSNumber:" */
                buf = string_pool_alloc(30);
                if (buf == 0) return value_from_int(keyword_args[0].int_val);
                cstr_copy(buf, "NSNumber:", 30);
                if (neg) { v = -v; buf[pos++] = '-'; }
                if (v == 0) { buf[pos++] = '0'; }
                else {
                    char tmp[12];
                    int ti = 0;
                    while (v > 0) { tmp[ti++] = '0' + (v % 10); v /= 10; }
                    while (ti > 0) buf[pos++] = tmp[--ti];
                }
                buf[pos] = '\0';
                return value_from_id((id)buf);
            }
            return value_from_id(args[0]);
        }

        /* NSNumber: [NSNumber numberWithUnsignedInt:n] → wrap unsigned int */
        if (IS_FOUNDATION_CLASS("NSNumber") && target.is_class && cstr_eq(sel_name, "numberWithUnsignedInt:") && arg_count >= 1) {
            if (keyword_args[0].is_int) {
                char *buf = string_pool_alloc(30);
                unsigned int pos = 9;
                unsigned int v = (unsigned int)keyword_args[0].int_val;
                buf = string_pool_alloc(30);
                if (buf == 0) return value_from_int(keyword_args[0].int_val);
                cstr_copy(buf, "NSNumber:", 30);
                if (v == 0) { buf[pos++] = '0'; }
                else {
                    char tmp[12];
                    int ti = 0;
                    while (v > 0) { tmp[ti++] = '0' + (v % 10); v /= 10; }
                    while (ti > 0) buf[pos++] = tmp[--ti];
                }
                buf[pos] = '\0';
                return value_from_id((id)buf);
            }
            return value_from_id(args[0]);
        }

        /* NSNumber: [NSNumber numberWithLong:n] → wrap long as id */
        if (IS_FOUNDATION_CLASS("NSNumber") && target.is_class && cstr_eq(sel_name, "numberWithLong:") && arg_count >= 1) {
            if (keyword_args[0].is_int) {
                return value_from_id(args[0]); /* Same as numberWithInt: for interpreter */
            }
            return value_from_id(args[0]);
        }

        /* NSNumber: [NSNumber numberWithInteger:n] → wrap NSInteger as id */
        if (IS_FOUNDATION_CLASS("NSNumber") && target.is_class && cstr_eq(sel_name, "numberWithInteger:") && arg_count >= 1) {
            if (keyword_args[0].is_int) {
                return value_from_id(args[0]); /* Same as numberWithInt: for interpreter */
            }
            return value_from_id(args[0]);
        }

        /* NSNumber: [num intValue] → unwrap int from NSNumber encoding */
        if (cstr_eq(sel_name, "intValue") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            if (cstr_eq_n(s, "NSNumber:", 9)) {
                int val = 0;
                unsigned int i = 9;
                int neg = 0;
                if (s[i] == '-') { neg = 1; i++; }
                while (s[i] >= '0' && s[i] <= '9') val = val * 10 + (s[i++] - '0');
                return value_from_int(neg ? -val : val);
            }
            return value_from_int(0);
        }

        /* NSNumber: [num boolValue] → 1 if non-zero */
        if (cstr_eq(sel_name, "boolValue") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            if (cstr_eq_n(s, "NSNumber:", 9)) {
                int val = 0;
                unsigned int i = 9;
                while (s[i] >= '0' && s[i] <= '9') val = val * 10 + (s[i++] - '0');
                return value_from_int(val ? 1 : 0);
            }
            return value_from_int(0);
        }

        /* NSNumber: [num description] → numeric string */
        if (cstr_eq(sel_name, "description") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            /* NSData: display as <hex bytes> */
            if (cstr_eq_n(s, "NSData:", 7)) {
                const char *hex = s + 7;
                int hex_len = (int)cstr_len(hex);
                unsigned int needed = 2 + (unsigned int)hex_len + (unsigned int)(hex_len / 8) + 1;
                char *result = string_pool_alloc(needed);
                if (result) {
                    int ri = 0, i;
                    result[ri++] = '<';
                    for (i = 0; i < hex_len; i++) {
                        if (i > 0 && i % 8 == 0) result[ri++] = ' ';
                        result[ri++] = hex[i];
                    }
                    result[ri++] = '>';
                    result[ri] = '\0';
                    return value_from_id((id)result);
                }
            }
            /* NSNumber: display numeric value */
            if (cstr_eq_n(s, "NSNumber:", 9)) {
                nslog_append(s + 9, cstr_len(s + 9));
            }
            /* NSFloat: display float value */
            if (cstr_eq_n(s, "NSFloat:", 8)) {
                nslog_append(s + 8, cstr_len(s + 8));
            }
            return value_from_id(receiver);
        }

        /* NSNumber: [NSNumber numberWithFloat:f] → wrap float as id */
        if (IS_FOUNDATION_CLASS("NSNumber") && target.is_class && cstr_eq(sel_name, "numberWithFloat:") && arg_count >= 1) {
            if (keyword_args[0].is_float) {
                char *buf = string_pool_alloc(64);
                if (buf == 0) return value_from_float(keyword_args[0].float_val);
                cstr_copy(buf, "NSFloat:", 64);
                {
                    double fv = keyword_args[0].float_val;
                    int neg = fv < 0.0;
                    unsigned int pos = 8;
                    if (neg) { fv = -fv; buf[pos++] = '-'; }
                    unsigned long ipart = (unsigned long)fv;
                    double fpart = fv - (double)ipart;
                    if (ipart == 0) { buf[pos++] = '0'; }
                    else {
                        char tmp[20]; int ti = 0;
                        while (ipart > 0) { tmp[ti++] = '0' + (ipart % 10); ipart /= 10; }
                        while (ti > 0) buf[pos++] = tmp[--ti];
                    }
                    buf[pos++] = '.';
                    for (int d = 0; d < 6 && pos < 60; d++) {
                        fpart *= 10.0; int digit = (int)fpart;
                        buf[pos++] = '0' + digit; fpart -= digit;
                    }
                    /* Trim trailing zeros */
                    while (pos > 0 && buf[pos-1] == '0') pos--;
                    if (buf[pos-1] == '.') pos++; /* keep at least one decimal */
                    buf[pos] = '\0';
                }
                return value_from_id((id)buf);
            }
            return value_from_id(args[0]);
        }

        /* NSNumber: [NSNumber numberWithDouble:d] → wrap double as id */
        if (IS_FOUNDATION_CLASS("NSNumber") && target.is_class && cstr_eq(sel_name, "numberWithDouble:") && arg_count >= 1) {
            /* Same encoding as numberWithFloat */
            if (keyword_args[0].is_float) {
                char *buf = string_pool_alloc(64);
                if (buf == 0) return value_from_float(keyword_args[0].float_val);
                cstr_copy(buf, "NSFloat:", 64);
                {
                    double fv = keyword_args[0].float_val;
                    int neg = fv < 0.0;
                    unsigned int pos = 8;
                    if (neg) { fv = -fv; buf[pos++] = '-'; }
                    unsigned long ipart = (unsigned long)fv;
                    double fpart = fv - (double)ipart;
                    if (ipart == 0) { buf[pos++] = '0'; }
                    else {
                        char tmp[20]; int ti = 0;
                        while (ipart > 0) { tmp[ti++] = '0' + (ipart % 10); ipart /= 10; }
                        while (ti > 0) buf[pos++] = tmp[--ti];
                    }
                    buf[pos++] = '.';
                    for (int d = 0; d < 6 && pos < 60; d++) {
                        fpart *= 10.0; int digit = (int)fpart;
                        buf[pos++] = '0' + digit; fpart -= digit;
                    }
                    while (pos > 0 && buf[pos-1] == '0') pos--;
                    if (buf[pos-1] == '.') pos++;
                    buf[pos] = '\0';
                }
                return value_from_id((id)buf);
            }
            return value_from_id(args[0]);
        }

        /* NSNumber: [num floatValue] → unwrap float from NSFloat encoding */
        if (cstr_eq(sel_name, "floatValue") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            if (cstr_eq_n(s, "NSFloat:", 8)) {
                double val = 0.0;
                unsigned int i = 8;
                int neg = 0;
                if (s[i] == '-') { neg = 1; i++; }
                while (s[i] >= '0' && s[i] <= '9') val = val * 10.0 + (s[i++] - '0');
                if (s[i] == '.') {
                    double frac = 0.1;
                    i++;
                    while (s[i] >= '0' && s[i] <= '9') {
                        val += (s[i] - '0') * frac;
                        frac *= 0.1;
                        i++;
                    }
                }
                return value_from_float(neg ? -val : val);
            }
            return value_from_float(0.0);
        }

        /* NSNumber: [num doubleValue] → unwrap double from NSFloat encoding */
        if (cstr_eq(sel_name, "doubleValue") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            if (cstr_eq_n(s, "NSFloat:", 8)) {
                double val = 0.0;
                unsigned int i = 8;
                int neg = 0;
                if (s[i] == '-') { neg = 1; i++; }
                while (s[i] >= '0' && s[i] <= '9') val = val * 10.0 + (s[i++] - '0');
                if (s[i] == '.') {
                    double frac = 0.1;
                    i++;
                    while (s[i] >= '0' && s[i] <= '9') {
                        val += (s[i] - '0') * frac;
                        frac *= 0.1;
                        i++;
                    }
                }
                return value_from_float(neg ? -val : val);
            }
            return value_from_float(0.0);
        }

        /* NSNumber: [NSNumber numberWithBool:b] → wrap bool as NSNumber */
        if (IS_FOUNDATION_CLASS("NSNumber") && target.is_class && cstr_eq(sel_name, "numberWithBool:") && arg_count >= 1) {
            /* Convert argument to boolean using is_truthy for all value types */
            int v = is_truthy(keyword_args[0]) ? 1 : 0;
            char *buf = string_pool_alloc(14);
            if (buf == 0) return value_from_int(v);
            cstr_copy(buf, "NSNumber:", 14);
            buf[9] = '0' + v;
            buf[10] = '\0';
            return value_from_id((id)buf);
        }

        /* NSNumber: [num stringValue] → numeric string representation */
        if (cstr_eq(sel_name, "stringValue") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            if (cstr_eq_n(s, "NSNumber:", 9)) {
                unsigned int vlen = (unsigned int)cstr_len(s + 9);
                char *result = string_pool_alloc(vlen + 1);
                if (result == 0) return value_from_id(receiver);
                cstr_copy(result, s + 9, vlen + 1);
                return value_from_id((id)result);
            }
            if (cstr_eq_n(s, "NSFloat:", 8)) {
                unsigned int vlen = (unsigned int)cstr_len(s + 8);
                char *result = string_pool_alloc(vlen + 1);
                if (result == 0) return value_from_id(receiver);
                cstr_copy(result, s + 8, vlen + 1);
                return value_from_id((id)result);
            }
            return value_from_id(receiver);
        }

        /* NSNumber: [num longValue] → alias for intValue */
        if (cstr_eq(sel_name, "longValue") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            if (cstr_eq_n(s, "NSNumber:", 9)) {
                int val = 0;
                unsigned int i = 9;
                int neg = 0;
                if (s[i] == '-') { neg = 1; i++; }
                while (s[i] >= '0' && s[i] <= '9') val = val * 10 + (s[i++] - '0');
                return value_from_int(neg ? -val : val);
            }
            return value_from_int(0);
        }

        /* ── NSData dispatch ──────────────────────────────────────── */

        /* NSData: [NSData data] → empty data */
        if (IS_FOUNDATION_CLASS("NSData") && target.is_class && cstr_eq(sel_name, "data") && arg_count == 0) {
            char *buf = string_pool_alloc(8);
            if (buf == 0) return value_from_id((id)"NSData:");
            cstr_copy(buf, "NSData:", 8);
            return value_from_id((id)buf);
        }

        /* NSData: [NSData dataWithBytes:ptr length:len] → create from string bytes
         * Since we don't have real byte pointers, we accept a string (treating
         * each char as a byte) and encode as "NSData:<hex>". */
        if (IS_FOUNDATION_CLASS("NSData") && target.is_class && cstr_eq(sel_name, "dataWithBytes:length:") && arg_count >= 2) {
            const char *bytes = (const char *)keyword_args[0].obj_val;
            int len = keyword_args[1].is_int ? keyword_args[1].int_val : 0;
            if (len < 0) len = 0;
            {
                int blen = (int)cstr_len(bytes);
                if (len > blen) len = blen;
                /* Hex encoding: 2 chars per byte + "NSData:" prefix */
                unsigned int needed = 7 + (unsigned int)len * 2 + 1;
                char *buf = string_pool_alloc(needed);
                if (buf == 0) return value_from_id((id)"NSData:");
                cstr_copy(buf, "NSData:", needed);
                {
                    static const char hex_chars[] = "0123456789abcdef";
                    int i;
                    for (i = 0; i < len; i++) {
                        unsigned char c = (unsigned char)bytes[i];
                        buf[7 + i * 2] = hex_chars[(c >> 4) & 0x0f];
                        buf[7 + i * 2 + 1] = hex_chars[c & 0x0f];
                    }
                    buf[7 + len * 2] = '\0';
                }
                return value_from_id((id)buf);
            }
        }

        /* NSData instance methods — check for NSData: prefix on receiver */
        if (target.is_id && receiver != 0 && cstr_eq_n((const char *)receiver, "NSData:", 7)) {
            const char *s = (const char *)receiver;

            /* [data bytes] → decode hex back to raw bytes (as string) */
            if (cstr_eq(sel_name, "bytes")) {
                const char *hex = s + 7;
                int hex_len = (int)cstr_len(hex);
                int byte_len = hex_len / 2;
                char *result = string_pool_alloc((unsigned int)byte_len + 1);
                if (result == 0) return value_from_id(receiver);
                {
                    static const char hex_vals[] = "0123456789abcdef";
                    int i;
                    for (i = 0; i < byte_len; i++) {
                        char hi = hex[i * 2];
                        char lo = hex[i * 2 + 1];
                        int hi_val = 0, lo_val = 0, j;
                        for (j = 0; j < 16; j++) {
                            if (hi == hex_vals[j] || hi == hex_vals[j] - 32) hi_val = j;
                            if (lo == hex_vals[j] || lo == hex_vals[j] - 32) lo_val = j;
                        }
                        result[i] = (char)((hi_val << 4) | lo_val);
                    }
                    result[byte_len] = '\0';
                }
                return value_from_id((id)result);
            }

            /* [data description] → display as <hex bytes> */
            if (cstr_eq(sel_name, "description")) {
                const char *hex = s + 7;
                int hex_len = (int)cstr_len(hex);
                /* Format: <xxxx xxxx ...> with spaces every 8 hex chars */
                unsigned int needed = 2 + (unsigned int)hex_len + (unsigned int)(hex_len / 8) + 1;
                char *result = string_pool_alloc(needed);
                if (result == 0) return value_from_id(receiver);
                {
                    int ri = 0;
                    int i;
                    result[ri++] = '<';
                    for (i = 0; i < hex_len; i++) {
                        if (i > 0 && i % 8 == 0) result[ri++] = ' ';
                        result[ri++] = hex[i];
                    }
                    result[ri++] = '>';
                    result[ri] = '\0';
                }
                return value_from_id((id)result);
            }

            /* [data isEqual:other] → compare data */
            if (cstr_eq(sel_name, "isEqual:") && arg_count >= 1) {
                const char *other = (const char *)keyword_args[0].obj_val;
                if (other && cstr_eq_n(other, "NSData:", 7)) {
                    return value_from_int(cstr_eq(s, other) ? 1 : 0);
                }
                return value_from_int(0);
            }

            /* [data isEqualToData:other] → compare data */
            if (cstr_eq(sel_name, "isEqualToData:") && arg_count >= 1) {
                const char *other = (const char *)keyword_args[0].obj_val;
                if (other && cstr_eq_n(other, "NSData:", 7)) {
                    return value_from_int(cstr_eq(s, other) ? 1 : 0);
                }
                return value_from_int(0);
            }

            /* [data subdataWithRange:] — needs NSRange, deferred */
        }

        /* ── Foundation collection dispatch ──────────────────────── */

        /* NSArray: [NSArray array] → empty immutable array */
        if (IS_FOUNDATION_CLASS("NSArray") && target.is_class && cstr_eq(sel_name, "array") && arg_count == 0) {
            unsigned int cid = g_next_coll_id++;
            return value_from_id(coll_make_marker("NSArr:", cid));
        }

        /* NSMutableArray: [NSMutableArray arrayWithCapacity:n] → empty mutable array */
        if (IS_FOUNDATION_CLASS("NSMutableArray") && target.is_class && cstr_eq(sel_name, "arrayWithCapacity:") && arg_count >= 1) {
            unsigned int cid = g_next_coll_id++;
            return value_from_id(coll_make_marker("NSMutArr:", cid));
        }

        /* NSMutableArray: [NSMutableArray array] → empty mutable array */
        if (IS_FOUNDATION_CLASS("NSMutableArray") && target.is_class && cstr_eq(sel_name, "array") && arg_count == 0) {
            unsigned int cid = g_next_coll_id++;
            return value_from_id(coll_make_marker("NSMutArr:", cid));
        }

        /* NSDictionary: [NSDictionary dictionary] → empty immutable dict */
        if (IS_FOUNDATION_CLASS("NSDictionary") && target.is_class && cstr_eq(sel_name, "dictionary") && arg_count == 0) {
            unsigned int cid = g_next_coll_id++;
            return value_from_id(coll_make_marker("NSDict:", cid));
        }

        /* NSMutableDictionary: [NSMutableDictionary dictionaryWithCapacity:n] → empty mutable dict */
        if (IS_FOUNDATION_CLASS("NSMutableDictionary") && target.is_class && cstr_eq(sel_name, "dictionaryWithCapacity:") && arg_count >= 1) {
            unsigned int cid = g_next_coll_id++;
            return value_from_id(coll_make_marker("NSMutDict:", cid));
        }

        /* NSMutableDictionary: [NSMutableDictionary dictionary] → empty mutable dict */
        if (IS_FOUNDATION_CLASS("NSMutableDictionary") && target.is_class && cstr_eq(sel_name, "dictionary") && arg_count == 0) {
            unsigned int cid = g_next_coll_id++;
            return value_from_id(coll_make_marker("NSMutDict:", cid));
        }

        /* NSDictionary: [NSDictionary dictionaryWithObject:obj forKey:key] → dict with one entry */
        if (IS_FOUNDATION_CLASS("NSDictionary") && target.is_class && cstr_eq(sel_name, "dictionaryWithObject:forKey:") && arg_count >= 2) {
            unsigned int cid = g_next_coll_id++;
            coll_add(cid, keyword_args[1], keyword_args[0]); /* key, value */
            return value_from_id(coll_make_marker("NSDict:", cid));
        }

        /* NSSet: [NSSet setWithArray:arr] → set from array */
        if (IS_FOUNDATION_CLASS("NSSet") && target.is_class && cstr_eq(sel_name, "setWithArray:") && arg_count >= 1) {
            unsigned int cid = g_next_coll_id++;
            const char *arr_s = (const char *)keyword_args[0].obj_val;
            unsigned int arr_cid = coll_id_from_marker(arr_s, "NSArr:");
            if (arr_cid == 0) arr_cid = coll_id_from_marker(arr_s, "NSMutArr:");
            if (arr_cid > 0) {
                /* Copy unique elements from array to set */
                unsigned int i;
                for (i = 0; i < g_coll_entry_count; i++) {
                    if (g_coll_entries[i].coll_id == arr_cid) {
                        /* Check if already in set */
                        int existing = coll_find_by_key(cid, &g_coll_entries[i].key);
                        if (existing < 0) {
                            coll_add(cid, g_coll_entries[i].key, g_coll_entries[i].value);
                        }
                    }
                }
            }
            return value_from_id(coll_make_marker("NSSet:", cid));
        }

        /* ── Instance method dispatch on collection objects ────── */

        {
            unsigned int cid = 0;
            const char *s = (const char *)receiver;

            /* Try to identify the collection type and ID */
            if (target.is_id && receiver != 0) {
                cid = coll_id_from_marker(s, "NSArr:");
                if (cid == 0) cid = coll_id_from_marker(s, "NSMutArr:");
                if (cid == 0) cid = coll_id_from_marker(s, "NSDict:");
                if (cid == 0) cid = coll_id_from_marker(s, "NSMutDict:");
                if (cid == 0) cid = coll_id_from_marker(s, "NSSet:");
            }

            if (cid > 0) {
                /* [coll count] → number of entries */
                if (cstr_eq(sel_name, "count")) {
                    return value_from_int((int)coll_count(cid));
                }

                /* [arr objectAtIndex:i] → element at index */
                if (cstr_eq(sel_name, "objectAtIndex:") && arg_count >= 1 && keyword_args[0].is_int) {
                    int idx = coll_get_nth(cid, (unsigned int)keyword_args[0].int_val);
                    if (idx >= 0) {
                        return g_coll_entries[idx].key;
                    }
                    return value_from_id((id)"(nil)");
                }

                /* [mutArr addObject:obj] → append element */
                if (cstr_eq(sel_name, "addObject:") && arg_count >= 1) {
                    Value elem = keyword_args[0];
                    Value dummy = value_void();
                    if (coll_add(cid, elem, dummy) != 0) {
                        nslog_append("warning: collection entry table full\n", 38);
                    }
                    return value_from_id(receiver);
                }

                /* [mutArr removeLastObject] → remove last element */
                if (cstr_eq(sel_name, "removeLastObject")) {
                    unsigned int cnt = coll_count(cid);
                    if (cnt > 0) {
                        int idx = coll_get_nth(cid, cnt - 1);
                        if (idx >= 0) coll_remove_at((unsigned int)idx);
                    }
                    return value_from_id(receiver);
                }

                /* [mutArr replaceObjectAtIndex:n withObject:obj] → replace element */
                if (cstr_eq(sel_name, "replaceObjectAtIndex:withObject:") && arg_count >= 2) {
                    int idx = coll_get_nth(cid, (unsigned int)keyword_args[0].int_val);
                    if (idx >= 0) {
                        g_coll_entries[(unsigned int)idx].key = keyword_args[1];
                    }
                    return value_from_id(receiver);
                }

                /* [mutArr insertObject:obj atIndex:n] → insert element at index */
                if (cstr_eq(sel_name, "insertObject:atIndex:") && arg_count >= 2) {
                    Value dummy = value_void();
                    coll_insert_at(cid, (unsigned int)keyword_args[1].int_val, keyword_args[0], dummy);
                    return value_from_id(receiver);
                }

                /* [mutArr removeObjectAtIndex:n] → remove element at index */
                if (cstr_eq(sel_name, "removeObjectAtIndex:") && arg_count >= 1) {
                    int idx = coll_get_nth(cid, (unsigned int)keyword_args[0].int_val);
                    if (idx >= 0) coll_remove_at((unsigned int)idx);
                    return value_from_id(receiver);
                }

                /* [arr indexOfObject:obj] → find index of object */
                if (cstr_eq(sel_name, "indexOfObject:") && arg_count >= 1) {
                    unsigned int i, pos = 0;
                    for (i = 0; i < g_coll_entry_count; i++) {
                        if (g_coll_entries[i].coll_id != cid) continue;
                        if (g_coll_entries[i].key.is_int && keyword_args[0].is_int &&
                            g_coll_entries[i].key.int_val == keyword_args[0].int_val) {
                            return value_from_int((int)pos);
                        }
                        if (g_coll_entries[i].key.is_id && keyword_args[0].is_id &&
                            g_coll_entries[i].key.obj_val != 0 && keyword_args[0].obj_val != 0 &&
                            cstr_eq((const char *)g_coll_entries[i].key.obj_val,
                                    (const char *)keyword_args[0].obj_val)) {
                            return value_from_int((int)pos);
                        }
                        pos++;
                    }
                    return value_from_int(-1); /* NSNotFound */
                }

                /* [dict objectForKey:key] → value for key */
                if (cstr_eq(sel_name, "objectForKey:") && arg_count >= 1) {
                    int idx = coll_find_by_key(cid, &keyword_args[0]);
                    if (idx >= 0) return g_coll_entries[idx].value;
                    return value_from_id((id)"(nil)");
                }

                /* [mutDict setObject:obj forKey:key] → set key-value */
                if (cstr_eq(sel_name, "setObject:forKey:") && arg_count >= 2) {
                    Value val = keyword_args[0];  /* first arg after setObject: */
                    Value key = keyword_args[1];   /* second arg after forKey: */
                    int idx = coll_find_by_key(cid, &key);
                    if (idx >= 0) {
                        g_coll_entries[idx].value = val;
                    } else {
                        if (coll_add(cid, key, val) != 0) {
                            nslog_append("warning: collection entry table full\n", 38);
                        }
                    }
                    return value_from_id(receiver);
                }

                /* [mutDict removeObjectForKey:key] → remove entry */
                if (cstr_eq(sel_name, "removeObjectForKey:") && arg_count >= 1) {
                    int idx = coll_find_by_key(cid, &keyword_args[0]);
                    if (idx >= 0) coll_remove_at((unsigned int)idx);
                    return value_from_id(receiver);
                }

                /* [dict allKeys] → array of keys */
                if (cstr_eq(sel_name, "allKeys")) {
                    unsigned int new_cid = g_next_coll_id++;
                    unsigned int i;
                    for (i = 0; i < g_coll_entry_count; i++) {
                        if (g_coll_entries[i].coll_id == cid) {
                            Value dummy = value_void();
                            coll_add(new_cid, g_coll_entries[i].key, dummy);
                        }
                    }
                    return value_from_id(coll_make_marker("NSArr:", new_cid));
                }

                /* [set containsObject:obj] → BOOL */
                if (cstr_eq(sel_name, "containsObject:") && arg_count >= 1) {
                    int idx = coll_find_by_key(cid, &keyword_args[0]);
                    return value_from_int(idx >= 0 ? 1 : 0);
                }

                /* [dict setObject:forKey: — alternate keyword arg parsing
                 * The selector "setObject:forKey:" has two keyword parts.
                 * keyword_args[0] is the object, keyword_args[1] is the key.
                 * This is already handled above. */

                /* [mutColl removeAllObjects] → remove all entries */
                if (cstr_eq(sel_name, "removeAllObjects")) {
                    coll_remove_all(cid);
                    return value_from_id(receiver);
                }

                /* [dict allValues] → array of values */
                if (cstr_eq(sel_name, "allValues")) {
                    unsigned int new_cid = g_next_coll_id++;
                    unsigned int i;
                    for (i = 0; i < g_coll_entry_count; i++) {
                        if (g_coll_entries[i].coll_id == cid) {
                            Value dummy = value_void();
                            coll_add(new_cid, g_coll_entries[i].value, dummy);
                        }
                    }
                    return value_from_id(coll_make_marker("NSArr:", new_cid));
                }

                /* [dict isEqualToDictionary:other] → compare dicts */
                if (cstr_eq(sel_name, "isEqualToDictionary:") && arg_count >= 1) {
                    const char *other_s = (const char *)keyword_args[0].obj_val;
                    unsigned int other_cid = coll_id_from_marker(other_s, "NSDict:");
                    if (other_cid == 0) other_cid = coll_id_from_marker(other_s, "NSMutDict:");
                    if (other_cid == 0) return value_from_int(0);
                    {
                        unsigned int my_count = coll_count(cid);
                        unsigned int other_count = coll_count(other_cid);
                        if (my_count != other_count) return value_from_int(0);
                        /* Check all keys in self exist in other with same value */
                        unsigned int i;
                        for (i = 0; i < g_coll_entry_count; i++) {
                            if (g_coll_entries[i].coll_id == cid) {
                                int other_idx = coll_find_by_key(other_cid, &g_coll_entries[i].key);
                                if (other_idx < 0) return value_from_int(0);
                                /* Compare values — both are Values, check fields */
                                if (g_coll_entries[i].value.is_int != g_coll_entries[other_idx].value.is_int ||
                                    g_coll_entries[i].value.is_id != g_coll_entries[other_idx].value.is_id ||
                                    g_coll_entries[i].value.is_float != g_coll_entries[other_idx].value.is_float)
                                    return value_from_int(0);
                                if (g_coll_entries[i].value.is_int && g_coll_entries[i].value.int_val != g_coll_entries[other_idx].value.int_val)
                                    return value_from_int(0);
                                if (g_coll_entries[i].value.is_float && g_coll_entries[i].value.float_val != g_coll_entries[other_idx].value.float_val)
                                    return value_from_int(0);
                                if (g_coll_entries[i].value.is_id) {
                                    const char *a = (const char *)g_coll_entries[i].value.obj_val;
                                    const char *b = (const char *)g_coll_entries[other_idx].value.obj_val;
                                    if (a == 0 || b == 0) { if (a != b) return value_from_int(0); }
                                    else if (!cstr_eq(a, b)) return value_from_int(0);
                                }
                            }
                        }
                        return value_from_int(1);
                    }
                }

                /* [arr lastObject] → last element or nil */
                if (cstr_eq(sel_name, "lastObject")) {
                    unsigned int cnt = coll_count(cid);
                    if (cnt > 0) {
                        int idx = coll_get_nth(cid, cnt - 1);
                        if (idx >= 0) return g_coll_entries[idx].key;
                    }
                    return value_from_id((id)0);
                }

                /* [arr firstObject] → first element or nil */
                if (cstr_eq(sel_name, "firstObject")) {
                    if (coll_count(cid) > 0) {
                        int idx = coll_get_nth(cid, 0);
                        if (idx >= 0) return g_coll_entries[idx].key;
                    }
                    return value_from_id((id)0);
                }

                /* [arr arrayByAddingObject:obj] → new array with object appended */
                if (cstr_eq(sel_name, "arrayByAddingObject:") && arg_count >= 1) {
                    unsigned int new_cid = g_next_coll_id++;
                    unsigned int i;
                    for (i = 0; i < g_coll_entry_count; i++) {
                        if (g_coll_entries[i].coll_id == cid) {
                            coll_add(new_cid, g_coll_entries[i].key, g_coll_entries[i].value);
                        }
                    }
                    coll_add(new_cid, keyword_args[0], value_void());
                    return value_from_id(coll_make_marker("NSArr:", new_cid));
                }
                }

                /* [dict valueForKey:key] → same as objectForKey: */
                if (cstr_eq(sel_name, "valueForKey:") && arg_count >= 1) {
                    int idx = coll_find_by_key(cid, &keyword_args[0]);
                    if (idx >= 0) return g_coll_entries[idx].value;
                    return value_from_id((id)"(nil)");
                }

                /* [mutDict setValue:val forKey:key] → same as setObject:forKey: */
                if (cstr_eq(sel_name, "setValue:forKey:") && arg_count >= 2) {
                    Value val = keyword_args[0];
                    Value key = keyword_args[1];
                    int idx = coll_find_by_key(cid, &key);
                    if (idx >= 0) {
                        g_coll_entries[idx].value = val;
                    } else {
                        if (coll_add(cid, key, val) != 0) {
                            nslog_append("warning: collection entry table full\n", 38);
                        }
                    }
                    return value_from_id(receiver);
                }

                /* [arr enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) { ... }]
                 * The block argument is a block marker. We iterate the collection
                 * and invoke the block for each element. */
                if (cstr_eq(sel_name, "enumerateObjectsUsingBlock:") && arg_count >= 1) {
                    const char *blk_marker = (const char *)keyword_args[0].obj_val;
                    unsigned int bid = block_id_from_marker(blk_marker);
                    BlockImpl *blk = block_get(bid);
                    if (blk) {
                        unsigned int cnt = coll_count(cid);
                        unsigned int idx;
                        unsigned int saved_var_count = g_var_count;
                        for (idx = 0; idx < cnt; idx++) {
                            int entry_idx = coll_get_nth(cid, idx);
                            if (entry_idx < 0) break;

                            /* Restore captured variable values FIRST */
                            {
                                unsigned int ci;
                                for (ci = 0; ci < blk->capture_count; ci++) {
                                    InterpVar *cap_var = interp_get_or_create_var(blk->captures[ci].name);
                                    if (cap_var) {
                                        if (blk->captures[ci].is_by_ref) {
                                            /* __block: read from original variable slot */
                                            unsigned int vi = blk->captures[ci].var_index;
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
                                            cap_var->is_id = blk->captures[ci].value.is_id;
                                            cap_var->value = blk->captures[ci].value.obj_val;
                                            cap_var->is_int = blk->captures[ci].value.is_int;
                                            cap_var->int_value = blk->captures[ci].value.int_val;
                                            cap_var->is_float = blk->captures[ci].value.is_float;
                                            cap_var->float_value = blk->captures[ci].value.float_val;
                                            cap_var->is_class = blk->captures[ci].value.is_class;
                                            cap_var->cls = blk->captures[ci].value.cls_val;
                                            cap_var->is_sel = blk->captures[ci].value.is_sel;
                                            cap_var->sel = blk->captures[ci].value.sel_val;
                                        }
                                    }
                                }
                            }

                            /* Set up block argument variables (override captured) */
                            {
                                unsigned int ai;
                                for (ai = 0; ai < blk->arg_count; ai++) {
                                    InterpVar *arg_var = interp_get_or_create_var(blk->arg_names[ai]);
                                    if (arg_var) {
                                        if (ai == 0) {
                                            /* First arg: the object */
                                            arg_var->is_id = g_coll_entries[entry_idx].key.is_id;
                                            arg_var->value = g_coll_entries[entry_idx].key.obj_val;
                                            arg_var->is_int = g_coll_entries[entry_idx].key.is_int;
                                            arg_var->int_value = g_coll_entries[entry_idx].key.int_val;
                                            arg_var->is_class = g_coll_entries[entry_idx].key.is_class;
                                            arg_var->cls = g_coll_entries[entry_idx].key.cls_val;
                                            arg_var->is_sel = g_coll_entries[entry_idx].key.is_sel;
                                            arg_var->sel = g_coll_entries[entry_idx].key.sel_val;
                                        } else if (ai == 1) {
                                            /* Second arg: the index */
                                            arg_var->is_int = 1;
                                            arg_var->int_value = (int)idx;
                                            arg_var->is_id = 0;
                                        }
                                        /* Third arg (BOOL *stop) — we set up a 'stop' variable */
                                    }
                                }
                                /* Set up 'stop' variable for BOOL *stop */
                                {
                                    InterpVar *stop_var = interp_get_or_create_var("stop");
                                    if (stop_var) {
                                        stop_var->is_int = 1;
                                        stop_var->int_value = 0;
                                    }
                                }
                            }

                            /* Execute the block body */
                            g_return_pending = 0;
                            eval_source_range(0, blk->source_len, blk->source, 0);

                            /* Check stop flag */
                            {
                                InterpVar *stop_var = interp_find_var("stop");
                                if (stop_var && stop_var->is_int && stop_var->int_value != 0) {
                                    break;
                                }
                            }

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
                        }
                    }
                    return value_from_id(receiver);
                }
            }
        }

        /* Fall through: no built-in, interpreter method, or property matched.
         * Runtime IMP dispatch is not used because WASM enforces exact
         * function signatures — variadic IMP calls cause signature
         * mismatch traps. All supported methods must be handled as
         * built-ins or interpreter-registered methods above. */
        {
            const char *cls_name = "unknown";
            if (target_class_name) {
                cls_name = target_class_name;
            }
            /* Don't call object_getClass on id targets — the pointer
             * might be a C string from the string pool, which would crash. */
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
