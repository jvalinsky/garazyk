#ifndef OBJC_INTERP_STATE_H
#define OBJC_INTERP_STATE_H

/* ── State table operations ──────────────────────────────────────── */
/* Functions that operate on the interpreter's global state tables: */
/* variable table, collection side table, block side table,         */
/* instance variable side table, and property matching.             */

/* Value helpers (non-inline — access InterpVar internals) */
void interp_set_var_from_value(InterpVar *var, Value v);
Value value_from_interp_var(const InterpVar *var);
Value value_from_int_exported(int n);
Value value_from_id_exported(id obj);
Value value_from_float_exported(double f);

/* JavaScript Collection Helpers */
int coll_add_string_val(unsigned int coll_id, const char *key_str, const char *val_str);
int coll_add_int_val(unsigned int coll_id, const char *key_str, int val_int);
int coll_add_double_val(unsigned int coll_id, const char *key_str, double val_double);
int coll_add_bool_val(unsigned int coll_id, const char *key_str, int val_bool);
int coll_add_marker_val(unsigned int coll_id, const char *key_str, id marker);

/* String pool */
char *string_pool_alloc(unsigned int size);

/* Collection side table */
unsigned int coll_count(unsigned int coll_id);
unsigned int coll_create_new(void);
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

/* Host imports */
extern id objc_kernel_host_json_parse(const char *ptr, unsigned int len)
    __attribute__((import_module("objc_kernel_host"), import_name("json_parse")));
extern unsigned int objc_kernel_host_json_stringify(id obj, char *out_ptr, unsigned int out_len)
    __attribute__((import_module("objc_kernel_host"), import_name("json_stringify")));
extern int objc_kernel_host_fetch(int task_id, const char *url, const char *method, const char *headers_json, const char *body, unsigned int body_len)
    __attribute__((import_module("objc_kernel_host"), import_name("fetch")));

/* Crypto host imports */
extern int objc_kernel_host_sha256(const char *data_ptr, unsigned int data_len, char *out_ptr, unsigned int out_cap)
    __attribute__((import_module("objc_kernel_host"), import_name("sha256")));
extern int objc_kernel_host_random_bytes(char *out_ptr, unsigned int count)
    __attribute__((import_module("objc_kernel_host"), import_name("random_bytes")));
extern int objc_kernel_host_hmac_sha256(const char *key_ptr, unsigned int key_len, const char *data_ptr, unsigned int data_len, char *out_ptr, unsigned int out_cap)
    __attribute__((import_module("objc_kernel_host"), import_name("hmac_sha256")));

/* Encoding host imports */
extern int objc_kernel_host_base32_encode(const char *data_ptr, unsigned int data_len, char *out_ptr, unsigned int out_cap)
    __attribute__((import_module("objc_kernel_host"), import_name("base32_encode")));
extern int objc_kernel_host_base32_decode(const char *str_ptr, unsigned int str_len, char *out_ptr, unsigned int out_cap)
    __attribute__((import_module("objc_kernel_host"), import_name("base32_decode")));
extern int objc_kernel_host_base58btc_encode(const char *data_ptr, unsigned int data_len, char *out_ptr, unsigned int out_cap)
    __attribute__((import_module("objc_kernel_host"), import_name("base58btc_encode")));
extern int objc_kernel_host_base58btc_decode(const char *str_ptr, unsigned int str_len, char *out_ptr, unsigned int out_cap)
    __attribute__((import_module("objc_kernel_host"), import_name("base58btc_decode")));

/* CBOR host imports */
extern int objc_kernel_host_cbor_encode(const char *json_ptr, unsigned int json_len, char *out_ptr, unsigned int out_cap)
    __attribute__((import_module("objc_kernel_host"), import_name("cbor_encode")));
extern int objc_kernel_host_cbor_decode(const char *data_ptr, unsigned int data_len, char *out_ptr, unsigned int out_cap)
    __attribute__((import_module("objc_kernel_host"), import_name("cbor_decode")));

/* Network callback (exported to JS) */
void objc_kernel_on_fetch_complete(int task_id, int status_code, const char *data, unsigned int data_len);

#endif /* OBJC_INTERP_STATE_H */
