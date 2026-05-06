/* objc_interp_format.c
 * Extracted NSLog, format, and string GC helpers from the interpreter.
 */

#include "objc_interp_types.h"
#include "objc_interp_context.h"
#include "objc_interp_format.h"
#include "objc_interp_state.h"
#include <string.h>

/* Runtime / host helpers used by formatting and NSLog output. */
extern Class object_getClass(id);
extern void interp_emit_stream(const char *ptr, unsigned int len);
extern const char *sel_getName(SEL sel);

/* Helper: write integer to buffer, return chars written */
static int int_to_buf(char *buf, int capacity, int val) {
    int neg = val < 0;
    int i = 0;
    int start;
    if (neg) val = -val;
    if (capacity <= 1) return 0;
    start = neg ? 1 : 0;
    if (val == 0) { buf[0] = '0'; return 1; }
    while (val > 0 && i + start < capacity - 1) {
        buf[start + i] = '0' + (val % 10);
        val /= 10;
        i++;
    }
    if (neg && start + i < capacity) { buf[start + i] = '-'; i++; }
    /* Reverse digits */
    { int lo = 0, hi = i - 1;
      while (lo < hi) { char t = buf[lo]; buf[lo] = buf[hi]; buf[hi] = t; lo++; hi--; } }
    buf[i] = '\0';
    return i;
}

/* ── NSLog implementation ────────────────────────────────────────── */

void nslog_append(const char *text, unsigned int len) {
    unsigned int i;
    interp_emit_stream(text, len);
    for (i = 0; i < len && g_ctx.nslog_offset + 1 < OBJC_INTERP_NSLOG_BUFFER_SIZE; i++) {
        g_ctx.nslog_buffer[g_ctx.nslog_offset++] = text[i];
    }
    g_ctx.nslog_buffer[g_ctx.nslog_offset] = '\0';
}

void nslog_append_char(char ch) {
    char chunk[1];
    chunk[0] = ch;
    interp_emit_stream(chunk, 1u);
    if (g_ctx.nslog_offset + 1 < OBJC_INTERP_NSLOG_BUFFER_SIZE) {
        g_ctx.nslog_buffer[g_ctx.nslog_offset++] = ch;
        g_ctx.nslog_buffer[g_ctx.nslog_offset] = '\0';
    }
}

void nslog_append_int(int value) {
    char buf[16];
    int i = 0;
    int negative = 0;
    unsigned int u;

    if (value < 0) {
        negative = 1;
        u = (unsigned int)(-(value + 1)) + 1u;
    } else {
        u = (unsigned int)value;
    }

    if (u == 0) {
        nslog_append_char('0');
        return;
    }

    while (u > 0 && i < 15) {
        buf[i++] = '0' + (char)(u % 10u);
        u /= 10u;
    }

    if (negative) nslog_append_char('-');
    while (i > 0) {
        i--;
        nslog_append_char(buf[i]);
    }
}

void nslog_append_long(long value) {
    char buf[22];
    int i = 0;
    int negative = 0;
    unsigned long u;

    if (value < 0) {
        negative = 1;
        u = (unsigned long)(-(value + 1)) + 1ul;
    } else {
        u = (unsigned long)value;
    }

    if (u == 0) {
        nslog_append_char('0');
        return;
    }

    while (u > 0 && i < 21) {
        buf[i++] = '0' + (char)(u % 10ul);
        u /= 10ul;
    }

    if (negative) nslog_append_char('-');
    while (i > 0) {
        i--;
        nslog_append_char(buf[i]);
    }
}

/* ── NSLog format string evaluation ─────────────────────────────── */

/* Format values into a string pool entry, similar to NSLog but without
 * the trailing newline and host stream output. Returns the string pool
 * pointer as an id value. */
void format_warn_missing_argument(char spec) {
    nslog_append("warning: missing argument for format specifier %", 48);
    nslog_append(&spec, 1);
    nslog_append("\n", 1);
}

Value format_values_to_pool(const char *fmt, Value *args, int arg_count) {
    char buf[1024];
    unsigned int pos = 0;
    unsigned int fi = 0;
    int arg_idx = 0;

    if (fmt == 0) {
        char *r = string_pool_alloc(7);
        if (r == 0) return value_from_id(0);
        cstr_copy(r, "(null)", 7);
        return value_from_id((id)r);
    }

    while (fmt[fi] != '\0' && pos < sizeof(buf) - 1) {
        if (fmt[fi] == '%' && fmt[fi + 1] != '\0') {
            fi++;
            /* Parse format specifier: [flags][width][.precision][length]conversion */
            int flag_zero_pad = 0;
            int flag_left_align = 0;
            int flag_plus = 0;
            int flag_space = 0;
            int width = 0;
            int precision = -1; /* -1 means unspecified */
            int length_l = 0;  /* 0=none, 1=l, 2=ll */

            /* Flags */
            while (fmt[fi] == '0' || fmt[fi] == '-' || fmt[fi] == '+' || fmt[fi] == ' ') {
                if (fmt[fi] == '0') flag_zero_pad = 1;
                else if (fmt[fi] == '-') flag_left_align = 1;
                else if (fmt[fi] == '+') flag_plus = 1;
                else if (fmt[fi] == ' ') flag_space = 1;
                fi++;
            }

            /* Width (digits) */
            while (fmt[fi] >= '0' && fmt[fi] <= '9') {
                width = width * 10 + (fmt[fi] - '0');
                fi++;
            }

            /* Precision (.digits) */
            if (fmt[fi] == '.') {
                fi++;
                precision = 0;
                while (fmt[fi] >= '0' && fmt[fi] <= '9') {
                    precision = precision * 10 + (fmt[fi] - '0');
                    fi++;
                }
            }

            /* Length modifier (l, ll, z) */
            if (fmt[fi] == 'l') {
                length_l = 1;
                fi++;
                if (fmt[fi] == 'l') {
                    length_l = 2;
                    fi++;
                }
            } else if (fmt[fi] == 'z') {
                /* size_t — treat as unsigned long */
                length_l = 1;
                fi++;
            }

            /* Conversion specifier */
            switch (fmt[fi]) {
                case '%':
                    if (pos < sizeof(buf)-1) buf[pos++] = '%';
                    break;
                case '@':
                    if (arg_idx < arg_count) {
                        Value v = args[arg_idx++];
                        if (v.is_id && v.obj_val != 0) {
                            const char *s = (const char *)v.obj_val;
                            if (cstr_eq_n(s, "NSData:", 7)) {
                                const char *hex = s + 7;
                                int hex_len = (int)cstr_len(hex);
                                if (pos < sizeof(buf)-1) buf[pos++] = '<';
                                { int i; for (i = 0; i < hex_len && pos < sizeof(buf)-2; i++) buf[pos++] = hex[i]; }
                                if (pos < sizeof(buf)-1) buf[pos++] = '>';
                            } else if (cstr_eq_n(s, "NSNumber:", 9)) {
                                const char *val = s + 9;
                                while (*val && pos < sizeof(buf)-1) buf[pos++] = *val++;
                            } else if (cstr_eq_n(s, "NSFloat:", 8)) {
                                const char *val = s + 8;
                                while (*val && pos < sizeof(buf)-1) buf[pos++] = *val++;
                            } else if (cstr_eq_n(s, "FDObj:", 6)) {
                                if (pos < sizeof(buf)-1) buf[pos++] = '<';
                                { const char *cn = s + 6; while (*cn && pos < sizeof(buf)-2) buf[pos++] = *cn++; }
                                if (pos < sizeof(buf)-1) buf[pos++] = '>';
                            } else if (cstr_eq_n(s, "NSMutStr:", 9)) {
                                const char *val = s + 9;
                                while (*val && pos < sizeof(buf)-1) buf[pos++] = *val++;
                            } else if (cstr_eq_n(s, "NSArr:", 6) || cstr_eq_n(s, "NSMutArr:", 9)) {
                                /* Format array as ( elem1, elem2, ... ) */
                                unsigned int cid = coll_id_from_marker(s, "NSArr:");
                                if (cid == 0) cid = coll_id_from_marker(s, "NSMutArr:");
                                if (pos < sizeof(buf)-1) buf[pos++] = '(';
                                if (cid > 0) {
                                    unsigned int cnt = coll_count(cid);
                                    unsigned int ei;
                                    for (ei = 0; ei < cnt; ei++) {
                                        int idx = coll_get_nth(cid, ei);
                                        if (idx >= 0) {
                                            Value elem = g_ctx.coll_entries[(unsigned int)idx].key;
                                            if (ei > 0) { if (pos < sizeof(buf)-2) { buf[pos++] = ','; buf[pos++] = ' '; } }
                                            /* Format element value */
                                            if (elem.is_id && elem.obj_val != 0) {
                                                const char *es = (const char *)elem.obj_val;
                                                if (cstr_eq_n(es, "NSNumber:", 9)) es += 9;
                                                else if (cstr_eq_n(es, "NSFloat:", 8)) es += 8;
                                                while (*es && pos < sizeof(buf)-1) buf[pos++] = *es++;
                                            } else if (elem.is_int) {
                                                pos += int_to_buf(buf + pos, sizeof(buf) - pos, elem.int_val);
                                            }
                                        }
                                    }
                                }
                                if (pos < sizeof(buf)-1) buf[pos++] = ')';
                            } else if (cstr_eq_n(s, "NSDict:", 7) || cstr_eq_n(s, "NSMutDict:", 10)) {
                                /* Format dictionary as { key1 = val1; key2 = val2; } */
                                unsigned int cid = coll_id_from_marker(s, "NSDict:");
                                if (cid == 0) cid = coll_id_from_marker(s, "NSMutDict:");
                                if (pos < sizeof(buf)-1) buf[pos++] = '{';
                                if (cid > 0) {
                                    unsigned int cnt = coll_count(cid);
                                    unsigned int ei;
                                    for (ei = 0; ei < cnt; ei++) {
                                        int idx = coll_get_nth(cid, ei);
                                        if (idx >= 0) {
                                            Value key = g_ctx.coll_entries[(unsigned int)idx].key;
                                            Value val = g_ctx.coll_entries[(unsigned int)idx].value;
                                            if (ei > 0) { if (pos < sizeof(buf)-2) { buf[pos++] = ';'; buf[pos++] = ' '; } }
                                            /* Format key */
                                            if (key.is_id && key.obj_val != 0) {
                                                const char *ks = (const char *)key.obj_val;
                                                while (*ks && pos < sizeof(buf)-1) buf[pos++] = *ks++;
                                            }
                                            if (pos < sizeof(buf)-3) { buf[pos++] = ' '; buf[pos++] = '='; buf[pos++] = ' '; }
                                            /* Format value */
                                            if (val.is_id && val.obj_val != 0) {
                                                const char *vs = (const char *)val.obj_val;
                                                if (cstr_eq_n(vs, "NSNumber:", 9)) vs += 9;
                                                else if (cstr_eq_n(vs, "NSFloat:", 8)) vs += 8;
                                                while (*vs && pos < sizeof(buf)-1) buf[pos++] = *vs++;
                                            } else if (val.is_int) {
                                                pos += int_to_buf(buf + pos, sizeof(buf) - pos, val.int_val);
                                            }
                                        }
                                    }
                                }
                                if (pos < sizeof(buf)-1) buf[pos++] = '}';
                            } else if (cstr_eq_n(s, "NSSet:", 6)) {
                                /* Format set as { elem1, elem2, ... } */
                                unsigned int cid = coll_id_from_marker(s, "NSSet:");
                                if (pos < sizeof(buf)-1) buf[pos++] = '{';
                                if (cid > 0) {
                                    unsigned int cnt = coll_count(cid);
                                    unsigned int ei;
                                    for (ei = 0; ei < cnt; ei++) {
                                        int idx = coll_get_nth(cid, ei);
                                        if (idx >= 0) {
                                            Value elem = g_ctx.coll_entries[(unsigned int)idx].value;
                                            if (ei > 0) { if (pos < sizeof(buf)-2) { buf[pos++] = ','; buf[pos++] = ' '; } }
                                            if (elem.is_id && elem.obj_val != 0) {
                                                const char *es = (const char *)elem.obj_val;
                                                while (*es && pos < sizeof(buf)-1) buf[pos++] = *es++;
                                            }
                                        }
                                    }
                                }
                                if (pos < sizeof(buf)-1) buf[pos++] = '}';
                            } else {
                                while (*s && pos < sizeof(buf)-1) buf[pos++] = *s++;
                            }
                        } else if (v.is_class && v.cls_val != 0) {
                            const char *name = 0;
                            unsigned int vi;
                            for (vi = 0; vi < g_ctx.var_count; vi++) {
                                if (g_ctx.vars[vi].is_class && g_ctx.vars[vi].cls == v.cls_val) {
                                    name = g_ctx.vars[vi].name; break;
                                }
                            }
                            if (name == 0) name = "Class";
                            while (*name && pos < sizeof(buf)-1) buf[pos++] = *name++;
                        } else if (v.is_sel && v.sel_val != 0) {
                            const char *sel_name = sel_getName(v.sel_val);
                            if (sel_name) { while (*sel_name && pos < sizeof(buf)-1) buf[pos++] = *sel_name++; }
                        } else if (v.is_int) {
                            /* Format int as decimal */
                            int val = v.int_val;
                            int neg = val < 0;
                            if (neg) val = -val;
                            char tmp[12]; int ti = 0;
                            if (val == 0) tmp[ti++] = '0';
                            else { while (val > 0) { tmp[ti++] = '0' + (val % 10); val /= 10; } }
                            if (neg && pos < sizeof(buf)-1) buf[pos++] = '-';
                            while (ti > 0 && pos < sizeof(buf)-1) buf[pos++] = tmp[--ti];
                        } else {
                            const char *nil_s = "(nil)";
                            while (*nil_s && pos < sizeof(buf)-1) buf[pos++] = *nil_s++;
                        }
                    } else {
                        format_warn_missing_argument('@');
                    }
                    break;
                case 'd': case 'i': {
                    /* Signed integer, with optional width/zero-padding */
                    if (arg_idx < arg_count) {
                        Value v = args[arg_idx++];
                        long val;
                        int neg;
                        char tmp[22]; int ti = 0;
                        int sign_len = 0;

                        if (v.is_int) {
                            val = (length_l > 0) ? (long)v.int_val : (long)v.int_val;
                        } else if (v.is_id) {
                            val = (long)v.obj_val;
                        } else if (v.is_float) {
                            val = (long)v.float_val;
                        } else {
                            val = 0;
                        }
                        neg = val < 0;
                        if (neg) { val = -val; sign_len = 1; }
                        if (flag_plus && !neg) sign_len = 1;
                        else if (flag_space && !neg) sign_len = 1;

                        if (val == 0) tmp[ti++] = '0';
                        else { while (val > 0) { tmp[ti++] = '0' + (int)(val % 10); val /= 10; } }

                        /* Width padding */
                        if (width > 0 && !flag_left_align) {
                            int total = ti + sign_len;
                            char pad = flag_zero_pad ? '0' : ' ';
                            /* If zero-padding, sign goes first then zeros */
                            if (flag_zero_pad) {
                                if (neg && pos < sizeof(buf)-1) buf[pos++] = '-';
                                else if (flag_plus && pos < sizeof(buf)-1) buf[pos++] = '+';
                                else if (flag_space && pos < sizeof(buf)-1) buf[pos++] = ' ';
                                while (total < width && pos < sizeof(buf)-1) { buf[pos++] = pad; total++; }
                            } else {
                                while (total < width && pos < sizeof(buf)-1) { buf[pos++] = pad; total++; }
                                if (neg && pos < sizeof(buf)-1) buf[pos++] = '-';
                                else if (flag_plus && pos < sizeof(buf)-1) buf[pos++] = '+';
                                else if (flag_space && pos < sizeof(buf)-1) buf[pos++] = ' ';
                            }
                        } else {
                            if (neg && pos < sizeof(buf)-1) buf[pos++] = '-';
                            else if (flag_plus && pos < sizeof(buf)-1) buf[pos++] = '+';
                            else if (flag_space && pos < sizeof(buf)-1) buf[pos++] = ' ';
                        }
                        while (ti > 0 && pos < sizeof(buf)-1) buf[pos++] = tmp[--ti];
                        /* Left-align padding */
                        if (width > 0 && flag_left_align) {
                            int total = ti + sign_len;
                            while (total < width && pos < sizeof(buf)-1) { buf[pos++] = ' '; total++; }
                        }
                    } else {
                        format_warn_missing_argument(fmt[fi]);
                    }
                    break;
                }
                case 'u': {
                    /* Unsigned integer, with optional width/zero-padding */
                    if (arg_idx < arg_count) {
                        Value v = args[arg_idx++];
                        unsigned long val;
                        char tmp[22]; int ti = 0;

                        if (v.is_int) {
                            val = (unsigned long)(v.int_val);
                        } else if (v.is_id) {
                            val = (unsigned long)v.obj_val;
                        } else {
                            val = 0;
                        }
                        if (val == 0) tmp[ti++] = '0';
                        else { while (val > 0) { tmp[ti++] = '0' + (int)(val % 10); val /= 10; } }

                        if (width > 0 && !flag_left_align) {
                            int total = ti;
                            char pad = flag_zero_pad ? '0' : ' ';
                            while (total < width && pos < sizeof(buf)-1) { buf[pos++] = pad; total++; }
                        }
                        while (ti > 0 && pos < sizeof(buf)-1) buf[pos++] = tmp[--ti];
                        if (width > 0 && flag_left_align) {
                            int total = ti;
                            while (total < width && pos < sizeof(buf)-1) { buf[pos++] = ' '; total++; }
                        }
                    } else {
                        format_warn_missing_argument('u');
                    }
                    break;
                }
                case 'c': {
                    /* Character */
                    if (arg_idx < arg_count) {
                        Value v = args[arg_idx++];
                        char ch;
                        if (v.is_int) ch = (char)v.int_val;
                        else if (v.is_id && v.obj_val != 0) ch = ((const char *)v.obj_val)[0];
                        else ch = '?';
                        if (pos < sizeof(buf)-1) buf[pos++] = ch;
                    } else {
                        format_warn_missing_argument('c');
                    }
                    break;
                }
                case 'f': {
                    if (arg_idx >= arg_count) {
                        format_warn_missing_argument('f');
                    } else if (pos < sizeof(buf) - 20) {
                        Value v = args[arg_idx++];
                        double fv = v.is_float ? v.float_val : (v.is_int ? (double)v.int_val : 0.0);
                        int neg = fv < 0.0;
                        int prec = (precision >= 0) ? precision : 6;
                        if (neg) fv = -fv;
                        unsigned long ipart = (unsigned long)fv;
                        double fpart = fv - (double)ipart;
                        /* Write sign */
                        if (neg && pos < sizeof(buf)-1) buf[pos++] = '-';
                        else if (flag_plus && pos < sizeof(buf)-1) buf[pos++] = '+';
                        else if (flag_space && pos < sizeof(buf)-1) buf[pos++] = ' ';

                        /* Integer part */
                        if (ipart == 0 && pos < sizeof(buf)-1) buf[pos++] = '0';
                        else {
                            char ibuf[20]; int ii = 0;
                            while (ipart > 0) { ibuf[ii++] = '0' + (int)(ipart % 10); ipart /= 10; }
                            while (ii > 0 && pos < sizeof(buf)-1) buf[pos++] = ibuf[--ii];
                        }
                        if (pos < sizeof(buf)-1) buf[pos++] = '.';
                        /* Fractional part with specified precision */
                        { int d; for (d = 0; d < prec && pos < sizeof(buf)-2; d++) {
                            fpart *= 10.0;
                            int digit = (int)fpart;
                            buf[pos++] = '0' + digit;
                            fpart -= digit;
                        }}
                        /* If precision was unspecified (default 6), trim trailing zeros */
                        if (precision < 0) {
                            while (pos > 1 && buf[pos-1] == '0') pos--;
                            if (pos > 0 && buf[pos-1] == '.' && pos < sizeof(buf)-1) buf[pos++] = '0';
                        }
                    }
                    break;
                }
                case 'g': {
                    /* Compact float: use %f or %e notation, trim trailing zeros */
                    if (arg_idx >= arg_count) {
                        format_warn_missing_argument('g');
                    } else if (pos < sizeof(buf) - 20) {
                        Value v = args[arg_idx++];
                        double fv = v.is_float ? v.float_val : (v.is_int ? (double)v.int_val : 0.0);
                        int neg = fv < 0.0;
                        int prec = (precision > 0) ? precision : 6;
                        if (neg) fv = -fv;

                        if (fv == 0.0) {
                            if (neg && pos < sizeof(buf)-1) buf[pos++] = '-';
                            buf[pos++] = '0';
                        } else if (fv >= 1e-4 && fv < 1e6) {
                            /* Use %f-style formatting */
                            unsigned long ipart = (unsigned long)fv;
                            double fpart = fv - (double)ipart;
                            if (neg && pos < sizeof(buf)-1) buf[pos++] = '-';
                            if (ipart == 0 && pos < sizeof(buf)-1) buf[pos++] = '0';
                            else {
                                char ibuf[20]; int ii = 0;
                                while (ipart > 0) { ibuf[ii++] = '0' + (int)(ipart % 10); ipart /= 10; }
                                while (ii > 0 && pos < sizeof(buf)-1) buf[pos++] = ibuf[--ii];
                            }
                            if (pos < sizeof(buf)-1) buf[pos++] = '.';
                            { int d; for (d = 0; d < prec && pos < sizeof(buf)-2; d++) {
                                fpart *= 10.0;
                                int digit = (int)fpart;
                                buf[pos++] = '0' + digit;
                                fpart -= digit;
                            }}
                            /* Trim trailing zeros */
                            while (pos > 1 && buf[pos-1] == '0') pos--;
                            if (pos > 0 && buf[pos-1] == '.' && pos < sizeof(buf)-1) buf[pos++] = '0';
                        } else {
                            /* Use %e-style (scientific) notation */
                            int exp = 0;
                            if (fv >= 1.0) {
                                while (fv >= 10.0) { fv /= 10.0; exp++; }
                            } else {
                                while (fv < 1.0 && fv > 0.0) { fv *= 10.0; exp--; }
                            }
                            if (neg && pos < sizeof(buf)-1) buf[pos++] = '-';
                            {
                                unsigned long ipart = (unsigned long)fv;
                                double fpart = fv - (double)ipart;
                                buf[pos++] = '0' + (int)ipart;
                                if (pos < sizeof(buf)-1) buf[pos++] = '.';
                                { int d; for (d = 0; d < prec - 1 && pos < sizeof(buf)-2; d++) {
                                    fpart *= 10.0;
                                    int digit = (int)fpart;
                                    buf[pos++] = '0' + digit;
                                    fpart -= digit;
                                }}
                                while (pos > 1 && buf[pos-1] == '0') pos--;
                                if (pos > 0 && buf[pos-1] == '.' && pos < sizeof(buf)-1) buf[pos++] = '0';
                            }
                            buf[pos++] = 'e';
                            if (exp >= 0) buf[pos++] = '+';
                            else { buf[pos++] = '-'; exp = -exp; }
                            if (exp < 10) { buf[pos++] = '0'; buf[pos++] = '0' + exp; }
                            else {
                                char ebuf[8]; int ei = 0;
                                while (exp > 0) { ebuf[ei++] = '0' + (exp % 10); exp /= 10; }
                                while (ei > 0 && pos < sizeof(buf)-1) buf[pos++] = ebuf[--ei];
                            }
                        }
                    }
                    break;
                }
                case 's':
                    if (arg_idx < arg_count) {
                        Value v = args[arg_idx++];
                        if (v.is_id && v.obj_val != 0) {
                            const char *s = (const char *)v.obj_val;
                            int slen = (int)cstr_len(s);
                            int max_chars = (precision >= 0 && precision < slen) ? precision : slen;
                            int i;
                            if (width > 0 && max_chars < width && !flag_left_align) {
                                int pad = width - max_chars;
                                for (i = 0; i < pad && pos < sizeof(buf)-1; i++) buf[pos++] = ' ';
                            }
                            for (i = 0; i < max_chars && pos < sizeof(buf)-1; i++) buf[pos++] = s[i];
                            if (width > 0 && max_chars < width && flag_left_align) {
                                int pad = width - max_chars;
                                for (i = 0; i < pad && pos < sizeof(buf)-1; i++) buf[pos++] = ' ';
                            }
                        }
                    } else {
                        format_warn_missing_argument('s');
                    }
                    break;
                case 'p':
                    if (arg_idx < arg_count && pos < sizeof(buf) - 3) {
                        Value v = args[arg_idx++];
                        if (pos < sizeof(buf)-1) buf[pos++] = '0';
                        if (pos < sizeof(buf)-1) buf[pos++] = 'x';
                        if (v.is_id) {
                            unsigned long ptr = (unsigned long)v.obj_val;
                            char hex[17]; int hi = 0;
                            if (ptr == 0 && pos < sizeof(buf)-1) buf[pos++] = '0';
                            else {
                                while (ptr > 0 && hi < 16) { hex[hi++] = "0123456789abcdef"[ptr % 16]; ptr /= 16; }
                                while (hi > 0 && pos < sizeof(buf)-1) buf[pos++] = hex[--hi];
                            }
                        }
                    } else if (arg_idx >= arg_count) {
                        format_warn_missing_argument('p');
                    }
                    break;
                case 'x':
                    if (arg_idx < arg_count) {
                        Value v = args[arg_idx++];
                        unsigned long val = (unsigned long)(v.is_int ? v.int_val : (v.is_id ? (long)v.obj_val : 0));
                        if (val == 0 && pos < sizeof(buf)-1) buf[pos++] = '0';
                        else {
                            char hex[20]; int hi = 0;
                            while (val > 0 && hi < 19) { hex[hi++] = "0123456789abcdef"[val % 16]; val /= 16; }
                            if (width > 0 && !flag_left_align) {
                                int total = hi;
                                char pad = flag_zero_pad ? '0' : ' ';
                                while (total < width && pos < sizeof(buf)-1) { buf[pos++] = pad; total++; }
                            }
                            while (hi > 0 && pos < sizeof(buf)-1) buf[pos++] = hex[--hi];
                        }
                    } else {
                        format_warn_missing_argument('x');
                    }
                    break;
                case 'X':
                    if (arg_idx < arg_count) {
                        Value v = args[arg_idx++];
                        unsigned long val = (unsigned long)(v.is_int ? v.int_val : (v.is_id ? (long)v.obj_val : 0));
                        if (val == 0 && pos < sizeof(buf)-1) buf[pos++] = '0';
                        else {
                            char hex[20]; int hi = 0;
                            while (val > 0 && hi < 19) { hex[hi++] = "0123456789ABCDEF"[val % 16]; val /= 16; }
                            if (width > 0 && !flag_left_align) {
                                int total = hi;
                                char pad = flag_zero_pad ? '0' : ' ';
                                while (total < width && pos < sizeof(buf)-1) { buf[pos++] = pad; total++; }
                            }
                            while (hi > 0 && pos < sizeof(buf)-1) buf[pos++] = hex[--hi];
                        }
                    } else {
                        format_warn_missing_argument('X');
                    }
                    break;
                case 'o':
                    if (arg_idx < arg_count) {
                        Value v = args[arg_idx++];
                        unsigned long val = (unsigned long)(v.is_int ? v.int_val : (v.is_id ? (long)v.obj_val : 0));
                        if (val == 0 && pos < sizeof(buf)-1) buf[pos++] = '0';
                        else {
                            char oct[32]; int oi = 0;
                            while (val > 0 && oi < 31) { oct[oi++] = '0' + (int)(val % 8); val /= 8; }
                            while (oi > 0 && pos < sizeof(buf)-1) buf[pos++] = oct[--oi];
                        }
                    } else {
                        format_warn_missing_argument('o');
                    }
                    break;
                default:
                    if (pos < sizeof(buf)-2) { buf[pos++] = '%'; buf[pos++] = fmt[fi]; }
                    break;
            }
            fi++;
        } else {
            buf[pos++] = fmt[fi++];
        }
    }
    buf[pos] = '\0';

    {
        unsigned int needed = pos + 1;
        char *result = string_pool_alloc(needed);
        if (result == 0) return value_from_id(0);
        cstr_copy(result, buf, needed);
        return value_from_id((id)result);
    }
}

/* ── Value formatting for REPL display ─────────────────────────── */

void fmt_append_char(char *buf, unsigned int capacity, unsigned int *offset, char ch) {
    if (*offset + 1u < capacity) {
        buf[*offset] = ch;
        *offset += 1u;
        buf[*offset] = '\0';
    }
}

void fmt_append_str(char *buf, unsigned int capacity, unsigned int *offset, const char *str) {
    unsigned int i = 0u;
    if (str == 0) return;
    while (str[i] != '\0') {
        fmt_append_char(buf, capacity, offset, str[i]);
        i++;
    }
}

void fmt_append_uint(char *buf, unsigned int capacity, unsigned int *offset, unsigned int val) {
    char digits[12];
    int di = 0;
    if (val == 0u) {
        fmt_append_char(buf, capacity, offset, '0');
        return;
    }
    while (val > 0u && di < 11) {
        digits[di++] = '0' + (char)(val % 10u);
        val /= 10u;
    }
    while (di > 0) {
        di--;
        fmt_append_char(buf, capacity, offset, digits[di]);
    }
}

void fmt_append_hex(char *buf, unsigned int capacity, unsigned int *offset, unsigned long ptr) {
    char hex[17];
    int hi = 0;
    if (ptr == 0) {
        fmt_append_char(buf, capacity, offset, '0');
        return;
    }
    while (ptr > 0 && hi < 16) {
        hex[hi++] = "0123456789abcdef"[ptr % 16];
        ptr /= 16;
    }
    while (hi > 0) {
        hi--;
        fmt_append_char(buf, capacity, offset, hex[hi]);
    }
}

void format_value(Value v, char *buf, unsigned int capacity) {
    unsigned int offset = 0;
    buf[0] = '\0';

    if (v.is_int) {
        int val = v.int_val;
        unsigned int uval;
        if (val < 0) {
            fmt_append_char(buf, capacity, &offset, '-');
            uval = (unsigned int)(-(val + 1)) + 1u;
        } else {
            uval = (unsigned int)val;
        }
        fmt_append_uint(buf, capacity, &offset, uval);
    } else if (v.is_float) {
        /* Format float with up to 6 decimal places, trimming trailing zeros */
        double fv = v.float_val;
        int negative = 0;
        if (fv < 0.0) { negative = 1; fv = -fv; }
        if (negative) fmt_append_char(buf, capacity, &offset, '-');
        unsigned long ipart = (unsigned long)fv;
        double fpart = fv - (double)ipart;
        /* Integer part */
        if (ipart == 0) {
            fmt_append_char(buf, capacity, &offset, '0');
        } else {
            char ibuf[20];
            int ii = 0;
            while (ipart > 0) { ibuf[ii++] = '0' + (ipart % 10); ipart /= 10; }
            while (ii > 0) fmt_append_char(buf, capacity, &offset, ibuf[--ii]);
        }
        /* Fractional part: up to 6 digits, trim trailing zeros */
        {
            char fbuf[7];
            int fi = 0;
            int last_nonzero = 0;
            for (int d = 0; d < 6; d++) {
                fpart *= 10.0;
                int digit = (int)fpart;
                fbuf[fi++] = '0' + digit;
                if (digit != 0) last_nonzero = fi;
                fpart -= digit;
            }
            /* Whole number: skip decimal point entirely (4.0 → "4") */
            if (last_nonzero > 0) {
                fmt_append_char(buf, capacity, &offset, '.');
                for (int d = 0; d < last_nonzero; d++) {
                    fmt_append_char(buf, capacity, &offset, fbuf[d]);
                }
            }
        }
    } else if (v.is_class && v.cls_val != 0) {
        /* Look up class name from variable table (class_getName
         * crashes on sentinel pointers in WASM) */
        const char *name = 0;
        {
            unsigned int vi;
            for (vi = 0; vi < g_ctx.var_count; vi++) {
                if (g_ctx.vars[vi].is_class && g_ctx.vars[vi].cls == v.cls_val) {
                    name = g_ctx.vars[vi].name;
                    break;
                }
            }
        }
        if (name) fmt_append_str(buf, capacity, &offset, name);
        else fmt_append_str(buf, capacity, &offset, "Class");
    } else if (v.is_sel && v.sel_val != 0) {
        const char *name = sel_getName(v.sel_val);
        fmt_append_str(buf, capacity, &offset, "(SEL) ");
        fmt_append_str(buf, capacity, &offset, name);
    } else if (v.is_id && v.obj_val != 0) {
        /* Object — try to show class name and pointer.
         * But object_getClass can crash on non-ObjC pointers (C strings),
         * so we check if the pointer looks like a Foundation stub or C string first. */
        Class cls = (Class)0;
        const char *str_val = (const char *)v.obj_val;
        /* NSNumber marker: "NSNumber:<value>" — display just the value */
        if (cstr_starts(str_val, "NSNumber:")) {
            fmt_append_str(buf, capacity, &offset, str_val + 9);
            return;
        }
        /* NSFloat marker: "NSFloat:<value>" — display just the value */
        if (cstr_starts(str_val, "NSFloat:")) {
            fmt_append_str(buf, capacity, &offset, str_val + 8);
            return;
        }
        /* NSMutableString marker: "NSMutStr:<content>" — display the content */
        if (cstr_starts(str_val, "NSMutStr:")) {
            fmt_append_str(buf, capacity, &offset, str_val + 8);
            return;
        }
        /* String pool pointer — it's a C string, show the content */
        if (str_val >= g_ctx.string_pool &&
            str_val < g_ctx.string_pool + OBJC_INTERP_STRING_POOL_SIZE) {
            fmt_append_str(buf, capacity, &offset, str_val);
            return;
        }
        if (!cstr_starts(str_val, "FDObj:") &&
            str_val != 0 &&
            (str_val < g_ctx.string_pool || str_val >= g_ctx.string_pool + OBJC_INTERP_STRING_POOL_SIZE)) {
            cls = object_getClass(v.obj_val);
        }
        const char *name = "id";
        if (cstr_starts(str_val, "FDObj:")) {
            name = str_val + 6; /* Show class name from FDObj: marker */
        } else if (cls) {
            /* Look up class name from variable table (class_getName
             * crashes on sentinel pointers in WASM) */
            unsigned int vi;
            for (vi = 0; vi < g_ctx.var_count; vi++) {
                if (g_ctx.vars[vi].is_class && g_ctx.vars[vi].cls == cls) {
                    name = g_ctx.vars[vi].name;
                    break;
                }
            }
        }
        fmt_append_str(buf, capacity, &offset, "<");
        fmt_append_str(buf, capacity, &offset, name);
        fmt_append_str(buf, capacity, &offset, ": 0x");
        fmt_append_hex(buf, capacity, &offset, (unsigned long)v.obj_val);
        fmt_append_str(buf, capacity, &offset, ">");
    } else if (v.is_id && v.obj_val == 0) {
        fmt_append_str(buf, capacity, &offset, "nil");
    }
    /* void values produce an empty string — no display */
}

/* ── String pool garbage collection ─────────────────────────────── */
/* RelocEntry is defined in objc_interp_types.h */

/* Centralized root visitor: marks or updates every id/Value pointer in
 * InterpContext that could reference the string pool.  Used for both
 * Phase 1 (mark) and Phase 3 (update) to ensure the root set is
 * identical — no more "mark but forget to update" bugs. */
typedef enum {
    GC_MARK,   /* Phase 1: record old_off into relocs[] */
    GC_UPDATE  /* Phase 3: rewrite pointer from relocs[] */
} GcPhase;

static void gc_visit_id_ptr(id *ptr, RelocEntry *relocs, unsigned int *reloc_count,
                            unsigned int max_relocs, unsigned long pool_start,
                            unsigned long pool_end, GcPhase phase) {
    if (*ptr == 0) return;
    unsigned long addr = (unsigned long)(*ptr);
    if (addr < pool_start || addr >= pool_end) return;
    unsigned int off = (unsigned int)(addr - pool_start);
    if (phase == GC_MARK) {
        if (*reloc_count < max_relocs) {
            relocs[*reloc_count].old_off = off;
            relocs[*reloc_count].new_off = 0;
            (*reloc_count)++;
        }
    } else {
        /* Binary search: relocs[] is sorted by old_off after Phase 2. */
        unsigned int lo = 0, hi = *reloc_count;
        while (lo < hi) {
            unsigned int mid = lo + (hi - lo) / 2;
            if (relocs[mid].old_off < off) lo = mid + 1;
            else hi = mid;
        }
        if (lo < *reloc_count && relocs[lo].old_off == off) {
            *ptr = (id)(g_ctx.string_pool + relocs[lo].new_off);
        }
    }
}

static void gc_visit_value(Value *v, RelocEntry *relocs, unsigned int *reloc_count,
                           unsigned int max_relocs, unsigned long pool_start,
                           unsigned long pool_end, GcPhase phase) {
    if (!v->is_id || v->obj_val == 0) return;
    gc_visit_id_ptr(&v->obj_val, relocs, reloc_count, max_relocs,
                    pool_start, pool_end, phase);
}

static void gc_visit_roots(RelocEntry *relocs, unsigned int *reloc_count,
                           unsigned int max_relocs, unsigned long pool_start,
                           unsigned long pool_end, GcPhase phase) {
    unsigned int i, ci;

    /* Variables */
    for (i = 0; i < g_ctx.var_count; i++) {
        if (g_ctx.vars[i].is_id && g_ctx.vars[i].value != 0) {
            gc_visit_id_ptr(&g_ctx.vars[i].value, relocs, reloc_count,
                            max_relocs, pool_start, pool_end, phase);
        }
    }

    /* Return value */
    gc_visit_value(&g_ctx.return_value, relocs, reloc_count, max_relocs,
                   pool_start, pool_end, phase);

    /* Instance variables: object key (FDObj: marker) + value */
    for (i = 0; i < g_ctx.instance_var_count; i++) {
        gc_visit_id_ptr(&g_ctx.instance_vars[i].object, relocs, reloc_count,
                        max_relocs, pool_start, pool_end, phase);
        gc_visit_value(&g_ctx.instance_vars[i].value, relocs, reloc_count,
                       max_relocs, pool_start, pool_end, phase);
    }

    /* Collection entries: key + value */
    for (i = 0; i < g_ctx.coll_entry_count; i++) {
        gc_visit_value(&g_ctx.coll_entries[i].key, relocs, reloc_count,
                       max_relocs, pool_start, pool_end, phase);
        gc_visit_value(&g_ctx.coll_entries[i].value, relocs, reloc_count,
                       max_relocs, pool_start, pool_end, phase);
    }

    /* Block captures */
    for (i = 0; i < g_ctx.block_count; i++) {
        for (ci = 0; ci < g_ctx.blocks[i].capture_count; ci++) {
            gc_visit_value(&g_ctx.blocks[i].captures[ci].value, relocs,
                           reloc_count, max_relocs, pool_start, pool_end, phase);
        }
    }

    /* Invocations: receiver + args */
    for (i = 0; i < g_ctx.next_invocation_id && i < MAX_INVOCATIONS; i++) {
        gc_visit_id_ptr(&g_ctx.invocations[i].receiver, relocs, reloc_count,
                        max_relocs, pool_start, pool_end, phase);
        {
            unsigned int ai;
            for (ai = 0; ai < g_ctx.invocations[i].arg_count; ai++) {
                gc_visit_value(&g_ctx.invocations[i].args[ai], relocs,
                               reloc_count, max_relocs, pool_start, pool_end, phase);
            }
        }
    }

    /* Associations: target + value */
    for (i = 0; i < g_ctx.association_count; i++) {
        gc_visit_id_ptr(&g_ctx.associations[i].target, relocs, reloc_count,
                        max_relocs, pool_start, pool_end, phase);
        gc_visit_value(&g_ctx.associations[i].value, relocs, reloc_count,
                       max_relocs, pool_start, pool_end, phase);
    }

    /* KVO observers: target + observer */
    for (i = 0; i < g_ctx.kvo_count; i++) {
        gc_visit_id_ptr(&g_ctx.kvo_observers[i].target, relocs, reloc_count,
                        max_relocs, pool_start, pool_end, phase);
        gc_visit_id_ptr(&g_ctx.kvo_observers[i].observer, relocs, reloc_count,
                        max_relocs, pool_start, pool_end, phase);
    }

    /* Current exception */
    gc_visit_value(&g_ctx.current_exception, relocs, reloc_count,
                   max_relocs, pool_start, pool_end, phase);

    /* Autorelease pool objects */
    for (i = 0; i < g_ctx.pool_depth; i++) {
        unsigned int j;
        for (j = 0; j < g_ctx.pools[i].count; j++) {
            gc_visit_id_ptr(&g_ctx.pools[i].object_markers[j], relocs,
                            reloc_count, max_relocs, pool_start, pool_end, phase);
        }
    }
}

void objc_interp_gc_strings(void) {
    static RelocEntry relocs[MAX_STRING_POOL_MARKS];
    unsigned int reloc_count = 0;
    unsigned int new_offset = 0;
    unsigned int i;
    unsigned int pool_limit = g_ctx.string_pool_offset;
    unsigned long pool_start = (unsigned long)g_ctx.string_pool;
    unsigned long pool_end = pool_start + (unsigned long)pool_limit;

    /* Phase 1: Mark — collect live strings from ALL persistent roots. */
    gc_visit_roots(relocs, &reloc_count, MAX_STRING_POOL_MARKS,
                   pool_start, pool_end, GC_MARK);

    if (reloc_count == 0) {
        g_ctx.string_pool_offset = 0;
        return;
    }

    /* Sort by old offset so compaction runs in ascending order. */
    {
        unsigned int j;
        for (i = 1; i < reloc_count; i++) {
            RelocEntry tmp = relocs[i];
            j = i;
            while (j > 0 && relocs[j - 1].old_off > tmp.old_off) {
                relocs[j] = relocs[j - 1];
                j--;
            }
            relocs[j] = tmp;
        }
    }

    /* Phase 2: Compact — move only unique live strings.
     * Bounds check: if old_off is beyond pool_limit, skip it (stale pointer). */
    for (i = 0; i < reloc_count; i++) {
        unsigned int old = relocs[i].old_off;
        if (i > 0 && relocs[i - 1].old_off == old) {
            relocs[i].new_off = relocs[i - 1].new_off;
            continue;
        }

        if (old >= pool_limit) {
            /* Stale relocation — pointer was beyond used pool. Mark as dead. */
            relocs[i].new_off = new_offset;
            continue;
        }

        {
            unsigned int len = cstr_len(g_ctx.string_pool + old) + 1;
            /* Clamp length to remaining pool to prevent OOB read */
            if (old + len > pool_limit) {
                len = pool_limit - old;
            }
            if (old != new_offset) {
                memmove(g_ctx.string_pool + new_offset, g_ctx.string_pool + old, len);
            }
            relocs[i].new_off = new_offset;
            new_offset += len;
        }
    }
    g_ctx.string_pool_offset = new_offset;

    /* Phase 3: Update — rewrite ALL root pointers to their new offsets.
     * Uses the same root enumeration as Phase 1 (mark), guaranteeing
     * every marked pointer is also updated — no more "mark but forget
     * to update" bugs. */
    gc_visit_roots(relocs, &reloc_count, MAX_STRING_POOL_MARKS,
                   pool_start, pool_end, GC_UPDATE);
}

