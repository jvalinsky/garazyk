#ifndef OBJC_INTERP_DISPATCH_H
#define OBJC_INTERP_DISPATCH_H

#include "objc_interp_types.h"

/* Method dispatch */
unsigned int find_interpreter_method(SEL sel, Value target, id receiver, int is_setter);
Value execute_interpreter_method(struct Parser *p, MethodImpl *method, SEL sel, id receiver,
                                 const Value *keyword_args, unsigned int keyword_count,
                                 int return_receiver_on_void);

/* NSLog evaluation */
void eval_nslog(struct Parser *p);

#endif /* OBJC_INTERP_DISPATCH_H */
