/* objc_interp_state.c
 * State table operations: variable table, collection side table,
 * block side table, instance variable side table, property matching,
 * string pool, and interpreter helpers.
 */

#include "objc_interp_types.h"
#include "objc_interp_context.h"
#include "objc_interp_state.h"

/* Runtime functions exported from the WASM module */
extern int objc_kernel_host_should_interrupt(void)
    __attribute__((import_module("objc_kernel_host"), import_name("should_interrupt")));
extern void objc_kernel_host_stream(int fd, const char *ptr, unsigned int len)
    __attribute__((import_module("objc_kernel_host"), import_name("stream")));
extern id objc_kernel_host_json_parse(const char *ptr, unsigned int len)
    __attribute__((import_module("objc_kernel_host"), import_name("json_parse")));
extern int objc_kernel_host_fetch(int task_id, const char *url, const char *method, const char *headers_json, const char *body, unsigned int body_len)
    __attribute__((import_module("objc_kernel_host"), import_name("fetch")));

/* ── Interpreter helpers ────────────────────────────────────────── */

extern InterpVar *interp_get_or_create_var(const char *name);

/* ── Network callback (exported to JS) ──────────────────────────── */

void objc_kernel_on_fetch_complete(int task_id, int status_code, const char *data, unsigned int data_len) {
    unsigned int i;
    for (i = 0; i < g_ctx.network_task_count; i++) {
        if (g_ctx.network_tasks[i].task_id == task_id && g_ctx.network_tasks[i].active) {
            unsigned int block_id = g_ctx.network_tasks[i].block_id;
            g_ctx.network_tasks[i].active = 0; /* Mark as complete */

            /* Construct NSData for the response body */
            Value data_val = value_from_id(0);
            if (data && data_len > 0) {
                unsigned int needed = 7 + data_len * 2 + 1;
                char *buf = string_pool_alloc(needed);
                if (buf) {
                    static const char hex_chars[] = "0123456789abcdef";
                    unsigned int j;
                    cstr_copy(buf, "NSData:", needed);
                    for (j = 0; j < data_len; j++) {
                        unsigned char c = (unsigned char)data[j];
                        buf[7 + j * 2] = hex_chars[(c >> 4) & 0x0f];
                        buf[7 + j * 2 + 1] = hex_chars[c & 0x0f];
                    }
                    buf[7 + data_len * 2] = '\0';
                    data_val = value_from_id((id)buf);
                }
            }

            /* Construct NSHTTPURLResponse marker (simplified for now) */
            Value response_val = value_from_id((id)"FDObj:NSHTTPURLResponse"); /* Simplified */
            
            /* Error value */
            Value error_val = value_from_id(0); /* nil error for now if we got a response */

            /* We need to execute the block with (data, response, error) */
            /* This is a bit tricky: we are outside the normal parse_statement loop.
               We must locate the block, set up arguments, and call eval_source_range.
               Save ALL dispatch-critical state so the callback runs in a clean
               interpreter context and cannot corrupt the caller's state. */
            {
                BlockImpl *blk = block_get(block_id);
                if (blk) {
                    /* Save full interpreter state */
                    unsigned int saved_var_count = g_ctx.var_count;
                    int saved_error_code = g_ctx.error_code;
                    char saved_error_buffer[OBJC_INTERP_ERROR_SIZE];
                    cstr_copy(saved_error_buffer, g_ctx.error_buffer, OBJC_INTERP_ERROR_SIZE);
                    int saved_return_pending = g_ctx.return_pending;
                    int saved_break_pending = g_ctx.break_pending;
                    int saved_continue_pending = g_ctx.continue_pending;
                    int saved_exception_pending = g_ctx.exception_pending;
                    Value saved_current_exception = g_ctx.current_exception;
                    unsigned int saved_try_depth = g_ctx.try_depth;
                    unsigned int saved_pool_depth = g_ctx.pool_depth;
                    unsigned int saved_parse_depth = g_ctx.parse_depth;
                    unsigned int saved_eval_depth = g_ctx.eval_depth;
                    unsigned int saved_loop_iterations = g_ctx.loop_iterations;
                    int saved_suppress = g_ctx.suppress_side_effects;
                    unsigned int saved_ast_count = g_ctx.ast_count;

                    /* Reset for clean callback execution */
                    g_ctx.error_code = OBJC_INTERP_OK;
                    g_ctx.error_buffer[0] = '\0';
                    g_ctx.return_pending = 0;
                    g_ctx.break_pending = 0;
                    g_ctx.continue_pending = 0;
                    g_ctx.exception_pending = 0;
                    g_ctx.current_exception = value_void();
                    g_ctx.try_depth = 0;
                    g_ctx.pool_depth = 0;
                    g_ctx.parse_depth = 0;
                    g_ctx.eval_depth = 0;
                    g_ctx.loop_iterations = 0;
                    g_ctx.suppress_side_effects = 0;
                    g_ctx.ast_count = 0;

                    /* Set up arguments */
                    if (blk->arg_count > 0) {
                        InterpVar *arg = interp_get_or_create_var(blk->arg_names[0]);
                        if (arg) interp_set_var_from_value(arg, data_val);
                    }
                    if (blk->arg_count > 1) {
                        InterpVar *arg = interp_get_or_create_var(blk->arg_names[1]);
                        if (arg) interp_set_var_from_value(arg, response_val);
                    }
                    if (blk->arg_count > 2) {
                        InterpVar *arg = interp_get_or_create_var(blk->arg_names[2]);
                        if (arg) interp_set_var_from_value(arg, error_val);
                    }

                    /* Execute block */
                    {
                        extern Value eval_source_range(unsigned int start, unsigned int len, const char *source, unsigned int line_offset);
                        eval_source_range(0, blk->source_len, blk->source, 0);
                    }

                    /* Restore full interpreter state */
                    g_ctx.var_count = saved_var_count;
                    g_ctx.error_code = saved_error_code;
                    cstr_copy(g_ctx.error_buffer, saved_error_buffer, OBJC_INTERP_ERROR_SIZE);
                    g_ctx.return_pending = saved_return_pending;
                    g_ctx.break_pending = saved_break_pending;
                    g_ctx.continue_pending = saved_continue_pending;
                    g_ctx.exception_pending = saved_exception_pending;
                    g_ctx.current_exception = saved_current_exception;
                    g_ctx.try_depth = saved_try_depth;
                    g_ctx.pool_depth = saved_pool_depth;
                    g_ctx.parse_depth = saved_parse_depth;
                    g_ctx.eval_depth = saved_eval_depth;
                    g_ctx.loop_iterations = saved_loop_iterations;
                    g_ctx.suppress_side_effects = saved_suppress;
                    g_ctx.ast_count = saved_ast_count;
                }
            }
            break;
        }
    }
}

int objc_kernel_has_pending_tasks(void) {
    unsigned int i;
    int count = 0;
    for (i = 0; i < g_ctx.network_task_count; i++) {
        if (g_ctx.network_tasks[i].active) count++;
    }
    return count;
}

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
    g_ctx.error_code = OBJC_INTERP_RESOURCE_ERROR;
    cstr_copy(g_ctx.error_buffer, msg, OBJC_INTERP_ERROR_SIZE);
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

Value value_from_int_exported(int n) {
    return value_from_int(n);
}

Value value_from_id_exported(id obj) {
    return value_from_id(obj);
}

Value value_from_float_exported(double f) {
    return value_from_float(f);
}

/* ── JavaScript Collection Helpers ─────────────────────────────── */

int coll_add_string_val(unsigned int coll_id, const char *key_str, const char *val_str) {
    Value key = value_void();
    Value val = value_void();
    if (key_str) {
        unsigned int len = cstr_len(key_str);
        char *k = string_pool_alloc(len + 1);
        if (k) { cstr_copy(k, key_str, len + 1); key = value_from_id((id)k); }
    }
    if (val_str) {
        unsigned int len = cstr_len(val_str);
        char *v = string_pool_alloc(len + 1);
        if (v) { cstr_copy(v, val_str, len + 1); val = value_from_id((id)v); }
    }
    return coll_add(coll_id, key, val);
}

int coll_add_int_val(unsigned int coll_id, const char *key_str, int val_int) {
    Value key = value_void();
    if (key_str) {
        unsigned int len = cstr_len(key_str);
        char *k = string_pool_alloc(len + 1);
        if (k) { cstr_copy(k, key_str, len + 1); key = value_from_id((id)k); }
    }
    return coll_add(coll_id, key, value_from_int(val_int));
}

int coll_add_double_val(unsigned int coll_id, const char *key_str, double val_double) {
    Value key = value_void();
    if (key_str) {
        unsigned int len = cstr_len(key_str);
        char *k = string_pool_alloc(len + 1);
        if (k) { cstr_copy(k, key_str, len + 1); key = value_from_id((id)k); }
    }
    return coll_add(coll_id, key, value_from_float(val_double));
}

int coll_add_bool_val(unsigned int coll_id, const char *key_str, int val_bool) {
    return coll_add_int_val(coll_id, key_str, val_bool ? 1 : 0);
}

int coll_add_marker_val(unsigned int coll_id, const char *key_str, id marker) {
    Value key = value_void();
    if (key_str) {
        unsigned int len = cstr_len(key_str);
        char *k = string_pool_alloc(len + 1);
        if (k) { cstr_copy(k, key_str, len + 1); key = value_from_id((id)k); }
    }
    return coll_add(coll_id, key, value_from_id(marker));
}

/* ── String pool ───────────────────────────────────────────────── */

/* Allocate `size` bytes from the string pool.
 * Returns pointer to the start of the allocation, or 0 if the pool is full.
 * The pool is append-only — strings persist for the lifetime of the kernel.
 * This is safe because the interpreter never frees string pool entries. */
char *string_pool_alloc(unsigned int size) {
    if (g_ctx.string_pool_offset + size > OBJC_INTERP_STRING_POOL_SIZE) {
        return 0; /* pool full — caller must handle */
    }
    {
        char *ptr = g_ctx.string_pool + g_ctx.string_pool_offset;
        g_ctx.string_pool_offset += size;
        return ptr;
    }
}

/* ── Collection side table ──────────────────────────────────────── */

/* Initialize the collection handle table. Must be called after
 * memset(&g_ctx, 0, ...) because the free list uses -1 as sentinel. */
void coll_init(void) {
    int i;
    g_ctx.coll_free_list = -1;
    for (i = 0; i < MAX_COLLECTIONS; i++) {
        g_ctx.coll_slot_active[i] = 0;
        g_ctx.coll_generation[i] = 0;
        g_ctx.coll_free_next[i] = -1;
    }
}

/* Initialize the block free list. Must be called after memset. */
void block_init(void) {
    int i;
    g_ctx.block_free_list = -1;
    for (i = 0; i < 32; i++) {
        g_ctx.block_free_next[i] = -1;
    }
}

/* Initialize the invocation free list. Must be called after memset. */
void invocation_init(void) {
    int i;
    g_ctx.invocation_free_list = -1;
    for (i = 0; i < MAX_INVOCATIONS; i++) {
        g_ctx.invocation_free_next[i] = -1;
    }
}

/* Initialize the association free list. Must be called after memset. */
void association_init(void) {
    int i;
    g_ctx.association_free_list = -1;
    for (i = 0; i < MAX_ASSOCIATIONS; i++) {
        g_ctx.association_free_next[i] = -1;
    }
}

/* Count entries for a given collection ID. */
unsigned int coll_count(unsigned int coll_id) {
    unsigned int i, count = 0;
    for (i = 0; i < g_ctx.coll_entry_count; i++) {
        if (g_ctx.coll_entries[i].coll_id == coll_id) count++;
    }
    return count;
}

unsigned int coll_create_new(void) {
    int slot;
    /* Try to pop from the free list first */
    if (g_ctx.coll_free_list >= 0) {
        slot = g_ctx.coll_free_list;
        g_ctx.coll_free_list = g_ctx.coll_free_next[slot];
    } else if (g_ctx.next_coll_id < MAX_COLLECTIONS) {
        /* Allocate a new slot */
        slot = (int)g_ctx.next_coll_id;
        g_ctx.next_coll_id++;
        g_ctx.coll_generation[slot] = 0;
    } else {
        /* No free slots and table full — error */
        g_ctx.error_code = OBJC_INTERP_RESOURCE_ERROR;
        cstr_copy(g_ctx.error_buffer, "collection table full (max 64)", OBJC_INTERP_ERROR_SIZE);
        return 0;
    }
    g_ctx.coll_slot_active[slot] = 1;
    /* Encode the collection ID as: (generation << 16) | slot_index
     * This allows coll_id_from_marker to validate the generation
     * and detect ABA reuse bugs. */
    return (unsigned int)((g_ctx.coll_generation[slot] << 16) | (unsigned int)slot);
}

/* Destroy a collection: free its slot and entries. */
void coll_destroy(unsigned int coll_id) {
    unsigned int slot = coll_id & 0xFFFF;
    if (slot >= g_ctx.next_coll_id) return;
    if (!g_ctx.coll_slot_active[slot]) return;
    /* Remove all entries for this collection */
    coll_remove_all(coll_id);
    /* Increment generation to invalidate stale markers */
    g_ctx.coll_generation[slot]++;
    g_ctx.coll_slot_active[slot] = 0;
    /* Push slot onto free list */
    g_ctx.coll_free_next[slot] = g_ctx.coll_free_list;
    g_ctx.coll_free_list = (int)slot;
}

/* Add an entry to a collection. Returns 0 on success, -1 if table full. */
int coll_add(unsigned int coll_id, Value key, Value value) {
    unsigned int slot = coll_id & 0xFFFF;
    if (g_ctx.coll_entry_count >= MAX_COLL_ENTRIES) return -1;
    if (slot >= MAX_COLLECTIONS || !g_ctx.coll_slot_active[slot]) return -1;
    g_ctx.coll_entries[g_ctx.coll_entry_count].coll_id = coll_id;
    g_ctx.coll_entries[g_ctx.coll_entry_count].key = key;
    g_ctx.coll_entries[g_ctx.coll_entry_count].value = value;
    g_ctx.coll_entry_count++;
    return 0;
}

/* Find an entry in a collection by key (for dicts/sets). Returns index or -1. */
int coll_find_by_key(unsigned int coll_id, Value *key) {
    unsigned int i;
    for (i = 0; i < g_ctx.coll_entry_count; i++) {
        if (g_ctx.coll_entries[i].coll_id != coll_id) continue;
        /* Compare keys: int by value, id by string content (not pointer) */
        if (key->is_int && g_ctx.coll_entries[i].key.is_int &&
            key->int_val == g_ctx.coll_entries[i].key.int_val) return (int)i;
        if (key->is_id && g_ctx.coll_entries[i].key.is_id &&
            key->obj_val != 0 && g_ctx.coll_entries[i].key.obj_val != 0) {
            /* String content comparison — two different @"key" literals
             * may have different string pool pointers but same content. */
            if (cstr_eq((const char *)key->obj_val, (const char *)g_ctx.coll_entries[i].key.obj_val))
                return (int)i;
        }
    }
    return -1;
}

/* Remove an entry at index. */
void coll_remove_at(unsigned int idx) {
    unsigned int i;
    for (i = (unsigned int)idx; i < g_ctx.coll_entry_count - 1; i++) {
        g_ctx.coll_entries[i] = g_ctx.coll_entries[i + 1];
    }
    g_ctx.coll_entry_count--;
}

/* Remove all entries for a collection ID. */
void coll_remove_all(unsigned int coll_id) {
    unsigned int i = 0;
    while (i < g_ctx.coll_entry_count) {
        if (g_ctx.coll_entries[i].coll_id == coll_id) {
            coll_remove_at(i);
        } else {
            i++;
        }
    }
}

/* Get the Nth entry for a collection (for array indexing). Returns index or -1. */
int coll_get_nth(unsigned int coll_id, unsigned int n) {
    unsigned int i, count = 0;
    for (i = 0; i < g_ctx.coll_entry_count; i++) {
        if (g_ctx.coll_entries[i].coll_id == coll_id) {
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
    if (g_ctx.coll_entry_count >= MAX_COLL_ENTRIES) return -1;
    /* Shift entries from nth onward to make room */
    {
        unsigned int i;
        for (i = g_ctx.coll_entry_count; i > (unsigned int)nth; i--) {
            g_ctx.coll_entries[i] = g_ctx.coll_entries[i - 1];
        }
    }
    g_ctx.coll_entries[(unsigned int)nth].coll_id = coll_id;
    g_ctx.coll_entries[(unsigned int)nth].key = key;
    g_ctx.coll_entries[(unsigned int)nth].value = value;
    g_ctx.coll_entry_count++;
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
        /* Prevent overflow: if id * 10 would exceed 2^31, clamp */
        if (id > 214748364) { /* (2^31 - 1) / 10 */
            id = 0;
            break;
        }
        id = id * 10 + digit;
    }
    /* Validate: the slot must be active and the generation must match.
     * The encoded ID is (generation << 16) | slot_index. */
    {
        unsigned int slot = id & 0xFFFF;
        unsigned int gen = (id >> 16) & 0xFFFF;
        if (slot >= MAX_COLLECTIONS) return 0;
        if (!g_ctx.coll_slot_active[slot]) return 0;
        if (g_ctx.coll_generation[slot] != gen) return 0;
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
            g_ctx.error_code = OBJC_INTERP_RESOURCE_ERROR;
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
    for (i = 0; i < g_ctx.block_count; i++) {
        if (g_ctx.blocks[i].block_id == block_id) return &g_ctx.blocks[i];
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
    for (i = 0; i < g_ctx.instance_var_count; i++) {
        if (g_ctx.instance_vars[i].object == object &&
            cstr_eq(g_ctx.instance_vars[i].prop_name, prop_name)) {
            return &g_ctx.instance_vars[i].value;
        }
    }
    return 0;
}

/* Store an instance variable in the side table.
 * Overwrites existing entry for (object, prop_name), or adds new. */
int instance_var_set(id object, const char *prop_name, Value val) {
    unsigned int i;
    for (i = 0; i < g_ctx.instance_var_count; i++) {
        if (g_ctx.instance_vars[i].object == object &&
            cstr_eq(g_ctx.instance_vars[i].prop_name, prop_name)) {
            g_ctx.instance_vars[i].value = val;
            return 0;
        }
    }
    /* Add new entry */
    if (g_ctx.instance_var_count < MAX_INSTANCE_VARS) {
        g_ctx.instance_vars[g_ctx.instance_var_count].object = object;
        cstr_copy(g_ctx.instance_vars[g_ctx.instance_var_count].prop_name, prop_name, 64);
        g_ctx.instance_vars[g_ctx.instance_var_count].value = val;
        g_ctx.instance_var_count++;
        return 0;
    }
    return -1;
}

/* ── Property matching ─────────────────────────────────────────── */

/* Check if a property belongs to the receiver's class.
 * For FDObj: markers, extracts the class name and compares against
 * g_ctx.properties[pi].class_name. For non-FDObj: receivers (Foundation
 * objects), returns 1 (always match) since Foundation classes don't
 * have user-defined properties. */
int property_matches_class(id receiver, unsigned int pi) {
    const char *s;
    unsigned long addr;
    unsigned long pool_start = (unsigned long)g_ctx.string_pool;
    unsigned long pool_end = pool_start + OBJC_INTERP_STRING_POOL_SIZE;
    if (receiver == 0) return 0;
    addr = (unsigned long)receiver;
    if (addr < pool_start || addr >= pool_end) return 0;
    s = (const char *)receiver;
    if (cstr_starts(s, "FDObj:")) {
        const char *recv_class = s + 6;
        if (g_ctx.properties[pi].class_name[0] != '\0' &&
            !cstr_eq(recv_class, g_ctx.properties[pi].class_name)) {
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
    for (pi = 0; pi < g_ctx.property_count; pi++) {
        if (g_ctx.properties[pi].synthesized &&
            g_ctx.properties[pi].ivar_name[0] != '\0' &&
            cstr_eq(var_name, g_ctx.properties[pi].ivar_name) &&
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
        Value *val = instance_var_get(self, g_ctx.properties[pi].name);
        if (val) return *val;
    }
    return value_void();
}

/* Write a synthesized ivar value to the side table. */
int synthesized_ivar_set(id self, const char *var_name, Value val) {
    int pi = find_synthesized_ivar(var_name, self);
    if (pi >= 0) {
        if (instance_var_set(self, g_ctx.properties[pi].name, val) != 0) {
            g_ctx.error_code = OBJC_INTERP_RESOURCE_ERROR;
            cstr_copy(g_ctx.error_buffer, "instance variable table full (max 256)", OBJC_INTERP_ERROR_SIZE);
            interp_emit_stream("warning: instance variable table full (max 256)\n", cstr_len("warning: instance variable table full (max 256)\n"));
            return -1;
        }
    }
    return 0;
}

/* ── String pool pointer check ──────────────────────────────────── */

int is_string_pool_pointer(id value) {
    unsigned long addr = (unsigned long)value;
    unsigned long pool_start = (unsigned long)g_ctx.string_pool;
    unsigned long pool_end = pool_start + OBJC_INTERP_STRING_POOL_SIZE;
    return value != 0 && addr >= pool_start && addr < pool_end;
}

/* ── Class lookup for FDObj: markers ────────────────────────────── */

Class class_for_fdobj_marker(id receiver) {
    const char *s = (const char *)receiver;
    unsigned int vi;
    if (!is_string_pool_pointer(receiver) || !cstr_starts(s, "FDObj:")) return (Class)0;
    for (vi = 0; vi < g_ctx.var_count; vi++) {
        if (g_ctx.vars[vi].is_class && cstr_eq(g_ctx.vars[vi].name, s + 6)) {
            return g_ctx.vars[vi].cls;
        }
    }
    return (Class)0;
}
