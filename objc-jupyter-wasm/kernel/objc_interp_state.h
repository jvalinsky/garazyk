#ifndef OBJC_INTERP_STATE_H
#define OBJC_INTERP_STATE_H

/* ── State table operations ──────────────────────────────────────── */
/* Functions that operate on the interpreter's global state tables: */
/* variable table, collection side table, block side table,         */
/* instance variable side table, and property matching.             */

/* Value helpers (non-inline — access InterpVar internals) */
void interp_set_var_from_value(InterpVar *var, Value v);
Value value_from_interp_var(const InterpVar *var);

/* String pool */
char *string_pool_alloc(unsigned int size);

/* Collection side table */
unsigned int coll_count(unsigned int coll_id);
int coll_add(unsigned int coll_id, Value key, Value value);
int coll_find_by_key(unsigned int coll_id, Value *key);
void coll_remove_at(unsigned int idx);
void coll_remove_all(unsigned int coll_id);
int coll_get_nth(unsigned int coll_id, unsigned int n);
int coll_insert_at(unsigned int coll_id, unsigned int pos, Value key, Value value);
unsigned int coll_id_from_marker(const char *s, const char *prefix);
id coll_make_marker(const char *prefix, unsigned int coll_id);

/* Block side table */
BlockImpl *block_get(unsigned int block_id);
unsigned int block_id_from_marker(const char *s);
id block_make_marker(unsigned int block_id);

/* Instance variable side table */
Value *instance_var_get(id object, const char *prop_name);
int instance_var_set(id object, const char *prop_name, Value val);

/* Property matching */
int property_matches_class(id receiver, unsigned int pi);
int find_synthesized_ivar(const char *var_name, id receiver);
Value synthesized_ivar_get(id self, const char *var_name);
int synthesized_ivar_set(id self, const char *var_name, Value val);

/* String pool pointer check */
int is_string_pool_pointer(id value);

/* Class lookup for FDObj: markers */
Class class_for_fdobj_marker(id receiver);

/* Interrupt / stream / error helpers */
int interp_should_interrupt(void);
void interp_emit_stream(const char *ptr, unsigned int len);
void interp_set_resource_error(const char *msg);

#endif /* OBJC_INTERP_STATE_H */
