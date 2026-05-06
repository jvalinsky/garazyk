#ifndef OBJC_INTERP_DISPATCH_H
#define OBJC_INTERP_DISPATCH_H

#include "objc_interp_types.h"

/* Method dispatch */
unsigned int find_interpreter_method(SEL sel, Value target, id receiver, int is_setter);
unsigned int find_interpreter_method_super(SEL sel, Value target, id receiver, Class skip_class);
Value execute_interpreter_method(struct Parser *p, MethodImpl *method, SEL sel, id receiver,
                                 const Value *keyword_args, unsigned int keyword_count,
                                 int return_receiver_on_void);

/* NSLog evaluation */
void eval_nslog(struct Parser *p);

/* Protocol conformance */
int class_conforms_to_protocol(const char *class_name, const char *protocol_name);

/* Class hierarchy helpers */
const char *class_get_superclass_name(const char *class_name);
Class class_ptr_for_name(const char *name);
const char *class_name_for_ptr(Class cls);

/* +initialize tracking */
int class_is_initialized(Class cls);
void mark_class_initialized(Class cls);

#endif /* OBJC_INTERP_DISPATCH_H */
