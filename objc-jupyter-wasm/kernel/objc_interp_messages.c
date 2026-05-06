/*
 * objc_interp_messages.c
 * Message send parsing and Foundation dispatch extracted from the main interpreter.
 */

#include "objc_interp_types.h"
#include "objc_interp_context.h"
#include "objc_interp_parser.h"
#include "objc_interp_state.h"
#include "objc_interp_dispatch.h"
#include "objc_interp_format.h"
#include "objc_interp_lexer.h"
#include "objc_interp_primary.h"
#include "objc_interp_ast.h"

/* Parser layout must match the definition in objc_interpreter.c. */

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
extern unsigned int find_interpreter_method(SEL sel, Value target, id receiver, int is_setter);
extern unsigned int find_interpreter_method_super(SEL sel, Value target, id receiver, Class skip_class);
extern Value execute_interpreter_method(struct Parser *p, MethodImpl *method, SEL sel, id receiver,
                                        const Value *keyword_args, unsigned int keyword_count,
                                        int return_receiver_on_void);

/* ── Static helpers for JSON serialization ──────────────────────── */

static void append_json_str(char *buf, unsigned int *pos, unsigned int max_len, const char *s) {
    if (!s) return;
    while (*s != '\0' && *pos < max_len - 1) {
        if (*s == '"' || *s == '\\') {
            if (*pos < max_len - 2) {
                buf[(*pos)++] = '\\';
                buf[(*pos)++] = *s;
            }
        } else {
            buf[(*pos)++] = *s;
        }
        s++;
    }
}

static void append_json_value(char *buf, unsigned int *pos, unsigned int max_len, Value v) {
    if (v.is_int) {
        char nbuf[32];
        int val = v.int_val;
        unsigned int npos = 0;
        if (val < 0) { if (*pos < max_len) buf[(*pos)++] = '-'; val = -val; }
        if (val == 0) { if (*pos < max_len) buf[(*pos)++] = '0'; }
        else {
            int t = val;
            while (t > 0) { npos++; t /= 10; }
            t = val;
            { unsigned int d = npos; do { d--; nbuf[d] = '0' + (t % 10); t /= 10; } while (t > 0); }
            { unsigned int i; for(i=0; i<npos && *pos<max_len; i++) buf[(*pos)++] = nbuf[i]; }
        }
    } else if (v.is_float) {
        if (*pos < max_len - 3) { buf[(*pos)++] = '0'; buf[(*pos)++] = '.'; buf[(*pos)++] = '0'; } /* simplified float */
    } else if (v.is_id) {
        const char *s = (const char *)v.obj_val;
        if (s == 0 || cstr_starts(s, "NSNull:")) {
            append_json_str(buf, pos, max_len, "null");
        } else if (cstr_starts(s, "NSDict:") || cstr_starts(s, "NSMutDict:")) {
            unsigned int cid = coll_id_from_marker(s, cstr_starts(s, "NSDict:") ? "NSDict:" : "NSMutDict:");
            unsigned int i;
            int first = 1;
            if (*pos < max_len) buf[(*pos)++] = '{';
            for (i = 0; i < g_ctx.coll_entry_count; i++) {
                if (g_ctx.coll_entries[i].coll_id == cid) {
                    if (!first && *pos < max_len) buf[(*pos)++] = ',';
                    first = 0;
                    if (*pos < max_len) buf[(*pos)++] = '"';
                    if (g_ctx.coll_entries[i].key.is_id && g_ctx.coll_entries[i].key.obj_val) {
                        append_json_str(buf, pos, max_len, (const char *)g_ctx.coll_entries[i].key.obj_val);
                    }
                    if (*pos < max_len) buf[(*pos)++] = '"';
                    if (*pos < max_len) buf[(*pos)++] = ':';
                    append_json_value(buf, pos, max_len, g_ctx.coll_entries[i].value);
                }
            }
            if (*pos < max_len) buf[(*pos)++] = '}';
        } else if (cstr_starts(s, "NSArr:") || cstr_starts(s, "NSMutArr:")) {
            unsigned int cid = coll_id_from_marker(s, cstr_starts(s, "NSArr:") ? "NSArr:" : "NSMutArr:");
            unsigned int i;
            int first = 1;
            if (*pos < max_len) buf[(*pos)++] = '[';
            for (i = 0; i < g_ctx.coll_entry_count; i++) {
                if (g_ctx.coll_entries[i].coll_id == cid) {
                    if (!first && *pos < max_len) buf[(*pos)++] = ',';
                    first = 0;
                    append_json_value(buf, pos, max_len, g_ctx.coll_entries[i].key);
                }
            }
            if (*pos < max_len) buf[(*pos)++] = ']';
        } else if (cstr_starts(s, "NSNumber:")) {
            append_json_str(buf, pos, max_len, s + 9);
        } else if (cstr_starts(s, "NSFloat:")) {
            append_json_str(buf, pos, max_len, s + 8);
        } else {
            /* Raw string */
            if (*pos < max_len) buf[(*pos)++] = '"';
            append_json_str(buf, pos, max_len, s);
            if (*pos < max_len) buf[(*pos)++] = '"';
        }
    } else {
        append_json_str(buf, pos, max_len, "null");
    }
}

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

        /* When side effects are suppressed (short-circuit evaluation of &&/||/?:),
         * skip Foundation dispatch and return nil. */
        if (g_ctx.suppress_side_effects) {
            result = value_from_id(0);
            return result;
        }

        /* Determine target class name for Foundation dispatch.
         * Foundation classes are not registered in the runtime (to avoid
         * WASM traps from objc_allocateClassPair), so we dispatch by name.
         * We look up the variable name from g_ctx.vars[].
         * IMPORTANT: We can't call object_getClass on non-ObjC pointers
         * (like C strings from the string pool) — it causes WASM traps.
         * So we only call it for class targets, not id targets. */
        if (target.is_class && target.cls_val) {
            /* Look up class name from variable table.
             * We can't call class_getName on sentinel pointers (crashes in WASM).
             * Sentinel pointers: Foundation classes (1-9), custom classes (100+). */
            {
                unsigned int vi;
                for (vi = 0; vi < g_ctx.var_count; vi++) {
                    if (g_ctx.vars[vi].is_class && g_ctx.vars[vi].cls == target.cls_val) {
                        target_class_name = g_ctx.vars[vi].name;
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

        /* ── +initialize auto-call ────────────────────────────────────
         * In ObjC 2.0, +initialize is called lazily on a class the first
         * time it receives a message. We walk the superclass chain first
         * (superclass +initialize before subclass), and mark the class as
         * initialized BEFORE calling to prevent re-entrancy. */
        if (target.is_class && target.cls_val && target_class_name &&
            !class_is_initialized(target.cls_val)) {
            /* Build superclass chain: current → parent → ... → root */
            const char *chain[16];
            unsigned int chain_len = 0;
            const char *cur = target_class_name;
            while (cur && cur[0] != '\0' && chain_len < 16) {
                chain[chain_len++] = cur;
                cur = class_get_superclass_name(cur);
            }
            /* Walk from root to current class, calling +initialize on each
             * un-initialized class in the chain. */
            while (chain_len > 0) {
                chain_len--;
                const char *cname = chain[chain_len];
                Class ccls = class_ptr_for_name(cname);
                if (ccls && !class_is_initialized(ccls)) {
                    mark_class_initialized(ccls);
                    SEL init_sel = sel_registerName("initialize");
                    unsigned int mi = find_interpreter_method(init_sel, target, receiver, 0);
                    if (mi < g_ctx.method_count) {
                        execute_interpreter_method(p, &g_ctx.methods[mi], init_sel,
                                                   receiver, 0, 0, 0);
                    }
                }
            }
        }

        /* ── Primitive numeric value dispatch ─────────────────────── */
        if (target.is_int || target.is_float) {
            if (cstr_eq(sel_name, "intValue") || cstr_eq(sel_name, "longValue") || cstr_eq(sel_name, "integerValue")) {
                if (target.is_int) return target;
                return value_from_int((int)target.float_val);
            }
            if (cstr_eq(sel_name, "floatValue") || cstr_eq(sel_name, "doubleValue")) {
                if (target.is_float) return target;
                return value_from_float((double)target.int_val);
            }
            if (cstr_eq(sel_name, "boolValue")) {
                if (target.is_int) return value_from_int(target.int_val != 0);
                return value_from_int(target.float_val != 0.0);
            }
        }

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
         * When target_is_super is set, use super dispatch: skip the
         * current class's methods and search the superclass chain. */
        if (target_is_super &&
            target.is_id && receiver != 0 &&
            is_string_pool_pointer(receiver) &&
            cstr_starts((const char *)receiver, "FDObj:")) {
            unsigned int mi = find_interpreter_method_super(sel, target, receiver,
                                                            g_ctx.current_class_ptr);
            if (mi < g_ctx.method_count) {
                return execute_interpreter_method(p, &g_ctx.methods[mi], sel, receiver,
                                                  keyword_args, arg_count, 1);
            }
            /* Fall through to built-in dispatch (NSObject methods, etc.) */
        }

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
                if (mi < g_ctx.method_count) {
                    return execute_interpreter_method(p, &g_ctx.methods[mi], sel, receiver,
                                                      keyword_args, arg_count, 1);
                }

                /* Synthesized property getter/setter dispatch.
                 * If no interpreter method matched, check if the selector
                 * corresponds to a synthesized @property accessor. */
                {
                    unsigned int pi;

                    /* Setter pattern: setXxx: → property xxx */
                    if (sel_name[0] == 's' && sel_name[1] == 'e' &&
                        sel_name[2] == 't' &&
                        sel_name[3] >= 'A' && sel_name[3] <= 'Z' &&
                        arg_count >= 1) {
                        char prop_name[64];
                        unsigned int si = 3, di = 0;
                        prop_name[di++] = sel_name[si++] + 32; /* lowercase */
                        while (sel_name[si] && sel_name[si] != ':' && di < 62)
                            prop_name[di++] = sel_name[si++];
                        prop_name[di] = '\0';

                        for (pi = 0; pi < g_ctx.property_count; pi++) {
                            if (g_ctx.properties[pi].synthesized &&
                                !g_ctx.properties[pi].is_readonly &&
                                cstr_eq(prop_name, g_ctx.properties[pi].name) &&
                                property_matches_class(receiver, pi)) {
                                instance_var_set(receiver,
                                    g_ctx.properties[pi].name, keyword_args[0]);
                                return value_from_id(receiver);
                            }
                        }
                    }

                    /* Getter pattern: xxx (no args, selector = property name) */
                    if (arg_count == 0) {
                        for (pi = 0; pi < g_ctx.property_count; pi++) {
                            if (g_ctx.properties[pi].synthesized &&
                                cstr_eq(sel_name, g_ctx.properties[pi].name) &&
                                property_matches_class(receiver, pi)) {
                                Value *stored = instance_var_get(receiver,
                                    g_ctx.properties[pi].name);
                                if (stored) return *stored;
                                if (g_ctx.properties[pi].is_int)
                                    return value_from_int(0);
                                return value_from_id(0);
                            }
                        }
                    }
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
                unsigned int cid = g_ctx.next_coll_id++;
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

        /* Built-in: [obj conformsToProtocol:] */
        if (cstr_eq(sel_name, "conformsToProtocol:") && arg_count == 1) {
            const char *proto_arg = (const char *)args[0];
            if (proto_arg) {
                const char *protocol_name = 0;
                if (cstr_starts(proto_arg, "FDProt:")) {
                    protocol_name = proto_arg + 7;
                } else if (is_string_pool_pointer(proto_arg) && !cstr_starts(proto_arg, "FDObj:")) {
                    /* Assume it's a string object with the protocol name */
                    protocol_name = proto_arg;
                }

                if (protocol_name) {
                    const char *class_name = 0;
                    if (target.is_class) {
                        /* Class target: find class name by pointer */
                        unsigned int vi;
                        for (vi = 0; vi < g_ctx.var_count; vi++) {
                            if (g_ctx.vars[vi].is_class && g_ctx.vars[vi].cls == target.cls_val) {
                                class_name = g_ctx.vars[vi].name;
                                break;
                            }
                        }
                    } else if (target.is_id && receiver != 0 && is_string_pool_pointer(receiver) && cstr_starts((const char *)receiver, "FDObj:")) {
                        class_name = ((const char *)receiver) + 6;
                    }

                    if (class_name) {
                        if (class_conforms_to_protocol(class_name, protocol_name)) {
                            return value_from_int(1);
                        }
                    }
                }
            }
            return value_from_int(0);
        }

        /* Built-in: [obj objectEnumerator] and [obj allObjects] */
        if (target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            unsigned int cid = 0;
            if (cstr_starts(s, "NSArr:")) cid = coll_id_from_marker(s, "NSArr:");
            else if (cstr_starts(s, "NSMutArr:")) cid = coll_id_from_marker(s, "NSMutArr:");
            else if (cstr_starts(s, "NSDict:")) cid = coll_id_from_marker(s, "NSDict:");
            else if (cstr_starts(s, "NSMutDict:")) cid = coll_id_from_marker(s, "NSMutDict:");
            else if (cstr_starts(s, "NSSet:")) cid = coll_id_from_marker(s, "NSSet:");

            if (cid > 0) {
                if (cstr_eq(sel_name, "objectEnumerator")) {
                    unsigned int eid = g_ctx.next_enumerator_id % MAX_ENUMERATORS;
                    g_ctx.enumerators[eid].coll_id = cid;
                    g_ctx.enumerators[eid].index = 0;
                    g_ctx.enumerators[eid].active = 1;
                    g_ctx.next_enumerator_id++;
                    
                    char *buf = string_pool_alloc(24);
                    if (buf) {
                        cstr_copy(buf, "NSEnum:", 24);
                        {
                            char tmp[12]; int ti = 0, v = (int)eid;
                            if (v == 0) buf[7] = '0', buf[8] = '\0';
                            else {
                                while (v > 0) { tmp[ti++] = '0' + (v % 10); v /= 10; }
                                int j = 0; while (ti > 0) buf[7 + j++] = tmp[--ti];
                                buf[7 + j] = '\0';
                            }
                        }
                        return value_from_id((id)buf);
                    }
                }
                if (cstr_eq(sel_name, "allObjects")) {
                    unsigned int new_cid = g_ctx.next_coll_id++;
                    unsigned int count = coll_count(cid);
                    unsigned int i;
                    Value dummy = value_void();
                    for (i = 0; i < count; i++) {
                        int eidx = coll_get_nth(cid, i);
                        if (eidx >= 0) coll_add(new_cid, g_ctx.coll_entries[eidx].key, dummy);
                    }
                    return value_from_id(coll_make_marker("NSArr:", new_cid));
                }
            }
        }

        /* Built-in: [NSEnum nextObject] */
        if (target.is_id && receiver != 0 && cstr_starts((const char *)receiver, "NSEnum:")) {
            if (cstr_eq(sel_name, "nextObject")) {
                const char *s = (const char *)receiver;
                unsigned int eid = 0;
                const char *p = s + 7;
                while (*p >= '0' && *p <= '9') { eid = eid * 10 + (*p - '0'); p++; }
                
                if (eid < MAX_ENUMERATORS && g_ctx.enumerators[eid].active) {
                    unsigned int cid = g_ctx.enumerators[eid].coll_id;
                    unsigned int idx = g_ctx.enumerators[eid].index;
                    unsigned int count = coll_count(cid);
                    if (idx < count) {
                        int eidx = coll_get_nth(cid, idx);
                        g_ctx.enumerators[eid].index++;
                        if (eidx >= 0) return g_ctx.coll_entries[eidx].key;
                    }
                    g_ctx.enumerators[eid].active = 0;
                }
                return value_from_id(0);
            }
        }

        /* Built-in: [obj methodSignatureForSelector:] */
        if (cstr_eq(sel_name, "methodSignatureForSelector:") && target.is_id && arg_count >= 1) {
            SEL fwd_sel = sel_registerName("forwardInvocation:");
            if (find_interpreter_method(fwd_sel, target, receiver, 0) < g_ctx.method_count) {
                return value_from_id((id)"FDSig:v@:@");
            }
            return value_from_id(0);
        }

        /* Built-in: [NSInvocation invocationWithMethodSignature:] */
        if (IS_FOUNDATION_CLASS("NSInvocation") && target.is_class && cstr_eq(sel_name, "invocationWithMethodSignature:")) {
            unsigned int inv_id = g_ctx.next_invocation_id % MAX_INVOCATIONS;
            g_ctx.invocations[inv_id].selector = 0;
            g_ctx.invocations[inv_id].receiver = 0;
            g_ctx.invocations[inv_id].arg_count = 0;
            g_ctx.next_invocation_id++;
            char *buf = string_pool_alloc(24);
            if (buf) {
                cstr_copy(buf, "FDInv:", 24);
                {
                    char tmp[12]; int ti = 0, v = (int)inv_id;
                    if (v == 0) buf[6] = '0', buf[7] = '\0';
                    else {
                        while (v > 0) { tmp[ti++] = '0' + (v % 10); v /= 10; }
                        int j = 0; while (ti > 0) buf[6 + j++] = tmp[--ti];
                        buf[6 + j] = '\0';
                    }
                }
                return value_from_id((id)buf);
            }
        }

        if (target.is_id && receiver != 0 && cstr_starts((const char *)receiver, "FDInv:")) {
            unsigned int inv_id = 0;
            const char *p_inv = ((const char *)receiver) + 6;
            while (*p_inv >= '0' && *p_inv <= '9') { inv_id = inv_id * 10 + (*p_inv - '0'); p_inv++; }
            
            if (inv_id < MAX_INVOCATIONS) {
                if (cstr_eq(sel_name, "setSelector:") && arg_count >= 1) {
                    if (keyword_args[0].is_sel) g_ctx.invocations[inv_id].selector = keyword_args[0].sel_val;
                    return value_void();
                }
                if (cstr_eq(sel_name, "selector")) {
                    return value_from_sel(g_ctx.invocations[inv_id].selector);
                }
                if (cstr_eq(sel_name, "setTarget:") && arg_count >= 1) {
                    if (keyword_args[0].is_id) g_ctx.invocations[inv_id].receiver = keyword_args[0].obj_val;
                    return value_void();
                }
                if (cstr_eq(sel_name, "target")) {
                    return value_from_id(g_ctx.invocations[inv_id].receiver);
                }
                if (cstr_eq(sel_name, "getArgument:atIndex:") && arg_count >= 2) {
                    /* Not fully supported (pointers), but return the Value for reflection if possible */
                    return value_void();
                }
                if (cstr_eq(sel_name, "setArgument:atIndex:") && arg_count >= 2) {
                    int idx = keyword_args[1].is_int ? keyword_args[1].int_val : 0;
                    if (idx >= 2 && idx - 2 < 16) {
                        g_ctx.invocations[inv_id].args[idx - 2] = keyword_args[0];
                        if (idx - 2 + 1 > g_ctx.invocations[inv_id].arg_count)
                            g_ctx.invocations[inv_id].arg_count = (unsigned int)(idx - 2 + 1);
                    }
                    return value_void();
                }
                if (cstr_eq(sel_name, "invoke") || cstr_eq(sel_name, "invokeWithTarget:")) {
                    id invoke_receiver = g_ctx.invocations[inv_id].receiver;
                    if (cstr_eq(sel_name, "invokeWithTarget:")) invoke_receiver = keyword_args[0].obj_val;
                    
                    if (invoke_receiver) {
                        /* Use eval_source_range trick to re-dispatch */
                        InterpVar *tmp = interp_get_or_create_var("__inv_recv");
                        if (tmp) {
                            tmp->is_id = 1; tmp->value = invoke_receiver;
                            const char *s_name = sel_getName(g_ctx.invocations[inv_id].selector);
                            /* This is complex to build source with multiple args.
                             * For now, just support 0 or 1 args for forwarding. */
                            if (g_ctx.invocations[inv_id].arg_count == 0) {
                                char buf[128];
                                cstr_copy(buf, "[__inv_recv ", 128);
                                cstr_copy(buf + 12, s_name, 110);
                                unsigned int blen = cstr_len(buf);
                                buf[blen++] = ']'; buf[blen] = '\0';
                                return eval_source_range(0, blen, buf, 0);
                            }
                        }
                    }
                    return value_void();
                }
            }
        }

        /* Built-in: [obj valueForKey:] */
        if (cstr_eq(sel_name, "valueForKey:") && target.is_id && receiver != 0 && arg_count == 1) {
            const char *key = (const char *)args[0];
            /* For collection markers, fall through to collection dispatch
             * which handles valueForKey: as objectForKey: */
            const char *r = (const char *)receiver;
            if (is_string_pool_pointer(receiver) &&
                (cstr_starts(r, "NSDict:") || cstr_starts(r, "NSMutDict:") ||
                 cstr_starts(r, "NSArr:") || cstr_starts(r, "NSMutArr:") ||
                 cstr_starts(r, "NSSet:"))) {
                /* Fall through to collection dispatch below */
            } else if (key) {
                unsigned int pi;
                /* 1. Try property getter */
                for (pi = 0; pi < g_ctx.property_count; pi++) {
                    if (cstr_eq(g_ctx.properties[pi].name, key) && property_matches_class(receiver, pi)) {
                        Value *v = instance_var_get(receiver, g_ctx.properties[pi].name);
                        if (v) return *v;
                        if (g_ctx.properties[pi].is_int) return value_from_int(0);
                        return value_from_id(0);
                    }
                }
                /* 2. Try raw ivar access */
                Value *v = instance_var_get(receiver, key);
                if (v) return *v;
                return value_from_id(0);
            } else {
                return value_from_id(0);
            }
        }

        /* Built-in: [obj setValue:forKey:] */
        if (cstr_eq(sel_name, "setValue:forKey:") && target.is_id && receiver != 0 && arg_count == 2) {
            const char *key = (const char *)args[1];
            if (key) {
                unsigned int pi;
                /* 1. Try property setter */
                for (pi = 0; pi < g_ctx.property_count; pi++) {
                    if (cstr_eq(g_ctx.properties[pi].name, key) && property_matches_class(receiver, pi)) {
                        instance_var_set(receiver, g_ctx.properties[pi].name, keyword_args[0]);
                        return value_void();
                    }
                }
                /* 2. Try raw ivar access */
                instance_var_set(receiver, key, keyword_args[0]);
            }
            return value_void();
        }

        /* Built-in: [obj autorelease] → add to current pool */
        if (cstr_eq(sel_name, "autorelease") && target.is_id && receiver != 0) {
            if (g_ctx.pool_depth > 0) {
                AutoreleasePool *pool = &g_ctx.pools[g_ctx.pool_depth - 1];
                if (pool->count < MAX_AUTORELEASE_OBJECTS) {
                    pool->object_markers[pool->count++] = receiver;
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
                for (vi = 0; vi < g_ctx.var_count; vi++) {
                    if (g_ctx.vars[vi].is_class && cstr_eq(g_ctx.vars[vi].name, recv_class_name)) {
                        return value_from_class(g_ctx.vars[vi].cls);
                    }
                }
                return value_from_class((Class)0);
            }
            /* Tagged Foundation string pool objects — return their sentinel class.
             * Class IDs must match objc_interpreter.c foundation_classes[]:
             * NSObject=1, NSString=2, NSNumber=3, NSArray=4, NSMutableArray=5,
             * NSDictionary=6, NSMutableDictionary=7, NSSet=8, NSData=9,
             * NSCharacterSet=10 */
            if (cstr_starts(s, "NSNumber:")) return value_from_class((Class)3);
            if (cstr_starts(s, "NSFloat:")) return value_from_class((Class)3);
            if (cstr_starts(s, "NSArr:")) return value_from_class((Class)4);
            if (cstr_starts(s, "NSMutArr:")) return value_from_class((Class)5);
            if (cstr_starts(s, "NSDict:")) return value_from_class((Class)6);
            if (cstr_starts(s, "NSMutDict:")) return value_from_class((Class)7);
            if (cstr_starts(s, "NSSet:")) return value_from_class((Class)8);
            if (cstr_starts(s, "NSData:")) return value_from_class((Class)9);
            if (cstr_starts(s, "NSBlock:")) return value_from_class((Class)20);
            if (cstr_starts(s, "NSMutStr:")) return value_from_class((Class)12);
            /* String pool pointers that don't match any known marker prefix
             * are NSString instances (plain @"" literals stored as C strings). */
            if (is_string_pool_pointer(receiver)) return value_from_class((Class)2);
            Class cls = (Class)0;
            cls = object_getClass(receiver);
            return value_from_class(cls);
        }

        /* ── Category method dispatch for Foundation instances ─────── */
        /* String literals (@"..."), NSNumber markers, collection markers,
         * etc. are not FDObj: markers, so the normal interpreter method
         * lookup above skips them.  Check the interpreter method table
         * for category methods on Foundation classes before falling
         * through to built-in dispatch. */
        if (target.is_id && receiver != 0 &&
            is_string_pool_pointer(receiver) &&
            !cstr_starts((const char *)receiver, "FDObj:")) {
            /* Determine the Foundation class name for this receiver */
            const char *foundation_cls_name = (const char *)0;
            const char *s = (const char *)receiver;
            /* Plain C strings are NSString instances */
            foundation_cls_name = "NSString";
            /* Check for NSNumber/NSData/collection markers */
            if (cstr_starts(s, "NSNumber:") || cstr_starts(s, "NSFloat:"))
                foundation_cls_name = "NSNumber";
            else if (cstr_starts(s, "NSArr:"))
                foundation_cls_name = "NSArray";
            else if (cstr_starts(s, "NSMutArr:"))
                foundation_cls_name = "NSMutableArray";
            else if (cstr_starts(s, "NSDict:"))
                foundation_cls_name = "NSDictionary";
            else if (cstr_starts(s, "NSMutDict:"))
                foundation_cls_name = "NSMutableDictionary";
            else if (cstr_starts(s, "NSSet:"))
                foundation_cls_name = "NSSet";
            else if (cstr_starts(s, "NSData:"))
                foundation_cls_name = "NSData";
            else if (cstr_starts(s, "NSBlock:"))
                foundation_cls_name = "NSBlock";

            if (foundation_cls_name) {
                /* Look up the class pointer for this Foundation class */
                InterpVar *cls_var = interp_find_var(foundation_cls_name);
                if (cls_var && cls_var->is_class) {
                    /* Search interpreter methods for this class + selector */
                    unsigned int mi;
                    for (mi = 0; mi < g_ctx.method_count; mi++) {
                        MethodImpl *method = &g_ctx.methods[mi];
                        if (method->selector == sel && method->source_len > 0 &&
                            method->class_ptr == cls_var->cls &&
                            !method->is_class_method) {
                            return execute_interpreter_method(p, &g_ctx.methods[mi], sel,
                                                              receiver, keyword_args, arg_count, 1);
                        }
                    }
                }
            }
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
                if (ptr >= g_ctx.string_pool && ptr < g_ctx.string_pool + OBJC_INTERP_STRING_POOL_SIZE) {
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
                for (mi = 0; mi < g_ctx.method_count; mi++) {
                    if (g_ctx.methods[mi].selector == keyword_args[0].sel_val) {
                        return value_from_int(1);
                    }
                }
            }
            return value_from_int(0);
        }

        /* NSObject: [obj conformsToProtocol:proto] → check protocol conformance */
        if (cstr_eq(sel_name, "conformsToProtocol:") && target.is_id && arg_count >= 1) {
            const char *protocol_name = 0;
            /* The argument is a protocol object or a string name.
             * In our interpreter, protocols are name strings in the protocol table.
             * @protocol(Name) returns FDProt:Name markers. */
            if (keyword_args[0].is_id && keyword_args[0].obj_val != 0) {
                const char *arg = (const char *)keyword_args[0].obj_val;
                if (cstr_starts(arg, "FDProt:")) {
                    protocol_name = arg + 7;
                } else {
                    protocol_name = arg;
                }
            }
            if (protocol_name && target_class_name) {
                extern int class_conforms_to_protocol(const char *, const char *);
                int conforms = class_conforms_to_protocol(target_class_name, protocol_name);
                return value_from_int(conforms);
            }
            return value_from_int(0);
        }

        /* NSObject: [obj performSelector:sel] → dispatch selector */
        if (cstr_eq(sel_name, "performSelector:") && target.is_id && arg_count >= 1) {
            if (keyword_args[0].is_sel) {
                SEL perf_sel = keyword_args[0].sel_val;
                unsigned int mi = find_interpreter_method(perf_sel, target, receiver, 0);
                if (mi < g_ctx.method_count) {
                    return execute_interpreter_method(p, &g_ctx.methods[mi], perf_sel,
                                                      receiver, 0, 0, 1);
                }
            }
            return value_from_id(receiver);
        }

        /* NSObject: [obj performSelector:sel withObject:obj] → dispatch selector with one arg */
        if (cstr_eq(sel_name, "performSelector:withObject:") && target.is_id && arg_count >= 2) {
            if (keyword_args[0].is_sel) {
                SEL perf_sel = keyword_args[0].sel_val;
                unsigned int mi = find_interpreter_method(perf_sel, target, receiver, 0);
                if (mi < g_ctx.method_count) {
                    Value perf_args[1];
                    perf_args[0] = keyword_args[1];
                    return execute_interpreter_method(p, &g_ctx.methods[mi], perf_sel,
                                                      receiver, perf_args, 1, 1);
                }
            }
            return value_from_id(receiver);
        }

        /* NSObject: [obj performSelector:sel withObject:obj1 withObject:obj2] → dispatch with two args */
        if (cstr_eq(sel_name, "performSelector:withObject:withObject:") && target.is_id && arg_count >= 3) {
            if (keyword_args[0].is_sel) {
                SEL perf_sel = keyword_args[0].sel_val;
                unsigned int mi = find_interpreter_method(perf_sel, target, receiver, 0);
                if (mi < g_ctx.method_count) {
                    Value perf_args[2];
                    perf_args[0] = keyword_args[1];
                    perf_args[1] = keyword_args[2];
                    return execute_interpreter_method(p, &g_ctx.methods[mi], perf_sel,
                                                      receiver, perf_args, 2, 1);
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

        /* NSMutableString: [NSMutableString stringWithString:str] → create mutable string */
        if (IS_FOUNDATION_CLASS("NSMutableString") && target.is_class && cstr_eq(sel_name, "stringWithString:") && arg_count >= 1) {
            if (keyword_args[0].is_id && keyword_args[0].obj_val != 0) {
                const char *s = (const char *)keyword_args[0].obj_val;
                unsigned int slen = cstr_len(s);
                /* Create NSMutStr:content marker in string pool */
                char *result = string_pool_alloc(9 + slen + 1);
                if (result == 0) return value_from_id(0);
                cstr_copy(result, "NSMutStr:", 10);
                cstr_copy(result + 9, s, slen + 1);
                return value_from_id((id)result);
            }
            return value_from_id(0);
        }

        /* NSMutableString: [ms appendString:str] → append to mutable string.
         * Since the string pool is append-only, we create a new marker and
         * update any variable that points to the old marker. */
        if (cstr_eq(sel_name, "appendString:") && target.is_id && receiver != 0 && arg_count >= 1) {
            const char *r = (const char *)receiver;
            if (cstr_starts(r, "NSMutStr:")) {
                const char *old_content = r + 9;
                unsigned int old_len = cstr_len(old_content);
                if (keyword_args[0].is_id && keyword_args[0].obj_val != 0) {
                    const char *append = (const char *)keyword_args[0].obj_val;
                    unsigned int append_len = cstr_len(append);
                    char *result = string_pool_alloc(9 + old_len + append_len + 1);
                    if (result == 0) return value_from_id(receiver);
                    cstr_copy(result, "NSMutStr:", 10);
                    cstr_copy(result + 9, old_content, old_len + 1);
                    cstr_copy(result + 9 + old_len, append, append_len + 1);
                    /* Update any variable pointing to the old marker */
                    {
                        unsigned int vi;
                        for (vi = 0; vi < g_ctx.var_count; vi++) {
                            if (g_ctx.vars[vi].is_id && g_ctx.vars[vi].value == receiver) {
                                g_ctx.vars[vi].value = (id)result;
                            }
                        }
                    }
                    return value_from_id((id)result);
                }
                return value_from_id(receiver);
            }
        }

        /* NSMutableString: [ms setString:str] → replace mutable string content */
        if (cstr_eq(sel_name, "setString:") && target.is_id && receiver != 0 && arg_count >= 1) {
            const char *r = (const char *)receiver;
            if (cstr_starts(r, "NSMutStr:")) {
                if (keyword_args[0].is_id && keyword_args[0].obj_val != 0) {
                    const char *new_content = (const char *)keyword_args[0].obj_val;
                    unsigned int new_len = cstr_len(new_content);
                    char *result = string_pool_alloc(9 + new_len + 1);
                    if (result == 0) return value_from_id(receiver);
                    cstr_copy(result, "NSMutStr:", 10);
                    cstr_copy(result + 9, new_content, new_len + 1);
                    /* Update any variable pointing to the old marker */
                    {
                        unsigned int vi;
                        for (vi = 0; vi < g_ctx.var_count; vi++) {
                            if (g_ctx.vars[vi].is_id && g_ctx.vars[vi].value == receiver) {
                                g_ctx.vars[vi].value = (id)result;
                            }
                        }
                    }
                    return value_from_id((id)result);
                }
                return value_from_id(receiver);
            }
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

        /* NSString: [str containsString:substr] → check if string contains substring */
        if (cstr_eq(sel_name, "containsString:") && target.is_id && receiver != 0 && arg_count >= 1) {
            const char *s = (const char *)receiver;
            const char *substr = 0;
            if (keyword_args[0].is_id && keyword_args[0].obj_val != 0) {
                substr = (const char *)keyword_args[0].obj_val;
            }
            if (substr == 0) return value_from_int(0);
            /* strstr returns a pointer to the first occurrence, or NULL */
            {
                const char *found = strstr(s, substr);
                return value_from_int(found != 0 ? 1 : 0);
            }
        }

        /* NSString: [str rangeOfString:substr] → NSRange {location, length}
         * Returns NSRange as a marker string "NSRange:loc:len" or NSNotFound */
        if (cstr_eq(sel_name, "rangeOfString:") && target.is_id && receiver != 0 && arg_count >= 1) {
            const char *s = (const char *)receiver;
            const char *substr = 0;
            if (keyword_args[0].is_id && keyword_args[0].obj_val != 0) {
                substr = (const char *)keyword_args[0].obj_val;
            }
            if (substr == 0 || cstr_len(substr) == 0) {
                /* Empty substring: return {0, 0} */
                return value_from_id((id)"NSRange:0:0");
            }
            {
                const char *found = strstr(s, substr);
                if (found != 0) {
                    unsigned int loc = (unsigned int)(found - s);
                    unsigned int len = (unsigned int)cstr_len(substr);
                    /* Format "NSRange:loc:len" manually (no stdio.h in WASM) */
                    char buf[64];
                    unsigned int bp = 8; /* after "NSRange:" */
                    unsigned int tmp_loc = loc, tmp_len = len;
                    char loc_buf[12], len_buf[12];
                    int li = 0, lei = 0;
                    cstr_copy(buf, "NSRange:", 64);
                    /* Convert loc to string */
                    if (tmp_loc == 0) loc_buf[li++] = '0';
                    else { while (tmp_loc > 0) { loc_buf[li++] = '0' + (tmp_loc % 10); tmp_loc /= 10; } }
                    /* Convert len to string */
                    if (tmp_len == 0) len_buf[lei++] = '0';
                    else { while (tmp_len > 0) { len_buf[lei++] = '0' + (tmp_len % 10); tmp_len /= 10; } }
                    /* Write loc (reversed) */
                    { int j; for (j = li - 1; j >= 0; j--) buf[bp++] = loc_buf[j]; }
                    buf[bp++] = ':';
                    /* Write len (reversed) */
                    { int j; for (j = lei - 1; j >= 0; j--) buf[bp++] = len_buf[j]; }
                    buf[bp] = '\0';
                    {
                        char *marker = string_pool_alloc(bp + 1);
                        if (marker) { cstr_copy(marker, buf, bp + 1); }
                        return value_from_id((id)marker);
                    }
                }
                /* NSNotFound: location = UINT_MAX, length = 0 */
                return value_from_id((id)"NSRange:4294967295:0");
            }
        }

        /* NSString: [str substringWithRange:range] → substring from NSRange marker */
        if (cstr_eq(sel_name, "substringWithRange:") && target.is_id && receiver != 0 && arg_count >= 1) {
            const char *s = (const char *)receiver;
            const char *range_marker = 0;
            unsigned int loc = 0, len = 0;
            if (keyword_args[0].is_id && keyword_args[0].obj_val != 0) {
                range_marker = (const char *)keyword_args[0].obj_val;
            }
            if (range_marker != 0 && cstr_starts(range_marker, "NSRange:")) {
                /* Parse "NSRange:loc:len" manually (no stdio.h in WASM) */
                const char *p = range_marker + 8; /* skip "NSRange:" */
                loc = 0;
                while (*p >= '0' && *p <= '9') { loc = loc * 10 + (unsigned int)(*p - '0'); p++; }
                if (*p == ':') p++;
                len = 0;
                while (*p >= '0' && *p <= '9') { len = len * 10 + (unsigned int)(*p - '0'); p++; }
            }
            {
                int slen = (int)cstr_len(s);
                if (loc < (unsigned int)slen && loc + len <= (unsigned int)slen) {
                    char *result = string_pool_alloc((unsigned int)len + 1);
                    if (result != 0) {
                        unsigned int i;
                        for (i = 0; i < len; i++) result[i] = s[loc + i];
                        result[len] = '\0';
                        return value_from_id((id)result);
                    }
                }
                return value_from_id((id)"");
            }
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

        /* NSString: [str stringByAppendingFormat:@"..."] → format and append */
        if (cstr_eq(sel_name, "stringByAppendingFormat:") && target.is_id && receiver != 0 && arg_count >= 1) {
            const char *base = (const char *)receiver;
            const char *fmt = 0;
            if (keyword_args[0].is_id && keyword_args[0].obj_val != 0) {
                fmt = (const char *)keyword_args[0].obj_val;
            }
            if (fmt != 0) {
                Value formatted = format_values_to_pool(fmt, &keyword_args[1], arg_count - 1);
                if (formatted.is_id && formatted.obj_val != 0) {
                    const char *suffix = (const char *)formatted.obj_val;
                    int base_len = (int)cstr_len(base);
                    int suffix_len = (int)cstr_len(suffix);
                    char *result = string_pool_alloc((unsigned int)(base_len + suffix_len + 1));
                    if (result != 0) {
                        int i;
                        for (i = 0; i < base_len; i++) result[i] = base[i];
                        for (i = 0; i < suffix_len; i++) result[base_len + i] = suffix[i];
                        result[base_len + suffix_len] = '\0';
                        return value_from_id((id)result);
                    }
                }
            }
            return value_from_id(receiver);
        }

        /* NSString: [str componentsSeparatedByString:sep] → NSArray of components */
        if (cstr_eq(sel_name, "componentsSeparatedByString:") && target.is_id && receiver != 0 && arg_count >= 1) {
            const char *src = (const char *)receiver;
            const char *sep = (const char *)keyword_args[0].obj_val;
            int src_len = (int)cstr_len(src);
            int sep_len = (int)cstr_len(sep);
            unsigned int new_cid = g_ctx.next_coll_id++;
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

        /* NSCharacterSet: [NSCharacterSet whitespaceCharacterSet] → return marker */
        if (IS_FOUNDATION_CLASS("NSCharacterSet") && target.is_class &&
            cstr_eq(sel_name, "whitespaceCharacterSet")) {
            return value_from_id((id)"NSCharSet:whitespace");
        }
        /* NSCharacterSet: [NSCharacterSet whitespaceAndNewlineCharacterSet] → return marker */
        if (IS_FOUNDATION_CLASS("NSCharacterSet") && target.is_class &&
            cstr_eq(sel_name, "whitespaceAndNewlineCharacterSet")) {
            return value_from_id((id)"NSCharSet:whitespaceAndNewline");
        }

        /* NSString: [str stringByTrimmingCharactersInSet:charSet] → trim chars in set */
        if (cstr_eq(sel_name, "stringByTrimmingCharactersInSet:") && target.is_id && receiver != 0 && arg_count >= 1) {
            const char *s = (const char *)receiver;
            const char *cs_marker = 0;
            if (keyword_args[0].is_id && keyword_args[0].obj_val != 0) {
                cs_marker = (const char *)keyword_args[0].obj_val;
            }
            int slen = (int)cstr_len(s);
            int start = 0, end = slen;
            /* Determine which characters to trim based on the charset marker */
            if (cs_marker != 0 && cstr_eq_n(cs_marker, "NSCharSet:", 10)) {
                const char *cs_type = cs_marker + 10;
                int is_whitespace = cstr_eq(cs_type, "whitespace");
                int is_whitespace_and_newline = cstr_eq(cs_type, "whitespaceAndNewline");
                if (is_whitespace) {
                    while (start < end && (s[start] == ' ' || s[start] == '\t'))
                        start++;
                    while (end > start && (s[end-1] == ' ' || s[end-1] == '\t'))
                        end--;
                } else if (is_whitespace_and_newline) {
                    while (start < end && (s[start] == ' ' || s[start] == '\t' || s[start] == '\n' || s[start] == '\r'))
                        start++;
                    while (end > start && (s[end-1] == ' ' || s[end-1] == '\t' || s[end-1] == '\n' || s[end-1] == '\r'))
                        end--;
                }
            }
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

        /* NSNumber: [NSNumber numberWithUnsignedLong:n] → wrap unsigned long as id */
        if (IS_FOUNDATION_CLASS("NSNumber") && target.is_class && cstr_eq(sel_name, "numberWithUnsignedLong:") && arg_count >= 1) {
            if (keyword_args[0].is_int) {
                /* Encode as NSNumber: with unsigned value */
                unsigned int v = (unsigned int)keyword_args[0].int_val;
                char *buf = string_pool_alloc(30);
                unsigned int pos = 9;
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

        /* NSNumber: [NSNumber numberWithLongLong:n] → wrap long long as id */
        if (IS_FOUNDATION_CLASS("NSNumber") && target.is_class && cstr_eq(sel_name, "numberWithLongLong:") && arg_count >= 1) {
            if (keyword_args[0].is_int) {
                /* Same encoding as numberWithInt: — interpreter uses 32-bit ints */
                int v = keyword_args[0].int_val;
                int neg = v < 0;
                unsigned int pos = 9;
                char *buf = string_pool_alloc(30);
                if (buf == 0) return value_from_int(v);
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

        /* NSNumber: [num integerValue] → alias for intValue */
        if (cstr_eq(sel_name, "integerValue") && target.is_id && receiver != 0) {
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

        /* NSNumber: [num unsignedIntegerValue] → unsigned alias for intValue */
        if (cstr_eq(sel_name, "unsignedIntegerValue") && target.is_id && receiver != 0) {
            const char *s = (const char *)receiver;
            if (cstr_eq_n(s, "NSNumber:", 9)) {
                int val = 0;
                unsigned int i = 9;
                while (s[i] >= '0' && s[i] <= '9') val = val * 10 + (s[i++] - '0');
                return value_from_int(val);
            }
            return value_from_int(0);
        }

        /* ── NSJSONSerialization dispatch ─────────────────────────── */

        if (IS_FOUNDATION_CLASS("NSJSONSerialization") && target.is_class) {
            if (cstr_eq(sel_name, "JSONObjectWithData:options:error:") && arg_count >= 1) {
                id data_obj = keyword_args[0].obj_val;
                if (data_obj != 0 && cstr_eq_n((const char *)data_obj, "NSData:", 7)) {
                    /* Decode hex data to a string */
                    const char *hex = ((const char *)data_obj) + 7;
                    int hex_len = (int)cstr_len(hex);
                    int byte_len = hex_len / 2;
                    char *json_str = string_pool_alloc((unsigned int)byte_len + 1);
                    if (json_str) {
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
                            json_str[i] = (char)((hi_val << 4) | lo_val);
                        }
                        json_str[byte_len] = '\0';
                        
                        /* Call host import to parse JSON and build collections */
                        return value_from_id(objc_kernel_host_json_parse(json_str, (unsigned int)byte_len));
                    }
                }
                return value_from_id(0); /* Return nil on failure */
            }
            if (cstr_eq(sel_name, "dataWithJSONObject:options:error:") && arg_count >= 1) {
                static char json_gen_buf[262144]; /* 256KB buffer for JSON stringification */
                unsigned int pos = 0;
                Value obj = keyword_args[0];
                append_json_value(json_gen_buf, &pos, sizeof(json_gen_buf), obj);
                json_gen_buf[pos] = '\0';
                
                /* Now encode as NSData hex string */
                {
                    unsigned int needed = 7 + pos * 2 + 1;
                    char *buf = string_pool_alloc(needed);
                    if (buf) {
                        static const char hex_chars[] = "0123456789abcdef";
                        unsigned int i;
                        cstr_copy(buf, "NSData:", needed);
                        for (i = 0; i < pos; i++) {
                            unsigned char c = (unsigned char)json_gen_buf[i];
                            buf[7 + i * 2] = hex_chars[(c >> 4) & 0x0f];
                            buf[7 + i * 2 + 1] = hex_chars[c & 0x0f];
                        }
                        buf[7 + pos * 2] = '\0';
                        return value_from_id((id)buf);
                    }
                }
                return value_from_id(0);
            }
        }

        /* ── Networking dispatch (NSURL, NSURLRequest, NSURLSession) ── */

        /* NSURL */
        if (IS_FOUNDATION_CLASS("NSURL") && target.is_class) {
            if (cstr_eq(sel_name, "URLWithString:") && arg_count >= 1) {
                const char *url_str = (const char *)keyword_args[0].obj_val;
                if (url_str) {
                    unsigned int len = cstr_len(url_str);
                    char *buf = string_pool_alloc(len + 7);
                    if (buf) {
                        cstr_copy(buf, "NSURL:", 7);
                        cstr_copy(buf + 6, url_str, len + 1);
                        return value_from_id((id)buf);
                    }
                }
                return value_from_id(0);
            }
        }

        /* NSMutableURLRequest */
        if (IS_FOUNDATION_CLASS("NSMutableURLRequest") && target.is_class) {
            if (cstr_eq(sel_name, "requestWithURL:") && arg_count >= 1) {
                const char *url_marker = (const char *)keyword_args[0].obj_val;
                if (url_marker && cstr_starts(url_marker, "NSURL:")) {
                    unsigned int cid = g_ctx.next_coll_id++;
                    coll_add_string_val(cid, "url", url_marker + 6);
                    coll_add_string_val(cid, "method", "GET");
                    unsigned int headers_cid = g_ctx.next_coll_id++;
                    coll_add_marker_val(cid, "headers", coll_make_marker("NSMutDict:", headers_cid));
                    return value_from_id(coll_make_marker("NSURLReq:", cid));
                }
                return value_from_id(0);
            }
        }
        
        if (target.is_id && receiver != 0 && cstr_starts((const char *)receiver, "NSURLReq:")) {
            unsigned int cid = coll_id_from_marker((const char *)receiver, "NSURLReq:");
            if (cstr_eq(sel_name, "setHTTPMethod:") && arg_count >= 1) {
                Value key = value_void();
                Value val = keyword_args[0];
                char *k = string_pool_alloc(7);
                if (k) { cstr_copy(k, "method", 7); key = value_from_id((id)k); }
                int idx = coll_find_by_key(cid, &key);
                if (idx >= 0) g_ctx.coll_entries[idx].value = val;
                else coll_add(cid, key, val);
                return value_from_id(receiver);
            }
            if (cstr_eq(sel_name, "setValue:forHTTPHeaderField:") && arg_count >= 2) {
                Value headers_key = value_void();
                char *hk = string_pool_alloc(8);
                if (hk) { cstr_copy(hk, "headers", 8); headers_key = value_from_id((id)hk); }
                int h_idx = coll_find_by_key(cid, &headers_key);
                if (h_idx >= 0) {
                    Value headers_dict = g_ctx.coll_entries[h_idx].value;
                    if (headers_dict.is_id) {
                        unsigned int hcid = coll_id_from_marker((const char *)headers_dict.obj_val, "NSMutDict:");
                        if (hcid) {
                            Value key = keyword_args[1];
                            Value val = keyword_args[0];
                            int idx = coll_find_by_key(hcid, &key);
                            if (idx >= 0) g_ctx.coll_entries[idx].value = val;
                            else coll_add(hcid, key, val);
                        }
                    }
                }
                return value_from_id(receiver);
            }
            if (cstr_eq(sel_name, "setHTTPBody:") && arg_count >= 1) {
                Value key = value_void();
                Value val = keyword_args[0];
                char *k = string_pool_alloc(5);
                if (k) { cstr_copy(k, "body", 5); key = value_from_id((id)k); }
                int idx = coll_find_by_key(cid, &key);
                if (idx >= 0) g_ctx.coll_entries[idx].value = val;
                else coll_add(cid, key, val);
                return value_from_id(receiver);
            }
        }

        /* NSURLSession */
        if (IS_FOUNDATION_CLASS("NSURLSession") && target.is_class) {
            if (cstr_eq(sel_name, "sharedSession")) {
                return value_from_id((id)"NSURLSession:shared");
            }
        }
        
        if (target.is_id && receiver != 0 && cstr_starts((const char *)receiver, "NSURLSession:")) {
            if (cstr_eq(sel_name, "dataTaskWithRequest:completionHandler:") && arg_count >= 2) {
                const char *req_marker = (const char *)keyword_args[0].obj_val;
                const char *blk_marker = (const char *)keyword_args[1].obj_val;
                if (req_marker && cstr_starts(req_marker, "NSURLReq:") && blk_marker && cstr_starts(blk_marker, "NSBlock:")) {
                    if (g_ctx.network_task_count < MAX_NETWORK_TASKS) {
                        int task_id = g_ctx.next_network_task_id++;
                        g_ctx.network_tasks[g_ctx.network_task_count].task_id = task_id;
                        g_ctx.network_tasks[g_ctx.network_task_count].block_id = block_id_from_marker(blk_marker);
                        g_ctx.network_tasks[g_ctx.network_task_count].active = 0; /* not active until resume */
                        
                        /* Store the request marker so we can fetch it when resumed */
                        unsigned int cid = g_ctx.next_coll_id++;
                        coll_add_int_val(cid, "task_id", task_id);
                        coll_add_string_val(cid, "req", req_marker);
                        
                        g_ctx.network_task_count++;
                        return value_from_id(coll_make_marker("NSURLTask:", cid));
                    }
                }
                return value_from_id(0);
            }
        }
        
        if (target.is_id && receiver != 0 && cstr_starts((const char *)receiver, "NSURLTask:")) {
            if (cstr_eq(sel_name, "resume")) {
                unsigned int cid = coll_id_from_marker((const char *)receiver, "NSURLTask:");
                Value key_task = value_void();
                char *kt = string_pool_alloc(8);
                if (kt) { cstr_copy(kt, "task_id", 8); key_task = value_from_id((id)kt); }
                int idx_task = coll_find_by_key(cid, &key_task);
                
                Value key_req = value_void();
                char *kr = string_pool_alloc(4);
                if (kr) { cstr_copy(kr, "req", 4); key_req = value_from_id((id)kr); }
                int idx_req = coll_find_by_key(cid, &key_req);
                
                if (idx_task >= 0 && idx_req >= 0) {
                    int task_id = g_ctx.coll_entries[idx_task].value.int_val;
                    const char *req_marker = (const char *)g_ctx.coll_entries[idx_req].value.obj_val;
                    unsigned int req_cid = coll_id_from_marker(req_marker, "NSURLReq:");
                    
                    /* Mark active */
                    unsigned int i;
                    for (i = 0; i < g_ctx.network_task_count; i++) {
                        if (g_ctx.network_tasks[i].task_id == task_id) {
                            g_ctx.network_tasks[i].active = 1;
                            break;
                        }
                    }
                    
                    /* Extract properties for fetch */
                    const char *url = "";
                    const char *method = "GET";
                    const char *body = 0;
                    unsigned int body_len = 0;
                    
                    Value k_url = value_void(); char *ku = string_pool_alloc(4); if(ku){cstr_copy(ku,"url",4); k_url=value_from_id((id)ku);}
                    Value k_method = value_void(); char *km = string_pool_alloc(7); if(km){cstr_copy(km,"method",7); k_method=value_from_id((id)km);}
                    Value k_body = value_void(); char *kb = string_pool_alloc(5); if(kb){cstr_copy(kb,"body",5); k_body=value_from_id((id)kb);}
                    Value k_headers = value_void(); char *kh = string_pool_alloc(8); if(kh){cstr_copy(kh,"headers",8); k_headers=value_from_id((id)kh);}
                    
                    int i_u = coll_find_by_key(req_cid, &k_url);
                    if (i_u >= 0) url = (const char *)g_ctx.coll_entries[i_u].value.obj_val;
                    
                    int i_m = coll_find_by_key(req_cid, &k_method);
                    if (i_m >= 0) method = (const char *)g_ctx.coll_entries[i_m].value.obj_val;
                    
                    int i_b = coll_find_by_key(req_cid, &k_body);
                    if (i_b >= 0) {
                        const char *data_str = (const char *)g_ctx.coll_entries[i_b].value.obj_val;
                        if (data_str && cstr_starts(data_str, "NSData:")) {
                            /* hex string NSData:XXXX */
                            const char *hex = data_str + 7;
                            int hex_len = (int)cstr_len(hex);
                            body_len = hex_len / 2;
                            char *bin_body = string_pool_alloc(body_len);
                            if (bin_body) {
                                static const char hex_vals[] = "0123456789abcdef";
                                int x;
                                for (x = 0; x < body_len; x++) {
                                    char hi = hex[x * 2];
                                    char lo = hex[x * 2 + 1];
                                    int hi_val = 0, lo_val = 0, j;
                                    for (j = 0; j < 16; j++) {
                                        if (hi == hex_vals[j] || hi == hex_vals[j] - 32) hi_val = j;
                                        if (lo == hex_vals[j] || lo == hex_vals[j] - 32) lo_val = j;
                                    }
                                    bin_body[x] = (char)((hi_val << 4) | lo_val);
                                }
                                body = bin_body;
                            }
                        }
                    }
                    
                    /* Stringify headers dict to JSON using our C stringifier */
                    static char headers_json[4096];
                    headers_json[0] = '\0';
                    int i_h = coll_find_by_key(req_cid, &k_headers);
                    if (i_h >= 0) {
                        unsigned int pos = 0;
                        append_json_value(headers_json, &pos, sizeof(headers_json), g_ctx.coll_entries[i_h].value);
                        headers_json[pos] = '\0';
                    }
                    
                    extern int objc_kernel_host_fetch(int task_id, const char *url, const char *method, const char *headers_json, const char *body, unsigned int body_len);
                    
                    /* Tell host to perform the fetch */
                    objc_kernel_host_fetch(task_id, url, method, headers_json[0] ? headers_json : "{}", body, body_len);
                }
                return value_from_id(receiver);
            }
        }

        /* ── Networking dispatch (NSURL, NSURLRequest, NSURLSession) ── */

        /* NSURL */
        if (IS_FOUNDATION_CLASS("NSURL") && target.is_class) {
            if (cstr_eq(sel_name, "URLWithString:") && arg_count >= 1) {
                const char *url_str = (const char *)keyword_args[0].obj_val;
                if (url_str) {
                    unsigned int len = cstr_len(url_str);
                    char *buf = string_pool_alloc(len + 7);
                    if (buf) {
                        cstr_copy(buf, "NSURL:", 7);
                        cstr_copy(buf + 6, url_str, len + 1);
                        return value_from_id((id)buf);
                    }
                }
                return value_from_id(0);
            }
        }

        /* NSMutableURLRequest */
        if (IS_FOUNDATION_CLASS("NSMutableURLRequest") && target.is_class) {
            if (cstr_eq(sel_name, "requestWithURL:") && arg_count >= 1) {
                const char *url_marker = (const char *)keyword_args[0].obj_val;
                if (url_marker && cstr_starts(url_marker, "NSURL:")) {
                    unsigned int cid = g_ctx.next_coll_id++;
                    coll_add_string_val(cid, "url", url_marker + 6);
                    coll_add_string_val(cid, "method", "GET");
                    unsigned int headers_cid = g_ctx.next_coll_id++;
                    coll_add_marker_val(cid, "headers", coll_make_marker("NSMutDict:", headers_cid));
                    return value_from_id(coll_make_marker("NSURLReq:", cid));
                }
                return value_from_id(0);
            }
        }
        
        if (target.is_id && receiver != 0 && cstr_starts((const char *)receiver, "NSURLReq:")) {
            unsigned int cid = coll_id_from_marker((const char *)receiver, "NSURLReq:");
            if (cstr_eq(sel_name, "setHTTPMethod:") && arg_count >= 1) {
                Value key = value_void();
                Value val = keyword_args[0];
                char *k = string_pool_alloc(7);
                if (k) { cstr_copy(k, "method", 7); key = value_from_id((id)k); }
                int idx = coll_find_by_key(cid, &key);
                if (idx >= 0) g_ctx.coll_entries[idx].value = val;
                else coll_add(cid, key, val);
                return value_from_id(receiver);
            }
            if (cstr_eq(sel_name, "setValue:forHTTPHeaderField:") && arg_count >= 2) {
                Value headers_key = value_void();
                char *hk = string_pool_alloc(8);
                if (hk) { cstr_copy(hk, "headers", 8); headers_key = value_from_id((id)hk); }
                int h_idx = coll_find_by_key(cid, &headers_key);
                if (h_idx >= 0) {
                    Value headers_dict = g_ctx.coll_entries[h_idx].value;
                    if (headers_dict.is_id) {
                        unsigned int hcid = coll_id_from_marker((const char *)headers_dict.obj_val, "NSMutDict:");
                        if (hcid) {
                            Value key = keyword_args[1];
                            Value val = keyword_args[0];
                            int idx = coll_find_by_key(hcid, &key);
                            if (idx >= 0) g_ctx.coll_entries[idx].value = val;
                            else coll_add(hcid, key, val);
                        }
                    }
                }
                return value_from_id(receiver);
            }
            if (cstr_eq(sel_name, "setHTTPBody:") && arg_count >= 1) {
                Value key = value_void();
                Value val = keyword_args[0];
                char *k = string_pool_alloc(5);
                if (k) { cstr_copy(k, "body", 5); key = value_from_id((id)k); }
                int idx = coll_find_by_key(cid, &key);
                if (idx >= 0) g_ctx.coll_entries[idx].value = val;
                else coll_add(cid, key, val);
                return value_from_id(receiver);
            }
        }

        /* NSURLSession */
        if (IS_FOUNDATION_CLASS("NSURLSession") && target.is_class) {
            if (cstr_eq(sel_name, "sharedSession")) {
                return value_from_id((id)"NSURLSession:shared");
            }
        }
        
        if (target.is_id && receiver != 0 && cstr_starts((const char *)receiver, "NSURLSession:")) {
            if (cstr_eq(sel_name, "dataTaskWithRequest:completionHandler:") && arg_count >= 2) {
                const char *req_marker = (const char *)keyword_args[0].obj_val;
                const char *blk_marker = (const char *)keyword_args[1].obj_val;
                if (req_marker && cstr_starts(req_marker, "NSURLReq:") && blk_marker && cstr_starts(blk_marker, "NSBlock:")) {
                    if (g_ctx.network_task_count < MAX_NETWORK_TASKS) {
                        int task_id = g_ctx.next_network_task_id++;
                        g_ctx.network_tasks[g_ctx.network_task_count].task_id = task_id;
                        g_ctx.network_tasks[g_ctx.network_task_count].block_id = block_id_from_marker(blk_marker);
                        g_ctx.network_tasks[g_ctx.network_task_count].active = 0; /* not active until resume */
                        
                        /* Store the request marker so we can fetch it when resumed */
                        unsigned int cid = g_ctx.next_coll_id++;
                        coll_add_int_val(cid, "task_id", task_id);
                        coll_add_string_val(cid, "req", req_marker);
                        
                        g_ctx.network_task_count++;
                        return value_from_id(coll_make_marker("NSURLTask:", cid));
                    }
                }
                return value_from_id(0);
            }
        }
        
        if (target.is_id && receiver != 0 && cstr_starts((const char *)receiver, "NSURLTask:")) {
            if (cstr_eq(sel_name, "resume")) {
                unsigned int cid = coll_id_from_marker((const char *)receiver, "NSURLTask:");
                Value key_task = value_void();
                char *kt = string_pool_alloc(8);
                if (kt) { cstr_copy(kt, "task_id", 8); key_task = value_from_id((id)kt); }
                int idx_task = coll_find_by_key(cid, &key_task);
                
                Value key_req = value_void();
                char *kr = string_pool_alloc(4);
                if (kr) { cstr_copy(kr, "req", 4); key_req = value_from_id((id)kr); }
                int idx_req = coll_find_by_key(cid, &key_req);
                
                if (idx_task >= 0 && idx_req >= 0) {
                    int task_id = g_ctx.coll_entries[idx_task].value.int_val;
                    const char *req_marker = (const char *)g_ctx.coll_entries[idx_req].value.obj_val;
                    unsigned int req_cid = coll_id_from_marker(req_marker, "NSURLReq:");
                    
                    /* Mark active */
                    unsigned int i;
                    for (i = 0; i < g_ctx.network_task_count; i++) {
                        if (g_ctx.network_tasks[i].task_id == task_id) {
                            g_ctx.network_tasks[i].active = 1;
                            break;
                        }
                    }
                    
                    /* Extract properties for fetch */
                    const char *url = "";
                    const char *method = "GET";
                    const char *body = 0;
                    unsigned int body_len = 0;
                    
                    Value k_url = value_void(); char *ku = string_pool_alloc(4); if(ku){cstr_copy(ku,"url",4); k_url=value_from_id((id)ku);}
                    Value k_method = value_void(); char *km = string_pool_alloc(7); if(km){cstr_copy(km,"method",7); k_method=value_from_id((id)km);}
                    Value k_body = value_void(); char *kb = string_pool_alloc(5); if(kb){cstr_copy(kb,"body",5); k_body=value_from_id((id)kb);}
                    Value k_headers = value_void(); char *kh = string_pool_alloc(8); if(kh){cstr_copy(kh,"headers",8); k_headers=value_from_id((id)kh);}
                    
                    int i_u = coll_find_by_key(req_cid, &k_url);
                    if (i_u >= 0) url = (const char *)g_ctx.coll_entries[i_u].value.obj_val;
                    
                    int i_m = coll_find_by_key(req_cid, &k_method);
                    if (i_m >= 0) method = (const char *)g_ctx.coll_entries[i_m].value.obj_val;
                    
                    int i_b = coll_find_by_key(req_cid, &k_body);
                    if (i_b >= 0) {
                        const char *data_str = (const char *)g_ctx.coll_entries[i_b].value.obj_val;
                        if (data_str && cstr_starts(data_str, "NSData:")) {
                            /* hex string NSData:XXXX */
                            const char *hex = data_str + 7;
                            int hex_len = (int)cstr_len(hex);
                            body_len = hex_len / 2;
                            char *bin_body = string_pool_alloc(body_len);
                            if (bin_body) {
                                static const char hex_vals[] = "0123456789abcdef";
                                int x;
                                for (x = 0; x < body_len; x++) {
                                    char hi = hex[x * 2];
                                    char lo = hex[x * 2 + 1];
                                    int hi_val = 0, lo_val = 0, j;
                                    for (j = 0; j < 16; j++) {
                                        if (hi == hex_vals[j] || hi == hex_vals[j] - 32) hi_val = j;
                                        if (lo == hex_vals[j] || lo == hex_vals[j] - 32) lo_val = j;
                                    }
                                    bin_body[x] = (char)((hi_val << 4) | lo_val);
                                }
                                body = bin_body;
                            }
                        }
                    }
                    
                    /* Stringify headers dict to JSON using our C stringifier */
                    static char headers_json[4096];
                    headers_json[0] = '\0';
                    int i_h = coll_find_by_key(req_cid, &k_headers);
                    if (i_h >= 0) {
                        unsigned int pos = 0;
                        append_json_value(headers_json, &pos, sizeof(headers_json), g_ctx.coll_entries[i_h].value);
                        headers_json[pos] = '\0';
                    }
                    
                    extern int objc_kernel_host_fetch(int task_id, const char *url, const char *method, const char *headers_json, const char *body, unsigned int body_len);
                    
                    /* Tell host to perform the fetch */
                    objc_kernel_host_fetch(task_id, url, method, headers_json[0] ? headers_json : "{}", body, body_len);
                }
                return value_from_id(receiver);
            }
        }

        /* ── NSNull dispatch ──────────────────────────────────────── */

        /* NSNull: [NSNull null] → singleton marker */
        if (IS_FOUNDATION_CLASS("NSNull") && target.is_class && cstr_eq(sel_name, "null") && arg_count == 0) {
            char *buf = string_pool_alloc(8);
            if (buf == 0) return value_from_id((id)"NSNull:");
            cstr_copy(buf, "NSNull:", 8);
            return value_from_id((id)buf);
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

        /* NSMutableData: [NSMutableData dataWithCapacity:n] → empty mutable data */
        if (IS_FOUNDATION_CLASS("NSMutableData") && target.is_class && cstr_eq(sel_name, "dataWithCapacity:") && arg_count >= 1) {
            char *buf = string_pool_alloc(8);
            if (buf == 0) return value_from_id((id)"NSData:");
            cstr_copy(buf, "NSData:", 8);
            return value_from_id((id)buf);
        }

        /* NSMutableData: [NSMutableData data] → empty mutable data */
        if (IS_FOUNDATION_CLASS("NSMutableData") && target.is_class && cstr_eq(sel_name, "data") && arg_count == 0) {
            char *buf = string_pool_alloc(8);
            if (buf == 0) return value_from_id((id)"NSData:");
            cstr_copy(buf, "NSData:", 8);
            return value_from_id((id)buf);
        }

        /* NSData: [NSData dataWithData:other] → copy of other data */
        if (IS_FOUNDATION_CLASS("NSData") && target.is_class && cstr_eq(sel_name, "dataWithData:") && arg_count >= 1) {
            const char *other = (const char *)keyword_args[0].obj_val;
            if (other && cstr_eq_n(other, "NSData:", 7)) {
                unsigned int needed = (unsigned int)cstr_len(other) + 1;
                char *buf = string_pool_alloc(needed);
                if (buf == 0) return value_from_id((id)"NSData:");
                cstr_copy(buf, other, needed);
                return value_from_id((id)buf);
            }
            char *buf = string_pool_alloc(8);
            if (buf == 0) return value_from_id((id)"NSData:");
            cstr_copy(buf, "NSData:", 8);
            return value_from_id((id)buf);
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

            /* [data byteAtIndex:i] → return integer value of byte at index */
            if (cstr_eq(sel_name, "byteAtIndex:") && arg_count >= 1) {
                const char *hex = s + 7;
                int hex_len = (int)cstr_len(hex);
                int idx = keyword_args[0].is_int ? keyword_args[0].int_val : 0;
                if (idx < 0 || idx * 2 + 1 >= hex_len) return value_from_int(0);
                {
                    static const char hex_vals[] = "0123456789abcdef";
                    char hi = hex[idx * 2];
                    char lo = hex[idx * 2 + 1];
                    int hi_val = 0, lo_val = 0, j;
                    for (j = 0; j < 16; j++) {
                        if (hi == hex_vals[j] || hi == hex_vals[j] - 32) hi_val = j;
                        if (lo == hex_vals[j] || lo == hex_vals[j] - 32) lo_val = j;
                    }
                    return value_from_int((hi_val << 4) | lo_val);
                }
            }

            /* [data subdataWithRange:] → extract subrange as new NSData
             * Accepts two integer args: location and length (simulating NSRange). */
            if (cstr_eq(sel_name, "subdataWithRange:") && arg_count >= 2) {
                const char *hex = s + 7;
                int hex_len = (int)cstr_len(hex);
                int loc = keyword_args[0].is_int ? keyword_args[0].int_val : 0;
                int len = keyword_args[1].is_int ? keyword_args[1].int_val : 0;
                if (loc < 0) loc = 0;
                if (len < 0) len = 0;
                if (loc * 2 > hex_len) loc = hex_len / 2;
                if (loc + len > hex_len / 2) len = (hex_len / 2) - loc;
                {
                    unsigned int needed = 7 + (unsigned int)len * 2 + 1;
                    char *buf = string_pool_alloc(needed);
                    if (buf == 0) return value_from_id((id)"NSData:");
                    cstr_copy(buf, "NSData:", needed);
                    {
                        int i;
                        for (i = 0; i < len * 2 && (loc * 2 + i) < hex_len; i++) {
                            buf[7 + i] = hex[loc * 2 + i];
                        }
                        buf[7 + len * 2] = '\0';
                    }
                    return value_from_id((id)buf);
                }
            }

            /* [data appendData:other] → append other's bytes (NSMutableData) */
            if (cstr_eq(sel_name, "appendData:") && arg_count >= 1) {
                const char *other = (const char *)keyword_args[0].obj_val;
                if (other && cstr_eq_n(other, "NSData:", 7)) {
                    const char *hex1 = s + 7;
                    const char *hex2 = other + 7;
                    int len1 = (int)cstr_len(hex1);
                    int len2 = (int)cstr_len(hex2);
                    unsigned int needed = 7 + (unsigned int)(len1 + len2) + 1;
                    char *buf = string_pool_alloc(needed);
                    if (buf == 0) return value_from_id(receiver);
                    cstr_copy(buf, "NSData:", needed);
                    {
                        int i;
                        for (i = 0; i < len1; i++) buf[7 + i] = hex1[i];
                        for (i = 0; i < len2; i++) buf[7 + len1 + i] = hex2[i];
                        buf[7 + len1 + len2] = '\0';
                    }
                    return value_from_id((id)buf);
                }
                return value_from_id(receiver);
            }

            /* [data appendBytes:length:] → append raw bytes (NSMutableData)
             * Accepts a string (each char = byte) and length. */
            if (cstr_eq(sel_name, "appendBytes:length:") && arg_count >= 2) {
                const char *bytes = (const char *)keyword_args[0].obj_val;
                int len = keyword_args[1].is_int ? keyword_args[1].int_val : 0;
                const char *hex = s + 7;
                int hex_len = (int)cstr_len(hex);
                if (len < 0) len = 0;
                {
                    int blen = (int)cstr_len(bytes);
                    if (len > blen) len = blen;
                    unsigned int needed = 7 + (unsigned int)(hex_len + len * 2) + 1;
                    char *buf = string_pool_alloc(needed);
                    if (buf == 0) return value_from_id(receiver);
                    cstr_copy(buf, "NSData:", needed);
                    {
                        int i;
                        for (i = 0; i < hex_len; i++) buf[7 + i] = hex[i];
                        {
                            static const char hex_chars[] = "0123456789abcdef";
                            for (i = 0; i < len; i++) {
                                unsigned char c = (unsigned char)bytes[i];
                                buf[7 + hex_len + i * 2] = hex_chars[(c >> 4) & 0x0f];
                                buf[7 + hex_len + i * 2 + 1] = hex_chars[c & 0x0f];
                            }
                            buf[7 + hex_len + len * 2] = '\0';
                        }
                    }
                    return value_from_id((id)buf);
                }
            }

            /* [data copy] → return a copy of this NSData */
            if (cstr_eq(sel_name, "copy") && arg_count == 0) {
                unsigned int needed = (unsigned int)cstr_len(s) + 1;
                char *buf = string_pool_alloc(needed);
                if (buf == 0) return value_from_id(receiver);
                cstr_copy(buf, s, needed);
                return value_from_id((id)buf);
            }
        }

        /* ── Host-bridged crypto/encoding dispatch ─────────────────── */

        /* [CID sha256Digest:data] → SHA-256 via host bridge
         * Accepts NSData, returns NSData (32 bytes). */
        if (IS_FOUNDATION_CLASS("CID") && target.is_class && cstr_eq(sel_name, "sha256Digest:") && arg_count >= 1) {
            const char *arg = (const char *)keyword_args[0].obj_val;
            if (arg && cstr_eq_n(arg, "NSData:", 7)) {
                const char *hex = arg + 7;
                int hex_len = (int)cstr_len(hex);
                int byte_len = hex_len / 2;
                /* Decode hex to raw bytes in a temp buffer, call host, encode result */
                char *raw = (char *)0;
                if (byte_len > 0) {
                    raw = string_pool_alloc((unsigned int)byte_len);
                    if (raw) {
                        static const char hv[] = "0123456789abcdef";
                        int i;
                        for (i = 0; i < byte_len; i++) {
                            char hi = hex[i * 2], lo = hex[i * 2 + 1];
                            int hiv = 0, lov = 0, j;
                            for (j = 0; j < 16; j++) {
                                if (hi == hv[j] || hi == hv[j] - 32) hiv = j;
                                if (lo == hv[j] || lo == hv[j] - 32) lov = j;
                            }
                            raw[i] = (char)((hiv << 4) | lov);
                        }
                    }
                }
                {
                    char out_buf[64]; /* SHA-256 = 32 bytes, hex = 64 chars */
                    int result_len = objc_kernel_host_sha256(raw ? raw : "", (unsigned int)byte_len, out_buf, 64);
                    if (result_len > 0) {
                        /* result_len is byte count of hash; encode as NSData:hex */
                        unsigned int needed = 7 + (unsigned int)result_len * 2 + 1;
                        char *buf = string_pool_alloc(needed);
                        if (buf) {
                            static const char hc[] = "0123456789abcdef";
                            int i;
                            cstr_copy(buf, "NSData:", needed);
                            for (i = 0; i < result_len; i++) {
                                unsigned char c = (unsigned char)out_buf[i];
                                buf[7 + i * 2] = hc[(c >> 4) & 0x0f];
                                buf[7 + i * 2 + 1] = hc[c & 0x0f];
                            }
                            buf[7 + result_len * 2] = '\0';
                            return value_from_id((id)buf);
                        }
                    }
                }
            }
            return value_from_id((id)"NSData:");
        }

        /* [CID sha256:data] → CID with SHA-256 via host bridge
         * Accepts NSData, returns a CID string marker. */
        if (IS_FOUNDATION_CLASS("CID") && target.is_class && cstr_eq(sel_name, "sha256:") && arg_count >= 1) {
            /* Delegate to sha256Digest: then wrap in CID */
            /* For now, return the digest as NSData (same as sha256Digest:) */
            const char *arg = (const char *)keyword_args[0].obj_val;
            if (arg && cstr_eq_n(arg, "NSData:", 7)) {
                const char *hex = arg + 7;
                int hex_len = (int)cstr_len(hex);
                int byte_len = hex_len / 2;
                char *raw = (char *)0;
                if (byte_len > 0) {
                    raw = string_pool_alloc((unsigned int)byte_len);
                    if (raw) {
                        static const char hv[] = "0123456789abcdef";
                        int i;
                        for (i = 0; i < byte_len; i++) {
                            char hi = hex[i * 2], lo = hex[i * 2 + 1];
                            int hiv = 0, lov = 0, j;
                            for (j = 0; j < 16; j++) {
                                if (hi == hv[j] || hi == hv[j] - 32) hiv = j;
                                if (lo == hv[j] || lo == hv[j] - 32) lov = j;
                            }
                            raw[i] = (char)((hiv << 4) | lov);
                        }
                    }
                }
                {
                    char out_buf[64];
                    int result_len = objc_kernel_host_sha256(raw ? raw : "", (unsigned int)byte_len, out_buf, 64);
                    if (result_len > 0) {
                        unsigned int needed = 7 + (unsigned int)result_len * 2 + 1;
                        char *buf = string_pool_alloc(needed);
                        if (buf) {
                            static const char hc[] = "0123456789abcdef";
                            int i;
                            cstr_copy(buf, "NSData:", needed);
                            for (i = 0; i < result_len; i++) {
                                unsigned char c = (unsigned char)out_buf[i];
                                buf[7 + i * 2] = hc[(c >> 4) & 0x0f];
                                buf[7 + i * 2 + 1] = hc[c & 0x0f];
                            }
                            buf[7 + result_len * 2] = '\0';
                            return value_from_id((id)buf);
                        }
                    }
                }
            }
            return value_from_id((id)"NSData:");
        }

        /* [CID base32Encode:data] → base32 string via host bridge */
        if (IS_FOUNDATION_CLASS("CID") && target.is_class && cstr_eq(sel_name, "base32Encode:") && arg_count >= 1) {
            const char *arg = (const char *)keyword_args[0].obj_val;
            if (arg && cstr_eq_n(arg, "NSData:", 7)) {
                const char *hex = arg + 7;
                int hex_len = (int)cstr_len(hex);
                int byte_len = hex_len / 2;
                char *raw = (char *)0;
                if (byte_len > 0) {
                    raw = string_pool_alloc((unsigned int)byte_len);
                    if (raw) {
                        static const char hv[] = "0123456789abcdef";
                        int i;
                        for (i = 0; i < byte_len; i++) {
                            char hi = hex[i * 2], lo = hex[i * 2 + 1];
                            int hiv = 0, lov = 0, j;
                            for (j = 0; j < 16; j++) {
                                if (hi == hv[j] || hi == hv[j] - 32) hiv = j;
                                if (lo == hv[j] || lo == hv[j] - 32) lov = j;
                            }
                            raw[i] = (char)((hiv << 4) | lov);
                        }
                    }
                }
                {
                    char out_buf[512];
                    int result_len = objc_kernel_host_base32_encode(raw ? raw : "", (unsigned int)byte_len, out_buf, 512);
                    if (result_len > 0) {
                        unsigned int needed = (unsigned int)result_len + 1;
                        char *buf = string_pool_alloc(needed);
                        if (buf) {
                            int i;
                            for (i = 0; i < result_len; i++) buf[i] = out_buf[i];
                            buf[result_len] = '\0';
                            return value_from_id((id)buf);
                        }
                    }
                }
            }
            return value_from_id((id)"");
        }

        /* [CID base32Decode:string] → NSData via host bridge */
        if (IS_FOUNDATION_CLASS("CID") && target.is_class && cstr_eq(sel_name, "base32Decode:") && arg_count >= 1) {
            const char *str = (const char *)keyword_args[0].obj_val;
            if (str) {
                int str_len = (int)cstr_len(str);
                char out_buf[512];
                int result_len = objc_kernel_host_base32_decode(str, (unsigned int)str_len, out_buf, 512);
                if (result_len > 0) {
                    unsigned int needed = 7 + (unsigned int)result_len * 2 + 1;
                    char *buf = string_pool_alloc(needed);
                    if (buf) {
                        static const char hc[] = "0123456789abcdef";
                        int i;
                        cstr_copy(buf, "NSData:", needed);
                        for (i = 0; i < result_len; i++) {
                            unsigned char c = (unsigned char)out_buf[i];
                            buf[7 + i * 2] = hc[(c >> 4) & 0x0f];
                            buf[7 + i * 2 + 1] = hc[c & 0x0f];
                        }
                        buf[7 + result_len * 2] = '\0';
                        return value_from_id((id)buf);
                    }
                }
            }
            return value_from_id((id)"NSData:");
        }

        /* [CryptoUtils sha256:data] → NSData via host bridge */
        if (IS_FOUNDATION_CLASS("CryptoUtils") && target.is_class && cstr_eq(sel_name, "sha256:") && arg_count >= 1) {
            const char *arg = (const char *)keyword_args[0].obj_val;
            if (arg && cstr_eq_n(arg, "NSData:", 7)) {
                const char *hex = arg + 7;
                int hex_len = (int)cstr_len(hex);
                int byte_len = hex_len / 2;
                char *raw = (char *)0;
                if (byte_len > 0) {
                    raw = string_pool_alloc((unsigned int)byte_len);
                    if (raw) {
                        static const char hv[] = "0123456789abcdef";
                        int i;
                        for (i = 0; i < byte_len; i++) {
                            char hi = hex[i * 2], lo = hex[i * 2 + 1];
                            int hiv = 0, lov = 0, j;
                            for (j = 0; j < 16; j++) {
                                if (hi == hv[j] || hi == hv[j] - 32) hiv = j;
                                if (lo == hv[j] || lo == hv[j] - 32) lov = j;
                            }
                            raw[i] = (char)((hiv << 4) | lov);
                        }
                    }
                }
                {
                    char out_buf[64];
                    int result_len = objc_kernel_host_sha256(raw ? raw : "", (unsigned int)byte_len, out_buf, 64);
                    if (result_len > 0) {
                        unsigned int needed = 7 + (unsigned int)result_len * 2 + 1;
                        char *buf = string_pool_alloc(needed);
                        if (buf) {
                            static const char hc[] = "0123456789abcdef";
                            int i;
                            cstr_copy(buf, "NSData:", needed);
                            for (i = 0; i < result_len; i++) {
                                unsigned char c = (unsigned char)out_buf[i];
                                buf[7 + i * 2] = hc[(c >> 4) & 0x0f];
                                buf[7 + i * 2 + 1] = hc[c & 0x0f];
                            }
                            buf[7 + result_len * 2] = '\0';
                            return value_from_id((id)buf);
                        }
                    }
                }
            }
            return value_from_id((id)"NSData:");
        }

        /* ── Foundation collection dispatch ──────────────────────── */

        /* NSArray: [NSArray array] → empty immutable array */
        if (IS_FOUNDATION_CLASS("NSArray") && target.is_class && cstr_eq(sel_name, "array") && arg_count == 0) {
            unsigned int cid = g_ctx.next_coll_id++;
            return value_from_id(coll_make_marker("NSArr:", cid));
        }

        /* NSMutableArray: [NSMutableArray arrayWithCapacity:n] → empty mutable array */
        if (IS_FOUNDATION_CLASS("NSMutableArray") && target.is_class && cstr_eq(sel_name, "arrayWithCapacity:") && arg_count >= 1) {
            unsigned int cid = g_ctx.next_coll_id++;
            return value_from_id(coll_make_marker("NSMutArr:", cid));
        }

        /* NSMutableArray: [NSMutableArray array] → empty mutable array */
        if (IS_FOUNDATION_CLASS("NSMutableArray") && target.is_class && cstr_eq(sel_name, "array") && arg_count == 0) {
            unsigned int cid = g_ctx.next_coll_id++;
            return value_from_id(coll_make_marker("NSMutArr:", cid));
        }

        /* NSDictionary: [NSDictionary dictionary] → empty immutable dict */
        if (IS_FOUNDATION_CLASS("NSDictionary") && target.is_class && cstr_eq(sel_name, "dictionary") && arg_count == 0) {
            unsigned int cid = g_ctx.next_coll_id++;
            return value_from_id(coll_make_marker("NSDict:", cid));
        }

        /* NSMutableDictionary: [NSMutableDictionary dictionaryWithCapacity:n] → empty mutable dict */
        if (IS_FOUNDATION_CLASS("NSMutableDictionary") && target.is_class && cstr_eq(sel_name, "dictionaryWithCapacity:") && arg_count >= 1) {
            unsigned int cid = g_ctx.next_coll_id++;
            return value_from_id(coll_make_marker("NSMutDict:", cid));
        }

        /* NSMutableDictionary: [NSMutableDictionary dictionary] → empty mutable dict */
        if (IS_FOUNDATION_CLASS("NSMutableDictionary") && target.is_class && cstr_eq(sel_name, "dictionary") && arg_count == 0) {
            unsigned int cid = g_ctx.next_coll_id++;
            return value_from_id(coll_make_marker("NSMutDict:", cid));
        }

        /* NSDictionary: [NSDictionary dictionaryWithObject:obj forKey:key] → dict with one entry */
        if (IS_FOUNDATION_CLASS("NSDictionary") && target.is_class && cstr_eq(sel_name, "dictionaryWithObject:forKey:") && arg_count >= 2) {
            unsigned int cid = g_ctx.next_coll_id++;
            coll_add(cid, keyword_args[1], keyword_args[0]); /* key, value */
            return value_from_id(coll_make_marker("NSDict:", cid));
        }

        /* NSDictionary/NSMutableDictionary: [NSMutableDictionary dictionaryWithDictionary:dict] → shallow copy */
        if ((IS_FOUNDATION_CLASS("NSDictionary") || IS_FOUNDATION_CLASS("NSMutableDictionary")) &&
            target.is_class && cstr_eq(sel_name, "dictionaryWithDictionary:") && arg_count >= 1) {
            unsigned int new_cid = g_ctx.next_coll_id++;
            const char *src_s = (const char *)keyword_args[0].obj_val;
            unsigned int src_cid = coll_id_from_marker(src_s, "NSDict:");
            if (src_cid == 0) src_cid = coll_id_from_marker(src_s, "NSMutDict:");
            if (src_cid > 0) {
                /* Copy all entries from source dictionary */
                unsigned int i;
                for (i = 0; i < g_ctx.coll_entry_count; i++) {
                    if (g_ctx.coll_entries[i].coll_id == src_cid) {
                        coll_add(new_cid, g_ctx.coll_entries[i].key, g_ctx.coll_entries[i].value);
                    }
                }
            }
            return value_from_id(coll_make_marker("NSMutDict:", new_cid));
        }

        /* NSSet: [NSSet setWithArray:arr] → set from array */
        if (IS_FOUNDATION_CLASS("NSSet") && target.is_class && cstr_eq(sel_name, "setWithArray:") && arg_count >= 1) {
            unsigned int cid = g_ctx.next_coll_id++;
            const char *arr_s = (const char *)keyword_args[0].obj_val;
            unsigned int arr_cid = coll_id_from_marker(arr_s, "NSArr:");
            if (arr_cid == 0) arr_cid = coll_id_from_marker(arr_s, "NSMutArr:");
            if (arr_cid > 0) {
                /* Copy unique elements from array to set */
                unsigned int i;
                for (i = 0; i < g_ctx.coll_entry_count; i++) {
                    if (g_ctx.coll_entries[i].coll_id == arr_cid) {
                        /* Check if already in set */
                        int existing = coll_find_by_key(cid, &g_ctx.coll_entries[i].key);
                        if (existing < 0) {
                            coll_add(cid, g_ctx.coll_entries[i].key, g_ctx.coll_entries[i].value);
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
                        return g_ctx.coll_entries[idx].key;
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
                        g_ctx.coll_entries[(unsigned int)idx].key = keyword_args[1];
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
                    for (i = 0; i < g_ctx.coll_entry_count; i++) {
                        if (g_ctx.coll_entries[i].coll_id != cid) continue;
                        if (g_ctx.coll_entries[i].key.is_int && keyword_args[0].is_int &&
                            g_ctx.coll_entries[i].key.int_val == keyword_args[0].int_val) {
                            return value_from_int((int)pos);
                        }
                        if (g_ctx.coll_entries[i].key.is_id && keyword_args[0].is_id &&
                            g_ctx.coll_entries[i].key.obj_val != 0 && keyword_args[0].obj_val != 0 &&
                            cstr_eq((const char *)g_ctx.coll_entries[i].key.obj_val,
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
                    if (idx >= 0) return g_ctx.coll_entries[idx].value;
                    return value_from_id((id)"(nil)");
                }

                /* [mutDict setObject:obj forKey:key] → set key-value */
                if (cstr_eq(sel_name, "setObject:forKey:") && arg_count >= 2) {
                    Value val = keyword_args[0];  /* first arg after setObject: */
                    Value key = keyword_args[1];   /* second arg after forKey: */
                    int idx = coll_find_by_key(cid, &key);
                    if (idx >= 0) {
                        g_ctx.coll_entries[idx].value = val;
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

                /* [mutDict addEntriesFromDictionary:other] → merge entries from other dict */
                if (cstr_eq(sel_name, "addEntriesFromDictionary:") && arg_count >= 1) {
                    const char *other_s = (const char *)keyword_args[0].obj_val;
                    unsigned int other_cid = coll_id_from_marker(other_s, "NSDict:");
                    if (other_cid == 0) other_cid = coll_id_from_marker(other_s, "NSMutDict:");
                    if (other_cid > 0) {
                        unsigned int i;
                        for (i = 0; i < g_ctx.coll_entry_count; i++) {
                            if (g_ctx.coll_entries[i].coll_id == other_cid) {
                                /* Add or update entry in target dict */
                                int idx = coll_find_by_key(cid, &g_ctx.coll_entries[i].key);
                                if (idx >= 0) {
                                    g_ctx.coll_entries[idx].value = g_ctx.coll_entries[i].value;
                                } else {
                                    coll_add(cid, g_ctx.coll_entries[i].key, g_ctx.coll_entries[i].value);
                                }
                            }
                        }
                    }
                    return value_from_id(receiver);
                }

                /* [dict allKeys] → array of keys */
                if (cstr_eq(sel_name, "allKeys")) {
                    unsigned int new_cid = g_ctx.next_coll_id++;
                    unsigned int i;
                    for (i = 0; i < g_ctx.coll_entry_count; i++) {
                        if (g_ctx.coll_entries[i].coll_id == cid) {
                            Value dummy = value_void();
                            coll_add(new_cid, g_ctx.coll_entries[i].key, dummy);
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
                    unsigned int new_cid = g_ctx.next_coll_id++;
                    unsigned int i;
                    for (i = 0; i < g_ctx.coll_entry_count; i++) {
                        if (g_ctx.coll_entries[i].coll_id == cid) {
                            Value dummy = value_void();
                            coll_add(new_cid, g_ctx.coll_entries[i].value, dummy);
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
                        for (i = 0; i < g_ctx.coll_entry_count; i++) {
                            if (g_ctx.coll_entries[i].coll_id == cid) {
                                int other_idx = coll_find_by_key(other_cid, &g_ctx.coll_entries[i].key);
                                if (other_idx < 0) return value_from_int(0);
                                /* Compare values — both are Values, check fields */
                                if (g_ctx.coll_entries[i].value.is_int != g_ctx.coll_entries[other_idx].value.is_int ||
                                    g_ctx.coll_entries[i].value.is_id != g_ctx.coll_entries[other_idx].value.is_id ||
                                    g_ctx.coll_entries[i].value.is_float != g_ctx.coll_entries[other_idx].value.is_float)
                                    return value_from_int(0);
                                if (g_ctx.coll_entries[i].value.is_int && g_ctx.coll_entries[i].value.int_val != g_ctx.coll_entries[other_idx].value.int_val)
                                    return value_from_int(0);
                                if (g_ctx.coll_entries[i].value.is_float && g_ctx.coll_entries[i].value.float_val != g_ctx.coll_entries[other_idx].value.float_val)
                                    return value_from_int(0);
                                if (g_ctx.coll_entries[i].value.is_id) {
                                    const char *a = (const char *)g_ctx.coll_entries[i].value.obj_val;
                                    const char *b = (const char *)g_ctx.coll_entries[other_idx].value.obj_val;
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
                        if (idx >= 0) return g_ctx.coll_entries[idx].key;
                    }
                    return value_from_id((id)0);
                }

                /* [arr firstObject] → first element or nil */
                if (cstr_eq(sel_name, "firstObject")) {
                    if (coll_count(cid) > 0) {
                        int idx = coll_get_nth(cid, 0);
                        if (idx >= 0) return g_ctx.coll_entries[idx].key;
                    }
                    return value_from_id((id)0);
                }

                /* [arr arrayByAddingObject:obj] → new array with object appended */
                if (cstr_eq(sel_name, "arrayByAddingObject:") && arg_count >= 1) {
                    unsigned int new_cid = g_ctx.next_coll_id++;
                    unsigned int i;
                    for (i = 0; i < g_ctx.coll_entry_count; i++) {
                        if (g_ctx.coll_entries[i].coll_id == cid) {
                            coll_add(new_cid, g_ctx.coll_entries[i].key, g_ctx.coll_entries[i].value);
                        }
                    }
                    coll_add(new_cid, keyword_args[0], value_void());
                    return value_from_id(coll_make_marker("NSArr:", new_cid));
                }
                }

                /* [dict valueForKey:key] → same as objectForKey: */
                if (cstr_eq(sel_name, "valueForKey:") && arg_count >= 1) {
                    int idx = coll_find_by_key(cid, &keyword_args[0]);
                    if (idx >= 0) return g_ctx.coll_entries[idx].value;
                    return value_from_id((id)"(nil)");
                }

                /* [mutDict setValue:val forKey:key] → same as setObject:forKey: */
                if (cstr_eq(sel_name, "setValue:forKey:") && arg_count >= 2) {
                    Value val = keyword_args[0];
                    Value key = keyword_args[1];
                    int idx = coll_find_by_key(cid, &key);
                    if (idx >= 0) {
                        g_ctx.coll_entries[idx].value = val;
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
                        unsigned int saved_var_count = g_ctx.var_count;
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
                                            if (vi < g_ctx.var_count) {
                                                cap_var->is_id = g_ctx.vars[vi].is_id;
                                                cap_var->value = g_ctx.vars[vi].value;
                                                cap_var->is_int = g_ctx.vars[vi].is_int;
                                                cap_var->int_value = g_ctx.vars[vi].int_value;
                                                cap_var->is_float = g_ctx.vars[vi].is_float;
                                                cap_var->float_value = g_ctx.vars[vi].float_value;
                                                cap_var->is_class = g_ctx.vars[vi].is_class;
                                                cap_var->cls = g_ctx.vars[vi].cls;
                                                cap_var->is_sel = g_ctx.vars[vi].is_sel;
                                                cap_var->sel = g_ctx.vars[vi].sel;
                                                cap_var->is_block_captured = g_ctx.vars[vi].is_block_captured;
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
                                            arg_var->is_id = g_ctx.coll_entries[entry_idx].key.is_id;
                                            arg_var->value = g_ctx.coll_entries[entry_idx].key.obj_val;
                                            arg_var->is_int = g_ctx.coll_entries[entry_idx].key.is_int;
                                            arg_var->int_value = g_ctx.coll_entries[entry_idx].key.int_val;
                                            arg_var->is_class = g_ctx.coll_entries[entry_idx].key.is_class;
                                            arg_var->cls = g_ctx.coll_entries[entry_idx].key.cls_val;
                                            arg_var->is_sel = g_ctx.coll_entries[entry_idx].key.is_sel;
                                            arg_var->sel = g_ctx.coll_entries[entry_idx].key.sel_val;
                                        } else if (ai == 1) {
                                            /* Second arg: the index */
                                            arg_var->is_int = 1;
                                            arg_var->int_value = (int)idx;
                                            arg_var->is_id = 0;
                                        } else if (ai == 2) {
                                            /* Third arg (BOOL *stop) — initialize to 0 */
                                            arg_var->is_int = 1;
                                            arg_var->int_value = 0;
                                            arg_var->is_id = 0;
                                        }
                                    }
                                }
                                /* Also set up a default 'stop' variable if the block
                                 * has fewer than 3 parameters, for compatibility with
                                 * scripts that might assume its existence. */
                                if (blk->arg_count < 3) {
                                    InterpVar *stop_var = interp_get_or_create_var("stop");
                                    if (stop_var) {
                                        stop_var->is_int = 1;
                                        stop_var->int_value = 0;
                                    }
                                }
                            }

                            /* Execute the block body */
                            g_ctx.return_pending = 0;
                            eval_source_range(0, blk->source_len, blk->source, 0);

                            /* Check for interpreter error after block execution */
                            if (g_ctx.error_code != OBJC_INTERP_OK) break;

                            /* Check stop flag. Use the name of the 3rd parameter if it exists,
                             * otherwise fall back to "stop". */
                            {
                                const char *stop_name = (blk->arg_count >= 3) ? blk->arg_names[2] : "stop";
                                InterpVar *stop_var = interp_find_var(stop_name);
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
                                        if (cap_var && vi < g_ctx.var_count) {
                                            g_ctx.vars[vi].is_id = cap_var->is_id;
                                            g_ctx.vars[vi].value = cap_var->value;
                                            g_ctx.vars[vi].is_int = cap_var->is_int;
                                            g_ctx.vars[vi].int_value = cap_var->int_value;
                                            g_ctx.vars[vi].is_float = cap_var->is_float;
                                            g_ctx.vars[vi].float_value = cap_var->float_value;
                                            g_ctx.vars[vi].is_class = cap_var->is_class;
                                            g_ctx.vars[vi].cls = cap_var->cls;
                                            g_ctx.vars[vi].is_sel = cap_var->is_sel;
                                            g_ctx.vars[vi].sel = cap_var->sel;
                                        }
                                    }
                                }
                            }

                            g_ctx.var_count = saved_var_count;
                        }
                    }
                    return value_from_id(receiver);
                }
            }
        }

        /* Class method dispatch: [ClassName userDefinedMethod:]
         * When the target is a class (not an instance), check for
         * interpreter-registered class methods (+ methods) before
         * falling through to the error. */
        if (target.is_class && target_class_name) {
            /* [ClassName class] — return the class itself (meta-class identity) */
            if (cstr_eq(sel_name, "class")) {
                return value_from_class(target.cls_val);
            }
            unsigned int mi = find_interpreter_method(sel, target, receiver, 0);
            if (mi < g_ctx.method_count) {
                return execute_interpreter_method(p, &g_ctx.methods[mi], sel, receiver,
                                                  keyword_args, arg_count, 1);
            }
        }

        /* NSObject: isKindOfClass: — walk class hierarchy */
        if (cstr_eq(sel_name, "isKindOfClass:") && target.is_id && arg_count >= 1) {
            Class target_cls = 0;
            if (keyword_args[0].is_class) {
                target_cls = keyword_args[0].cls_val;
            } else if (keyword_args[0].is_id && keyword_args[0].obj_val != 0) {
                target_cls = class_for_fdobj_marker(keyword_args[0].obj_val);
                if (!target_cls) target_cls = object_getClass(keyword_args[0].obj_val);
            }
            if (target_cls) {
                Class recv_cls = 0;
                const char *r = (const char *)receiver;
                if (r && is_string_pool_pointer(receiver)) {
                    if (cstr_starts(r, "FDObj:")) {
                        recv_cls = class_for_fdobj_marker(receiver);
                    } else {
                        /* Foundation tagged objects — map marker prefix to sentinel class.
                         * Must match objc_interpreter.c foundation_classes[] order:
                         * NSObject=1, NSString=2, NSNumber=3, NSArray=4, NSMutableArray=5,
                         * NSDictionary=6, NSMutableDictionary=7, NSSet=8, NSData=9 */
                        if (cstr_starts(r, "NSNumber:") || cstr_starts(r, "NSFloat:")) recv_cls = (Class)3;
                        else if (cstr_starts(r, "NSArr:")) recv_cls = (Class)4;
                        else if (cstr_starts(r, "NSMutArr:")) recv_cls = (Class)5;
                        else if (cstr_starts(r, "NSDict:")) recv_cls = (Class)6;
                        else if (cstr_starts(r, "NSMutDict:")) recv_cls = (Class)7;
                        else if (cstr_starts(r, "NSSet:")) recv_cls = (Class)8;
                        else if (cstr_starts(r, "NSData:")) recv_cls = (Class)9;
                        else if (cstr_starts(r, "NSMutStr:")) recv_cls = (Class)12;
                        else if (cstr_starts(r, "NSBlock:")) recv_cls = (Class)20;
                        /* String pool pointers without NSStr: prefix are NSString */
                        else recv_cls = (Class)2;
                    }
                } else {
                    recv_cls = object_getClass(receiver);
                }
                while (recv_cls) {
                    if (recv_cls == target_cls) return value_from_int(1);
                    const char *name = class_name_for_ptr(recv_cls);
                    if (!name) break;
                    const char *super_name = class_get_superclass_name(name);
                    if (!super_name || super_name[0] == '\0') break;
                    recv_cls = class_ptr_for_name(super_name);
                }
            }
            return value_from_int(0);
        }

        /* NSObject: isMemberOfClass: — exact class match */
        if (cstr_eq(sel_name, "isMemberOfClass:") && target.is_id && arg_count >= 1) {
            Class target_cls = 0;
            if (keyword_args[0].is_class) {
                target_cls = keyword_args[0].cls_val;
            } else if (keyword_args[0].is_id && keyword_args[0].obj_val != 0) {
                target_cls = class_for_fdobj_marker(keyword_args[0].obj_val);
                if (!target_cls) target_cls = object_getClass(keyword_args[0].obj_val);
            }
            if (target_cls) {
                Class recv_cls = 0;
                const char *r = (const char *)receiver;
                if (r && is_string_pool_pointer(receiver)) {
                    if (cstr_starts(r, "FDObj:")) {
                        recv_cls = class_for_fdobj_marker(receiver);
                    } else {
                        if (cstr_starts(r, "NSNumber:") || cstr_starts(r, "NSFloat:")) recv_cls = (Class)3;
                        else if (cstr_starts(r, "NSArr:")) recv_cls = (Class)4;
                        else if (cstr_starts(r, "NSMutArr:")) recv_cls = (Class)5;
                        else if (cstr_starts(r, "NSDict:")) recv_cls = (Class)6;
                        else if (cstr_starts(r, "NSMutDict:")) recv_cls = (Class)7;
                        else if (cstr_starts(r, "NSSet:")) recv_cls = (Class)8;
                        else if (cstr_starts(r, "NSData:")) recv_cls = (Class)9;
                        else if (cstr_starts(r, "NSMutStr:")) recv_cls = (Class)12;
                        else if (cstr_starts(r, "NSBlock:")) recv_cls = (Class)20;
                        else recv_cls = (Class)2;
                    }
                } else {
                    recv_cls = object_getClass(receiver);
                }
                return value_from_int(recv_cls == target_cls ? 1 : 0);
            }
            return value_from_int(0);
        }

        /* NSObject: copy / mutableCopy — return self for value types.
         * In this interpreter, strings and collections are value-typed
         * (C strings in the string pool, or interpreter-managed objects),
         * so copy/mutableCopy can return the receiver directly. */
        if ((cstr_eq(sel_name, "copy") || cstr_eq(sel_name, "mutableCopy")) &&
            target.is_id && receiver != 0) {
            return value_from_id(receiver);
        }

        /* NSObject: retain / release / autorelease — no-ops in interpreter.
         * The interpreter uses a string pool and collection side table,
         * not reference counting. These messages return self (for retain,
         * autorelease) or void (for release) to avoid "does not respond"
         * errors when code uses ARC patterns. */
        if (cstr_eq(sel_name, "retain") && target.is_id) {
            return value_from_id(receiver);
        }
        if (cstr_eq(sel_name, "release") && target.is_id) {
            return value_void();
        }
        if (cstr_eq(sel_name, "autorelease") && target.is_id) {
            /* In a real runtime, this adds to the current autorelease pool.
             * Here we just return self — the pool stack exists but is a no-op. */
            return value_from_id(receiver);
        }
        if (cstr_eq(sel_name, "drain") && target.is_id) {
            /* NSAutoreleasePool drain — no-op */
            return value_void();
        }

        /* NSObject: drain / release / autorelease ... (existing no-ops) */

        /* Fall through: check for forwarding before reporting error */
        if (target.is_id && receiver != 0 && is_string_pool_pointer(receiver) && cstr_starts((const char *)receiver, "FDObj:")) {
             /* 1. Try forwardingTargetForSelector: */
             SEL fwd_target_sel = sel_registerName("forwardingTargetForSelector:");
             unsigned int mi_target = find_interpreter_method(fwd_target_sel, target, receiver, 0);
             if (mi_target < g_ctx.method_count) {
                 Value sel_val = value_from_sel(sel);
                 Value fwd_target = execute_interpreter_method(p, &g_ctx.methods[mi_target], fwd_target_sel, receiver, &sel_val, 1, 0);
                 if (fwd_target.is_id && fwd_target.obj_val != 0 && fwd_target.obj_val != receiver) {
                     /* Re-dispatch to new target using eval_source_range trick */
                     InterpVar *tmp = interp_get_or_create_var("__fwd_target");
                     if (tmp) {
                         tmp->is_id = 1; tmp->value = fwd_target.obj_val;
                         /* Build message send source ... this is complex for many args.
                          * For now, just support simple re-dispatch if target changed. */
                     }
                 }
             }

             /* 2. Try forwardInvocation: */
             SEL fwd_sel = sel_registerName("forwardInvocation:");
             unsigned int mi = find_interpreter_method(fwd_sel, target, receiver, 0);
             if (mi < g_ctx.method_count) {
                 unsigned int inv_id = g_ctx.next_invocation_id % MAX_INVOCATIONS;
                 g_ctx.invocations[inv_id].selector = sel;
                 g_ctx.invocations[inv_id].receiver = receiver;
                 g_ctx.invocations[inv_id].arg_count = arg_count;
                 {
                     unsigned int ai;
                     for (ai = 0; ai < arg_count && ai < 16; ai++)
                         g_ctx.invocations[inv_id].args[ai] = keyword_args[ai];
                 }
                 g_ctx.next_invocation_id++;

                 char *buf = string_pool_alloc(24);
                 if (buf) {
                     cstr_copy(buf, "FDInv:", 24);
                     {
                         char tmp[12]; int ti = 0, v = (int)inv_id;
                         if (v == 0) buf[6] = '0', buf[7] = '\0';
                         else {
                             while (v > 0) { tmp[ti++] = '0' + (v % 10); v /= 10; }
                             int j = 0; while (ti > 0) buf[6 + j++] = tmp[--ti];
                             buf[6 + j] = '\0';
                         }
                     }
                     Value inv_val = value_from_id((id)buf);
                     return execute_interpreter_method(p, &g_ctx.methods[mi], fwd_sel, receiver, &inv_val, 1, 0);
                 }
             }
        }

        /* Fall through: report error */
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
