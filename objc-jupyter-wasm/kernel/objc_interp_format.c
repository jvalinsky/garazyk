/* objc_interp_format.c
 * Extracted NSLog, format, and string GC helpers from the interpreter.
 */

#include "objc_interp_types.h"
#include "objc_interp_globals.h"
#include "objc_interp_format.h"
#include "objc_interp_state.h"
#include <string.h>

/* Runtime / host helpers used by formatting and NSLog output. */
extern Class object_getClass(id);
extern void interp_emit_stream(const char *ptr, unsigned int len);
extern const char *sel_getName(SEL sel);

/* ── NSLog implementation ────────────────────────────────────────── */

void nslog_append(const char *text, unsigned int len) {
    unsigned int i;
    interp_emit_stream(text, len);
    for (i = 0; i < len && g_nslog_offset + 1 < OBJC_INTERP_NSLOG_BUFFER_SIZE; i++) {
        g_nslog_buffer[g_nslog_offset++] = text[i];
    }
    g_nslog_buffer[g_nslog_offset] = '\0';
}

void nslog_append_char(char ch) {
    char chunk[1];
    chunk[0] = ch;
    interp_emit_stream(chunk, 1u);
    if (g_nslog_offset + 1 < OBJC_INTERP_NSLOG_BUFFER_SIZE) {
        g_nslog_buffer[g_nslog_offset++] = ch;
        g_nslog_buffer[g_nslog_offset] = '\0';
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
                            } else {
                                while (*s && pos < sizeof(buf)-1) buf[pos++] = *s++;
                            }
                        } else if (v.is_class && v.cls_val != 0) {
                            const char *name = 0;
                            unsigned int vi;
                            for (vi = 0; vi < g_var_count; vi++) {
                                if (g_vars[vi].is_class && g_vars[vi].cls == v.cls_val) {
                                    name = g_vars[vi].name; break;
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
                case 'd': case 'i':
                    if (arg_idx < arg_count) {
                        Value v = args[arg_idx++];
                        if (v.is_int) {
                            int val = v.int_val;
                            int neg = val < 0;
                            if (neg) val = -val;
                            char tmp[12]; int ti = 0;
                            if (val == 0) tmp[ti++] = '0';
                            else { while (val > 0) { tmp[ti++] = '0' + (val % 10); val /= 10; } }
                            if (neg && pos < sizeof(buf)-1) buf[pos++] = '-';
                            while (ti > 0 && pos < sizeof(buf)-1) buf[pos++] = tmp[--ti];
                        } else if (v.is_id) {
                            int val = (int)(long)v.obj_val;
                            int neg = val < 0;
                            if (neg) val = -val;
                            char tmp[12]; int ti = 0;
                            if (val == 0) tmp[ti++] = '0';
                            else { while (val > 0) { tmp[ti++] = '0' + (val % 10); val /= 10; } }
                            if (neg && pos < sizeof(buf)-1) buf[pos++] = '-';
                            while (ti > 0 && pos < sizeof(buf)-1) buf[pos++] = tmp[--ti];
                        }
                    } else {
                        format_warn_missing_argument(fmt[fi]);
                    }
                    break;
                case 'l':
                    if (fmt[fi + 1] == 'l' && (fmt[fi + 2] == 'd' || fmt[fi + 2] == 'i')) {
                        /* %lld — long long */
                        fi += 2;
                        if (arg_idx < arg_count) {
                            Value v = args[arg_idx++];
                            if (v.is_int) {
                                long val = (long)v.int_val;
                                int neg = val < 0;
                                if (neg) val = -val;
                                char tmp[20]; int ti = 0;
                                if (val == 0) tmp[ti++] = '0';
                                else { while (val > 0) { tmp[ti++] = '0' + (int)(val % 10); val /= 10; } }
                                if (neg && pos < sizeof(buf)-1) buf[pos++] = '-';
                                while (ti > 0 && pos < sizeof(buf)-1) buf[pos++] = tmp[--ti];
                            }
                        } else {
                            format_warn_missing_argument('d');
                        }
                    } else if (fmt[fi + 1] == 'd' || fmt[fi + 1] == 'i') {
                        /* %ld */
                        fi++;
                        if (arg_idx < arg_count) {
                            Value v = args[arg_idx++];
                            if (v.is_int) {
                                long val = (long)v.int_val;
                                int neg = val < 0;
                                if (neg) val = -val;
                                char tmp[20]; int ti = 0;
                                if (val == 0) tmp[ti++] = '0';
                                else { while (val > 0) { tmp[ti++] = '0' + (int)(val % 10); val /= 10; } }
                                if (neg && pos < sizeof(buf)-1) buf[pos++] = '-';
                                while (ti > 0 && pos < sizeof(buf)-1) buf[pos++] = tmp[--ti];
                            }
                        } else {
                            format_warn_missing_argument('d');
                        }
                    }
                    break;
                case 'u':
                    if (arg_idx < arg_count) {
                        Value v = args[arg_idx++];
                        if (v.is_int) {
                            int val = v.int_val;
                            if (val < 0) val = 0;
                            char tmp[12]; int ti = 0;
                            if (val == 0) tmp[ti++] = '0';
                            else { while (val > 0) { tmp[ti++] = '0' + (val % 10); val /= 10; } }
                            while (ti > 0 && pos < sizeof(buf)-1) buf[pos++] = tmp[--ti];
                        }
                    } else {
                        format_warn_missing_argument('u');
                    }
                    break;
                case 'f': {
                    if (arg_idx >= arg_count) {
                        format_warn_missing_argument('f');
                    } else if (pos < sizeof(buf) - 10) {
                        Value v = args[arg_idx++];
                        double fv = v.is_float ? v.float_val : (v.is_int ? (double)v.int_val : 0.0);
                        int neg = fv < 0.0;
                        if (neg) fv = -fv;
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
                        { int d; for (d = 0; d < 6 && pos < sizeof(buf)-2; d++) {
                            fpart *= 10.0;
                            int digit = (int)fpart;
                            buf[pos++] = '0' + digit;
                            fpart -= digit;
                        }}
                        while (pos > 1 && buf[pos-1] == '0') pos--;
                        if (pos > 0 && buf[pos-1] == '.' && pos < sizeof(buf)-1) buf[pos++] = '0';
                    }
                    break;
                }
                case 's':
                    if (arg_idx < arg_count) {
                        Value v = args[arg_idx++];
                        if (v.is_id && v.obj_val != 0) {
                            const char *s = (const char *)v.obj_val;
                            while (*s && pos < sizeof(buf)-1) buf[pos++] = *s++;
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
                        unsigned int val = (unsigned int)(v.is_int ? v.int_val : (v.is_id ? (long)v.obj_val : 0));
                        if (val == 0 && pos < sizeof(buf)-1) buf[pos++] = '0';
                        else {
                            char hex[17]; int hi = 0;
                            while (val > 0 && hi < 16) { hex[hi++] = "0123456789abcdef"[val % 16]; val /= 16; }
                            while (hi > 0 && pos < sizeof(buf)-1) buf[pos++] = hex[--hi];
                        }
                    } else {
                        format_warn_missing_argument('x');
                    }
                    break;
                case 'o':
                    if (arg_idx < arg_count) {
                        Value v = args[arg_idx++];
                        unsigned int val = (unsigned int)(v.is_int ? v.int_val : (v.is_id ? (long)v.obj_val : 0));
                        if (val == 0 && pos < sizeof(buf)-1) buf[pos++] = '0';
                        else {
                            char oct[32]; int oi = 0;
                            while (val > 0 && oi < 31) { oct[oi++] = '0' + (val % 8); val /= 8; }
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
        fmt_append_char(buf, capacity, &offset, '.');
        /* Fractional part: up to 6 digits, trim trailing zeros */
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
        /* If all zeros, show at least one */
        if (last_nonzero == 0) last_nonzero = 1;
        for (int d = 0; d < last_nonzero; d++) {
            fmt_append_char(buf, capacity, &offset, fbuf[d]);
        }
    } else if (v.is_class && v.cls_val != 0) {
        /* Look up class name from variable table (class_getName
         * crashes on sentinel pointers in WASM) */
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
        if (!cstr_starts(str_val, "FDObj:") &&
            str_val != 0 &&
            (str_val < g_string_pool || str_val >= g_string_pool + OBJC_INTERP_STRING_POOL_SIZE)) {
            cls = object_getClass(v.obj_val);
        }
        const char *name = "id";
        if (cstr_starts(str_val, "FDObj:")) {
            name = str_val + 6; /* Show class name from FDObj: marker */
        } else if (cls) {
            /* Look up class name from variable table (class_getName
             * crashes on sentinel pointers in WASM) */
            unsigned int vi;
            for (vi = 0; vi < g_var_count; vi++) {
                if (g_vars[vi].is_class && g_vars[vi].cls == cls) {
                    name = g_vars[vi].name;
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

void objc_interp_gc_strings(void) {
    static RelocEntry relocs[MAX_STRING_POOL_MARKS];
    unsigned int reloc_count = 0;
    unsigned int new_offset = 0;
    unsigned int i;
    unsigned int pool_limit = g_string_pool_offset;
    unsigned long pool_start = (unsigned long)g_string_pool;
    unsigned long pool_end = pool_start + (unsigned long)pool_limit;

    /* Phase 1: Mark — collect live strings from persistent roots. */
    for (i = 0; i < g_var_count && reloc_count < MAX_STRING_POOL_MARKS; i++) {
        if (g_vars[i].is_id && g_vars[i].value != 0) {
            const char *ptr = (const char *)g_vars[i].value;
            if ((unsigned long)ptr >= pool_start && (unsigned long)ptr < pool_end) {
                relocs[reloc_count].old_off = (unsigned int)((unsigned long)ptr - pool_start);
                relocs[reloc_count].new_off = 0;
                reloc_count++;
            }
        }
    }
    /* Mark the static g_return_value if it holds a string pool pointer */
    if (g_return_value.is_id && g_return_value.obj_val != 0 && reloc_count < MAX_STRING_POOL_MARKS) {
        const char *ptr = (const char *)g_return_value.obj_val;
        if ((unsigned long)ptr >= pool_start && (unsigned long)ptr < pool_end) {
            relocs[reloc_count].old_off = (unsigned int)((unsigned long)ptr - pool_start);
            relocs[reloc_count].new_off = 0;
            reloc_count++;
        }
    }
    for (i = 0; i < g_instance_var_count && reloc_count < MAX_STRING_POOL_MARKS; i++) {
        /* Mark the object key (FDObj: marker) if it's in the string pool */
        {
            const char *obj_ptr = (const char *)g_instance_vars[i].object;
            if ((unsigned long)obj_ptr >= pool_start && (unsigned long)obj_ptr < pool_end) {
                if (reloc_count >= MAX_STRING_POOL_MARKS) break;
                relocs[reloc_count].old_off = (unsigned int)((unsigned long)obj_ptr - pool_start);
                relocs[reloc_count].new_off = 0;
                reloc_count++;
            }
        }
        /* Mark the value if it's an id-typed string pool pointer */
        if (g_instance_vars[i].value.is_id && g_instance_vars[i].value.obj_val != 0) {
            const char *ptr = (const char *)g_instance_vars[i].value.obj_val;
            if ((unsigned long)ptr >= pool_start && (unsigned long)ptr < pool_end) {
                if (reloc_count >= MAX_STRING_POOL_MARKS) break;
                relocs[reloc_count].old_off = (unsigned int)((unsigned long)ptr - pool_start);
                relocs[reloc_count].new_off = 0;
                reloc_count++;
            }
        }
    }
    /* Mark collection entry keys and values that are string pool pointers */
    for (i = 0; i < g_coll_entry_count && reloc_count < MAX_STRING_POOL_MARKS; i++) {
        if (g_coll_entries[i].key.is_id && g_coll_entries[i].key.obj_val != 0) {
            const char *ptr = (const char *)g_coll_entries[i].key.obj_val;
            if ((unsigned long)ptr >= pool_start && (unsigned long)ptr < pool_end) {
                if (reloc_count >= MAX_STRING_POOL_MARKS) break;
                relocs[reloc_count].old_off = (unsigned int)((unsigned long)ptr - pool_start);
                relocs[reloc_count].new_off = 0;
                reloc_count++;
            }
        }
        if (g_coll_entries[i].value.is_id && g_coll_entries[i].value.obj_val != 0) {
            const char *ptr = (const char *)g_coll_entries[i].value.obj_val;
            if ((unsigned long)ptr >= pool_start && (unsigned long)ptr < pool_end) {
                if (reloc_count >= MAX_STRING_POOL_MARKS) break;
                relocs[reloc_count].old_off = (unsigned int)((unsigned long)ptr - pool_start);
                relocs[reloc_count].new_off = 0;
                reloc_count++;
            }
        }
    }

    /* Mark block captured values that are string pool pointers */
    for (i = 0; i < g_block_count && reloc_count < MAX_STRING_POOL_MARKS; i++) {
        unsigned int ci;
        for (ci = 0; ci < g_blocks[i].capture_count && reloc_count < MAX_STRING_POOL_MARKS; ci++) {
            if (g_blocks[i].captures[ci].value.is_id && g_blocks[i].captures[ci].value.obj_val != 0) {
                const char *ptr = (const char *)g_blocks[i].captures[ci].value.obj_val;
                if ((unsigned long)ptr >= pool_start && (unsigned long)ptr < pool_end) {
                    if (reloc_count >= MAX_STRING_POOL_MARKS) break;
                    relocs[reloc_count].old_off = (unsigned int)((unsigned long)ptr - pool_start);
                    relocs[reloc_count].new_off = 0;
                    reloc_count++;
                }
            }
        }
    }

    if (reloc_count == 0) {
        g_string_pool_offset = 0;
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

    /* Phase 2: Compact — move only unique live strings. */
    for (i = 0; i < reloc_count; i++) {
        unsigned int old = relocs[i].old_off;
        if (i > 0 && relocs[i - 1].old_off == old) {
            relocs[i].new_off = relocs[i - 1].new_off;
            continue;
        }

        {
            unsigned int len = cstr_len(g_string_pool + old) + 1;
            if (old != new_offset) {
                memmove(g_string_pool + new_offset, g_string_pool + old, len);
            }
            relocs[i].new_off = new_offset;
            new_offset += len;
        }
    }
    g_string_pool_offset = new_offset;

    /* Phase 3: Update — rewrite all root pointers to their new offsets.
     * This includes variable values, instance var values, AND instance var
     * object keys (since FDObj: markers live in the string pool). */
    for (i = 0; i < g_var_count; i++) {
        if (g_vars[i].is_id && g_vars[i].value != 0) {
            const char *ptr = (const char *)g_vars[i].value;
            if ((unsigned long)ptr >= pool_start && (unsigned long)ptr < pool_end) {
                unsigned int off = (unsigned int)((unsigned long)ptr - pool_start);
                unsigned int r;
                for (r = 0; r < reloc_count; r++) {
                    if (relocs[r].old_off == off) {
                        g_vars[i].value = (id)(g_string_pool + relocs[r].new_off);
                        break;
                    }
                }
            }
        }
    }
    /* Update g_return_value if it holds a string pool pointer */
    if (g_return_value.is_id && g_return_value.obj_val != 0) {
        const char *ptr = (const char *)g_return_value.obj_val;
        if ((unsigned long)ptr >= pool_start && (unsigned long)ptr < pool_end) {
            unsigned int off = (unsigned int)((unsigned long)ptr - pool_start);
            unsigned int r;
            for (r = 0; r < reloc_count; r++) {
                if (relocs[r].old_off == off) {
                    g_return_value.obj_val = (id)(g_string_pool + relocs[r].new_off);
                    break;
                }
            }
        }
    }
    for (i = 0; i < g_instance_var_count; i++) {
        /* Update the object key if it's a string pool pointer (FDObj: marker) */
        {
            const char *obj_ptr = (const char *)g_instance_vars[i].object;
            if ((unsigned long)obj_ptr >= pool_start && (unsigned long)obj_ptr < pool_end) {
                unsigned int off = (unsigned int)((unsigned long)obj_ptr - pool_start);
                unsigned int r;
                for (r = 0; r < reloc_count; r++) {
                    if (relocs[r].old_off == off) {
                        g_instance_vars[i].object = (id)(g_string_pool + relocs[r].new_off);
                        break;
                    }
                }
            }
        }
        /* Update the value if it's an id-typed string pool pointer */
        if (g_instance_vars[i].value.is_id && g_instance_vars[i].value.obj_val != 0) {
            const char *ptr = (const char *)g_instance_vars[i].value.obj_val;
            if ((unsigned long)ptr >= pool_start && (unsigned long)ptr < pool_end) {
                unsigned int off = (unsigned int)((unsigned long)ptr - pool_start);
                unsigned int r;
                for (r = 0; r < reloc_count; r++) {
                    if (relocs[r].old_off == off) {
                        g_instance_vars[i].value.obj_val = (id)(g_string_pool + relocs[r].new_off);
                        break;
                    }
                }
            }
        }
    }
    /* Update collection entry keys and values that are string pool pointers */
    for (i = 0; i < g_coll_entry_count; i++) {
        if (g_coll_entries[i].key.is_id && g_coll_entries[i].key.obj_val != 0) {
            const char *ptr = (const char *)g_coll_entries[i].key.obj_val;
            if ((unsigned long)ptr >= pool_start && (unsigned long)ptr < pool_end) {
                unsigned int off = (unsigned int)((unsigned long)ptr - pool_start);
                unsigned int r;
                for (r = 0; r < reloc_count; r++) {
                    if (relocs[r].old_off == off) {
                        g_coll_entries[i].key.obj_val = (id)(g_string_pool + relocs[r].new_off);
                        break;
                    }
                }
            }
        }
        if (g_coll_entries[i].value.is_id && g_coll_entries[i].value.obj_val != 0) {
            const char *ptr = (const char *)g_coll_entries[i].value.obj_val;
            if ((unsigned long)ptr >= pool_start && (unsigned long)ptr < pool_end) {
                unsigned int off = (unsigned int)((unsigned long)ptr - pool_start);
                unsigned int r;
                for (r = 0; r < reloc_count; r++) {
                    if (relocs[r].old_off == off) {
                        g_coll_entries[i].value.obj_val = (id)(g_string_pool + relocs[r].new_off);
                        break;
                    }
                }
            }
        }
    }
    /* Update block captured values that are string pool pointers */
    for (i = 0; i < g_block_count; i++) {
        unsigned int ci;
        for (ci = 0; ci < g_blocks[i].capture_count; ci++) {
            if (g_blocks[i].captures[ci].value.is_id && g_blocks[i].captures[ci].value.obj_val != 0) {
                const char *ptr = (const char *)g_blocks[i].captures[ci].value.obj_val;
                if ((unsigned long)ptr >= pool_start && (unsigned long)ptr < pool_end) {
                    unsigned int off = (unsigned int)((unsigned long)ptr - pool_start);
                    unsigned int r;
                    for (r = 0; r < reloc_count; r++) {
                        if (relocs[r].old_off == off) {
                            g_blocks[i].captures[ci].value.obj_val = (id)(g_string_pool + relocs[r].new_off);
                            break;
                        }
                    }
                }
            }
        }
    }
}

