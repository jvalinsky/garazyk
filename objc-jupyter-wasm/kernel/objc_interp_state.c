/* objc_interp_state.c
 * State table operations: variable table, collection side table,
 * block side table, instance variable side table, property matching,
 * string pool, and interpreter helpers.
 */

#include "objc_interp_types.h"
#include "objc_interp_globals.h"
#include "objc_interp_state.h"

/* Runtime functions exported from the WASM module */
extern int objc_kernel_host_should_interrupt(void);
extern void objc_kernel_host_stream(int fd, const char *ptr, unsigned int len);

/* ── Interpreter helpers ────────────────────────────────────────── */

int interp_should_interrupt(void) {
    return objc_kernel_host_should_interrupt() != 0;
}

void interp_emit_stream(const char *ptr, unsigned int len) {
    if (ptr == 0 || len == 0u) {
        return;
    }
    objc_kernel_host_stream(1, ptr, len);
}

void interp_set_resource_error(const char *msg) {
    g_error_code = OBJC_INTERP_RESOURCE_ERROR;
    cstr_copy(g_error_buffer, msg, OBJC_INTERP_ERROR_SIZE);
    interp_emit_stream("Error: ", 7);
    interp_emit_stream(msg, cstr_len(msg));
    interp_emit_stream("\n", 1);
}

/* ── Value helpers (non-inline — access InterpVar internals) ──── */

/* Set all type flags in a variable from a Value, clearing incompatible flags */
void interp_set_var_from_value(InterpVar *var, Value v) {
    var->is_int = v.is_int;
    var->int_value = v.int_val;
    var->is_float = v.is_float;
    var->float_value = v.float_val;
    var->is_id = v.is_id;
    var->value = v.obj_val;
    var->is_class = v.is_class;
    var->cls = v.cls_val;
    var->is_sel = v.is_sel;
    var->sel = v.sel_val;
}

Value value_from_interp_var(const InterpVar *var) {
    Value v = value_void();
    if (var == 0) return v;
    v.obj_val = var->value;
    v.cls_val = var->cls;
    v.sel_val = var->sel;
    v.int_val = var->int_value;
    v.float_val = var->float_value;
    v.is_int = var->is_int;
    v.is_float = var->is_float;
    v.is_class = var->is_class;
    v.is_sel = var->is_sel;
    v.is_id = var->is_id;
    v.is_void = 0;
    return v;
}

/* ── String pool ───────────────────────────────────────────────── */

/* Allocate `size` bytes from the string pool.
 * Returns pointer to the start of the allocation, or 0 if the pool is full.
 * The pool is append-only — strings persist for the lifetime of the kernel.
 * This is safe because the interpreter never frees string pool entries. */
char *string_pool_alloc(unsigned int size) {
    if (g_string_pool_offset + size > OBJC_INTERP_STRING_POOL_SIZE) {
        return 0; /* pool full — caller must handle */
    }
    {
        char *ptr = g_string_pool + g_string_pool_offset;
        g_string_pool_offset += size;
        return ptr;
    }
}

/* ── Collection side table ──────────────────────────────────────── */

/* Count entries for a given collection ID. */
unsigned int coll_count(unsigned int coll_id) {
    unsigned int i, count = 0;
    for (i = 0; i < g_coll_entry_count; i++) {
        if (g_coll_entries[i].coll_id == coll_id) count++;
    }
    return count;
}

/* Add an entry to a collection. Returns 0 on success, -1 if table full. */
int coll_add(unsigned int coll_id, Value key, Value value) {
    if (g_coll_entry_count >= MAX_COLL_ENTRIES) return -1;
    if (coll_id >= g_next_coll_id + MAX_COLLECTIONS) return -1;
    g_coll_entries[g_coll_entry_count].coll_id = coll_id;
    g_coll_entries[g_coll_entry_count].key = key;
    g_coll_entries[g_coll_entry_count].value = value;
    g_coll_entry_count++;
    return 0;
}

/* Find an entry in a collection by key (for dicts/sets). Returns index or -1. */
int coll_find_by_key(unsigned int coll_id, Value *key) {
    unsigned int i;
    for (i = 0; i < g_coll_entry_count; i++) {
        if (g_coll_entries[i].coll_id != coll_id) continue;
        /* Compare keys: int by value, id by string content (not pointer) */
        if (key->is_int && g_coll_entries[i].key.is_int &&
            key->int_val == g_coll_entries[i].key.int_val) return (int)i;
        if (key->is_id && g_coll_entries[i].key.is_id &&
            key->obj_val != 0 && g_coll_entries[i].key.obj_val != 0) {
            /* String content comparison — two different @"key" literals
             * may have different string pool pointers but same content. */
            if (cstr_eq((const char *)key->obj_val, (const char *)g_coll_entries[i].key.obj_val))
                return (int)i;
        }
    }
    return -1;
}

/* Remove an entry at index. */
void coll_remove_at(unsigned int idx) {
    unsigned int i;
    for (i = (unsigned int)idx; i < g_coll_entry_count - 1; i++) {
        g_coll_entries[i] = g_coll_entries[i + 1];
    }
    g_coll_entry_count--;
}

/* Remove all entries for a collection ID. */
void coll_remove_all(unsigned int coll_id) {
    unsigned int i = 0;
    while (i < g_coll_entry_count) {
        if (g_coll_entries[i].coll_id == coll_id) {
            coll_remove_at(i);
        } else {
            i++;
        }
    }
}

/* Get the Nth entry for a collection (for array indexing). Returns index or -1. */
int coll_get_nth(unsigned int coll_id, unsigned int n) {
    unsigned int i, count = 0;
    for (i = 0; i < g_coll_entry_count; i++) {
        if (g_coll_entries[i].coll_id == coll_id) {
            if (count == n) return (int)i;
            count++;
        }
    }
    return -1;
}

/* Insert an entry at a logical position within a collection.
 * Shifts existing entries at that position and later to make room.
 * Returns 0 on success, -1 if table full or position invalid. */
int coll_insert_at(unsigned int coll_id, unsigned int pos, Value key, Value value) {
    int nth = coll_get_nth(coll_id, pos);
    if (nth < 0) return -1;
    if (g_coll_entry_count >= MAX_COLL_ENTRIES) return -1;
    /* Shift entries from nth onward to make room */
    {
        unsigned int i;
        for (i = g_coll_entry_count; i > (unsigned int)nth; i--) {
            g_coll_entries[i] = g_coll_entries[i - 1];
        }
    }
    g_coll_entries[(unsigned int)nth].coll_id = coll_id;
    g_coll_entries[(unsigned int)nth].key = key;
    g_coll_entries[(unsigned int)nth].value = value;
    g_coll_entry_count++;
    return 0;
}

/* Parse a collection ID from a marker string like "NSDict:5" or "NSMutArr:12".
 * Returns the ID, or 0 if not a valid collection marker. */
unsigned int coll_id_from_marker(const char *s, const char *prefix) {
    unsigned int prefix_len = cstr_len(prefix);
    unsigned int id = 0;
    unsigned int i;
    if (!cstr_eq_n(s, prefix, prefix_len)) return 0;
    for (i = prefix_len; s[i] >= '0' && s[i] <= '9'; i++) {
        unsigned int digit = (unsigned int)(s[i] - '0');
        /* Prevent overflow: if id * 10 would exceed MAX_COLL_ENTRIES, clamp */
        if (id > 429496729) { /* (2^32 - 1) / 10 */
            id = 0;
            break;
        }
        id = id * 10 + digit;
        if (id >= 512) { /* MAX_COLL_ENTRIES */
            id = 0;
            break;
        }
    }
    return id;
}

/* Create a collection marker string in the string pool. */
id coll_make_marker(const char *prefix, unsigned int coll_id) {
    char buf[64];
    unsigned int pos = cstr_len(prefix);
    unsigned int tmp = coll_id;
    unsigned int digits;
    cstr_copy(buf, prefix, 64);
    /* Count digits */
    digits = 0;
    if (tmp == 0) digits = 1;
    else { unsigned int t = tmp; while (t > 0) { digits++; t /= 10; } }
    /* Write digits */
    { unsigned int t = tmp; unsigned int d = digits; do { d--; buf[pos + d] = '0' + (t % 10); t /= 10; } while (t > 0); }
    buf[pos + digits] = '\0';
    {
        char *result = string_pool_alloc(pos + digits + 1);
        if (result == 0) {
            g_error_code = OBJC_INTERP_RESOURCE_ERROR;
            interp_emit_stream("Error: string pool exhausted (cannot create collection)\n", 56);
            return (id)0;
        }
        cstr_copy(result, buf, pos + digits + 1);
        return (id)result;
    }
}

/* ── Block side table ──────────────────────────────────────────── */

/* Look up a block by its ID. Returns pointer or 0. */
BlockImpl *block_get(unsigned int block_id) {
    unsigned int i;
    for (i = 0; i < g_block_count; i++) {
        if (g_blocks[i].block_id == block_id) return &g_blocks[i];
    }
    return 0;
}

/* Parse a block ID from a marker string like "NSBlock:5". */
unsigned int block_id_from_marker(const char *s) {
    return coll_id_from_marker(s, "NSBlock:");
}

/* Create a block marker string in the string pool. */
id block_make_marker(unsigned int block_id) {
    return coll_make_marker("NSBlock:", block_id);
}

/* ── Instance variable side table ───────────────────────────────── */

/* Look up an instance variable in the side table.
 * Returns pointer to the value (mutable), or 0 if not found. */
Value *instance_var_get(id object, const char *prop_name) {
    unsigned int i;
    for (i = 0; i < g_instance_var_count; i++) {
        if (g_instance_vars[i].object == object &&
            cstr_eq(g_instance_vars[i].prop_name, prop_name)) {
            return &g_instance_vars[i].value;
        }
    }
    return 0;
}

/* Store an instance variable in the side table.
 * Overwrites existing entry for (object, prop_name), or adds new. */
int instance_var_set(id object, const char *prop_name, Value val) {
    unsigned int i;
    for (i = 0; i < g_instance_var_count; i++) {
        if (g_instance_vars[i].object == object &&
            cstr_eq(g_instance_vars[i].prop_name, prop_name)) {
            g_instance_vars[i].value = val;
            return 0;
        }
    }
    /* Add new entry */
    if (g_instance_var_count < MAX_INSTANCE_VARS) {
        g_instance_vars[g_instance_var_count].object = object;
        cstr_copy(g_instance_vars[g_instance_var_count].prop_name, prop_name, 64);
        g_instance_vars[g_instance_var_count].value = val;
        g_instance_var_count++;
        return 0;
    }
    return -1;
}

/* ── Property matching ─────────────────────────────────────────── */

/* Check if a property belongs to the receiver's class.
 * For FDObj: markers, extracts the class name and compares against
 * g_properties[pi].class_name. For non-FDObj: receivers (Foundation
 * objects), returns 1 (always match) since Foundation classes don't
 * have user-defined properties. */
int property_matches_class(id receiver, unsigned int pi) {
    const char *s;
    unsigned long addr;
    unsigned long pool_start = (unsigned long)g_string_pool;
    unsigned long pool_end = pool_start + OBJC_INTERP_STRING_POOL_SIZE;
    if (receiver == 0) return 0;
    addr = (unsigned long)receiver;
    if (addr < pool_start || addr >= pool_end) return 0;
    s = (const char *)receiver;
    if (cstr_starts(s, "FDObj:")) {
        const char *recv_class = s + 6;
        if (g_properties[pi].class_name[0] != '\0' &&
            !cstr_eq(recv_class, g_properties[pi].class_name)) {
            return 0;
        }
    }
    return 1;
}

/* Check if a variable name is a synthesized ivar name.
 * Returns the property index if found, or -1 if not.
 * This is used to redirect ivar access in method bodies to the side table. */
int find_synthesized_ivar(const char *var_name, id receiver) {
    unsigned int pi;
    for (pi = 0; pi < g_property_count; pi++) {
        if (g_properties[pi].synthesized &&
            g_properties[pi].ivar_name[0] != '\0' &&
            cstr_eq(var_name, g_properties[pi].ivar_name) &&
            property_matches_class(receiver, pi)) {
            return (int)pi;
        }
    }
    return -1;
}

/* Read a synthesized ivar value from the side table.
 * Returns the value, or value_void() if not found. */
Value synthesized_ivar_get(id self, const char *var_name) {
    int pi = find_synthesized_ivar(var_name, self);
    if (pi >= 0) {
        Value *val = instance_var_get(self, g_properties[pi].name);
        if (val) return *val;
    }
    return value_void();
}

/* Write a synthesized ivar value to the side table. */
int synthesized_ivar_set(id self, const char *var_name, Value val) {
    int pi = find_synthesized_ivar(var_name, self);
    if (pi >= 0) {
        if (instance_var_set(self, g_properties[pi].name, val) != 0) {
            g_error_code = OBJC_INTERP_RESOURCE_ERROR;
            cstr_copy(g_error_buffer, "instance variable table full (max 256)", OBJC_INTERP_ERROR_SIZE);
            interp_emit_stream("warning: instance variable table full (max 256)\n", cstr_len("warning: instance variable table full (max 256)\n"));
            return -1;
        }
    }
    return 0;
}

/* ── String pool pointer check ──────────────────────────────────── */

int is_string_pool_pointer(id value) {
    unsigned long addr = (unsigned long)value;
    unsigned long pool_start = (unsigned long)g_string_pool;
    unsigned long pool_end = pool_start + OBJC_INTERP_STRING_POOL_SIZE;
    return value != 0 && addr >= pool_start && addr < pool_end;
}

/* ── Class lookup for FDObj: markers ────────────────────────────── */

Class class_for_fdobj_marker(id receiver) {
    const char *s = (const char *)receiver;
    unsigned int vi;
    if (!is_string_pool_pointer(receiver) || !cstr_starts(s, "FDObj:")) return (Class)0;
    for (vi = 0; vi < g_var_count; vi++) {
        if (g_vars[vi].is_class && cstr_eq(g_vars[vi].name, s + 6)) {
            return g_vars[vi].cls;
        }
    }
    return (Class)0;
}
